"""zhTW: release tool for the Chinese (Taiwan) PoB with automatic updates.

PoB's built-in updater (src/UpdateCheck.lua) downloads manifest.xml from the URL in the local
manifest, compares the sha1 of every file and downloads the ones that changed. Friends' copies
point at our GitHub repository (src/Export/zhTWRelease.ini), so they get our updates and never
the official PoB ones (which would remove the Chinese interface).

Commands (run from anywhere, Python 3.10+):

  python src/Export/zhTWRelease.py publish --version 2.67.2-zhTW.2 --note "..." [--note "..."]
      Adds a changelog entry, regenerates manifest.xml from the committed files, and commits.
      Then push to the release branch:  git push origin HEAD:release
      Friends' copies pick it up within a few minutes (GitHub's raw file cache).

  python src/Export/zhTWRelease.py package [--out DIR]
      Builds the zip to give to friends from the current commit (HEAD): a portable PoB in one
      folder whose manifest has platform/branch set, so updates are turned on.

  python src/Export/zhTWRelease.py manifest [--version V]
      Only regenerates manifest.xml (from the index). Used by publish.

Testing: --base-url replaces https://raw.githubusercontent.com/<repo>/{branch}/ (for example a
local HTTP server), see src/zhTWUpdateTest.lua.

Personal files are never included: only files tracked by git are listed, and Settings.xml,
Builds/, Export/ (game data extraction) and the zhTW test scripts are left out.
"""

import argparse
import configparser
import datetime
import hashlib
import io
import pathlib
import re
import subprocess
import sys
import xml.etree.ElementTree as Et
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]

DEFAULT_FILES = {"changelog.txt", "help.txt", "LICENSE.md"}
# Same exclusions as PoB's manifest.cfg, plus our own tools and tests
RUNTIME_EXCLUDE = {"lua-profiler.lua", "msvcr100.dll", "SimpleGraphic.cfg", "Update.exe", "imgui.ini", "SimpleGraphic.log"}
# Not updated, but needed in the package: Update.exe applies runtime updates (it needs msvcr100.dll)
RUNTIME_PACKAGE_ONLY = {"Update.exe", "msvcr100.dll"}
PROGRAM_EXCLUDE_FILES = {"HeadlessWrapper.lua", "LaunchInstall.lua", "Settings.xml", "_SimpleGraphic.def.lua"}
PROGRAM_EXCLUDE_DIRS = ("Export/", "Builds/")
PROGRAM_EXCLUDE_RE = re.compile(r"^zhTW\w*\.(lua|log)$")


def git(*args, binary=False, stdin=None):
	out = subprocess.run(["git", "-C", str(ROOT), "-c", "core.quotepath=false", *args], input=stdin, capture_output=True, check=True)
	return out.stdout if binary else out.stdout.decode("utf-8")


def load_config():
	cfg = configparser.ConfigParser()
	cfg.read(ROOT / "src" / "Export" / "zhTWRelease.ini", encoding="utf-8")
	return cfg["release"]["repo"].strip(), cfg["release"]["branch"].strip()


def classify(path):
	"""Repository path -> (part, name in manifest) or None if not part of the release."""
	if "/" not in path:
		return ("default", path) if path in DEFAULT_FILES else None
	top, rest = path.split("/", 1)
	if top == "runtime":
		if rest.rsplit("/", 1)[-1] in RUNTIME_EXCLUDE:
			return None
		return ("runtime", rest)
	if top == "src":
		if rest.startswith(PROGRAM_EXCLUDE_DIRS) or rest in PROGRAM_EXCLUDE_FILES or ("/" not in rest and PROGRAM_EXCLUDE_RE.match(rest)):
			return None
		if rest.startswith("Data/TimelessJewelData/") and rest.endswith(".bin"):
			return None
		return ("tree" if rest.startswith("TreeData/") else "program", rest)
	return None


def read_blobs(entries):
	"""entries: list of (path, blob id) -> {path: bytes}, read in one git cat-file call."""
	req = "".join(blob + "\n" for _, blob in entries).encode()
	out = git("cat-file", "--batch", binary=True, stdin=req)
	result, pos = {}, 0
	for path, _ in entries:
		header_end = out.index(b"\n", pos)
		size = int(out[pos:header_end].split()[2])
		result[path] = out[header_end + 1:header_end + 1 + size]
		pos = header_end + 1 + size + 1
	return result


