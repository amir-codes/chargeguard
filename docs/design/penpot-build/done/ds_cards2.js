const t = penpotUtils.findShapeById(storage.tci); const where = t && t.parent && t.parent.name; if (t) t.remove();
const lg = penpot.root.children.find(s => s.name === "Logo");
const board = penpot.root.children.find(s => s.name === "Cards");
const row1 = H.find(board, "Row 1");
// Stat tiles
const mkStat = (name, title, value, detail, o) => {
  const s = H.box(name, Object.assign({ dir: "column", gap: 4, pad: 16, bg: "surf", r: 12 }, o.box));
  H.text(title, "caption", { parent: s, name: "Title", color: o.c2 || "text2" });
  H.text(value, "stat", Object.assign({ parent: s, name: "Value", color: o.c1 || "text" }, o.v || {}));
  if (detail) H.text(detail, "caption", { parent: s, name: "Detail", color: o.c2 || "text2" });
  return s;
};
const col = H.box("Stats", { dir: "column", gap: 24, parent: row1 });
const s1 = mkStat("Stat tile", "Cycle count", "344", "of 1000 rated", { box: { w: 220, hs: "fix" } }); col.appendChild(s1); H.mkComp(s1, "Card / Stat tile");
const s2 = mkStat("Stat tile compact", "Temperature", "30.4 °C", null, { box: { w: 96, hs: "fix", pad: [10, 10], gap: 2, r: 10 }, v: { size: 18, lh: 22, weight: "700", ls: -0.3, link: false } }); col.appendChild(s2); H.mkComp(s2, "Card / Stat tile / Compact");
// Social proof stat cards
const sp1 = H.box("Stat solid", { w: 340, h: 150, dir: "column", gap: 6, pad: 28, jc: "center", bg: "g700", r: 12, hs: "fix", vs: "fix", parent: row1 });
H.text("Open source", "stat", { parent: sp1, name: "Value", color: "white" });
H.text("MIT licensed", "bodyL", { parent: sp1, name: "Detail", color: "white" });
H.mkComp(sp1, "Card / Stat / Solid");
const sp2 = H.box("Stat tinted", { w: 340, h: 260, dir: "column", gap: 10, pad: 28, jc: "center", bg: "g100", r: 12, hs: "fix", vs: "fix", parent: row1 });
H.text("23 features", "body", { parent: sp2, name: "Title", color: "text2" });
H.text("100 % included", "stat", { parent: sp2, name: "Value" });
const rr2 = H.box("Rating", { dir: "row", gap: 8, ai: "center", parent: sp2 });
const tu = H.inst("Icon / thumbs-up", rr2); tu.resize(24, 24);
H.text("PLACEHOLDER rating", "bodyL", { parent: rr2, name: "Rating text", weight: "600", link: false, size: 18, lh: 28 });
H.mkComp(sp2, "Card / Stat / Tinted");
await H.sleep(300);
return { where, lgKids: lg.children.length, shapes: H.count(board) };
