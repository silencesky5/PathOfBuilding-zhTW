"""zhTW: end-to-end test of automatic updates, without GitHub and without any window.

  python src/Export/zhTWUpdateTest.py <empty work folder>

1. Builds the friends' zip from HEAD (zhTWRelease.py package) with the update source set to a
   local HTTP server, and unpacks it ("installed copy", with a fake Builds/ and Settings.xml).
2. Makes the "next version" on the server: the HEAD tree (git archive) with a changed program
   file, a new file, a removed file and a changed runtime file, and its manifest.xml.
3. Runs src/zhTWUpdateTest.lua inside the installed copy with its own exe: PoB's UpdateCheck.lua
   and UpdateApply.lua, then Update.exe for the runtime files (like Launch.lua does).
4. Checks every file against the server copy, that personal files are untouched, and that a
   second check finds nothing to update.
"""

import functools
import hashlib
import http.server
import pathlib
import shutil
import subprocess
import sys
import threading
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import zhTWRelease as rel

ROOT = rel.ROOT
BRANCH = "release"

CHANGED = "src/Modules/ZhTWLayout.lua"
ADDED = "src/Data/zhTW/UpdateTestAdded.lua"
REMOVED = "src/Data/zhTW/Font12.lua"
CHANGED_RUNTIME = "runtime/lua/base64.lua"
NEW_VERSION = "9.9.9-zhTW.test"

failures = []


def check(cond, what):
	print(("OK   " if cond else "FAIL ") + what)
	if not cond:
		failures.append(what)


def serve(directory):
	handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(directory))
	handler.log_message = lambda *a: None
	httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
	threading.Thread(target=httpd.serve_forever, daemon=True).start()
	return httpd


def run_update(install):
	shutil.copy(ROOT / "src" / "zhTWUpdateTest.lua", install / "zhTWUpdateTest.lua")
	log = install / "zhTWUpdateTest.log"
	if log.exists():
		log.unlink()
	subprocess.run([str(install / "Path of Building.exe"), str(install / "zhTWUpdateTest.lua")], cwd=install, timeout=600)
	text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else "(no log)"
	print("  --- zhTWUpdateTest.log ---")
	for line in text.splitlines():
		if not line.startswith("    "):
			print("  " + line)
	ops = install / "Update" / "opFileRuntime.txt"
	if ops.exists():
		# Launch.lua starts Update.exe, which applies the runtime files and then restarts PoB.
		# Same here, minus the restart (it would open a window).
		lines = [l for l in ops.read_text().splitlines() if not l.startswith("start ")]
		ops.write_text("\n".join(lines))
		subprocess.run([str(install / "Update.exe"), "UpdateApply.lua", "Update/opFileRuntime.txt"], cwd=install, timeout=120)
		print("  ran Update.exe for", len(lines), "runtime files")
	return text


def main():
	work = pathlib.Path(sys.argv[1]).resolve()
	if work.exists() and any(work.iterdir()):
		sys.exit("Use an empty work folder")
	work.mkdir(parents=True, exist_ok=True)
	server_root = work / "server"
	repo_dir = server_root / BRANCH
	repo_dir.mkdir(parents=True)
	httpd = serve(server_root)
	base_url = f"http://127.0.0.1:{httpd.server_port}/{{branch}}/"
	print("server", base_url)

	# 1. Installed copy
	subprocess.run([sys.executable, str(ROOT / "src/Export/zhTWRelease.py"), "package", "--base-url", base_url, "--out", str(work), "--name", "install", "--branch", BRANCH], check=True)
	with zipfile.ZipFile(work / "install.zip") as z:
		z.extractall(work)
	install = work / "install"
	(install / "Builds").mkdir()
	(install / "Builds" / "my build.xml").write_text("<PathOfBuilding/>")
	(install / "Settings.xml").write_text("<PathOfBuilding><Mode mode=\"LIST\"/></PathOfBuilding>")
	check((install / "Path of Building.exe").exists() and (install / "Launch.lua").exists(), "package is one portable folder (exe next to Launch.lua)")
	check(not (install / "HeadlessWrapper.lua").exists() and not (install / "Export").exists(), "package has no tools/test files")

	# 2. Next version on the server (exact committed bytes, like raw.githubusercontent.com)
	# (git archive would convert line endings on Windows; GitHub serves the blobs as they are)
	head_files = rel.tracked_files("HEAD")
	for rp, data in rel.read_blobs(head_files).items():
		(repo_dir / rp).parent.mkdir(parents=True, exist_ok=True)
		(repo_dir / rp).write_bytes(data)
	with open(repo_dir / CHANGED, "ab") as f:
		f.write(b"\n-- update test: changed\n")
	(repo_dir / ADDED).write_bytes("-- update test: 新增的檔案\nreturn { }\n".encode("utf-8"))
	(repo_dir / REMOVED).unlink()
	with open(repo_dir / CHANGED_RUNTIME, "ab") as f:
		f.write(b"\n-- update test: changed runtime file\n")
	files, contents = [], {}
	for p in repo_dir.rglob("*"):
		if p.is_file():
			rp = p.relative_to(repo_dir).as_posix()
			files.append((rp, None))
			if rel.classify(rp):
				contents[rp] = p.read_bytes()
	data, count = rel.build_manifest(NEW_VERSION, base_url, [f for f in files if f[0] != "manifest.xml"], contents)
	(repo_dir / "manifest.xml").write_bytes(data)
	print("server version", NEW_VERSION, count, "files")

	# 3. Update
	text = run_update(install)
	check("devMode\tfalse" in text, "installed copy is not in dev mode (updates are on)")
	check("portable\ttrue" in text, "Builds and Settings stay in the program folder")
	check("updateMode\tbasic" in text, "update found (runtime file changed -> basic mode)")
	downloads = text.count("  Downloading ") - 1  # minus "Downloading update..."
	check(downloads == 3, f"only the changed files were downloaded ({downloads}, expected 3)")

	# 4. Results
	for rp, data in contents.items():
		part, name = rel.classify(rp)
		local = install / name.replace("{space}", " ")
		if not local.exists() or local.read_bytes() != data:
			check(False, "file matches server: " + rp)
	check(True, f"all {len(contents)} files match the server copy")
	check(not (install / REMOVED.split("/", 1)[1]).exists(), "removed file was deleted")
	check((install / ADDED.split("/", 1)[1]).exists(), "new file was downloaded")
	check((install / "lua/base64.lua").read_bytes().endswith(b"changed runtime file\n"), "runtime file updated by Update.exe")
	check((install / "Builds" / "my build.xml").exists() and (install / "Settings.xml").exists(), "personal files untouched")
	check((install / "Update.exe").exists(), "Update.exe kept")
	man = (install / "manifest.xml").read_text(encoding="utf-8")
	check(f'number="{NEW_VERSION}"' in man and f'branch="{BRANCH}"' in man and 'platform="win32"' in man, "local manifest has the new version and still follows our branch")
	check("PathOfBuildingCommunity" not in man and str(httpd.server_port) in man, "update source is still ours, not official PoB")

	text = run_update(install)
	check("updateMode\tnone" in text, "second check: no update available")
	httpd.shutdown()
	print()
	print("FAILED: %d" % len(failures) if failures else "ALL PASSED")
	sys.exit(1 if failures else 0)


if __name__ == "__main__":
	main()
