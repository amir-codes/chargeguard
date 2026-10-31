await H.page("Design System");
// colour style + swatch caption fixes
const glow = penpot.library.local.colors.find(c => c.name === "Glow"); glow.gradient = H.G.glow;
const cb = penpot.root.children.find(s => s.name === "Colours");
const GD = { "Primary": "linear 120°\n#33C761 → #0E8F6F", "Band": "linear 150°\n#33C761 → #30B0C7", "Glow": "radial, 35 %\n#33C761 → #FFFFFF 70 %" };
for (const k of Object.keys(GD)) { const sw = H.find(cb, "Swatch / " + k); const v = H.find(sw, "Value"); v.characters = GD[k]; const chip = H.find(sw, "Chip"); chip.fills = H.fill(k === "Primary" ? "primary" : k === "Band" ? "band" : "glow"); }
H.kill("Typography");
const board = H.box("Typography", { w: 1440, dir: "column", gap: 40, pad: 64, bg: "bg", x: 3280, y: 0, hs: "fix" });
H.text("Typography", "h2", { parent: board });
H.text("Inter for text, Inter Tight for display sizes, standing in for SF Pro on the web. Numbers use tabular figures. Every sample is linked to its typography style.", "body", { parent: board, color: "text2", w: 820 });
const samples = { display: "Keep your MacBook's battery healthier.", h2: "Why your MacBook needs ChargeGuard", h3: "Set a limit and forget it", sub: "The all-in-one charge limiter for your MacBook.", bodyL: "Charging to 100 % every day is what wears a battery out.", body: "ChargeGuard holds the charge where you want it, keeps the battery cool, and shows you what is really going on.", caption: "hardware 79.6 %", label: "Charge control", button: "Free Download", stat: "80 %  344  84 %", mDisplay: "Keep your MacBook's battery healthier." };
for (const k of Object.keys(H.TY)) {
  const s = H.TY[k];
  const row = H.box("Style / " + s.n, { dir: "row", gap: 40, ai: "center", w: 1312, hs: "fix", pad: [20, 0], parent: board });
  row.strokes = []; 
  const meta = H.box("Meta", { dir: "column", gap: 4, w: 260, hs: "fix", parent: row });
  H.text(s.n, "caption", { parent: meta, weight: "600", link: false, size: 13, lh: 18 });
  H.text(`${s.f} · ${s.s}/${s.lh} · ${s.w}${s.ls ? " · " + (s.ls > 0 ? "+" : "−") + Math.abs(s.ls) + " px" : ""}${s.up ? " · uppercase" : ""}`, "caption", { parent: meta, color: "text2", name: "Spec" });
  H.text(samples[k], k, { parent: row, w: 1000, name: "Sample", color: k === "label" ? "g700" : "text" });
  const rule = H.rect("Divider", { w: 1312, h: 1, bg: "border", parent: board });
}
await H.sleep(400);
return { shapes: H.count(board) };
