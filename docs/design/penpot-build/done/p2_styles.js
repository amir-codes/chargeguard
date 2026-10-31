const pages = penpot.currentFile.pages;
if (pages[0].name === "Page 1") pages[0].name = "Cover";
for (const n of ["Design System", "Landing / Desktop 1440", "Landing / Mobile 390", "Assets"]) {
  if (!penpot.currentFile.pages.find(p => p.name === n)) { const p = penpot.createPage(); p.name = n; }
}
const lib = penpot.library.local;
let made = 0;
for (const [path, name, key] of H.COLOR_STYLES) {
  if (lib.colors.find(c => c.path === path && c.name === name)) continue;
  const c = lib.createColor();
  c.name = path + " / " + name;
  if (H.G[key]) { c.gradient = H.G[key]; c.opacity = key === "glow" ? 1 : 1; }
  else { c.color = H.C[key]; c.opacity = 1; }
  made++;
}
let ty = 0;
for (const k of Object.keys(H.TY)) {
  const s = H.TY[k];
  if (lib.typographies.find(t => t.name === s.n)) continue;
  const t = lib.createTypography();
  t.name = "ChargeGuard / " + s.n;
  const font = H.font(s.f); const v = font.variants.find(v => v.fontWeight === s.w && v.fontStyle === "normal");
  t.setFont(font, v);
  t.fontSize = String(s.s); t.lineHeight = String(+(s.lh / s.s).toFixed(4)); t.letterSpacing = String(s.ls);
  if (s.up) t.textTransform = "uppercase";
  ty++;
}
await H.sleep(300);
return { pages: penpot.currentFile.pages.map(p => p.name), made, ty,
  colors: lib.colors.map(c => c.path + " | " + c.name + " | " + (c.color || "grad")),
  typos: lib.typographies.map(t => [t.path, t.name, t.fontFamilies, t.fontSize, t.fontWeight, t.lineHeight, t.letterSpacing, t.textTransform].join(" ")) };
