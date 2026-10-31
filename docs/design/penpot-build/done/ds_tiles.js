await H.page("Design System");
const board = penpot.root.children.find(s => s.name === "Icons");
for (const n of ["Section tiles", "Tiles", "Section social", "Social row"]) { const x = H.find(board, n); if (x) x.remove(); }
for (const c of penpot.library.local.components.filter(c => /^(Icon tile|Social)/.test(H.fullName(c)))) { const m = c.mainInstance(); if (m) m.remove(); }
const vc = penpot.root.children.find(s => s.name === "Icon tile"); if (vc) vc.remove();
H.text("Tiles · 96 px", "label", { parent: board, color: "g700", name: "Section tiles" });
const tiles = H.box("Tiles", { dir: "row", gap: 24, wrap: true, w: 1312, hs: "fix", parent: board });
const TILE = ["charge-limiter", "discharge", "heat", "calibration", "sailing", "stats", "bolt", "limit-reached", "schedule", "shortcuts", "sleep"];
const mains = [];
for (const key of TILE) {
  const t = H.box(key, { w: 96, h: 96, r: 24, bg: "bg", stroke: "border", sw: 1.5, x: 0, y: 0 });
  const g = H.glyph(key, 44, t.x + 26, t.y + 26, { sw: 3 }); t.appendChild(g);
  g.constraintsHorizontal = "scale"; g.constraintsVertical = "scale";
  tiles.appendChild(t);
  H.mkComp(t, "Icon tile / " + key);
  mains.push(t);
}
H.text("Social · 36 px", "label", { parent: board, color: "g700", name: "Section social" });
const srow = H.box("Social row", { dir: "row", gap: 16, pad: [24, 24], bg: "band", r: 16, parent: board });
for (const [key, nm] of [["github", "GitHub"], ["x", "X"], ["youtube", "YouTube"], ["mastodon", "Mastodon"]]) {
  const s = H.box(nm, { w: 36, h: 36, r: 8, bg: "white" });
  const g = H.glyph(key, 20, s.x + 8, s.y + 8, { sw: 1.75 }); s.appendChild(g);
  srow.appendChild(s);
  H.mkComp(s, "Social / " + nm);
}
await H.sleep(300);
let variant = null;
try {
  const cont = penpot.createVariantFromComponents(mains);
  await H.sleep(300);
  variant = { name: cont.name, props: cont.variants.properties, n: cont.variants.variantComponents().length, vals: cont.variants.currentValues(cont.variants.properties[0]).slice(0, 4), parent: cont.parent && cont.parent.name };
} catch (e) { variant = "ERR " + e.message; }
return { variant, shapes: H.count(board) };
