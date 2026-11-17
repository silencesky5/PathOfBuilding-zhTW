// zhTW: JS side of the engine comparison (see Export/zhTWCraftCompare.py)
// JS side of the engine comparison: prints "case<TAB>key<TAB>frequency" lines
const fs = require("fs"), path = require("path");
const site = process.argv[2], N = +(process.argv[3] || 3000);
global.window = {};
eval(fs.readFileSync(path.join(site, "craft-data.js"), "utf8"));
const CE = require(path.join(site, "craft-engine.js"));
const E = CE.create(window.CRAFT_DATA);
const byName = n => E.bases.findIndex(b => b.n === n);
const out = [];
function tally(name, makeItem) {
  const ty = {}, cnt = {};
  for (let i = 0; i < N; i++) {
    const it = makeItem();
    cnt[it.mods.length] = (cnt[it.mods.length] || 0) + 1;
    for (const x of it.mods) { const k = E.mods[x.m].ty + "/" + E.mods[x.m].g; ty[k] = (ty[k] || 0) + 1; }
  }
  for (const k in ty) out.push(name + "\tty:" + k + "\t" + (ty[k] / N).toFixed(4));
  for (const k in cnt) out.push(name + "\tn:" + k + "\t" + (cnt[k] / N).toFixed(4));
}
const helm = byName("Hubris Circlet"), ring = byName("Two-Stone Ring"), bow = byName("Thicket Bow");
const ap = (it, k) => E.apply(it, k).item;
tally("alch_helm", () => ap(E.make(helm, 86), "alch"));
tally("transmute_ring", () => ap(E.make(ring, 84), "transmute"));
tally("chaos_bow", () => ap(ap(E.make(bow, 84), "alch"), "chaos"));
tally("exalt_helm", () => ap(ap(E.make(helm, 86), "alch"), "exalt"));
tally("aug_ring", () => { const t = ap(E.make(ring, 84), "transmute"); return t.mods.length === 1 ? ap(t, "aug") : t; });
const ess = E.essences.find(e => e.lv >= 5 && e.m["Helmet"] !== undefined);
tally("essence_helm", () => ap(E.make(helm, 86), ess.k));
const fos = E.fossils.filter(f => !f.why).slice(0, 2).map(f => f.id);
tally("fossil_helm", () => ap(E.make(helm, 86), E.resoKey(fos)));
out.push("meta\tessence\t" + ess.id);
out.push("meta\tfossils\t" + fos.join("|"));
// deterministic: error texts and mod text
out.push("check\tchaos_normal\t" + E.check(E.make(helm, 86), "chaos"));
const lifeMod = E.mods.findIndex(m => m.id === "IncreasedLife7");
out.push("text\tIncreasedLife7_en\t" + E.render(lifeMod, [80], "en").join("|"));
out.push("text\tIncreasedLife7_zh\t" + E.render(lifeMod, [80], "zh").join("|"));
out.push("text\tIncreasedLife7_range\t" + E.render(lifeMod, null, "zh").join("|"));
out.push("tier\tIncreasedLife7_helm\t" + E.tierOf(helm, lifeMod));
out.push("implicit\tring\t" + E.implicitLines(ring, "zh").join("|"));
process.stdout.write(out.join("\n") + "\n");
