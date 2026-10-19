// Manichino 3D per l'esecuzione degli esercizi: lo stesso calcolo di Manichino.swift (app), qui per provarlo nel browser.
// Il corpo è fatto di capsule (proiezione ortografica: una capsula 3D diventa una capsula 2D), ordinate per profondità.
// Assi del corpo: x = destra della persona, y = su, z = avanti. Unità: metri. Pavimento a y = 0.
"use strict";
const D2R = Math.PI / 180;
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const mul = (a, k) => [a[0] * k, a[1] * k, a[2] * k];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const len = (a) => Math.sqrt(dot(a, a));
const unit = (a, d) => { const l = len(a); return l < 1e-6 ? (d || [0, 0, 1]) : mul(a, 1 / l); };
const perp = (h, u, d) => unit(sub(h, mul(u, dot(h, u))), d);   // parte di h perpendicolare a u
const mid = (a, b) => mul(add(a, b), 0.5);
const rotX = (v, a) => { const c = Math.cos(a), s = Math.sin(a); return [v[0], v[1] * c - v[2] * s, v[1] * s + v[2] * c]; };
const rotY = (v, a) => { const c = Math.cos(a), s = Math.sin(a); return [v[0] * c + v[2] * s, v[1], -v[0] * s + v[2] * c]; };
const rotZ = (v, a) => { const c = Math.cos(a), s = Math.sin(a); return [v[0] * c - v[1] * s, v[0] * s + v[1] * c, v[2]]; };

// misure del corpo (1,73 m)
const M = { vita: 0.22, petto: 0.30, spalla: 0.19, anca: 0.09, braccio: 0.29, avambraccio: 0.26, coscia: 0.43, gamba: 0.42 };

// direzione di un arto da due angoli: φ = piano (0 di lato, 90 avanti, −90 indietro), θ = alzata (0 giù, 90 orizzontale, 180 su)
function dirArto(side, fi, te) {
  fi *= D2R; te *= D2R;
  return [side * Math.cos(fi) * Math.sin(te), -Math.cos(te), Math.sin(fi) * Math.sin(te)];
}

