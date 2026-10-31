const board = penpot.root.children.find(s => s.name === "Cards");
for (const n of ["Row 2", "Row 3"]) { const x = H.find(board, n); if (x) x.remove(); }
const row2 = H.box("Row 2", { dir: "column", gap: 16, w: 640, hs: "fix", parent: board });
// FAQ closed
const fq = H.box("FAQ row", { w: 640, h: 64, dir: "row", gap: 16, ai: "center", pad: [0, 24], r: 100, stroke: "border", sw: 1.5, bg: "bg", hs: "fix", vs: "fix", parent: row2 });
const pi = H.inst("Icon / plus", fq, { name: "Toggle" });
H.text("Is it safe? How do I undo it?", "body", { parent: fq, name: "Question", weight: "500", link: false, size: 16, lh: 24 });
const ans = H.text("Answer", "body", { parent: fq, name: "Answer", color: "text2", w: 400 }); ans.hidden = true;
H.mkComp(fq, "Card / FAQ row");
// FAQ open
const fo = H.box("FAQ row open", { w: 640, dir: "column", gap: 8, pad: [20, 24, 24, 24], r: 32, stroke: "g700", sw: 1.5, bg: "bg", hs: "fix", parent: row2 });
const qr = H.box("Question row", { dir: "row", gap: 16, ai: "center", parent: fo });
H.inst("Icon / minus", qr, { name: "Toggle" });
H.text("Is it safe? How do I undo it?", "body", { parent: qr, name: "Question", weight: "500", link: false, size: 16, lh: 24 });
const a2 = H.text("Every change is one command away from the macOS default: Restore normal charging in the menu, chargectl restore in Terminal, or simply a reboot.", "body", { parent: fo, name: "Answer", color: "text2", w: 552 });
a2.layoutChild.leftMargin = 40;
H.mkComp(fo, "Card / FAQ row / Open");
// chips, tabs
const row3 = H.box("Row 3", { dir: "row", gap: 24, ai: "center", wrap: true, w: 1312, hs: "fix", parent: board });
const chip = H.box("Chip", { h: 32, dir: "row", ai: "center", pad: [0, 14], r: 100, bg: "surf", vs: "fix", parent: row3 });
H.text("16″ M5 Pro/Max", "caption", { parent: chip, name: "Text" });
H.mkComp(chip, "Chip / Model");
const ta = H.box("Tab active", { h: 40, dir: "row", ai: "center", pad: [0, 18], r: 100, stroke: "yel", sw: 2, bg: "bg", vs: "fix", parent: row3 });
H.text("MacBook Pro", "body", { parent: ta, name: "Text", weight: "600", link: false, size: 16, lh: 24 });
H.mkComp(ta, "Tab / Active");
const td = H.box("Tab default", { h: 40, dir: "row", ai: "center", pad: [0, 18], r: 100, vs: "fix", parent: row3 });
H.text("MacBook Air", "body", { parent: td, name: "Text", weight: "500", link: false, size: 16, lh: 24, color: "text2" });
H.mkComp(td, "Tab / Default");
// fields
const fs = H.box("Search field", { w: 420, h: 48, dir: "row", gap: 12, ai: "center", pad: [0, 20], r: 100, bg: "surf", stroke: "border", sw: 1, hs: "fix", vs: "fix", parent: row3 });
const si = H.inst("Icon / search", fs); si.resize(20, 20);
const ic = si.children[0]; 
H.text("Search for your MacBook", "body", { parent: fs, name: "Placeholder", color: "text2" });
H.mkComp(fs, "Field / Search");
const fe = H.box("Email field", { w: 420, h: 56, dir: "row", ai: "center", pad: [0, 24], r: 40, bg: "bg", stroke: "border", sw: 1, hs: "fix", vs: "fix", parent: row3 });
H.text("Email Address*", "body", { parent: fe, name: "Placeholder", color: "text2" });
H.mkComp(fe, "Field / Email");
const cb = H.box("Checkbox", { w: 420, dir: "row", gap: 12, ai: "start", hs: "fix", parent: row3 });
const box = H.box("Box", { w: 20, h: 20, r: 6, bg: "bg", stroke: "text2", sw: 1.5, parent: cb });
box.layoutChild.topMargin = 2;
const ct = H.text("I agree to receive the newsletter and have read the Privacy Policy", "body", { parent: cb, name: "Text", color: "text2", w: 388, size: 14, lh: 22, weight: "400", link: false });
const st = ct.characters.indexOf("Privacy Policy"); const rg = ct.getRange(st, st + 14); rg.fills = H.fill("g700"); rg.textDecoration = "underline";
H.mkComp(cb, "Control / Checkbox");
// conflict banner (dashboard screenshot only)
const bn = H.box("Conflict banner", { w: 420, dir: "row", gap: 10, ai: "start", pad: 12, r: 12, bg: "danger", hs: "fix", parent: row3 });
const bi = H.inst("Icon / quit", bn); bi.resize(18, 18); bi.children[0].strokes = H.stroke("white", 1.75, "center", { strokeCapStart: "round", strokeCapEnd: "round" });
const bt = H.box("Text", { dir: "column", gap: 2, w: 362, hs: "fix", parent: bn });
H.text("Another charging tool is running", "body", { parent: bt, name: "Title", color: "white", weight: "600", link: false, size: 15, lh: 20 });
H.text("AlDente. ChargeGuard will not change any charging setting until it is quit, because two tools writing the same keys fight each other.", "caption", { parent: bt, name: "Body", color: "white", w: 362 });
H.mkComp(bn, "Banner / Conflict");
await H.sleep(400);
return { shapes: H.count(board) };
