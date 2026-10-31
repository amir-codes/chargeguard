await H.page("Design System");
H.kill("Nav and footer");
for (const c of penpot.library.local.components.filter(c => /^(Nav|Sub-nav|Footer)/.test(H.fullName(c)))) { const m = c.mainInstance(); if (m) m.remove(); }
const board = H.box("Nav and footer", { w: 1568, dir: "column", gap: 40, pad: 64, bg: "surf", x: 9840, y: 0, hs: "fix" });
H.text("Nav and footer", "h2", { parent: board });
H.text("Nav is transparent over the hero. The sub-navigation pill floats at the top right of the hero on desktop and becomes a bottom sticky pill on mobile.", "body", { parent: board, color: "text2", w: 820 });
// Desktop nav
const nav = H.box("Nav desktop", { w: 1440, h: 88, dir: "row", jc: "space-between", ai: "center", pad: [0, 125], bg: "bg", hs: "fix", vs: "fix", parent: board });
H.inst("Logo / Lockup", nav, { name: "Logo" });
const links = H.box("Links", { dir: "row", gap: 32, ai: "center", parent: nav });
for (const l of ["Home", "ChargeGuard", "Blog", "About", "Support"]) H.text(l, "body", { parent: links, name: l, weight: l === "ChargeGuard" ? "600" : "500", link: false, size: 16, lh: 24, color: l === "ChargeGuard" ? "g700" : "text" });
const lang = H.box("Language", { dir: "row", gap: 4, ai: "center", parent: links });
H.text("EN", "body", { parent: lang, weight: "500", link: false, size: 16, lh: 24 });
const cd = H.inst("Icon / chevron-down", lang); cd.resize(16, 16);
const cta = H.inst("Button / Nav CTA / Default", nav, { name: "CTA" });
nav.fills = [];
H.mkComp(nav, "Nav / Desktop");
// Mobile nav
const mnav = H.box("Nav mobile", { w: 390, h: 64, dir: "row", jc: "space-between", ai: "center", pad: [0, 20], hs: "fix", vs: "fix", parent: board });
H.inst("Logo / Lockup", mnav, { name: "Logo" });
const mb = H.box("Menu button", { w: 44, h: 44, r: 100, dir: "row", ai: "center", jc: "center", stroke: "border", sw: 1, bg: "bg", hs: "fix", vs: "fix", parent: mnav });
H.inst("Icon / menu", mb);
H.mkComp(mnav, "Nav / Mobile");
// Sub-nav pills
const mkSub = (name, items, o) => {
  const p = H.box(name, Object.assign({ h: 56, dir: "row", gap: 4, ai: "center", pad: [0, 8], r: 60, stroke: "border", sw: 2, bg: "bg", bgOp: 0.9, vs: "fix" }, o));
  items.forEach((t, i) => {
    const it = H.box("Item / " + t, { h: 40, dir: "row", ai: "center", pad: [0, o.ip || 18], r: 100, bg: i === 0 ? "g100" : null, vs: "fix", parent: p });
    H.text(t, "body", { parent: it, name: "Text", weight: i === 0 ? "600" : "500", link: false, size: o.fs || 16, lh: 24, color: i === 0 ? "g700" : "text" });
  });
  return p;
};
const subRow = H.box("Sub-nav row", { dir: "row", gap: 40, ai: "center", parent: board });
const sd = mkSub("Sub-nav (sticky)", ["Overview", "Features", "Download", "GitHub"], {}); subRow.appendChild(sd); H.mkComp(sd, "Sub-nav / Desktop");
const sm = mkSub("Sub-nav bottom (sticky)", ["Overview", "Features", "Download", "GitHub"], { w: 350, hs: "fix", jc: "space-between", ip: 12, fs: 14 }); subRow.appendChild(sm); H.mkComp(sm, "Sub-nav / Mobile");
await H.sleep(300);
return { shapes: H.count(board) };
