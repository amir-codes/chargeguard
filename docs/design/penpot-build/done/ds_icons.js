await H.page("Design System");
H.kill("Icons");
for (const c of penpot.library.local.components.filter(c => /^Icon \//.test(H.fullName(c)))) { const m = c.mainInstance(); if (m) m.remove(); }
const board = H.box("Icons", { w: 1440, dir: "column", gap: 32, pad: 64, bg: "bg", x: 6560, y: 0, hs: "fix" });
H.text("Icons", "h2", { parent: board });
H.text("Original line icons on a 24 px grid: 2 px stroke, round caps, Green 700. They stand in for the SF Symbols the app uses. Each glyph is a single path, so instances scale.", "body", { parent: board, color: "text2", w: 820 });
H.text("24 px · 1×", "label", { parent: board, color: "g700", name: "Section 24" });
const grid = H.box("Grid 24", { dir: "row", gap: 16, wrap: true, w: 1312, hs: "fix", parent: board });
for (const key of Object.keys(H.ICONS)) {
  const cell = H.box("Cell / " + key, { dir: "column", gap: 10, ai: "center", w: 112, hs: "fix", pad: [16, 0], bg: "surf", r: 12, parent: grid });
  const ic = H.icon(key, 24, { name: key, parent: cell });
  H.mkComp(ic, "Icon / " + key);
  H.text(key, "caption", { parent: cell, color: "text2", name: "Name" });
}
await H.sleep(400);
return { shapes: H.count(board), icons: Object.keys(H.ICONS).length };
