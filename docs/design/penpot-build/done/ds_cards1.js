await H.page("Design System");
// tidy the variant container into a row
const icons = penpot.root.children.find(s => s.name === "Icons");
const cont = H.find(icons, "Icon tile");
if (!cont.flex) { const L = penpotUtils.addFlexLayout(cont, "row"); }
cont.flex.columnGap = 24; cont.flex.topPadding = 24; cont.flex.bottomPadding = 24; cont.flex.leftPadding = 24; cont.flex.rightPadding = 24;
cont.flex.horizontalSizing = "auto"; cont.flex.verticalSizing = "auto";

H.kill("Cards");
for (const c of penpot.library.local.components.filter(c => /^(Card|Chip|Tab|Field|Control|Banner)/.test(H.fullName(c)))) { const m = c.mainInstance(); if (m) m.remove(); }
const board = H.box("Cards", { w: 1440, dir: "column", gap: 40, pad: 64, bg: "bg", x: 8200, y: 0, hs: "fix" });
H.text("Cards", "h2", { parent: board });
H.text("Radius 12 for small cards and stat tiles, 24 for large cards, 100 for pills. Surface #F5F7F9, no shadows in light mode.", "body", { parent: board, color: "text2", w: 820 });
const row1 = H.box("Row 1", { dir: "row", gap: 40, ai: "start", wrap: true, w: 1312, hs: "fix", parent: board });
// Feature card
const fc = H.box("Feature", { w: 499, h: 360, dir: "column", ai: "center", jc: "center", gap: 24, pad: [40, 40], bg: "surf", r: 24, hs: "fix", vs: "fix", parent: row1 });
const tileComp = cont.variants.variantComponents().find(c => c.variantProps.Icon === "charge-limiter");
const ti = tileComp.instance(); fc.appendChild(ti); ti.name = "Icon tile";
const tx = H.box("Text", { dir: "column", gap: 8, ai: "center", parent: fc });
H.text("Charge control", "label", { parent: tx, color: "g700", name: "Label" });
H.text("Set a limit and forget it", "h3", { parent: tx, name: "Title", align: "center", w: 420 });
H.text("Pick a percentage from 20 to 100. ChargeGuard stops charging there and only resumes a couple of percent lower, so the battery is never held at full.", "body", { parent: tx, name: "Body", color: "text2", align: "center", w: 420 });
H.mkComp(fc, "Card / Feature");
// Testimonial
const tc = H.box("Testimonial", { w: 360, h: 260, dir: "column", gap: 16, pad: 28, bg: "g100", r: 24, hs: "fix", vs: "fix", parent: row1 });
const who = H.box("Name row", { dir: "row", gap: 8, ai: "center", parent: tc });
const ui = H.inst("Icon / user", who); ui.resize(20, 20);
H.text("PLACEHOLDER name", "caption", { parent: who, name: "Name", color: "text" });
H.text("PLACEHOLDER — real user quote goes here", "body", { parent: tc, name: "Quote", w: 304 });
H.mkComp(tc, "Card / Testimonial");
// test nested variant switch inside a card instance
let sw = null;
try {
  const ci = H.comp("Card / Feature").instance(); ci.x = 20000; ci.y = 0;
  await H.sleep(200);
  const nt = H.find(ci, "Icon tile");
  nt.switchVariant(0, "heat");
  await H.sleep(500);
  const nt2 = H.find(ci, "Icon tile");
  sw = { parent: nt2 && nt2.parent && nt2.parent.name, glyph: nt2 && nt2.children[0] && nt2.children[0].content.slice(0, 40), idx: nt2 && nt2.parentIndex };
  ci.remove();
} catch (e) { sw = "ERR " + e.message; }
await H.sleep(300);
return { shapes: H.count(board), sw };
