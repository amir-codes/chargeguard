const lib = penpot.library.local;
const out = [];
for (const k of Object.keys(H.TY)) {
  const s = H.TY[k]; const t = lib.typographies.find(t => t.name === s.n);
  const font = H.font(s.f); const v = font.variants.find(v => v.fontWeight === s.w && v.fontStyle === "normal");
  t.fontId = font.fontId; t.fontFamilies = font.fontFamily || s.f; t.fontVariantId = v.fontVariantId; t.fontWeight = s.w; t.fontStyle = "normal";
  out.push([t.name, t.fontId, t.fontFamilies, t.fontVariantId, t.fontWeight].join(" "));
}
return out;