// posa → punti del corpo e direzioni utili (gomito, ginocchio) per i muscoli
function corpo(q) {
  const t = (q.t || 0) * D2R, ro = (q.ro || 0) * D2R, ya = (q.ya || 0) * D2R, cu = (q.c || 0) * D2R;
  const Fp = (v) => rotY(rotZ(rotX(v, t), ro), ya);       // bacino
  const Fc = (v) => Fp(rotX(v, cu));                      // petto (si curva sul bacino: crunch)
  const P = q.p || [0, 0.97, 0];
  const pt = {}, dir = {};
  pt.pelvi = P;
  pt.vita = add(P, Fp([0, M.vita, 0]));
  pt.collo = add(pt.vita, Fc([0, M.petto, 0]));
  const dt = Fc(rotX([0, 1, 0], (q.hp || 0) * D2R));
  pt.testa = add(pt.collo, mul(dt, 0.17));
  pt.nuca = add(pt.collo, mul(dt, 0.07));
  dir.su_p = Fp([0, 1, 0]); dir.av_p = Fp([0, 0, 1]); dir.dx = Fp([1, 0, 0]);
  dir.su_c = Fc([0, 1, 0]); dir.av_c = Fc([0, 0, 1]); dir.dx_c = Fc([1, 0, 0]);
  pt.trapezi = add(add(pt.collo, mul(dir.av_c, -0.1)), mul(dir.su_c, -0.02));   // dove appoggia il bilanciere dello squat
  for (const [lato, side] of [["r", 1], ["l", -1]]) {
    // braccio: [φ, θ, gomito, verso del gomito x, y, z]
    const a = (side === 1 ? q.ra : (q.la || q.ra)) || [0, 6, 8, 0, 0, 1];
    const u = dirArto(side, a[0], a[1]);
    const h = [side * (a[3] ?? 0), a[4] ?? 0, a[5] ?? 1];
    const b = perp(h, u, [0, 0, 1]);
    const eps = a[2] * D2R;
    const f = add(mul(u, Math.cos(eps)), mul(b, Math.sin(eps)));
    const S = add(pt.collo, Fc([side * M.spalla, -0.05, -0.01]));
    const uw = Fc(u), fw = Fc(f), bw = Fc(b);
    pt["spalla_" + lato] = S;
    pt["gomito_" + lato] = add(S, mul(uw, M.braccio));
    pt["polso_" + lato] = add(pt["gomito_" + lato], mul(fw, M.avambraccio));
    pt["mano_" + lato] = add(pt["polso_" + lato], mul(fw, 0.05));
    dir["braccio_" + lato] = uw; dir["avambraccio_" + lato] = fw; dir["piega_" + lato] = bw;
    // gamba: [φ, θ, ginocchio, punta del piede]
    const g = (side === 1 ? q.rl : (q.ll || q.rl)) || [90, 0, 0, 0];
    const tl = dirArto(side, g[0], g[1]);
    const bk = perp([0, -tl[2], tl[1]], tl, [0, 0, -1]);        // il ginocchio piega all'indietro
    const ka = g[2] * D2R;
    const sl = add(mul(tl, Math.cos(ka)), mul(bk, Math.sin(ka)));
    const fwd = perp([0, sl[2], -sl[1]], sl, [0, 0, 1]);        // davanti alla gamba
    const pa = (g[3] || 0) * D2R;
    const fo = add(mul(fwd, Math.cos(pa)), mul(sl, Math.sin(pa)));
    const dietro = perp([0, -sl[2], sl[1]], sl, [0, 0, -1]);    // lato del polpaccio
    const H = add(P, Fp([side * M.anca, -0.03, 0]));
    const tw = Fp(tl), sw = Fp(sl), fow = Fp(fo), bkw = Fp(bk), dw = Fp(dietro);
    pt["anca_" + lato] = H;
    pt["ginocchio_" + lato] = add(H, mul(tw, M.coscia));
    pt["caviglia_" + lato] = add(pt["ginocchio_" + lato], mul(sw, M.gamba));
    const base = add(pt["caviglia_" + lato], mul(sw, 0.045));
    pt["tallone_" + lato] = add(base, mul(fow, -0.05));
    pt["punta_" + lato] = add(base, mul(fow, 0.16));
    pt["caviglia_" + lato + "_dietro"] = add(pt["caviglia_" + lato], mul(dw, 0.075));
    pt["caviglia_" + lato + "_davanti"] = add(pt["caviglia_" + lato], mul(dw, -0.07));
    pt["pianta_" + lato] = add(mid(pt["tallone_" + lato], pt["punta_" + lato]), mul(sw, 0.035));
    dir["coscia_" + lato] = tw; dir["gamba_" + lato] = sw; dir["piegag_" + lato] = bkw; dir["polpaccio_" + lato] = dw;
  }
  pt.mani = mid(pt.mano_r, pt.mano_l);
  pt.spalle = mid(pt.spalla_r, pt.spalla_l);
  pt.caviglie = mid(pt.caviglia_r, pt.caviglia_l);
  pt.piedi = mid(pt.pianta_r, pt.pianta_l);
  pt.punte = mid(pt.punta_r, pt.punta_l);
  pt.ginocchia = mid(pt.ginocchio_r, pt.ginocchio_l);
  return { pt, dir, Fp, Fc };
}

// muscoli: nomi dell'app → pezzi rossi sopra al corpo (con la direzione verso cui guardano, per nasconderli se sono dietro)
const MUSCOLI = {
  "Petto": "petto", "Dorsali": "dorsali", "Deltoidi laterali": "delt_lat", "Deltoidi anteriori": "delt_ant",
  "Deltoidi posteriori": "delt_post", "Bicipiti": "bicipiti", "Tricipiti": "tricipiti", "Quadricipiti": "quadricipiti",
  "Femorali": "femorali", "Glutei": "glutei", "Polpacci": "polpacci", "Addome": "addome",
};