def tracked_files(tree=None):
	"""[(path, blob id)] from the index (tree=None) or from a commit."""
	if tree:
		lines = git("ls-tree", "-r", "--full-tree", tree).splitlines()
		return [(l.split("\t", 1)[1], l.split()[2]) for l in lines if l.split()[1] == "blob"]
	lines = git("ls-files", "-s").splitlines()
	return [(l.split("\t", 1)[1], l.split()[1]) for l in lines]


def sources(base_url):
	return [
		{"part": "default", "url": base_url},
		{"part": "runtime", "platform": "win32", "url": base_url + "runtime/"},
		{"part": "program", "url": base_url + "src/"},
		{"part": "tree", "url": base_url + "src/"},
	]


def natural(name):
	return [int(c) if c.isdigit() else c.lower() for c in re.split(r"(\d+)", name)]


def build_manifest(version, base_url, files, contents, platform=None, branch=None):
	"""files: [(path, blob)] -> XML bytes. The sha1 is over the exact bytes GitHub serves."""
	root = Et.Element("PoBVersion")
	ver = {"number": version}
	if platform:
		ver["platform"] = platform
		ver["branch"] = branch
	Et.SubElement(root, "Version", ver)
	for attrib in sources(base_url):
		Et.SubElement(root, "Source", attrib)
	rows = []
	for path, _ in files:
		c = classify(path)
		if c:
			rows.append((c[0], c[1], hashlib.sha1(contents[path]).hexdigest()))
	rows.sort(key=lambda r: (r[0], natural(r[1])))
	for part, name, sha in rows:
		Et.SubElement(root, "File", {"name": name, "part": part, "sha1": sha})
	tree = Et.ElementTree(root)
	Et.indent(tree, "\t")
	buf = io.BytesIO()
	tree.write(buf, encoding="UTF-8", xml_declaration=True)
	return buf.getvalue().replace(b"\n", b"\r\n") + b"\r\n", len(rows)


def default_base_url():
	repo, _ = load_config()
	return "https://raw.githubusercontent.com/" + repo + "/{branch}/"


def current_version(text):
	m = re.search(rb'<Version number="([^"]+)"', text)
	return m.group(1).decode() if m else None


def cmd_manifest(args):
	files = tracked_files()
	files = [f for f in files if f[0] != "manifest.xml"]
	contents = read_blobs([f for f in files if classify(f[0])])
	version = args.version or current_version((ROOT / "manifest.xml").read_bytes())
	data, count = build_manifest(version, args.base_url or default_base_url(), files, contents)
	(ROOT / "manifest.xml").write_bytes(data)
	print(f"manifest.xml: version {version}, {count} files")


def cmd_publish(args):
	if git("status", "--porcelain", "--untracked-files=no").strip():
		sys.exit("Commit or discard your changes first (git status is not clean).")
	if not args.note:
		sys.exit("Give at least one --note describing the update.")
	changelog = ROOT / "changelog.txt"
	text = changelog.read_bytes().decode("utf-8")
	if f"VERSION[{args.version}]" in text:
		sys.exit(f"changelog.txt already has VERSION[{args.version}]")
	eol = "\r\n" if "\r\n" in text else "\n"
	entry = [f"VERSION[{args.version}][{datetime.date.today():%Y/%m/%d}]", "", "--- 台服版更新 ---"]
	entry += ["* " + n for n in args.note]
	changelog.write_bytes((eol.join(entry) + eol + eol + eol + text).encode("utf-8"))
	git("add", "changelog.txt")
	cmd_manifest(args)
	git("add", "manifest.xml")
	git("commit", "-q", "-m", f"zhTW: release {args.version}")
	print(f"Committed release {args.version}. Publish it with:  git push origin HEAD:{load_config()[1]}")


