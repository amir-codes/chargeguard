await H.page("Design System");
H.kill("Logo");
for (const c of penpot.library.local.components.filter(c => /^Logo/.test(H.fullName(c)))) { const m = c.mainInstance(); if (m) m.remove(); }
const board = H.box("Logo", { w: 1440, dir: "column", gap: 32, pad: 64, bg: "bg", x: 0, y: 0, hs: "fix" });
H.text("Logo", "h2", { parent: board });
H.text("The app icon is drawn from paths, so instances scale cleanly. Main component at 512 px, used at 180 (hero), 64 (footer) and 32 (nav).", "body", { parent: board, color: "text2", w: 760 });
const row = H.box("Sizes", { dir: "row", gap: 64, ai: "end", parent: board });
const icon = H.appIcon(512, 0, 0, "App icon");
row.appendChild(icon);
const cIcon = H.mkComp(icon, "Logo / App icon");
for (const s of [180, 64, 32]) { const i = cIcon.instance(); i.resize(s, s); i.name = "App icon " + s; row.appendChild(i); }
// lockups
const mkLock = (name, iconSize, textSize, gap) => {
  const l = H.box(name, { dir: "row", gap, ai: "center" });
  const i = cIcon.instance(); i.resize(iconSize, iconSize); i.name = "App icon"; l.appendChild(i);
  H.text("ChargeGuard", "h3", { parent: l, name: "Wordmark", size: textSize, lh: Math.round(textSize * 1.2), weight: "700", link: false });
  const w = H.find(l, "Wordmark"); const f = H.font("Inter Tight"); f.applyToText(w, f.variants.find(v => v.fontWeight === "700" && v.fontStyle === "normal")); w.letterSpacing = String(-textSize * 0.02);
  return l;
};
const row2 = H.box("Lockups", { dir: "row", gap: 64, ai: "center", parent: board });
const l1 = mkLock("Logo / Lockup", 32, 22, 10); row2.appendChild(l1); H.mkComp(l1, "Logo / Lockup");
const l2 = mkLock("Logo / Lockup / Large", 64, 36, 16); row2.appendChild(l2); H.mkComp(l2, "Logo / Lockup / Large");
const onc = H.box("On colour", { dir: "row", pad: [24, 32], bg: "band", r: 12, parent: row2 });
const li = H.comp("Logo / Lockup / Large").instance(); onc.appendChild(li); H.find(li, "Wordmark").fills = H.fill("white");
await H.sleep(500);
return { comps: penpot.library.local.components.map(H.fullName), shapes: H.count(board), h: board.height };