function primitiveCorpo(c) {
  const { pt, dir, Fp, Fc } = c;
  const L = [];
  const cap = (a, b, r, tag) => L.push({ k: "cap", a, b, r, col: "corpo", tag });
  cap(pt.anca_l, pt.anca_r, 0.1, "bacino");
  cap(pt.pelvi, pt.vita, 0.115, "pancia");
  cap(pt.vita, add(pt.collo, mul(dir.su_c, -0.04)), 0.135, "torace");
  cap(pt.spalla_l, pt.spalla_r, 0.072, "spalle");
  cap(pt.collo, pt.nuca, 0.048, "collo");
  L.push({ k: "sfera", c: pt.testa, r: 0.1, col: "corpo", tag: "testa" });
  for (const s of ["r", "l"]) {
    cap(pt["spalla_" + s], pt["gomito_" + s], 0.052, "braccio_" + s);
    cap(pt["gomito_" + s], pt["polso_" + s], 0.043, "avambraccio_" + s);
    cap(pt["polso_" + s], pt["mano_" + s], 0.038, "mano_" + s);
    cap(pt["anca_" + s], pt["ginocchio_" + s], 0.078, "coscia_" + s);
    cap(pt["ginocchio_" + s], pt["caviglia_" + s], 0.056, "gamba_" + s);
    cap(pt["tallone_" + s], pt["punta_" + s], 0.042, "piede_" + s);
  }
  return L;
}

// pezzi rossi: principale = 1, secondario = 0.45
function primitiveMuscoli(c, principale, secondari) {
  const { pt, dir, Fp, Fc } = c;
  const L = [];
  const mus = (nome, forza) => {
    const k = MUSCOLI[nome]; if (!k) return;
    const m = (o) => Object.assign(o, { col: "muscolo", forza });
    for (const [s, side] of [["r", 1], ["l", -1]]) {
      const S = pt["spalla_" + s];
      if (k === "petto") L.push(m({ k: "cap", a: add(pt.collo, Fc([side * 0.025, -0.13, 0.085])), b: add(pt.collo, Fc([side * 0.12, -0.1, 0.07])), r: 0.062, o: dir.av_c, sopra: "torace" }));
      if (k === "dorsali") L.push(m({ k: "cap", a: add(pt.collo, Fc([side * 0.13, -0.1, -0.06])), b: add(pt.vita, Fc([side * 0.085, 0.03, -0.075])), r: 0.06, o: unit(add(mul(dir.dx_c, side * 0.6), mul(dir.av_c, -1))), sopra: "torace" }));
      if (k === "addome" && s === "r") L.push(m({ k: "cap", a: add(pt.pelvi, Fp([0, 0.04, 0.065])), b: add(pt.vita, Fc([0, 0.06, 0.08])), r: 0.062, o: dir.av_p, sopra: "pancia" }));
      if (k.startsWith("delt")) {
        const off = k === "delt_lat" ? [side * 0.03, 0.005, 0] : k === "delt_ant" ? [side * 0.012, 0, 0.03] : [side * 0.012, 0, -0.03];
        L.push(m({ k: "sfera", c: add(S, Fc(off)), r: 0.06, o: unit(Fc(off)), sopra: "braccio_" + s }));
      }
      const u = dir["braccio_" + s], b = dir["piega_" + s];
      if (k === "bicipiti" || k === "tricipiti") {
        const o = k === "bicipiti" ? b : mul(b, -1);
        L.push(m({ k: "cap", a: add(add(S, mul(u, 0.08)), mul(o, 0.026)), b: add(add(S, mul(u, 0.23)), mul(o, 0.026)), r: 0.036, o, sopra: "braccio_" + s }));
      }
      const H = pt["anca_" + s], tw = dir["coscia_" + s], bk = dir["piegag_" + s];
      if (k === "quadricipiti" || k === "femorali") {
        const o = k === "femorali" ? bk : mul(bk, -1);
        L.push(m({ k: "cap", a: add(add(H, mul(tw, 0.09)), mul(o, 0.03)), b: add(add(H, mul(tw, 0.36)), mul(o, 0.03)), r: 0.054, o, sopra: "coscia_" + s }));
      }
      if (k === "glutei") L.push(m({ k: "sfera", c: add(H, Fp([side * 0.015, -0.02, -0.07])), r: 0.075, o: mul(dir.av_p, -1), sopra: "bacino" }));
      if (k === "polpacci") {
        const K = pt["ginocchio_" + s], sw = dir["gamba_" + s], o = dir["polpaccio_" + s];
        L.push(m({ k: "cap", a: add(add(K, mul(sw, 0.06)), mul(o, 0.024)), b: add(add(K, mul(sw, 0.24)), mul(o, 0.024)), r: 0.043, o, sopra: "gamba_" + s }));
      }
    }
  };
  mus(principale, 1);
  for (const x of secondari || []) mus(x, 0.45);
  return L;
}