def cmd_package(args):
	_, branch = load_config()
	branch = args.branch or branch
	head = git("rev-parse", "--short", "HEAD").strip()
	files = tracked_files("HEAD")
	blob_of = dict(files)
	remote_manifest = read_blobs([("manifest.xml", blob_of["manifest.xml"])])["manifest.xml"]
	version = current_version(remote_manifest)
	if args.base_url is None and default_base_url().encode() not in remote_manifest:
		sys.exit("manifest.xml in HEAD does not point at our repository; run publish first.")
	wanted = [f for f in files if classify(f[0]) or (f[0].startswith("runtime/") and f[0].split("/")[-1] in RUNTIME_PACKAGE_ONLY)]
	contents = read_blobs(wanted)
	local_manifest, count = build_manifest(version, args.base_url or default_base_url(), files, contents, "win32", branch)
	# The local manifest must list exactly the files of the remote one, or the updater would
	# download (or delete) files right after installing
	if args.base_url is None and local_manifest.split(b"<File", 1)[1] != remote_manifest.split(b"<File", 1)[1]:
		sys.exit("manifest.xml in HEAD is out of date; run publish (or the manifest command) and commit.")

	name = args.name or f"POB台服版_{version}"
	out_dir = pathlib.Path(args.out) if args.out else ROOT.parent
	zip_path = out_dir / (name + ".zip")
	readme = README.format(version=version, date=f"{datetime.date.today():%Y-%m-%d}", commit=head).replace("\n", "\r\n").encode("utf-8-sig")
	with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
		def add(arc, data):
			z.writestr(name + "/" + arc, data)
		for path, _ in wanted:
			c = classify(path)
			arc = c[1] if c else path.split("/", 1)[1]
			# The repository stores the launcher as Path{space}of{space}Building.exe
			add(arc.replace("{space}", " "), contents[path])
		add("manifest.xml", local_manifest)
		add("使用說明.txt", readme)
	print(f"Files: {count} (+{len(wanted) - count} not updated), version {version}, commit {head}")
	print(f"Zip: {zip_path} ({zip_path.stat().st_size / 1048576:.0f} MB)")


README = """POB 台服版（Path of Building Community 非官方繁體中文版）

【開啟】
  解壓縮後，雙擊資料夾裡的「Path of Building.exe」。
  解壓縮的路徑可以有中文。請整個資料夾一起使用，不要只拿出 exe。

【自動更新】
  每次開啟時會自動檢查更新（開著不關的話每 12 小時一次，也可以按 Ctrl+U）。
  有更新時左下角會出現「更新已就緒」，按下去再按「Update」就會更新並重開。
  更新來源是台服版自己的 GitHub 專案，不會被官方 POB 的更新蓋掉中文化。

【匯入台服角色】
  1. 進入一個 Build，到「匯入/匯出」分頁。
  2. 在「依帳號名稱匯入」輸入台服帳號名稱（要包含 # 後面的數字，例如 名稱#1234），按「開始」。
     台服帳號的角色資料要設為公開。
  3. 選聯盟和角色，按「全部匯入」。
  4. 台服資料不含盜賊任務的選擇，請到「設定」分頁手動選擇。

【語言】
  按「選項」按鈕，可以在選項視窗切回英文介面。

【注意】
  - 你的 Build 和設定存在這個資料夾裡（Builds、Settings.xml），更新不會動到它們；換資料夾時請一起搬。
  - Path of Building Community 為 MIT 授權（見 LICENSE.md）；中文字型 Noto Sans TC 為 SIL Open Font License。
    遊戲文字與資料版權屬於 Grinding Gear Games。本版本與官方無關。

版本：{version}（{date}，{commit}）
"""


def main():
	p = argparse.ArgumentParser(description="zhTW release tool")
	sub = p.add_subparsers(dest="cmd", required=True)
	for n in ("manifest", "publish", "package"):
		s = sub.add_parser(n)
		s.add_argument("--base-url", help="update source instead of the GitHub repository (testing)")
		if n in ("manifest", "publish"):
			s.add_argument("--version", required=(n == "publish"))
		if n == "publish":
			s.add_argument("--note", action="append")
		if n == "package":
			s.add_argument("--out")
			s.add_argument("--name")
			s.add_argument("--branch", help="branch friends follow (default from zhTWRelease.ini)")
	args = p.parse_args()
	{"manifest": cmd_manifest, "publish": cmd_publish, "package": cmd_package}[args.cmd](args)


if __name__ == "__main__":
	main()
