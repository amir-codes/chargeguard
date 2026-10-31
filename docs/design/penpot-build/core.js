(function () {
  const H = {};
  H.sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  // ---------- tokens ----------
  H.C = {
    g500: "#33C761", g700: "#0E8F6F", g100: "#E3F8EA", yel: "#F4D43A",
    bg: "#FFFFFF", surf: "#F5F7F9", border: "#E3E8EE", text: "#0B1220", text2: "#5B6470",
    charging: "#FF9500", limit: "#34C759", sailing: "#30B0C7", discharging: "#007AFF",
    heat: "#FF3B30", calibrating: "#AF52DE", topup: "#FFCC00", helper: "#8E8E93", conflict: "#FF2D55",
    white: "#FFFFFF", black: "#000000",
  };
  const st = (c, o, off) => ({ color: c, opacity: o, offset: off });
  H.G = {
    primary: { type: "linear", startX: 0.07, startY: 0.25, endX: 0.93, endY: 0.75, width: 1, stops: [st("#33C761", 1, 0), st("#0E8F6F", 1, 1)] },
    band: { type: "linear", startX: 0.25, startY: 0.07, endX: 0.75, endY: 0.93, width: 1, stops: [st("#33C761", 1, 0), st("#30B0C7", 1, 1)] },
    glow: { type: "radial", startX: 0.5, startY: 0.5, endX: 0.5, endY: 1, width: 1, stops: [st("#33C761", 0.35, 0), st("#FFFFFF", 0.35, 0.7), st("#FFFFFF", 0, 1)] },
    icon: { type: "linear", startX: 0.3, startY: 0, endX: 0.7, endY: 1, width: 1, stops: [st("#33C761", 1, 0), st("#0E8F6F", 1, 1)] },
    danger: { type: "linear", startX: 0, startY: 0, endX: 0, endY: 1, width: 1, stops: [st("#FF5A4F", 1, 0), st("#E5281D", 1, 1)] },
  };
  // [library path, name, key]
  H.COLOR_STYLES = [
    ["ChargeGuard / Brand", "Green 500", "g500"], ["ChargeGuard / Brand", "Green 700", "g700"],
    ["ChargeGuard / Brand", "Green 100", "g100"], ["ChargeGuard / Brand", "Yellow", "yel"],
    ["ChargeGuard / Gradient", "Primary", "primary"], ["ChargeGuard / Gradient", "Band", "band"],
    ["ChargeGuard / Gradient", "Glow", "glow"],
    ["ChargeGuard / Neutral", "Background", "bg"], ["ChargeGuard / Neutral", "Surface", "surf"],
    ["ChargeGuard / Neutral", "Border", "border"], ["ChargeGuard / Neutral", "Text", "text"],
    ["ChargeGuard / Neutral", "Text secondary", "text2"],
    ["ChargeGuard / State", "Charging", "charging"], ["ChargeGuard / State", "Limit reached", "limit"],
    ["ChargeGuard / State", "Sailing", "sailing"], ["ChargeGuard / State", "Discharging", "discharging"],
    ["ChargeGuard / State", "Heat paused, Error", "heat"], ["ChargeGuard / State", "Calibrating", "calibrating"],
    ["ChargeGuard / State", "Top up", "topup"], ["ChargeGuard / State", "Helper missing", "helper"],
    ["ChargeGuard / State", "Conflict", "conflict"],
  ];
  // size / line-height in px, letter-spacing px
  H.TY = {
    display: { n: "Display", f: "Inter Tight", s: 56, lh: 64, w: "700", ls: -1 },
    h2: { n: "H2", f: "Inter Tight", s: 40, lh: 48, w: "700", ls: -0.5 },
    h3: { n: "H3", f: "Inter", s: 20, lh: 28, w: "700", ls: 0 },
    sub: { n: "Hero subhead", f: "Inter", s: 28, lh: 36, w: "400", ls: 0 },
    bodyL: { n: "Body L", f: "Inter", s: 18, lh: 28, w: "400", ls: 0 },
    body: { n: "Body", f: "Inter", s: 16, lh: 24, w: "400", ls: 0 },
    caption: { n: "Caption", f: "Inter", s: 13, lh: 18, w: "500", ls: 0 },
    label: { n: "Label", f: "Inter", s: 14, lh: 20, w: "600", ls: 2, up: true },
    button: { n: "Button", f: "Inter", s: 18, lh: 24, w: "500", ls: 0 },
    stat: { n: "Stat number", f: "Inter Tight", s: 44, lh: 48, w: "700", ls: -1 },
    mDisplay: { n: "Mobile Display", f: "Inter Tight", s: 40, lh: 48, w: "700", ls: -0.5 },
  };

  // ---------- library lookups ----------
  H.lc = (key) => {
    const row = H.COLOR_STYLES.find((r) => r[2] === key);
    if (!row) return null;
    return penpot.library.local.colors.find((c) => c.path === row[0] && c.name === row[1]) || null;
  };
  H.lt = (key) => {
    const s = H.TY[key];
    return s ? penpot.library.local.typographies.find((t) => t.name === s.n) || null : null;
  };
  H.fullName = (c) => (c.path ? c.path + " / " : "") + c.name;
  H.comp = (name) => penpot.library.local.components.find((c) => H.fullName(c) === name) || null;

  // fill from a key ("g500", "primary"), a hex, or a gradient object
  H.fill = (c, op) => {
    if (!c) return [];
    const lib = typeof c === "string" ? H.lc(c) : null;
    let f;
    if (lib) f = lib.asFill();
    else if (typeof c === "string" && H.C[c]) f = { fillColor: H.C[c], fillOpacity: 1 };
    else if (typeof c === "string" && H.G[c]) f = { fillColorGradient: H.G[c], fillOpacity: 1 };
    else if (typeof c === "string") f = { fillColor: c, fillOpacity: 1 };
    else f = { fillColorGradient: c, fillOpacity: 1 };
    if (op != null) f = Object.assign({}, f, { fillOpacity: op });
    return [f];
  };
  H.stroke = (c, w, align, extra) => {
    const lib = H.lc(c);
    let s = lib ? lib.asStroke() : { strokeColor: H.C[c] || c, strokeOpacity: 1 };
    return [Object.assign({}, s, { strokeWidth: w == null ? 1 : w, strokeAlignment: align || "inner", strokeStyle: "solid" }, extra || {})];
  };

  // ---------- fonts / text ----------
  H.font = (fam) => penpot.fonts.all.find((f) => f.name === fam);
  H.text = (str, sty, o) => {
    o = o || {};
    const s = H.TY[sty];
    const t = penpot.createText(str);
    const font = H.font(s.f);
    const v = font.variants.find((v) => v.fontWeight === (o.weight || s.w) && v.fontStyle === "normal");
    font.applyToText(t, v);
    t.fontSize = String(o.size || s.s);
    t.lineHeight = String(+((o.lh || s.lh) / (o.size || s.s)).toFixed(4));
    t.letterSpacing = String(o.ls != null ? o.ls : s.ls || 0);
    if (s.up) t.textTransform = "uppercase";
    if (!o.weight && !o.size && o.link !== false) {
      const ty = H.lt(sty);
      if (ty) ty.applyToText(t);
    }
    t.fills = H.fill(o.color || "text");
    t.align = o.align || "left";
    if (o.w) {
      t.resize(o.w, o.lh || s.lh);
      t.growType = "auto-height";
    } else t.growType = "auto-width";
    t.name = o.name || str.replace(/\s+/g, " ").slice(0, 40);
    if (o.parent) {
      o.parent.appendChild(t);
      if (o.fillW) t.layoutChild.horizontalSizing = "fill";
    }
    return t;
  };

  // ---------- boards ----------
  const pad4 = (p) => (p == null ? [0, 0, 0, 0] : typeof p === "number" ? [p, p, p, p] : p.length === 2 ? [p[0], p[1], p[0], p[1]] : p);
  H.box = (name, o) => {
    o = o || {};
    const b = penpot.createBoard();
    b.name = name;
    b.fills = o.bg ? H.fill(o.bg, o.bgOp) : [];
    b.resize(o.w || 100, o.h || 100);
    if (o.r != null) b.borderRadius = o.r;
    if (o.stroke) b.strokes = H.stroke(o.stroke, o.sw || 1, "inner");
    b.clipContent = !!o.clip;
    if (o.x != null) b.x = o.x;
    if (o.y != null) b.y = o.y;
    if (o.dir) {
      const L = b.addFlexLayout();
      L.dir = o.dir;
      L.rowGap = o.gap || 0;
      L.columnGap = o.cgap != null ? o.cgap : o.gap || 0;
      if (o.rgap != null) L.rowGap = o.rgap;
      const p = pad4(o.pad);
      L.topPadding = p[0]; L.rightPadding = p[1]; L.bottomPadding = p[2]; L.leftPadding = p[3];
      L.alignItems = o.ai || "start";
      L.justifyContent = o.jc || "start";
      if (o.wrap) L.wrap = "wrap";
      L.horizontalSizing = o.hs || (o.w ? "fix" : "auto");
      L.verticalSizing = o.vs || (o.h ? "fix" : "auto");
    }
    if (o.parent) H.put(b, o.parent, o);
    return b;
  };
  // append to a parent and apply child sizing
  H.put = (s, parent, o) => {
    o = o || {};
    parent.appendChild(s);
    if (parent.flex || parent.grid) {
      if (o.fillW) s.layoutChild.horizontalSizing = "fill";
      if (o.fillH) s.layoutChild.verticalSizing = "fill";
      if (o.abs) s.layoutChild.absolute = true;
      if (o.self) s.layoutChild.alignSelf = o.self;
      if (o.mt != null) s.layoutChild.topMargin = o.mt;
      if (o.mb != null) s.layoutChild.bottomMargin = o.mb;
      if (o.z != null) s.layoutChild.zIndex = o.z;
    }
    return s;
  };
  H.rect = (name, o) => {
    const r = penpot.createRectangle();
    r.name = name;
    r.resize(o.w, o.h);
    r.fills = o.bg ? H.fill(o.bg, o.bgOp) : [];
    if (o.stroke) r.strokes = H.stroke(o.stroke, o.sw || 1, o.align || "inner");
    if (o.r != null) r.borderRadius = o.r;
    if (o.x != null) r.x = o.x;
    if (o.y != null) r.y = o.y;
    if (o.parent) H.put(r, o.parent, o);
    return r;
  };
  H.ellipse = (name, o) => {
    const e = penpot.createEllipse();
    e.name = name;
    e.resize(o.w, o.h);
    e.fills = o.bg ? H.fill(o.bg, o.bgOp) : [];
    if (o.stroke) e.strokes = H.stroke(o.stroke, o.sw || 1, o.align || "inner");
    else e.strokes = [];
    if (o.x != null) e.x = o.x;
    if (o.y != null) e.y = o.y;
    if (o.parent) H.put(e, o.parent, o);
    return e;
  };
  H.spacer = (parent, w, h, name) => {
    const b = H.box(name || "Spacer", { w: w || 1, h: h || 1 });
    H.put(b, parent);
    return b;
  };

  // ---------- SVG path normaliser (abs M/L/C/Z, arcs -> cubics) ----------
  function parse(d) {
    const segs = [];
    let i = 0, cmd = null;
    const n = d.length;
    const skip = () => { while (i < n && /[\s,]/.test(d[i])) i++; };
    const num = () => {
      skip();
      const m = /^[+-]?(\d*\.\d+|\d+\.?\d*)([eE][+-]?\d+)?/.exec(d.slice(i));
      if (!m) throw new Error("path num at " + i + ": " + d.slice(i, i + 12));
      i += m[0].length;
      return parseFloat(m[0]);
    };
    const flag = () => { skip(); const c = d[i++]; return c === "1" ? 1 : 0; };
    const cnt = { M: 2, L: 2, H: 1, V: 1, C: 6, S: 4, Q: 4, T: 2, A: 7, Z: 0 };
    for (;;) {
      skip();
      if (i >= n) break;
      if (/[MmLlHhVvCcSsQqTtAaZz]/.test(d[i])) cmd = d[i++];
      const up = cmd.toUpperCase();
      if (up === "Z") { segs.push([cmd]); continue; }
      const a = [];
      if (up === "A") a.push(num(), num(), num(), flag(), flag(), num(), num());
      else for (let k = 0; k < cnt[up]; k++) a.push(num());
      segs.push([cmd].concat(a));
      if (cmd === "M") cmd = "L";
      else if (cmd === "m") cmd = "l";
    }
    return segs;
  }
  function a2c(x1, y1, rx, ry, phi, fa, fs, x2, y2) {
    if (!rx || !ry) return [[x1, y1, x2, y2, x2, y2]];
    const rad = (phi * Math.PI) / 180, cs = Math.cos(rad), sn = Math.sin(rad);
    const dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
    const x1p = cs * dx + sn * dy, y1p = -sn * dx + cs * dy;
    rx = Math.abs(rx); ry = Math.abs(ry);
    const lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if (lam > 1) { rx *= Math.sqrt(lam); ry *= Math.sqrt(lam); }
    const rx2 = rx * rx, ry2 = ry * ry;
    let num = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p;
    if (num < 0) num = 0;
    let co = Math.sqrt(num / (rx2 * y1p * y1p + ry2 * x1p * x1p));
    if (fa === fs) co = -co;
    const cxp = (co * rx * y1p) / ry, cyp = (-co * ry * x1p) / rx;
    const cx = cs * cxp - sn * cyp + (x1 + x2) / 2, cy = sn * cxp + cs * cyp + (y1 + y2) / 2;
    const ang = (ux, uy, vx, vy) => Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
    const th1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
    let dth = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry);
    if (!fs && dth > 0) dth -= 2 * Math.PI;
    else if (fs && dth < 0) dth += 2 * Math.PI;
    const segs = Math.max(1, Math.ceil(Math.abs(dth) / (Math.PI / 2) - 1e-9));
    const dd = dth / segs, t = (4 / 3) * Math.tan(dd / 4);
    const P = (x, y) => [cs * rx * x - sn * ry * y + cx, sn * rx * x + cs * ry * y + cy];
    const out = [];
    let th = th1;
    for (let k = 0; k < segs; k++) {
      const c1 = Math.cos(th), s1 = Math.sin(th), c2 = Math.cos(th + dd), s2 = Math.sin(th + dd);
      out.push(P(c1 - t * s1, s1 + t * c1).concat(P(c2 + t * s2, s2 - t * c2), P(c2, s2)));
      th += dd;
    }
    return out;
  }
  function toAbs(segs) {
    let cx = 0, cy = 0, sx = 0, sy = 0, pc = null, pq = null;
    const out = [];
    for (const s of segs) {
      const c = s[0], up = c.toUpperCase(), rel = c !== up, a = s.slice(1);
      const X = (v) => (rel ? v + cx : v), Y = (v) => (rel ? v + cy : v);
      if (up === "M") { cx = X(a[0]); cy = Y(a[1]); sx = cx; sy = cy; out.push(["M", cx, cy]); pc = pq = null; }
      else if (up === "L") { cx = X(a[0]); cy = Y(a[1]); out.push(["L", cx, cy]); pc = pq = null; }
      else if (up === "H") { cx = rel ? cx + a[0] : a[0]; out.push(["L", cx, cy]); pc = pq = null; }
      else if (up === "V") { cy = rel ? cy + a[0] : a[0]; out.push(["L", cx, cy]); pc = pq = null; }
      else if (up === "C") {
        const v = [X(a[0]), Y(a[1]), X(a[2]), Y(a[3]), X(a[4]), Y(a[5])];
        out.push(["C"].concat(v)); pc = [v[2], v[3]]; pq = null; cx = v[4]; cy = v[5];
      } else if (up === "S") {
        const x1 = pc ? 2 * cx - pc[0] : cx, y1 = pc ? 2 * cy - pc[1] : cy;
        const v = [X(a[0]), Y(a[1]), X(a[2]), Y(a[3])];
        out.push(["C", x1, y1].concat(v)); pc = [v[0], v[1]]; pq = null; cx = v[2]; cy = v[3];
      } else if (up === "Q" || up === "T") {
        let qx, qy, x, y;
        if (up === "Q") { qx = X(a[0]); qy = Y(a[1]); x = X(a[2]); y = Y(a[3]); }
        else { qx = pq ? 2 * cx - pq[0] : cx; qy = pq ? 2 * cy - pq[1] : cy; x = X(a[0]); y = Y(a[1]); }
        out.push(["C", cx + (2 / 3) * (qx - cx), cy + (2 / 3) * (qy - cy), x + (2 / 3) * (qx - x), y + (2 / 3) * (qy - y), x, y]);
        pq = [qx, qy]; pc = null; cx = x; cy = y;
      } else if (up === "A") {
        const x = X(a[5]), y = Y(a[6]);
        for (const b of a2c(cx, cy, a[0], a[1], a[2], a[3], a[4], x, y)) out.push(["C"].concat(b));
        cx = x; cy = y; pc = pq = null;
      } else if (up === "Z") { out.push(["Z"]); cx = sx; cy = sy; pc = pq = null; }
    }
    return out;
  }
  const f2 = (v) => String(Math.round(v * 100) / 100);
  // scale a path from a `grid`-sized box to `size`, then offset by (ox, oy)
  H.d = (src, size, ox, oy, grid) => {
    const k = size / (grid || 24);
    return toAbs(parse(src))
      .map((s) => s[0] + s.slice(1).map((v, j) => f2(j % 2 === 0 ? v * k + ox : v * k + oy)).join(","))
      .join("");
  };
  // rounded rect / circle path sources (on any grid)
  H.rr = (x, y, w, h, r) =>
    `M${x + r} ${y}H${x + w - r}A${r} ${r} 0 0 1 ${x + w} ${y + r}V${y + h - r}A${r} ${r} 0 0 1 ${x + w - r} ${y + h}H${x + r}A${r} ${r} 0 0 1 ${x} ${y + h - r}V${y + r}A${r} ${r} 0 0 1 ${x + r} ${y}Z`;
  // counter-clockwise rounded rect: cuts a hole under the nonzero fill rule
  H.rrR = (x, y, w, h, r) =>
    `M${x + r} ${y}A${r} ${r} 0 0 0 ${x} ${y + r}V${y + h - r}A${r} ${r} 0 0 0 ${x + r} ${y + h}H${x + w - r}A${r} ${r} 0 0 0 ${x + w} ${y + h - r}V${y + r}A${r} ${r} 0 0 0 ${x + w - r} ${y}Z`;
  H.circ = (cx, cy, r) => `M${cx - r} ${cy}A${r} ${r} 0 1 1 ${cx + r} ${cy}A${r} ${r} 0 1 1 ${cx - r} ${cy}Z`;

  // ---------- icons (original line icons, 24 grid, 2 px stroke) ----------
  const rr = H.rr, circ = H.circ;
  H.ICONS = {
    "charge-limiter": [rr(2, 7, 17, 10, 2.5), "M21.5 10.5v3", "M5.5 10.5v3", "M8.5 10.5v3", "M14 4v16"],
    discharge: [circ(12, 12, 9), "M12 7.5v8.5", "M8.5 12.5l3.5 3.5 3.5-3.5"],
    heat: ["M10 14.5V5a2 2 0 0 1 4 0v9.5a4.5 4.5 0 1 1-4 0z", "M12 9v8"],
    calibration: ["M3.5 17.5a8.5 8.5 0 0 1 17 0", "M12 17.5l4.2-5.2", "M6.4 12.2l1.2 1", "M12 9v1.6", "M17.6 12.2l-1.2 1", circ(12, 17.5, 1.4)],
    sailing: ["M12 3v14.5", "M12 4.5l6.5 11H12", "M10 7.5l-4.5 8H10", "M3.5 18.5h17l-2.3 2.5H5.8z"],
    stats: ["M4 20.5h16", "M7 17v-5", "M12 17V6.5", "M17 17V9.5"],
    bolt: ["M13 2.5L4.5 13.5H11l-1 8 8.5-11H12z"],
    "limit-reached": [circ(12, 12, 9), "M8 12.4l2.8 2.8 5.2-5.6"],
    schedule: [rr(3, 5, 14.5, 13.5, 2.5), "M7 3v3.5", "M13.5 3v3.5", "M3 10h14.5", circ(17.5, 17.5, 4.5), "M17.5 15.5v2l1.4 1.2"],
    shortcuts: [rr(3, 3, 11.5, 11.5, 3), rr(9.5, 9.5, 11.5, 11.5, 3)],
    sleep: ["M20 13.5A8.5 8.5 0 1 1 10.5 4a7 7 0 0 0 9.5 9.5z"],
    user: [circ(12, 8, 4), "M4.5 20.5a7.5 7.5 0 0 1 15 0"],
    "thumbs-up": ["M7.5 10.5v10", "M7.5 10.5l3.8-7.2a2.3 2.3 0 0 1 3.2 2.2V9h5a2 2 0 0 1 2 2.4l-1.5 7.5a2 2 0 0 1-2 1.6H7.5", "M7.5 20.5H4a1.5 1.5 0 0 1-1.5-1.5v-7A1.5 1.5 0 0 1 4 10.5h3.5"],
    plus: ["M12 5v14", "M5 12h14"],
    menu: ["M4 7h16", "M4 12h16", "M4 17h16"],
    "chevron-down": ["M6 9.5l6 6 6-6"],
    quit: [circ(12, 12, 9), "M9 9l6 6", "M15 9l-6 6"],
    gear: [circ(12, 12, 3.2), "M12 2.8v2.6M12 18.6v2.6M2.8 12h2.6M18.6 12h2.6M5.5 5.5l1.8 1.8M16.7 16.7l1.8 1.8M5.5 18.5l1.8-1.8M16.7 7.3l1.8-1.8", circ(12, 12, 6.8)],
    dashboard: [rr(3, 3, 7.5, 9, 2), rr(13.5, 3, 7.5, 5.5, 2), rr(3, 15, 7.5, 6, 2), rr(13.5, 11.5, 7.5, 9.5, 2)],
    plug: ["M9 3v5M15 3v5", "M6.5 8h11v3.5a5.5 5.5 0 0 1-11 0z", "M12 17v4"],
    laptop: [rr(4.5, 5, 15, 10.5, 1.5), "M2.5 18.5h19"],
    minus: ["M5 12h14"],
    search: [circ(10.5, 10.5, 6.5), "M15.5 15.5l5 5"],
    check: ["M5 12.5l4.5 4.5L19 7.5"],
    "arrow-right": ["M4.5 12h15", "M13.5 6l6 6-6 6"],
    // social glyphs (GitHub after Feather's MIT-licensed outline; the others drawn here)
    github: ["M9 19c-5 1.5-5-2.5-7-3m14 6v-3.87a3.37 3.37 0 0 0-.94-2.61c3.14-.35 6.44-1.54 6.44-7A5.44 5.44 0 0 0 20 4.77 5.07 5.07 0 0 0 19.91 1S18.73.65 16 2.48a13.38 13.38 0 0 0-7 0C6.27.65 5.09 1 5.09 1A5.07 5.07 0 0 0 5 4.77a5.44 5.44 0 0 0-1.5 3.78c0 5.42 3.3 6.61 6.44 7A3.37 3.37 0 0 0 9 18.13V22"],
    x: ["M4 4l11 16h5L9 4z", "M20 4l-6.6 7.4", "M10.6 12.6L4 20"],
    youtube: [rr(2, 5, 20, 14, 4), "M10 9l5 3-5 3z"],
    mastodon: ["M20.5 9c0-4-2.6-5-2.6-5-1.3-.6-3.5-.9-5.8-.9h-.2c-2.3 0-4.5.3-5.8.9 0 0-2.6 1-2.6 5v3c.1 3.6.7 7.2 4 8 1.6.4 3 .5 4.1.5 2 0 3.2-.6 3.2-.6l-.1-1.6s-1.4.5-3 .4c-1.6-.1-3.3-.2-3.5-2.2v-.6s1.6.4 3.6.5c1.2 0 2.3-.1 3.4-.2 2.1-.3 3.9-1.6 4.1-2.8.4-1.9.2-4.4.2-4.4z", "M8.5 13.5V9.8c0-1 .7-1.8 1.7-1.8s1.8.8 1.8 1.8V12", "M12 12V9.8c0-1 .8-1.8 1.8-1.8s1.7.8 1.7 1.8v3.7"],
  };
  // draw an icon glyph as one stroked path; returns the path (absolute coords at ox, oy)
  H.glyph = (key, size, ox, oy, o) => {
    o = o || {};
    const p = penpot.createPath();
    p.content = H.ICONS[key].map((s) => H.d(s, size, ox, oy)).join("");
    p.name = o.name || "Glyph";
    p.fills = [];
    p.strokes = H.stroke(o.color || "g700", o.sw || 2, "center", { strokeCapStart: "round", strokeCapEnd: "round" });
    return p;
  };
  // an icon in a fixed transparent board (keeps the 24 grid box)
  H.icon = (key, size, o) => {
    o = o || {};
    const b = H.box(o.name || "Icon / " + key, { w: size, h: size, x: o.x || 0, y: o.y || 0 });
    const g = H.glyph(key, size, b.x, b.y, { color: o.color, sw: o.sw != null ? o.sw : (2 * size) / 24 > 3 ? 3 : Math.max(1.5, (2 * size) / 24) });
    b.appendChild(g);
    g.constraintsHorizontal = "scale";
    g.constraintsVertical = "scale";
    if (o.parent) H.put(b, o.parent, o);
    return b;
  };

  // ---------- app icon (all paths so instances scale cleanly) ----------
  H.appIcon = (S, x, y, name) => {
    const b = H.box(name || "App icon", { w: S, h: S, x: x || 0, y: y || 0 });
    const k = S / 512;
    const P = (d, fill, nm) => {
      const p = penpot.createPath();
      p.content = H.d(d, S, b.x, b.y, 512);
      p.name = nm;
      p.fills = H.fill(fill);
      p.strokes = [];
      b.appendChild(p);
      p.constraintsHorizontal = "scale";
      p.constraintsVertical = "scale";
      return p;
    };
    P(H.rr(0, 0, 512, 512, 112.64), H.G.icon, "Icon background");
    // battery ring: outer and inner rounded rects (even-odd hole), stroke 8 % of the icon
    const t = 41, bx = 96, by = 168, bw = 296, bh = 176, br = 35;
    P(H.rr(bx, by, bw, bh, br) + H.rrR(bx + t, by + t, bw - 2 * t, bh - 2 * t, Math.max(4, br - t * 0.6)), "white", "Battery outline");
    P(`M${bx + bw - 2} ${by + 56}H${bx + bw + 20}a8 8 0 0 1 8 8v48a8 8 0 0 1-8 8H${bx + bw - 2}z`, "white", "Battery tip");
    const lx = bx + bw * 0.7; // limit line at 70 % of the battery width
    P(H.rr(bx + t + 16, by + t + 16, lx - 14 - (bx + t + 16) - 10, bh - 2 * t - 32, 3), "white", "Charge level");
    P(H.rr(lx - 10, by - 40, 20, bh + 80, 2), "yel", "Limit line");
    return b;
  };

  // ---------- pages, cleanup, jobs ----------
  H.page = async (name) => {
    let p = penpot.currentFile.pages.find((p) => p.name === name);
    if (!p) { p = penpot.createPage(); p.name = name; await H.sleep(300); }
    if (penpot.currentPage.id !== p.id) { penpot.openPage(p); await H.sleep(900); }
    return penpot.currentPage;
  };
  H.kill = (name, root) => {
    const r = root || penpot.root;
    const xs = penpotUtils.findShapes((s) => s.name === name && s.parent && s.parent.id === r.id, r);
    xs.forEach((s) => s.remove());
    return xs.length;
  };
  H.run = (name, fn) => {
    storage.jobs = storage.jobs || {};
    const t0 = Date.now();
    storage.jobs[name] = { st: "run" };
    setTimeout(async () => {
      try {
        const r = await fn();
        storage.jobs[name] = { st: "ok", r, ms: Date.now() - t0 };
      } catch (e) {
        storage.jobs[name] = { st: "err", e: String((e && e.stack) || e).slice(0, 600) };
      }
    }, 0);
    return "started " + name;
  };
  // texts sometimes collapse to 1 px right after creation; toggling grow type re-measures them
  H.fixText = async (root) => {
    const ts = penpotUtils.findShapes((s) => s.type === "text" && (s.width <= 1.5 || s.height <= 1.5), root);
    for (const t of ts) {
      const g = t.growType === "fixed" ? "auto-width" : t.growType;
      t.growType = "fixed";
      t.growType = g;
    }
    await H.sleep(ts.length ? 400 : 0);
    return ts.length;
  };
  H.count = (s) => penpotUtils.findShapes(() => true, s).length;

  // ---------- components ----------
  // the shape keeps only the leaf name; the component name carries the path
  H.mkComp = (shape, fullName) => {
    shape.name = fullName.split(" / ").pop();
    const c = penpot.library.local.createComponent([shape]);
    c.name = fullName;
    return c;
  };
  H.inst = (name, parent, o) => {
    const c = H.comp(name);
    if (!c) throw new Error("no component " + name);
    const i = c.instance();
    if (o && o.name) i.name = o.name;
    if (parent) H.put(i, parent, o);
    return i;
  };
  // never search globally: a null root would silently match shapes on other boards
  H.find = (root, name) => (root ? penpotUtils.findShape((s) => s.name === name, root) : null);
  H.setText = (root, name, str) => {
    const t = H.find(root, name);
    if (t) t.characters = str;
    return t;
  };
  return H;
})()