// attrezzi: estremi fissi [x,y,z] oppure attaccati a un punto del corpo {pt, off}
function risolvi(e, pt) {
  if (Array.isArray(e)) return e;
  const nomi = Array.isArray(e.pt) ? e.pt : [e.pt];
  let p = [0, 0, 0];
  for (const n of nomi) p = add(p, pt[n]);
  return add(mul(p, 1 / nomi.length), e.off || [0, 0, 0]);
}

function primitiveAttrezzi(lista, pt) {
  const L = [];
  for (const a of lista || []) {
    if (a.k === "cap") L.push({ k: "cap", a: risolvi(a.a, pt), b: risolvi(a.b, pt), r: a.r, col: a.col || "metallo" });
    else if (a.k === "sfera") L.push({ k: "sfera", c: risolvi(a.c, pt), r: a.r, col: a.col || "metallo" });
    else if (a.k === "disco") L.push({ k: "disco", c: risolvi(a.c, pt), n: a.n, R: a.R, col: a.col || "disco" });
    else if (a.k === "box") L.push({ k: "box", c: risolvi(a.c, pt), s: a.s, rx: a.rx || 0, col: a.col || "scuro" });
    else if (a.k === "linea") L.push({ k: "linea", a: risolvi(a.a, pt), b: risolvi(a.b, pt), w: a.w || 0.012, col: a.col || "cavo" });
  }
  return L;
}

// posa intermedia tra A e B (k da 0 a 1)
function mescola(A, B, k) {
  const out = {};
  for (const key of new Set([...Object.keys(A), ...Object.keys(B)])) {
    const a = A[key] ?? B[key], b = B[key] ?? A[key];
    out[key] = Array.isArray(a) ? a.map((v, i) => v + ((b[i] ?? v) - v) * k) : (typeof a === "number" ? a + (b - a) * k : a);
  }
  return out;
}

// tutta la scena in un istante: corpo, muscoli, attrezzi, spostata perché il punto «fisso» resti dov'è
function scena(m, k, muscolo, secondari) {
  const q = mescola(m.A, m.B, k);
  let c = corpo(q);
  if (m.fisso) {
    const d = sub(m.fisso.a, risolvi({ pt: m.fisso.pt }, c.pt));
    q.p = add(q.p || [0, 0.97, 0], d);
    c = corpo(q);
  }
  return [...primitiveCorpo(c), ...primitiveMuscoli(c, muscolo, secondari), ...primitiveAttrezzi(m.attrezzi, c.pt)];
}

// tempo: [salita, fermo, discesa, pausa] in secondi → fase e avanzamento
const ease = (x) => x * x * (3 - 2 * x);
function fase(tempo, s) {
  const [su, fe, giu, pa] = tempo;
  let x = s % (su + fe + giu + pa);
  if (x < su) return { k: ease(x / su), f: 0, p: x / su };
  x -= su; if (x < fe) return { k: 1, f: 1, p: x / Math.max(fe, 1e-6) };
  x -= fe; if (x < giu) return { k: 1 - ease(x / giu), f: 2, p: x / giu };
  x -= giu; return { k: 0, f: 3, p: x / Math.max(pa, 1e-6) };
}

// ---------- disegno ----------
const COLORI = {
  corpo: [212, 215, 219], metallo: [120, 123, 130], scuro: [52, 53, 58], cuscino: [66, 67, 74], disco: [70, 72, 78], cavo: [150, 153, 160],
};
const ROSSO = [229, 72, 59];

function vista(v, cam) {
  const a = cam.yaw * D2R, b = cam.pitch * D2R;
  const x = v[0] * Math.cos(a) + v[2] * Math.sin(a);
  const d0 = -v[0] * Math.sin(a) + v[2] * Math.cos(a);
  return [x, v[1] * Math.cos(b) - d0 * Math.sin(b), v[1] * Math.sin(b) + d0 * Math.cos(b)];
}

function vertiBox(p) {
  const [w, h, d] = p.s.map((x) => x / 2);
  const V = [];
  for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const sz of [-1, 1]) V.push(add(p.c, rotX([sx * w, sy * h, sz * d], p.rx * D2R)));
  return V;
}

