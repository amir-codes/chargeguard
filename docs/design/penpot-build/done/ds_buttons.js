await H.page("Design System");
// tighten typography rows
const tb = penpot.root.children.find(s => s.name === "Typography");
tb.flex.rowGap = 0; tb.flex.bottomPadding = 64;
for (const r of tb.children.filter(c => c.name.startsWith("Style / "))) { r.flex.topPadding = 24; r.flex.bottomPadding = 24; }
const desc = tb.children.find(c => c.type === "text" && c.characters.startsWith("Inter for")); if (desc) desc.layoutChild.bottomMargin = 24;
const ttl = tb.children.find(c => c.type === "text" && c.characters === "Typography"); if (ttl) ttl.layoutChild.bottomMargin = 16;

H.kill("Buttons");
for (const c of penpot.library.local.components.filter(c => /^Button/.test(H.fullName(c)))) { const m = c.mainInstance(); if (m) m.remove(); }
const board = H.box("Buttons", { w: 1440, dir: "column", gap: 40, pad: 64, bg: "bg", x: 4920, y: 0, hs: "fix" });
H.text("Buttons", "h2", { parent: board });
H.text("Pills, radius 100. Primary uses Gradient / Primary with white text; outline is a 1.5 px Neutral / Text ring on white. Hover darkens to Green 700.", "body", { parent: board, color: "text2", w: 820 });
const kinds = [
  ["Primary", { pad: [13, 30], bg: "primary" }, { bg: "g700" }, "button", "white", "white", "See all features"],
  ["Outline", { pad: [13, 30], bg: "bg", stroke: "text", sw: 1.5 }, { bg: "g100", stroke: "g700", sw: 1.5 }, "button", "text", "g700", "Free Download"],
  ["Small", { pad: [8, 20], bg: "primary" }, { bg: "g700" }, "small", "white", "white", "Subscribe"],
  ["Nav CTA", { pad: [12, 24], bg: "primary" }, { bg: "g700" }, "small", "white", "white", "Get ChargeGuard"],
];
const made = [];
for (const [kind, def, hov, ts, c1, c2, label] of kinds) {
  const row = H.box(kind, { dir: "row", gap: 48, ai: "center", parent: board });
  H.text(kind, "caption", { parent: row, w: 120, weight: "600", link: false, size: 13, lh: 18 });
  for (const [state, o, col] of [["Default", def, c1], ["Hover", Object.assign({}, def, hov), c2]]) {
    const cell = H.box(state, { dir: "column", gap: 10, parent: row });
    const b = H.box("btn", { dir: "row", ai: "center", jc: "center", r: 100, pad: o.pad, bg: o.bg, stroke: o.stroke, sw: o.sw, parent: cell });
    if (ts === "small") H.text(label, "button", { parent: b, color: col, name: "Label", size: 16, lh: 24, weight: "500" });
    else H.text(label, "button", { parent: b, color: col, name: "Label" });
    H.mkComp(b, "Button / " + kind + " / " + state);
    H.text(state, "caption", { parent: cell, color: "text2" });
    made.push(kind + "/" + state);
  }
}
await H.sleep(500);
return { made, shapes: H.count(board), comps: penpot.library.local.components.length };
