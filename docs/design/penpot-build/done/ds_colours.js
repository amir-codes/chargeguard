await H.page("Design System");
H.kill("Colours");
const board = H.box("Colours", { w: 1440, dir: "column", gap: 40, pad: 64, bg: "bg", x: 1640, y: 0, hs: "fix" });
H.text("Colours", "h2", { parent: board });
H.text("Light theme, derived from AccentColor (sRGB 0.20 / 0.78 / 0.38) and the app icon. Every swatch is linked to its colour style. White text only on Primary, Band and Green 700; coloured text below 24 px uses Green 700.", "body", { parent: board, color: "text2", w: 820 });
const GDESC = { primary: "linear 120°, #33C761 → #0E8F6F", band: "linear 150°, #33C761 → #30B0C7", glow: "radial, #33C761 0 % → #FFFFFF 70 %, 35 %" };
const groups = ["Brand", "Gradient", "Neutral", "State"];
for (const g of groups) {
  const sec = H.box(g, { dir: "column", gap: 16, parent: board });
  H.text(g, "label", { parent: sec, color: "g700" });
  const row = H.box("Swatches", { dir: "row", gap: 24, wrap: true, w: 1312, hs: "fix", parent: sec });
  for (const [path, name, key] of H.COLOR_STYLES.filter(r => r[0] === "ChargeGuard / " + g)) {
    const sw = H.box("Swatch / " + name, { dir: "column", gap: 6, w: 120, hs: "fix", parent: row });
    H.rect("Chip", { w: 120, h: 120, r: 12, bg: key, stroke: ["bg", "surf", "g100", "border", "yel", "glow"].includes(key) ? "border" : null, parent: sw });
    H.text(name, "caption", { parent: sw, w: 120 });
    H.text(H.G[key] ? GDESC[key] : H.C[key], "caption", { parent: sw, color: "text2", w: 120, name: "Value" });
  }
}
await H.sleep(400);
return { shapes: H.count(board) };