// inquadratura: tutti i punti di A, metà e B devono stare dentro
function inquadra(m, cam, W, H, muscolo, sec) {
  let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
  for (const k of [0, 0.5, 1]) {
    for (const p of scena(m, k, muscolo, sec)) {
      const pts = p.k === "cap" || p.k === "linea" ? [p.a, p.b] : p.k === "box" ? vertiBox(p) : [p.c];
      const r = p.r || p.R || 0;
      for (const v of pts) {
        const s = vista(v, cam);
        x0 = Math.min(x0, s[0] - r); x1 = Math.max(x1, s[0] + r); y0 = Math.min(y0, s[1] - r); y1 = Math.max(y1, s[1] + r);
      }
    }
  }
  const sc = Math.min((W * 0.84) / (x1 - x0), (H * 0.82) / (y1 - y0));
  return { sc, cx: W / 2 - ((x0 + x1) / 2) * sc, cy: H / 2 + ((y0 + y1) / 2) * sc };
}

function disegna(ctx, W, H, m, k, cam, fr, muscolo, sec) {
  const prim = scena(m, k, muscolo, sec);
  const P = (v) => { const s = vista(v, cam); return [fr.cx + s[0] * fr.sc, fr.cy - s[1] * fr.sc, s[2]]; };
  // ombra sul pavimento
  ctx.save();
  const o = P([0, 0, 0]);
  const g = ctx.createRadialGradient(o[0], o[1], 0, o[0], o[1], 0.75 * fr.sc);
  g.addColorStop(0, "rgba(0,0,0,0.45)"); g.addColorStop(1, "rgba(0,0,0,0)");
  ctx.fillStyle = g; ctx.beginPath();
  ctx.ellipse(o[0], o[1], 0.75 * fr.sc, 0.75 * fr.sc * Math.max(0.12, Math.abs(Math.sin(cam.pitch * D2R))), 0, 0, Math.PI * 2); ctx.fill();
  ctx.restore();
  // profondità di ogni pezzo (i muscoli subito sopra il loro pezzo)
  const prof = (p) => {
    if (p.k === "cap" || p.k === "linea") return vista(mid(p.a, p.b), cam)[2];
    if (p.k === "box") return vista(p.c, cam)[2] - 0.02;
    return vista(p.c, cam)[2];
  };
  const perTag = {};
  for (const p of prim) if (p.tag) perTag[p.tag] = prof(p);
  const voci = prim.map((p, i) => ({ p, d: p.col === "muscolo" ? (perTag[p.sopra] ?? prof(p)) + 0.0005 : prof(p), i }));
  voci.sort((a, b) => a.d - b.d || a.i - b.i);
  const ds = voci.filter((v) => v.p.col === "corpo").map((v) => v.d);
  const dmin = Math.min(...ds), dmax = Math.max(...ds);
  for (const { p, d } of voci) {
    const luce = 0.62 + 0.38 * Math.min(1, Math.max(0, (d - dmin) / Math.max(1e-3, dmax - dmin)));
    let col = p.col === "muscolo" ? ROSSO : COLORI[p.col] || COLORI.metallo;
    let alpha = 1;
    if (p.col === "muscolo") {
      const oz = vista(p.o, cam)[2];
      alpha = Math.min(1, Math.max(0, (oz + 0.3) / 0.45)) * p.forza;
      if (alpha <= 0.02) continue;
    }
    const lum = p.col === "corpo" || p.col === "muscolo" ? luce : 0.85 + 0.15 * luce;
    if (p.k === "cap") capsula(ctx, P(p.a), P(p.b), p.r * fr.sc, col, lum, alpha, p.col === "muscolo");
    else if (p.k === "sfera") sfera(ctx, P(p.c), p.r * fr.sc, col, lum, alpha, p.col === "muscolo");
    else if (p.k === "linea") { const a = P(p.a), b = P(p.b); ctx.strokeStyle = rgb(col, 1); ctx.lineWidth = Math.max(1.2, p.w * fr.sc); ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke(); }
    else if (p.k === "disco") disco(ctx, p, cam, P, fr.sc, col);
    else if (p.k === "box") scatola(ctx, p, cam, P, col);
  }
}

const rgb = (c, k, a = 1) => `rgba(${Math.round(Math.min(255, c[0] * k))},${Math.round(Math.min(255, c[1] * k))},${Math.round(Math.min(255, c[2] * k))},${a})`;

