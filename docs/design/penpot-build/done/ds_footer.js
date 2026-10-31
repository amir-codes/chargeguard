const board = penpot.root.children.find(s => s.name === "Nav and footer");
const COL1 = ["Support", "FAQ", "Press", "GitHub", "Changelog"], COL2 = ["License (MIT)", "Imprint", "Privacy Policy", "Cookie settings", "Safety guide"];
const SOC = ["GitHub", "X", "YouTube", "Mastodon"];
const linkCol = (name, items, parent) => { const c = H.box(name, { dir: "column", gap: 12, parent }); items.forEach(t => H.text(t, "body", { parent: c, color: "white", name: t })); return c; };
const follow = (parent) => { const f = H.box("Follow us", { dir: "column", gap: 16, parent }); H.text("Follow us", "body", { parent: f, color: "white", weight: "600", link: false, size: 16, lh: 24, name: "Title" }); const r = H.box("Socials", { dir: "row", gap: 12, parent: f }); SOC.forEach(s => H.inst("Social / " + s, r)); return f; };
// Desktop footer
const fd = H.box("Footer desktop", { w: 1440, h: 320, dir: "row", jc: "space-between", ai: "start", pad: [72, 125], bg: "band", hs: "fix", vs: "fix", parent: board });
const left = H.box("Links", { dir: "row", gap: 96, parent: fd });
linkCol("Column 1", COL1, left); linkCol("Column 2", COL2, left); follow(left);
const right = H.box("Brand", { dir: "column", gap: 16, ai: "end", parent: fd });
const lg = H.inst("Logo / Lockup / Large", right, { name: "Logo" }); H.find(lg, "Wordmark").fills = H.fill("white");
H.text("© 2026 ChargeGuard", "caption", { parent: right, color: "white", name: "Copyright" });
H.mkComp(fd, "Footer / Desktop");
// Mobile footer
const fm = H.box("Footer mobile", { w: 390, dir: "column", gap: 32, pad: [48, 20], bg: "band", hs: "fix", parent: board });
const lg2 = H.inst("Logo / Lockup / Large", fm, { name: "Logo" }); H.find(lg2, "Wordmark").fills = H.fill("white");
const cols = H.box("Links", { dir: "row", gap: 40, parent: fm });
linkCol("Column 1", COL1, cols); linkCol("Column 2", COL2, cols);
follow(fm);
H.text("© 2026 ChargeGuard", "caption", { parent: fm, color: "white", name: "Copyright" });
H.mkComp(fm, "Footer / Mobile");
await H.sleep(400);
return { shapes: H.count(board) };