// capsula con la sfumatura di un cilindro: luce dall'alto a sinistra
function capsula(ctx, a, b, r, col, lum, alpha, muscolo) {
  let nx = -(b[1] - a[1]), ny = b[0] - a[0];
  const l = Math.hypot(nx, ny) || 1; nx /= l; ny /= l;
  if (nx * -0.6 + ny * -0.8 < 0) { nx = -nx; ny = -ny; }
  const m = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
  const g = ctx.createLinearGradient(m[0] + nx * r, m[1] + ny * r, m[0] - nx * r, m[1] - ny * r);
  g.addColorStop(0, rgb(col, lum * 1.12, alpha)); g.addColorStop(0.35, rgb(col, lum, alpha)); g.addColorStop(1, rgb(col, lum * 0.5, alpha));
  ctx.save();
  if (muscolo) { ctx.shadowColor = `rgba(229,72,59,${0.6 * alpha})`; ctx.shadowBlur = r * 0.9; }
  ctx.strokeStyle = g; ctx.lineWidth = r * 2; ctx.lineCap = "round";
  ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0] + (Math.abs(b[0] - a[0]) + Math.abs(b[1] - a[1]) < 0.01 ? 0.01 : 0), b[1]); ctx.stroke();
  ctx.restore();
}

function sfera(ctx, c, r, col, lum, alpha, muscolo) {
  const g = ctx.createRadialGradient(c[0] - r * 0.35, c[1] - r * 0.4, r * 0.1, c[0], c[1], r);
  g.addColorStop(0, rgb(col, lum * 1.15, alpha)); g.addColorStop(0.6, rgb(col, lum, alpha)); g.addColorStop(1, rgb(col, lum * 0.55, alpha));
  ctx.save();
  if (muscolo) { ctx.shadowColor = `rgba(229,72,59,${0.6 * alpha})`; ctx.shadowBlur = r * 0.9; }
  ctx.fillStyle = g; ctx.beginPath(); ctx.arc(c[0], c[1], r, 0, Math.PI * 2); ctx.fill();
  ctx.restore();
}

function disco(ctx, p, cam, P, sc, col) {
  const c = P(p.c), n = vista(p.n, cam);
  const nl = Math.hypot(n[0], n[1]);
  const ang = nl < 1e-4 ? 0 : Math.atan2(-n[1], n[0]);
  const rx = p.R * sc * Math.max(0.12, Math.abs(n[2])), ry = p.R * sc;
  ctx.save();
  ctx.translate(c[0], c[1]); ctx.rotate(ang);
  const g = ctx.createLinearGradient(0, -ry, 0, ry);
  g.addColorStop(0, rgb(col, 1.35)); g.addColorStop(1, rgb(col, 0.7));
  ctx.fillStyle = g; ctx.beginPath(); ctx.ellipse(0, 0, rx, ry, 0, 0, Math.PI * 2); ctx.fill();
  ctx.strokeStyle = rgb(col, 1.7, 0.5); ctx.lineWidth = 1; ctx.stroke();
  ctx.restore();
}

function scatola(ctx, p, cam, P, col) {
  const V = vertiBox(p);   // indice = sx*4 + sy*2 + sz (0 = −, 1 = +)
  const facce = [[[0, 1, 3, 2], [-1, 0, 0]], [[4, 6, 7, 5], [1, 0, 0]], [[0, 4, 5, 1], [0, -1, 0]], [[2, 3, 7, 6], [0, 1, 0]], [[0, 2, 6, 4], [0, 0, -1]], [[1, 5, 7, 3], [0, 0, 1]]];
  for (const [idx, n0] of facce) {
    const n = vista(rotX(n0, p.rx * D2R), cam);
    if (n[2] <= 0.001) continue;
    const luce = 0.75 + 0.45 * Math.max(0, n[1]) + 0.1 * n[0];
    ctx.fillStyle = rgb(col, luce);
    ctx.beginPath();
    idx.forEach((i, j) => { const q = P(V[i]); j ? ctx.lineTo(q[0], q[1]) : ctx.moveTo(q[0], q[1]); });
    ctx.closePath(); ctx.fill();
    ctx.strokeStyle = rgb(col, luce * 1.25, 0.6); ctx.lineWidth = 0.8; ctx.stroke();
  }
}

if (typeof module !== "undefined") module.exports = { scena, fase, corpo };
