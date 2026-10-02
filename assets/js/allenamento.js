'use strict';
// Allenamento stile Hevy: routine modificabili, allenamento live con colonna "Precedente",
// timer di recupero automatico, cronologia con calendario, record personali e statistiche.
// Usa le utilità di app.js tramite window.RCK (impostato da app.js prima del primo render).
(function () {
  const W = {};
  window.RCW = W;
  const K = () => window.RCK;

  const ui = { tab: 'routine', edit: null, draft: null, picker: null, detail: null, summary: null, month: null, exDetail: null, muscle: '' };

  /* ---------------- dati ---------------- */
  const lib = () => ({ ...K().D.exlib, ...K().store.get('exlib', {}) });
  const exOf = (id) => lib()[id] || { id, n: id, m: 'Altro', sec: [], inc: 2.5, unit: 'reps', eq: '', cue: '' };
  const isWork = (s) => s.type !== 'w';
  // esecuzione: due foto reali (inizio / fine del movimento) alternate come una GIF
  const IMG = (id, f) => `assets/esercizi/${id}-${f}.jpg`;
  function anim(e, size) {
    if (!e.img) return size === 'sm' ? `<button type="button" class="exanim sm none" data-w="exanim" data-ex="${e.id}" aria-label="Muscoli allenati da ${K().esc(e.n)}">${bodyMap(e, true)}</button>` : '';
    const tag = size === 'lg' ? 'div' : 'button';
    const attrs = size === 'lg' ? 'role="img" aria-label="Esecuzione di ' + K().esc(e.n) + '"' : `type="button" data-w="exanim" data-ex="${e.id}" aria-label="Guarda l'esecuzione di ${K().esc(e.n)}"`;
    return `<${tag} class="exanim ${size}" ${attrs}><img src="${IMG(e.img, 0)}" alt="" loading="lazy" decoding="async"><img class="t" src="${IMG(e.img, 1)}" alt="" loading="lazy" decoding="async"></${tag}>`;
  }
  // mappa dei muscoli: sagoma davanti / dietro, metà destra disegnata e specchiata
  const BODY = {
    f: [
      [null, 'M0 26h5v9H0z'],
      ['Deltoidi anteriori', 'M15 36q9-4 13 3l-3 12q-6-3-10-9z'],
      ['Deltoidi laterali', 'M28 39q5 5 3 15l-5 2-1-5z'],
      ['Petto', 'M1 37l13-1q3 8 8 13-8 9-21 7z'],
      ['Bicipiti', 'M24 55q7 1 8 10l-2 17q-5 0-7-8z'],
      [null, 'M24 84h7q2 15-1 30h-5q-3-15-1-30z'],
      ['Addome', 'M1 60h12l-1 41-11 1z'],
      ['Addome', 'M15 58q6 5 5 21l-2 21h-4z'],
      [null, 'M1 104l17-2 3 10-20 7z'],
      ['Quadricipiti', 'M3 121q8-10 19-9 3 19-2 48-8 6-14 0-5-19-3-39z'],
      [null, 'M6 162h13v6H6z'],
      ['Polpacci', 'M7 170q7-2 12 0 1 22-3 42h-6q-4-22-3-42z'],
      [null, 'M9 214h8l2 8H8z'],
    ],
    b: [
      [null, 'M0 26h5v9H0z'],
      [null, 'M1 32l9 2 13 3-12 8-10 14z'],
      ['Deltoidi posteriori', 'M17 37q10-3 13 6l-2 11q-6-3-11-9z'],
      ['Deltoidi laterali', 'M30 43q3 5 1 11l-3 1z'],
      ['Dorsali', 'M3 50q12-3 21 4-2 18-10 36H3z'],
      ['Tricipiti', 'M24 56q7 0 8 8l-1 18q-5 0-8-8z'],
      [null, 'M24 84h7q2 15-1 30h-5q-3-15-1-30z'],
      [null, 'M1 92h13l2 12-15 2z'],
      ['Glutei', 'M1 107q17-5 21 5 0 16-10 18-8 0-11-6z'],
      ['Femorali', 'M3 132q9-2 18-2 2 16-2 32-7 4-13 0-4-16-3-30z'],
      [null, 'M6 164h13v4H6z'],
      ['Polpacci', 'M7 170q8-4 13 2 0 18-5 34h-5q-5-18-3-36z'],
      [null, 'M9 208h7l1 14H8z'],
    ],
  };
  function bodyMap(e, mini) {
    const sec = new Set(e.sec || []);
    const cls = (m) => (!m ? 'bm-x' : m === e.m ? 'bm-p' : sec.has(m) ? 'bm-s' : 'bm-o');
    const half = (parts) => parts.map(([m, d]) => `<path class="${cls(m)}" d="${d}"/>`).join('');
    const fig = (k, x) => `<g transform="translate(${x} 0)"><circle class="bm-x" cx="0" cy="15" r="11"/><g>${half(BODY[k])}</g><g transform="scale(-1 1)">${half(BODY[k])}</g></g>`;
    return `<svg class="bodymap${mini ? ' mini' : ''}" viewBox="0 0 150 ${mini ? 226 : 240}" aria-hidden="true">${fig('f', 38)}${fig('b', 112)}${mini ? '' : '<text x="38" y="238">Davanti</text><text x="112" y="238">Dietro</text>'}</svg>`;
  }
  function muscoli(e) {
    const k = K();
    return `<div class="bm-card">${bodyMap(e)}<div class="bm-leg">
      <p class="eyebrow">Muscoli allenati</p>
      <p><span class="bm-dot p"></span><b>${k.esc(e.m)}</b></p>
      ${(e.sec || []).map((m) => `<p><span class="bm-dot s"></span>${k.esc(m)}</p>`).join('')}
</div></div>`;
  }
  function showAnim(id) {
    const k = K();
    const e = exOf(id);
    k.openSheet(`<div class="stack"><div><p class="eyebrow">${k.esc(e.eq || '')}</p><h2>${k.esc(e.n)}</h2></div>
      ${anim(e, 'lg')}
      ${muscoli(e)}
      ${e.cue ? `<p><strong>Tecnica:</strong> ${k.esc(e.cue)}</p>` : ''}
      ${e.img ? `<p class="tiny muted">Foto: free-exercise-db (pubblico dominio)${e.eqv ? ' · movimento equivalente: sulla tua macchina la posizione può essere diversa' : ''}</p>` : ''}
      <button type="button" class="btn" data-act="sheet-close">Chiudi</button></div>`);
  }

  const e1rm = (kg, r) => (kg > 0 && r > 0 ? kg * (1 + r / 30) : 0); // formula di Epley
  const volOf = (sets) => sets.filter(isWork).reduce((a, s) => a + (s.kg > 0 && s.r > 0 ? s.kg * s.r : 0), 0);
  const uid = (p) => p + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
  const clone = (o) => JSON.parse(JSON.stringify(o));

  function defaultRoutines() {
    return K().D.workouts.map((w) => ({
      id: w.id, name: w.name, day: w.day, focus: w.focus,
      items: w.ex.map((e) => ({ ex: e.lib, s: e.s, lo: e.lo, hi: e.hi, rest: e.rest, sup: e.sup || '', kg: e.kg != null ? e.kg : null })),
    }));
  }
  function routines() {
    const saved = K().store.get('routines', {});
    const list = defaultRoutines().map((r) => (saved[r.id] && !saved[r.id].del && !saved[r.id].reset ? { ...r, ...saved[r.id], id: r.id } : r));
    Object.values(saved).forEach((r) => { if (r && r.custom && !r.del) list.push(r); });
    return list;
  }
  const routineOf = (id) => routines().find((r) => r.id === id);
  function history() {
    return K().store.get('workouts', []).filter((w) => !w.del).sort((a, b) => b.start - a.start);
  }
  function prevSets(exId, beforeTs) {
    for (const w of history()) {
      if (beforeTs && w.start >= beforeTs) continue;
      const it = w.items.find((x) => x.ex === exId && x.sets.length);
      if (it) return { sets: it.sets, w };
    }
    return null;
  }
  function records(exId, excludeId) {
    const r = { kg: 0, e1: 0, reps: 0, vol: 0, sec: 0 };
    history().forEach((w) => {
      if (w.id === excludeId) return;
      w.items.filter((x) => x.ex === exId).forEach((it) => {
        const work = it.sets.filter(isWork);
        work.forEach((s) => {
          if (s.kg > r.kg) r.kg = s.kg;
          const e = e1rm(s.kg, s.r); if (e > r.e1) r.e1 = e;
          if (s.r > r.reps) r.reps = s.r;
          if (exOf(exId).unit === 'sec' && s.r > r.sec) r.sec = s.r;
        });
        const v = volOf(it.sets); if (v > r.vol) r.vol = v;
      });
    });
    return r;
  }

  /* ---------------- allenamento attivo ---------------- */
  const getActive = () => K().store.get('active', null);
  const setActive = (a) => K().store.set('active', a);

  function start(rid) {
    const k = K();
    if (getActive()) { ui.tab = 'routine'; ui.summary = null; location.hash = '#/scheda'; k.render(); return; }
    const r = rid ? routineOf(rid) : null;
    const a = {
      id: uid('w'), rid: r ? r.id : null, name: r ? r.name : 'Allenamento libero', start: Date.now(),
      items: r ? r.items.map((it) => ({
        ex: it.ex, lo: it.lo, hi: it.hi, rest: it.rest, sup: it.sup, kg: it.kg, note: '',
        sets: Array.from({ length: it.s }, () => ({ kg: null, r: null, type: 'n', done: false })),
      })) : [],
    };
    setActive(a);
    ui.tab = 'routine'; ui.summary = null; ui.detail = null; ui.exDetail = null;
    k.buzz('MEDIUM');
    if (location.hash !== '#/scheda') location.hash = '#/scheda'; else k.render(true);
  }

  function placeholder(it, j) {
    const p = prevSets(it.ex);
    const ps = p && p.sets.filter(isWork)[Math.min(j, p.sets.filter(isWork).length - 1)];
    return { kg: ps && ps.kg != null ? ps.kg : it.kg != null ? it.kg : null, r: ps && ps.r != null ? ps.r : it.lo };
  }

  function suggestion(it) {
    const k = K();
    const e = exOf(it.ex);
    const p = prevSets(it.ex);
    const work = p ? p.sets.filter((s) => isWork(s) && s.r != null) : [];
    if (!work.length) {
      if (e.unit === 'sec') return { cls: '', txt: `Tieni ${it.lo}″ su ogni serie, poi aumenta fino a ${it.hi}″.` };
      return { cls: '', txt: it.kg != null ? `Parti da ${k.fmtKg(it.kg)} kg: ${it.lo}–${it.hi} ripetizioni lasciandone 1–2 in riserva.` : `Carico da testare: trova il peso con cui chiudi ${it.lo}–${it.hi} ripetizioni con 1–2 in riserva.` };
    }
    if (e.unit === 'sec') {
      const all = work.length >= it.sets.length && work.every((s) => s.r >= it.hi);
      return all ? { cls: 'up', txt: `Tenuto ${it.hi}″ ovunque: oggi prova ${it.hi + e.inc}″.` } : { cls: '', txt: `Punta a ${Math.min(it.hi, Math.max(...work.map((s) => s.r)) + 5)}″ su ogni serie.` };
    }
    const kg = Math.max(...work.map((s) => s.kg || 0));
    if (!kg) return { cls: '', txt: 'Registra anche il carico per avere il consiglio.' };
    const target = it.sets.filter(isWork).length || it.sets.length;
    if (work.length >= target && work.every((s) => s.r >= it.hi)) return { cls: 'up', txt: `Tutte le serie a ${it.hi}: oggi sali a ${k.fmtKg(k.r1(kg + e.inc))} kg.` };
    if (work.some((s) => s.r < it.lo)) return { cls: '', txt: `Qualche serie sotto le ${it.lo}: resta a ${k.fmtKg(kg)} kg (se ricapita, −5/10%).` };
    return { cls: '', txt: `Resta a ${k.fmtKg(kg)} kg e aggiungi 1 ripetizione dove riesci.` };
  }

  function elapsed(a) {
    const s = Math.max(0, Math.floor((Date.now() - a.start) / 1000));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), ss = s % 60;
    return (h ? `${h}:${String(m).padStart(2, '0')}` : `${m}`) + `:${String(ss).padStart(2, '0')}`;
  }
  setInterval(() => { const a = getActive(); const el = document.getElementById('woElapsed'); if (a && el) el.textContent = elapsed(a); document.querySelectorAll('.wo-elapsed').forEach((x) => { if (a) x.textContent = elapsed(a); }); }, 1000);

  const typeLabel = { w: 'R', d: 'D', f: 'C' };
  const typeName = { n: 'Normale', w: 'Riscaldamento', d: 'Drop set', f: 'A cedimento' };

  function setRow(it, i, j, s, nums) {
    const k = K();
    const e = exOf(it.ex);
    const p = prevSets(it.ex);
    const ps = p && p.sets[j];
    const prevTxt = ps ? (e.unit === 'sec' ? `${ps.r ?? '–'}″` : `${ps.kg != null ? k.fmtKg(ps.kg) : '–'} × ${ps.r ?? '–'}`) : '—';
    const ph = placeholder(it, j);
    const label = s.type === 'n' ? String(nums[j]) : typeLabel[s.type];
    const kgIn = e.unit === 'sec' ? '<span class="wdash">—</span>'
      : `<input inputmode="decimal" autocomplete="off" data-wi="kg" data-i="${i}" data-j="${j}" value="${s.kg != null ? k.fmtKg(s.kg) : ''}" placeholder="${ph.kg != null ? k.fmtKg(ph.kg) : ''}" aria-label="Serie ${j + 1}, chili">`;
    return `<div class="wswipe" data-swipe="del" data-i="${i}" data-j="${j}"><span class="wswipe-bg" aria-hidden="true">Elimina</span><div class="wset${s.done ? ' done' : ''}">
      <button type="button" class="wtype t-${s.type}" data-w="type" data-i="${i}" data-j="${j}" aria-label="Tipo di serie: ${typeName[s.type]}, tocca per cambiare">${label}</button>
      <span class="wprev">${prevTxt}</span>
      ${kgIn}
      <input inputmode="numeric" autocomplete="off" data-wi="r" data-i="${i}" data-j="${j}" value="${s.r != null ? s.r : ''}" placeholder="${ph.r != null ? ph.r : ''}" aria-label="Serie ${j + 1}, ${e.unit === 'sec' ? 'secondi' : 'ripetizioni'}">
      <button type="button" class="wchk" data-w="done" data-i="${i}" data-j="${j}" aria-pressed="${s.done}" aria-label="Serie ${j + 1} completata">${K().I.check}</button>
    </div></div>`;
  }

  // Superserie sì/no (Profilo). Con «no» il primo esercizio della coppia prende il recupero del secondo:
  // si calcola al momento, così vale anche per un allenamento già iniziato
  const superOn = () => K().store.get('superserie', true) !== false;
  function restOf(a, it) {
    if (it.rest > 0 || !it.sup || superOn()) return it.rest;
    const mate = a.items.find((x) => x !== it && x.sup && x.sup.slice(0, -1) === it.sup.slice(0, -1));
    return mate && mate.rest > 0 ? mate.rest : 75;
  }

  function itemCard(a, it, i) {
    const k = K();
    const e = exOf(it.ex);
    let n = 0;
    const nums = it.sets.map((s) => (s.type === 'n' ? ++n : 0));
    const sg = suggestion(it);
    const sup = superOn() ? it.sup : '';
    const rest = restOf(a, it);
    const next = sup && sup.endsWith('a') ? a.items.find((x) => x.sup === sup.replace('a', 'b')) : null;
    return `<article class="card wx${sup ? ' sup' : ''}" id="wx-${i}">
      <div class="wx-h">
        ${anim(e, 'sm')}
        <div class="wx-t">${sup ? `<span class="badge on">${k.esc(sup)}</span> ` : ''}<h3>${k.esc(e.n)}</h3>
          <div class="ex-meta"><span>${k.esc(e.m)}</span><span><b>${it.sets.length} × ${it.lo}–${it.hi}</b>${e.unit === 'sec' ? '″' : ''}</span><span>Rec. <b>${rest > 0 ? k.restTxt(rest) : 'superserie'}</b></span></div></div>
        <div class="wx-menu">
          <button type="button" class="x-btn" data-w="move" data-d="-1" data-i="${i}" aria-label="Sposta su"${i === 0 ? ' disabled' : ''}>↑</button>
          <button type="button" class="x-btn" data-w="move" data-d="1" data-i="${i}" aria-label="Sposta giù"${i === a.items.length - 1 ? ' disabled' : ''}>↓</button>
          <button type="button" class="chip" data-w="note" data-i="${i}">Nota</button>
          <button type="button" class="chip" data-w="pick-swap" data-i="${i}">Cambia</button>
          <button type="button" class="x-btn" data-w="remove" data-i="${i}" aria-label="Togli ${k.esc(e.n)}">${k.I.trash}</button>
        </div>
      </div>
      ${next ? `<p class="sup-note">Superserie ${k.tip('superserie')} dopo ogni serie passa subito a ${k.esc(exOf(next.ex).n)}. <button type="button" class="chip" data-w="sup-off">Falli separati</button></p>` : ''}
      <p class="sugg ${sg.cls}" style="margin:0 14px 8px">${k.esc(sg.txt)} ${k.tip('progressione')}</p>
      ${it.showNote || it.note ? `<textarea class="wnote" data-wi="note" data-i="${i}" rows="2" placeholder="Nota (sedile, impugnatura, sensazioni…)">${k.esc(it.note || '')}</textarea>` : ''}
      <div class="wsets">
        <div class="wset head"><span>Serie</span><span>Precedente</span><span>${e.unit === 'sec' ? '' : 'kg'}</span><span>${e.unit === 'sec' ? 'sec' : 'Rip'}</span><span>✓</span></div>
        ${it.sets.map((s, j) => setRow(it, i, j, s, nums)).join('')}
      </div>
      <div class="ex-f"><button type="button" class="chip" data-w="addset" data-i="${i}">+ Serie</button>${it.sets.length > 1 ? `<button type="button" class="chip" data-w="delset" data-i="${i}">− Serie</button>` : ''}
        ${plateable(e) ? `<button type="button" class="chip" data-w="plates" data-i="${i}">Dischi</button>` : ''}
        ${e.cue ? `<button type="button" class="chip" data-act="toggle" data-t="wcue-${i}" aria-expanded="false">Tecnica</button>` : ''}<span class="spacer"></span><span class="tiny muted">Tipi di serie ${k.tip('serie')}</span></div>
      ${e.cue ? `<p class="cue hidden" id="wcue-${i}">${k.esc(e.cue)}</p>` : ''}
    </article>`;
  }

  function viewActive(a) {
    const k = K();
    const all = a.items.flatMap((it) => it.sets);
    const doneWork = a.items.reduce((acc, it) => acc + it.sets.filter((s) => s.done && isWork(s)).length, 0);
    const vol = a.items.reduce((acc, it) => acc + volOf(it.sets.filter((s) => s.done)), 0);
    return `<div class="stack">
      <section class="card wo-head">
        <div class="row"><div><p class="eyebrow">Allenamento in corso</p><h1>${k.esc(a.name)}</h1></div><span class="spacer"></span>
          <button type="button" class="btn" data-w="finish">Termina</button></div>
        <div class="wo-stats"><div><span>Durata</span><b id="woElapsed">${elapsed(a)}</b></div><div><span>Volume ${k.tip('volume')}</span><b>${k.f0(vol)} kg</b></div><div><span>Serie</span><b>${doneWork}/${all.filter(isWork).length}</b></div></div>
        <div class="row" style="margin-top:12px">${k.wakeChip()}<button type="button" class="chip${gymMode() ? ' accent' : ''}" data-w="gymmode" aria-pressed="${gymMode()}">Modalità palestra${gymMode() ? ': attiva' : ''}</button><button type="button" class="chip" data-w="plates" data-i="-1">Calcola dischi</button></div>
      </section>
      ${a.items.length ? a.items.map((it, i) => itemCard(a, it, i)).join('') : '<p class="card small muted">Nessun esercizio: aggiungine uno qui sotto.</p>'}
      <div class="row"><button type="button" class="btn ghost" data-w="pick-add">+ Aggiungi esercizio</button><span class="spacer"></span><button type="button" class="chip" data-w="discard">Annulla allenamento</button></div>
      <section class="card flat small"><strong>Cardio finale:</strong> tapis roulant 15–20′ al 14%, 4,0–4,5 km/h, senza corrimano.</section>
    </div>`;
  }


  /* ---------------- extra "pro" ---------------- */
  const gymMode = () => !!K().store.get('gymMode', false);
  function applyGymMode() { document.documentElement.classList.toggle('gym-mode', gymMode()); }
  function nextLabel(a, i, j) {
    const it = a.items[i];
    const k = K();
    const fmt = (x, jj) => {
      const e = exOf(x.ex); const ph = placeholder(x, jj); const s = x.sets[jj];
      const kg = s.kg != null ? s.kg : ph.kg; const r = s.r != null ? s.r : ph.r;
      return `${e.n.split(' · ')[0]} · serie ${jj + 1}${e.unit === 'sec' ? ` · ${r}″` : kg != null ? ` · ${k.fmtKg(kg)} kg × ${r}` : ''}`;
    };
    const jn = it.sets.findIndex((s, jj) => jj > j && !s.done);
    if (jn >= 0) return 'Prossima: ' + fmt(it, jn);
    for (let ii = i + 1; ii < a.items.length; ii++) { const jj = a.items[ii].sets.findIndex((s) => !s.done); if (jj >= 0) return 'Poi: ' + fmt(a.items[ii], jj); }
    return 'Ultima serie fatta: termina e fai il cardio';
  }

  // calcolatore dei dischi: per lato, dischi disponibili in palestra
  const PLATES = [25, 20, 15, 10, 5, 2.5, 1.25];
  const fkg2 = (x) => Number(x).toLocaleString('it-IT', { maximumFractionDigits: 2 });
  const plateable = (e) => /Bilanciere|Leg Press|Hack|Calf alla Leg|T-Bar|Hip Thrust|Squat/i.test(`${e.eq} ${e.n}`);
  function plateCalc(total, bar) {
    let side = Math.max(0, (total - bar) / 2);
    const out = [];
    PLATES.forEach((pl) => { while (side >= pl - 1e-9) { out.push(pl); side = Math.round((side - pl) * 100) / 100; } });
    return { plates: out, rest: side };
  }
  function platesHtml(total, bar) {
    const k = K();
    const { plates, rest } = plateCalc(total, bar);
    const count = {};
    plates.forEach((pl) => { count[pl] = (count[pl] || 0) + 1; });
    const list = Object.keys(count).sort((a, b) => b - a).map((pl) => `${count[pl]} × ${fkg2(pl)} kg`).join(' + ');
    return `<div class="plates-vis" aria-hidden="true"><span class="pv-bar"></span>${plates.map((pl) => `<span class="pv p${String(pl).replace('.', '_')}">${fkg2(pl)}</span>`).join('')}</div>
      <p><b>Per lato:</b> ${plates.length ? list : 'nessun disco'}</p>
      ${rest > 0.01 ? `<p class="small muted">Restano ${fkg2(rest)} kg per lato che non si fanno con i dischi standard: arrotonda.</p>` : ''}`;
  }
  function openPlates(kg, name) {
    const k = K();
    k.openSheet(`<div class="stack plates" id="platesBox">
      <h2>Calcola dischi</h2>${name ? `<p class="small muted">${k.esc(name)}</p>` : ''}
      <div class="form-row" style="grid-template-columns:1fr 1fr">
        <div class="field"><label for="plKg">Carico totale (kg)</label><input id="plKg" inputmode="decimal" value="${kg != null ? k.fmtKg(kg) : ''}" data-plate="1"></div>
        <div class="field"><label for="plBar">Base</label><select id="plBar" class="search" data-plate="1"><option value="20">Bilanciere 20 kg</option><option value="10">Bilanciere EZ 10 kg</option><option value="0">Macchina (solo dischi)</option></select></div>
      </div>
      <div id="plOut">${platesHtml(kg || 0, 20)}</div>
      <p class="tiny muted">Per la leg press e le macchine a dischi scegli «solo dischi»: il peso della slitta non è contato.</p>
      <button type="button" class="btn" data-act="sheet-close">Chiudi</button>
    </div>`);
  }
  W.sheetInput = function (t) {
    if (!t.dataset.plate) return;
    const k = K();
    const kg = k.num(document.getElementById('plKg').value) || 0;
    const bar = Number(document.getElementById('plBar').value);
    document.getElementById('plOut').innerHTML = platesHtml(kg, bar);
  };

  // coriandoli leggeri per i record (niente se è attivo «riduci movimento»)
  function confetti() {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const c = document.createElement('canvas');
    c.className = 'confetti';
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    c.width = innerWidth * dpr; c.height = innerHeight * dpr;
    document.body.appendChild(c);
    const ctx = c.getContext('2d');
    const cols = ['#c4f031', '#ff6a55', '#f2b64a', '#5ba4ec', '#f1f1ec'];
    const ps = Array.from({ length: 140 }, () => ({ x: Math.random() * c.width, y: -Math.random() * c.height * 0.4, vx: (Math.random() - 0.5) * 4 * dpr, vy: (2 + Math.random() * 4) * dpr, s: (4 + Math.random() * 5) * dpr, r: Math.random() * 6, vr: (Math.random() - 0.5) * 0.3, col: cols[(Math.random() * cols.length) | 0] }));
    const t0 = performance.now();
    (function draw(t) {
      const el = t - t0;
      ctx.clearRect(0, 0, c.width, c.height);
      ps.forEach((p) => { p.x += p.vx; p.y += p.vy; p.vy += 0.06 * dpr; p.r += p.vr; ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(p.r); ctx.globalAlpha = Math.max(0, 1 - el / 2200); ctx.fillStyle = p.col; ctx.fillRect(-p.s / 2, -p.s / 4, p.s, p.s / 2); ctx.restore(); });
      if (el < 2200) requestAnimationFrame(draw); else c.remove();
    })(t0);
  }

  // scorri a sinistra una serie per eliminarla (chiamato da app.js)
  W.delSet = function (i, j) {
    const a = getActive();
    if (!a || !a.items[i] || a.items[i].sets.length <= 1) return false;
    a.items[i].sets.splice(j, 1);
    setActive(a); K().buzz('MEDIUM'); K().render();
    return true;
  };

  /* ---------------- fine allenamento ---------------- */
  function finish() {
    const k = K();
    const a = getActive();
    if (!a) return;
    const items = a.items.map((it) => ({ ex: it.ex, lo: it.lo, hi: it.hi, sets: it.sets.filter((s) => s.done).map((s) => ({ kg: s.kg, r: s.r, type: s.type })), note: it.note || '' }))
      .filter((it) => it.sets.length);
    if (!items.length) {
      if (confirm("Nessuna serie spuntata. Vuoi annullare l'allenamento?")) { setActive(null); k.stopTimer(); k.render(true); }
      return;
    }
    const pending = a.items.reduce((acc, it) => acc + it.sets.filter((s) => !s.done && (s.kg != null || s.r != null)).length, 0);
    if (!confirm(`Terminare l'allenamento?${pending ? `\n${pending} serie compilate ma non spuntate verranno ignorate.` : ''}`)) return;
    const w = { id: a.id, rid: a.rid, name: a.name, start: a.start, end: Date.now(), items, t: Date.now() };
    // record personali battuti rispetto alla cronologia precedente
    w.prs = [];
    items.forEach((it) => {
      const old = records(it.ex, w.id);
      const e = exOf(it.ex);
      const work = it.sets.filter(isWork);
      if (!work.length || (!old.kg && !old.e1 && !old.sec)) return; // prima volta: nessun confronto
      if (e.unit === 'sec') { const best = Math.max(...work.map((s) => s.r || 0)); if (best > old.sec) w.prs.push({ ex: it.ex, k: 'Tempo massimo', v: `${best}″` }); return; }
      const bestKg = Math.max(...work.map((s) => s.kg || 0));
      const bestE1 = Math.max(...work.map((s) => e1rm(s.kg, s.r)));
      const vol = volOf(it.sets);
      if (bestKg > old.kg) w.prs.push({ ex: it.ex, k: 'Carico massimo', v: `${k.fmtKg(bestKg)} kg` });
      if (bestE1 > old.e1 + 0.05) w.prs.push({ ex: it.ex, k: '1RM stimato', v: `${k.fmtKg(k.r1(bestE1))} kg` });
      if (vol > old.vol) w.prs.push({ ex: it.ex, k: 'Volume', v: `${k.f0(vol)} kg` });
    });
    const all = k.store.get('workouts', []).filter((x) => x.id !== w.id);
    all.push(w);
    k.store.set('workouts', all);
    setActive(null);
    k.stopTimer(); // fine sessione: niente recupero né notifica rimasti attivi
    ui.summary = w.id;
    k.buzz('HEAVY');
    k.render(true);
    if (w.prs.length) setTimeout(confetti, 120);
  }

  /* ---------------- analisi di un allenamento (solo dati registrati, nessun voto) ---------------- */
  // sedute precedenti di un esercizio, dalla più recente
  function sessionsBefore(exId, ts, max) {
    const out = [];
    for (const x of history()) {
      if (x.start >= ts) continue;
      const it = x.items.find((y) => y.ex === exId && y.sets.some(isWork));
      if (it) { out.push({ w: x, it }); if (out.length >= max) break; }
    }
    return out;
  }
  function metrics(it, unit) {
    const work = it.sets.filter((s) => isWork(s) && s.r != null);
    if (unit === 'sec') return { n: work.length, kg: 0, reps: work.reduce((a, s) => a + s.r, 0), best: Math.max(0, ...work.map((s) => s.r)), e1: 0, list: work.map((s) => `${s.r}″`).join(' · ') };
    const kg = Math.max(0, ...work.map((s) => s.kg || 0));
    const top = work.filter((s) => (s.kg || 0) === kg);
    const same = work.every((s) => (s.kg || 0) === kg);
    return {
      n: work.length, kg, reps: top.reduce((a, s) => a + s.r, 0), best: 0, e1: Math.max(0, ...work.map((s) => e1rm(s.kg, s.r))),
      list: same ? `${K().fmtKg(kg)} kg × ${work.map((s) => s.r).join(' · ')}` : work.map((s) => `${K().fmtKg(s.kg || 0)}×${s.r}`).join(' · '),
    };
  }
  function rangeOf(w, it) {
    if (it.lo && it.hi) return { lo: it.lo, hi: it.hi };
    const r = w.rid ? routineOf(w.rid) : null;
    const ri = r && r.items.find((x) => x.ex === it.ex);
    return ri ? { lo: ri.lo, hi: ri.hi } : null;
  }
  function analyze(w) {
    const k = K();
    return w.items.filter((it) => it.sets.some(isWork)).map((it) => {
      const e = exOf(it.ex);
      const cur = metrics(it, e.unit);
      const prev = sessionsBefore(it.ex, w.start, 3).map((p) => metrics(p.it, e.unit));
      const rg = rangeOf(w, it);
      const work = it.sets.filter((s) => isWork(s) && s.r != null);
      const o = { ex: it.ex, n: e.n, cur, prev: prev[0] || null, st: 'new', why: 'prima seduta registrata', next: '', stall: false };
      if (prev[0]) {
        const p = prev[0];
        if (e.unit === 'sec') {
          o.st = cur.best > p.best ? 'up' : cur.best < p.best ? 'down' : 'same';
          o.why = cur.best === p.best ? 'stesso tempo' : `${cur.best > p.best ? '+' : '−'}${Math.abs(cur.best - p.best)}″ sul tempo migliore`;
        } else if (cur.kg > p.kg) { o.st = 'up'; o.why = `carico +${k.fmtKg(k.r1(cur.kg - p.kg))} kg`; }
        else if (cur.kg === p.kg) {
          const d = cur.reps - p.reps;
          o.st = d > 0 ? 'up' : d < 0 ? 'down' : 'same';
          o.why = d === 0 ? 'stesso carico e stesse ripetizioni' : `stesso carico, ${d > 0 ? '+' : '−'}${Math.abs(d)} ripetizion${Math.abs(d) === 1 ? 'e' : 'i'}`;
        } else {
          const better = cur.e1 > p.e1 * 1.01;
          o.st = better ? 'same' : 'down';
          o.why = `carico −${k.fmtKg(k.r1(p.kg - cur.kg))} kg${better ? ' ma più ripetizioni: forza stimata invariata' : ''}`;
        }
        // stallo: con questa sono 3 sedute di fila senza migliorare il valore migliore (1RM stimato o tempo)
        if (prev.length >= 2) {
          const val = (m) => (e.unit === 'sec' ? m.best : m.e1);
          o.stall = val(cur) <= val(prev[0]) * 1.005 && val(prev[0]) <= val(prev[1]) * 1.005;
        }
      }
      if (rg && work.length) {
        if (e.unit === 'sec') o.next = work.every((s) => s.r >= rg.hi) ? `prossima volta ${rg.hi + e.inc}″` : `punta a ${rg.hi}″ su tutte le serie`;
        else if (cur.kg > 0) {
          if (work.every((s) => s.r >= rg.hi && (s.kg || 0) === cur.kg)) o.next = `tutte le serie a ${rg.hi}: prossima volta sali a ${k.fmtKg(k.r1(cur.kg + e.inc))} kg`;
          else if (work.some((s) => s.r < rg.lo)) o.next = `qualche serie sotto le ${rg.lo}: resta a ${k.fmtKg(cur.kg)} kg`;
          else o.next = `resta a ${k.fmtKg(cur.kg)} kg e cerca 1 ripetizione in più (si sale a ${rg.hi} su tutte le serie)`;
        }
      }
      if (o.stall) o.next = (o.next ? o.next + '. ' : '') + 'Fermo da 3 sedute: controlla sonno e calorie, poi prova a scendere del 10% e risalire';
      return o;
    });
  }
  function analysisHtml(w) {
    const k = K();
    const rows = analyze(w);
    if (!rows.length) return '';
    const r = w.rid ? routineOf(w.rid) : null;
    const planned = r ? r.items.reduce((a, it) => a + it.s, 0) : 0;
    const done = rows.reduce((a, x) => a + x.cur.n, 0);
    const missed = r ? r.items.filter((it) => !w.items.some((x) => x.ex === it.ex && x.sets.some(isWork))).map((it) => exOf(it.ex).n.split(' · ')[0]) : [];
    const prevSame = w.rid ? history().find((x) => x.rid === w.rid && x.start < w.start) : null;
    const vol = w.items.reduce((a, it) => a + volOf(it.sets), 0);
    const pv = prevSame ? prevSame.items.reduce((a, it) => a + volOf(it.sets), 0) : 0;
    const grp = (st) => rows.filter((x) => x.st === st);
    const li = (x) => `<li><div class="an-h"><b>${k.esc(x.n)}</b><span class="an-why">${k.esc(x.why)}</span></div>
      <div class="an-d">Oggi: ${k.esc(x.cur.list)}${x.prev ? ` · Prima: ${k.esc(x.prev.list)}` : ''}</div>
      ${x.next ? `<div class="an-n">→ ${k.esc(x.next)}</div>` : ''}</li>`;
    const block = (st, title) => (grp(st).length ? `<div class="an-g an-${st}"><h3>${title} · ${grp(st).length}</h3><ul>${grp(st).map(li).join('')}</ul></div>` : '');
    const facts = [
      planned ? `${done} serie allenanti su ${planned} previste` : `${done} serie allenanti`,
      pv ? `volume ${vol >= pv ? '+' : '−'}${k.f0(Math.abs((vol - pv) / pv * 100))}% rispetto all’ultimo ${k.esc(w.name)}` : '',
      missed.length ? `non fatti: ${missed.map(k.esc).join(', ')}` : '',
    ].filter(Boolean);
    return `<section class="card stack analysis">
      <div class="row"><h2>Analisi</h2><span class="spacer"></span><span class="tiny muted">confronto con la seduta precedente di ogni esercizio</span></div>
      <div class="an-sum"><span class="an-up">${grp('up').length} in progresso</span><span class="an-same">${grp('same').length} stabili</span><span class="an-down">${grp('down').length} in calo</span>${grp('new').length ? `<span>${grp('new').length} prima volta</span>` : ''}</div>
      <p class="small">${facts.join(' · ')}.</p>
      ${block('up', 'In progresso')}${block('same', 'Stabili')}${block('down', 'In calo')}${block('new', 'Prima volta')}
      ${rows.some((x) => x.stall) ? `<p class="small an-stall"><strong>Da tenere d’occhio:</strong> ${rows.filter((x) => x.stall).map((x) => k.esc(x.n)).join(', ')} — nessun miglioramento nelle ultime 3 sedute.</p>` : ''}
      ${window.RCC ? `<div class="row"><a class="chip" href="#/coach" data-w="coach-workout" data-id="${w.id}">Chiedi un parere al Coach</a></div>` : ''}
    </section>`;
  }

  /* ---------------- carichi attuali: l'ultima seduta registrata di ogni esercizio ---------------- */
  function loadRow(it) {
    const k = K();
    const e = exOf(it.ex);
    const p = prevSets(it.ex);
    const m = p ? metrics({ sets: p.sets }, e.unit) : null;
    const work = p ? p.sets.filter((s) => isWork(s) && s.r != null) : [];
    const reps = work.map((s) => s.r);
    const uniform = reps.length && reps.every((r) => r === reps[0]) && work.every((s) => (s.kg || 0) === (work[0].kg || 0));
    const big = !m ? (e.unit === 'sec' ? `${it.lo}″` : it.kg != null ? k.fmtKg(it.kg) : '—') : e.unit === 'sec' ? `${m.best}″` : k.fmtKg(m.kg);
    const sub = !m ? (it.kg != null || e.unit === 'sec' ? 'carico di partenza della scheda · mai registrato' : 'carico da testare · mai registrato')
      : `${uniform ? `${reps.length} × ${reps[0]}${e.unit === 'sec' ? '″' : ''}` : e.unit === 'sec' ? m.list : work.map((s) => ((s.kg || 0) === m.kg ? s.r : `${s.r} (${k.fmtKg(s.kg || 0)} kg)`)).join(' · ')} · ultima sessione ${new Date(p.w.start).toLocaleDateString('it-IT', { day: '2-digit', month: '2-digit', year: 'numeric' })}`;
    const sg = suggestion({ ...it, sets: Array.from({ length: it.s || work.length || 3 }, () => ({ type: 'n' })) });
    return `<li><button type="button" class="ld" data-w="exdetail" data-ex="${it.ex}">
      <span class="ld-t"><b>${k.esc(e.n)}</b><small>${k.esc(sub)}</small><small class="ld-next${sg.cls === 'up' ? ' up' : ''}">${k.esc(sg.txt)}</small></span>
      <span class="ld-kg"><b>${big}</b>${e.unit === 'sec' || big === '—' ? '' : '<small>kg</small>'}</span></button></li>`;
  }
  function viewLoads() {
    const k = K();
    const list = routines();
    const inRoutine = new Set(list.flatMap((r) => r.items.map((it) => it.ex)));
    const others = [...new Set(history().flatMap((x) => x.items.map((it) => it.ex)))].filter((id) => !inRoutine.has(id));
    return `<div class="stack">
      <p class="small muted">Il carico più alto dell’ultima sessione registrata di ogni esercizio, con serie e ripetizioni, e cosa fare la prossima volta. Tocca un esercizio per vedere lo storico.</p>
      <div class="grid2">${list.map((r) => `<section class="card stack"><div><h2>${k.esc(r.name)}</h2><p class="small muted">${r.day ? k.esc(r.day) + ' · ' : ''}${k.esc(r.focus || '')}</p></div>
        <ul class="loads">${r.items.map(loadRow).join('')}</ul></section>`).join('')}
      ${others.length ? `<section class="card stack"><h2>Altri esercizi</h2><ul class="loads">${others.map((id) => loadRow({ ex: id, lo: 8, hi: 12, s: 0, kg: null })).join('')}</ul></section>` : ''}</div>
    </div>`;
  }

  function summaryView(w) {
    const k = K();
    const vol = w.items.reduce((a, it) => a + volOf(it.sets), 0);
    const sets = w.items.reduce((a, it) => a + it.sets.filter(isWork).length, 0);
    const min = Math.round((w.end - w.start) / 60000);
    return `<div class="stack">
      <section class="card summary">
        <p class="eyebrow">Allenamento completato</p><h1>${k.esc(w.name)} 💪</h1>
        <div class="wo-stats"><div><span>Durata</span><b>${min} min</b></div><div><span>Volume</span><b>${k.f0(vol)} kg</b></div><div><span>Serie</span><b>${sets}</b></div></div>
        ${w.prs && w.prs.length ? `<div class="stack"><h3>🏆 Record personali (${w.prs.length})</h3><ul class="prs">${w.prs.map((p) => `<li><span>${k.esc(exOf(p.ex).n)}</span><span class="muted">${k.esc(p.k)}</span><b>${k.esc(p.v)}</b></li>`).join('')}</ul></div>` : '<p class="small muted">Nessun nuovo record questa volta: la costanza è quello che conta.</p>'}
        <div class="row"><button type="button" class="btn" data-w="summary-close">Fatto</button><button type="button" class="btn ghost" data-w="detail" data-id="${w.id}">Vedi dettaglio</button></div>
      </section>
      ${analysisHtml(w)}
    </div>`;
  }

  /* ---------------- routine ---------------- */
  function routineCard(r) {
    const k = K();
    const names = r.items.map((it) => exOf(it.ex).n.split(' · ')[0]);
    return `<article class="card stack routine">
      <div class="row"><div><h2>${k.esc(r.name)}</h2><p class="small muted">${r.day ? k.esc(r.day) + ' · ' : ''}${k.esc(r.focus || '')} · ${r.items.length} esercizi</p></div></div>
      <p class="small">${names.map(k.esc).join(' · ')}</p>
      <div class="row"><button type="button" class="btn" data-w="start" data-rid="${r.id}">${k.I.play} Inizia</button><button type="button" class="chip" data-w="edit" data-rid="${r.id}">Modifica</button></div>
    </article>`;
  }

  function viewRoutines() {
    const k = K();
    const wk = k.blockWeek();
    const today = K().D.week[k.dayIdx(new Date())];
    const list = routines();
    const first = list.find((r) => r.id === today.wo);
    return `<div class="grid-main">
      <div class="stack">
        ${first ? `<section class="card hero"><p class="eyebrow">Oggi · ${k.esc(today.name)} 16:30</p><h2>${k.esc(first.name)} · ${k.esc(first.focus || '')}</h2>
          <div class="row" style="margin-top:12px"><button type="button" class="btn" data-w="start" data-rid="${first.id}">${k.I.play} Inizia l'allenamento</button></div></section>` : ''}
        <h2 class="sec-title">Le tue routine</h2>
        ${list.map(routineCard).join('')}
        <div class="row"><button type="button" class="btn ghost" data-w="new-routine">+ Nuova routine</button><button type="button" class="chip" data-w="start" data-rid="">Allenamento libero</button></div>
      </div>
      <aside class="stack sticky-col">
        <section class="card stack">
          <p class="eyebrow">Blocco ${wk.cycle} · settimana ${wk.n} di 7</p>
          <div class="row"><h2>${wk.deload ? 'Settimana di scarico' : wk.n <= 2 ? 'Adattamento' : 'Progressione'}</h2>${k.tip('block')}</div>
          <p class="small">${k.esc(wk.phase)} ${k.tip('rir')}</p>
          <div class="field"><label for="blockStart">Inizio del blocco (un lunedì)</label><input type="date" id="blockStart" data-act="blockstart" value="${wk.start}"></div>
        </section>
        <section class="card flat small"><strong>Riscaldamento (5′):</strong> 5 minuti leggeri, poi 1–2 serie di riscaldamento sul primo esercizio di ogni muscolo (segnale come "R" toccando il numero della serie).</section>
        <details class="card">
          <summary>Regole di progressione</summary>
          <div class="prose small">
            <p><strong>Doppia progressione.</strong> Quando chiudi tutte le serie al massimo del range, la volta dopo aumenti il carico: +5 kg su Leg Press e Leg Curl, +2,5 kg su macchine e cavi, manubri a 3×12 poi +2 kg. Sotto il minimo del range resti allo stesso carico; se ricapita scendi del 5–10%.</p>
            <p><strong>Settimane 1–2:</strong> RIR 2–3 · <strong>3–6:</strong> RIR 1–2 · <strong>7:</strong> scarico.</p>
            <p><strong>Tipi di serie:</strong> tocca il numero della serie per passare a R (riscaldamento, esclusa da volume e record), D (drop set), C (a cedimento).</p>
          </div>
        </details>
      </aside>
    </div>`;
  }

  function viewEditor() {
    const k = K();
    const d = ui.draft;
    const isDefault = !d.custom;
    return `<div class="stack">
      <div class="row"><button type="button" class="chip" data-w="edit-cancel">← Annulla</button><span class="spacer"></span><button type="button" class="btn" data-w="edit-save">Salva routine</button></div>
      <section class="card stack">
        <div class="field"><label for="rname">Nome</label><input id="rname" data-wi="rname" value="${k.esc(d.name)}"></div>
        <div class="field"><label for="rfocus">Descrizione</label><input id="rfocus" data-wi="rfocus" value="${k.esc(d.focus || '')}"></div>
      </section>
      ${d.items.map((it, i) => { const e = exOf(it.ex); return `<article class="card redit">
        <div class="row"><div style="flex:1;min-width:0"><h3>${it.sup ? `<span class="badge on">${k.esc(it.sup)}</span> ` : ''}${k.esc(e.n)}</h3><p class="tiny muted">${k.esc(e.m)}</p></div>
          <button type="button" class="x-btn" data-w="r-up" data-i="${i}" aria-label="Sposta su"${i === 0 ? ' disabled' : ''}>↑</button>
          <button type="button" class="x-btn" data-w="r-down" data-i="${i}" aria-label="Sposta giù"${i === d.items.length - 1 ? ' disabled' : ''}>↓</button>
          <button type="button" class="x-btn" data-w="r-del" data-i="${i}" aria-label="Togli ${k.esc(e.n)}">${k.I.trash}</button></div>
        <div class="rgrid">
          <label>Serie<input inputmode="numeric" data-wi="rs" data-i="${i}" value="${it.s}"></label>
          <label>Rip. min<input inputmode="numeric" data-wi="rlo" data-i="${i}" value="${it.lo}"></label>
          <label>Rip. max<input inputmode="numeric" data-wi="rhi" data-i="${i}" value="${it.hi}"></label>
          <label>Recupero (s)<input inputmode="numeric" data-wi="rrest" data-i="${i}" value="${it.rest}"></label>
        </div></article>`; }).join('')}
      <div class="row"><button type="button" class="btn ghost" data-w="pick-edit">+ Aggiungi esercizio</button><span class="spacer"></span>
        ${isDefault ? '<button type="button" class="chip" data-w="edit-reset">Ripristina originale</button>' : '<button type="button" class="chip" data-w="edit-delete">Elimina routine</button>'}</div>
    </div>`;
  }

  /* ---------------- scelta esercizio ---------------- */
  function viewPicker() {
    const k = K();
    const L = lib();
    const muscles = [...new Set(Object.values(L).map((e) => e.m))].sort((a, b) => a.localeCompare(b, 'it'));
    const ids = Object.keys(L).filter((id) => !ui.muscle || L[id].m === ui.muscle).sort((a, b) => L[a].n.localeCompare(L[b].n, 'it'));
    return `<div class="sheet" role="dialog" aria-modal="true" aria-label="Scegli un esercizio"><div class="sheet-in stack">
      <div class="row"><h2>Scegli esercizio</h2><span class="spacer"></span><button type="button" class="chip" data-w="pick-close">Chiudi</button></div>
      <input id="pickSearch" class="search" type="search" placeholder="Cerca esercizio…" autocomplete="off" data-wi="pick-search">
      <div class="pill-list">${['', ...muscles].map((m) => `<button type="button" class="chip${ui.muscle === m ? ' solid' : ''}" data-w="pick-muscle" data-m="${k.esc(m)}">${m ? k.esc(m) : 'Tutti'}</button>`).join('')}</div>
      <ul class="picklist">${ids.map((id) => `<li data-n="${k.esc(L[id].n.toLowerCase())}"><button type="button" data-w="pick" data-ex="${id}" class="pick-row">${L[id].img ? `<img class="pick-img" src="${IMG(L[id].img, 0)}" alt="" loading="lazy" decoding="async">` : '<span class="pick-img none"></span>'}<span class="pick-t"><b>${k.esc(L[id].n)}</b><span class="tiny muted">${k.esc(L[id].m)} · ${k.esc(L[id].eq || '')}</span></span></button></li>`).join('')}</ul>
      <details class="card flat"><summary>Crea un esercizio nuovo</summary>
        <div class="stack">
          <div class="field"><label for="nxName">Nome</label><input id="nxName" autocomplete="off"></div>
          <div class="field"><label for="nxMuscle">Muscolo principale</label><select id="nxMuscle" class="search">${muscles.map((m) => `<option>${k.esc(m)}</option>`).join('')}</select></div>
          <div class="field"><label for="nxUnit">Misura</label><select id="nxUnit" class="search"><option value="reps">Carico e ripetizioni</option><option value="sec">Tempo (secondi)</option></select></div>
          <div class="field"><label for="nxInc">Incremento di carico (kg)</label><input id="nxInc" inputmode="decimal" value="2,5"></div>
          <p class="err" id="nxErr"></p>
          <button type="button" class="btn" data-w="pick-create">Crea e aggiungi</button>
        </div></details>
    </div></div>`;
  }

  function pickDone(exId) {
    const p = ui.picker;
    ui.picker = null;
    if (p.ctx === 'edit') {
      ui.draft.items.push({ ex: exId, s: 3, lo: 8, hi: 12, rest: 90, sup: '', kg: null });
    } else {
      const a = getActive();
      if (!a) return;
      if (p.ctx === 'swap') {
        const it = a.items[p.i];
        it.ex = exId; it.kg = null;
        it.sets = it.sets.map(() => ({ kg: null, r: null, type: 'n', done: false }));
      } else {
        a.items.push({ ex: exId, lo: 8, hi: 12, rest: 90, sup: '', kg: null, note: '', sets: Array.from({ length: 3 }, () => ({ kg: null, r: null, type: 'n', done: false })) });
      }
      setActive(a);
    }
  }

  /* ---------------- cronologia ---------------- */
  function monthGrid(list) {
    const k = K();
    const now = new Date();
    const [y, m] = (ui.month || `${now.getFullYear()}-${now.getMonth() + 1}`).split('-').map(Number);
    const first = new Date(y, m - 1, 1);
    const days = new Date(y, m, 0).getDate();
    const off = k.dayIdx(first);
    const byDay = {};
    list.forEach((w) => { const d = k.dkey(new Date(w.start)); (byDay[d] = byDay[d] || []).push(w); });
    const sk = skipped();
    const cells = [];
    for (let i = 0; i < off; i++) cells.push('<span></span>');
    for (let d = 1; d <= days; d++) {
      const key = `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
      const ws = byDay[key];
      const today = key === k.dkey(now);
      cells.push(ws ? `<button type="button" class="cal-d has${today ? ' today' : ''}" data-w="detail" data-id="${ws[0].id}" aria-label="${d}: ${k.esc(ws[0].name)}">${d}</button>` : `<span class="cal-d${today ? ' today' : ''}${sk[key] ? ' skip' : ''}"${sk[key] ? ` aria-label="${d}: allenamento saltato"` : ''}>${d}</span>`);
    }
    const title = first.toLocaleDateString('it-IT', { month: 'long', year: 'numeric' });
    const inMonth = list.filter((w) => { const d = new Date(w.start); return d.getFullYear() === y && d.getMonth() === m - 1; }).length;
    return `<section class="card stack">
      <div class="row"><button type="button" class="x-btn" data-w="month" data-d="-1" aria-label="Mese precedente">‹</button><h2 style="flex:1;text-align:center">${k.cap(title)}</h2><button type="button" class="x-btn" data-w="month" data-d="1" aria-label="Mese successivo">›</button></div>
      <div class="cal">${['L', 'M', 'M', 'G', 'V', 'S', 'D'].map((x) => `<span class="cal-h">${x}</span>`).join('')}${cells.join('')}</div>
      <p class="small muted">${inMonth} allenamenti in questo mese${(() => { const n = Object.keys(sk).filter((d) => d.startsWith(`${y}-${String(m).padStart(2, '0')}`)).length; return n ? ` · ${n} saltat${n === 1 ? 'o' : 'i'} (barrati)` : ''; })()}.</p>
    </section>`;
  }

  function workoutRow(w) {
    const k = K();
    const vol = w.items.reduce((a, it) => a + volOf(it.sets), 0);
    const sets = w.items.reduce((a, it) => a + it.sets.filter(isWork).length, 0);
    const min = Math.round((w.end - w.start) / 60000);
    const d = new Date(w.start);
    return `<li><button type="button" class="card whist" data-w="detail" data-id="${w.id}">
      <div class="row"><b>${k.esc(w.name)}</b><span class="spacer"></span><span class="tiny muted">${k.cap(d.toLocaleDateString('it-IT', { weekday: 'short', day: 'numeric', month: 'short' }))}</span></div>
      <div class="ex-meta"><span>${min} min</span><span>${k.f0(vol)} kg</span><span>${sets} serie</span>${w.prs && w.prs.length ? `<span>🏆 ${w.prs.length}</span>` : ''}</div>
      <p class="tiny muted" style="margin-top:4px">${w.items.map((it) => `${it.sets.filter(isWork).length}× ${k.esc(exOf(it.ex).n.split(' · ')[0])}`).join(' · ')}</p>
    </button></li>`;
  }

  // giorni segnati come «palestra saltata» (rc.dayov), esclusi quelli in cui poi ti sei allenato lo stesso
  function skipped() {
    const k = K();
    const ov = k.store.get('dayov', {});
    const doneDays = new Set(history().map((w) => k.dkey(new Date(w.start))));
    const out = {};
    Object.keys(ov).forEach((d) => { if (ov[d].skip && !ov[d].del && !doneDays.has(d)) out[d] = ov[d]; });
    return out;
  }
  function viewHistory() {
    const k = K();
    const list = history();
    const sk = skipped();
    const rows = list.slice(0, 60).map((w) => ({ t: w.start, html: workoutRow(w) }))
      .concat(Object.keys(sk).map((d) => { const r = routineOf(sk[d].rid); const dt = k.fromKey(d);
        return { t: dt.getTime() + 16.5 * 3600000, html: `<li><div class="card whist skip"><div class="row"><b>${k.esc(r ? r.name : 'Allenamento')} · saltato</b><span class="spacer"></span><span class="tiny muted">${k.cap(dt.toLocaleDateString('it-IT', { weekday: 'short', day: 'numeric', month: 'short' }))}</span></div><p class="tiny muted" style="margin-top:4px">Non conta tra gli allenamenti fatti.</p></div></li>` }; }))
      .sort((a, b) => b.t - a.t);
    return `<div class="grid-main">
      <div class="stack"><h2 class="sec-title">Cronologia</h2>
        ${rows.length ? `<ul class="whlist">${rows.map((x) => x.html).join('')}</ul>` : '<p class="card small muted">Qui compariranno i tuoi allenamenti completati.</p>'}</div>
      <aside class="stack sticky-col">${monthGrid(list)}</aside>
    </div>`;
  }

  function viewDetail(w) {
    const k = K();
    const vol = w.items.reduce((a, it) => a + volOf(it.sets), 0);
    const min = Math.round((w.end - w.start) / 60000);
    const d = new Date(w.start);
    return `<div class="stack">
      <div class="row"><button type="button" class="chip" data-w="detail-close">← Indietro</button><span class="spacer"></span><button type="button" class="chip" data-w="delete-workout" data-id="${w.id}">${k.I.trash} Elimina</button></div>
      <section class="card stack"><p class="eyebrow">${k.esc(k.cap(d.toLocaleDateString('it-IT', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })))} · ${d.toLocaleTimeString('it-IT', { hour: '2-digit', minute: '2-digit' })}</p>
        <h1>${k.esc(w.name)}</h1>
        <div class="wo-stats"><div><span>Durata</span><b>${min} min</b></div><div><span>Volume</span><b>${k.f0(vol)} kg</b></div><div><span>Record</span><b>${(w.prs || []).length}</b></div></div></section>
      ${analysisHtml(w)}
      ${w.items.map((it) => { const e = exOf(it.ex); let n = 0; return `<article class="card stack">
        <div class="row"><h3 style="flex:1">${k.esc(e.n)}</h3><button type="button" class="chip" data-w="exdetail" data-ex="${it.ex}">Progressi</button></div>
        ${it.note ? `<p class="small muted">📝 ${k.esc(it.note)}</p>` : ''}
        <ol class="dsets">${it.sets.map((s) => `<li><span class="wtype t-${s.type}">${s.type === 'n' ? ++n : typeLabel[s.type]}</span>${e.unit === 'sec' ? `${s.r ?? '–'}″` : `${s.kg != null ? k.fmtKg(s.kg) : '–'} kg × ${s.r ?? '–'}`}${s.type === 'n' && e.unit !== 'sec' && s.kg && s.r ? `<span class="tiny muted">1RM ≈ ${k.fmtKg(k.r1(e1rm(s.kg, s.r)))}</span>` : ''}</li>`).join('')}</ol>
        ${(w.prs || []).filter((p) => p.ex === it.ex).map((p) => `<p class="small">🏆 ${k.esc(p.k)}: <b>${k.esc(p.v)}</b></p>`).join('')}
      </article>`; }).join('')}
    </div>`;
  }

  /* ---------------- statistiche ---------------- */
  function weekStart(ts) { const d = new Date(ts); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() - K().dayIdx(d)); return d.getTime(); }

  function viewStats() {
    const k = K();
    const list = history();
    const now = Date.now();
    const ws = weekStart(now);
    const thisWeek = list.filter((w) => w.start >= ws);
    const setsBy = {};
    thisWeek.forEach((w) => w.items.forEach((it) => { const m = exOf(it.ex).m; setsBy[m] = (setsBy[m] || 0) + it.sets.filter(isWork).length; }));
    const targets = k.D.muscleTargets;
    const muscles = [...new Set([...Object.keys(targets), ...Object.keys(setsBy)])];
    const weeks = Array.from({ length: 8 }, (_, i) => ws - (7 - i) * 7 * 86400000);
    const wdata = weeks.map((s) => { const e = s + 7 * 86400000; const ww = list.filter((w) => w.start >= s && w.start < e); return { s, n: ww.length, vol: ww.reduce((a, w) => a + w.items.reduce((b, it) => b + volOf(it.sets), 0), 0) }; });
    const maxV = Math.max(1, ...wdata.map((x) => x.vol));
    const exIds = [...new Set(list.flatMap((w) => w.items.map((it) => it.ex)))].sort((a, b) => exOf(a).n.localeCompare(exOf(b).n, 'it'));
    return `<div class="grid-main">
      <div class="stack">
        <section class="card stack"><h2>Serie per muscolo · questa settimana</h2>
          <p class="small muted">Serie allenanti (senza riscaldamento) rispetto a quelle previste dalla scheda.</p>
          ${muscles.map((m) => { const v = setsBy[m] || 0; const t = targets[m]; return `<div class="macro"><div class="lbl" style="flex-direction:row;justify-content:space-between"><span>${k.esc(m)}</span><span class="val">${v}${t ? `<span class="muted"> / ${t}</span>` : ''}</span></div><div class="bar g"><i style="width:${t ? Math.min(100, (v / t) * 100) : v ? 100 : 0}%"></i></div></div>`; }).join('')}
        </section>
        <section class="card stack"><h2>Ultime 8 settimane</h2>
          <div class="wbars">${wdata.map((x) => `<div class="wbar"><span class="tiny">${x.n}</span><i style="height:${Math.max(3, (x.vol / maxV) * 100)}%"></i><span class="tiny muted">${new Date(x.s).toLocaleDateString('it-IT', { day: '2-digit', month: '2-digit' })}</span></div>`).join('')}</div>
          <p class="tiny muted">Altezza = volume sollevato (kg × ripetizioni); numero = allenamenti della settimana.</p>
        </section>
      </div>
      <aside class="stack sticky-col">
        <section class="card stack"><h2>Esercizi e record</h2>
          ${exIds.length ? `<ul class="picklist">${exIds.map((id) => { const r = records(id); const e = exOf(id); return `<li><button type="button" data-w="exdetail" data-ex="${id}"><b>${k.esc(e.n)}</b><span class="tiny muted">${e.unit === 'sec' ? `Record ${r.sec}″` : `Max ${k.fmtKg(r.kg)} kg · 1RM ≈ ${k.fmtKg(k.r1(r.e1))} kg`}</span></button></li>`; }).join('')}</ul>` : '<p class="small muted">Completa il primo allenamento per vedere i record.</p>'}
        </section>
      </aside>
    </div>`;
  }

  function viewExDetail(id) {
    const k = K();
    const e = exOf(id);
    const r = records(id);
    const sessions = history().slice().reverse().map((w) => { const it = w.items.find((x) => x.ex === id); return it ? { w, it } : null; }).filter(Boolean);
    const pts = sessions.map(({ w, it }) => ({ t: w.start, v: e.unit === 'sec' ? Math.max(...it.sets.map((s) => s.r || 0)) : Math.max(...it.sets.filter(isWork).map((s) => e1rm(s.kg, s.r))) })).filter((p) => p.v > 0);
    let chart = '<p class="small muted">Il grafico compare dalla seconda seduta.</p>';
    if (pts.length >= 2) {
      const Wd = 640, H = 200, L = 44, R = 12, T = 12, B = 24;
      const t0 = pts[0].t, t1 = pts[pts.length - 1].t, lo = Math.min(...pts.map((p) => p.v)) * 0.95, hi = Math.max(...pts.map((p) => p.v)) * 1.05;
      const x = (t) => L + ((t - t0) / Math.max(1, t1 - t0)) * (Wd - L - R);
      const y = (v) => T + (1 - (v - lo) / Math.max(0.01, hi - lo)) * (H - T - B);
      chart = `<div class="chart"><svg viewBox="0 0 ${Wd} ${H}" role="img" aria-label="Andamento di ${k.esc(e.n)}">
        ${[lo, (lo + hi) / 2, hi].map((v) => `<line class="ax" x1="${L}" x2="${Wd - R}" y1="${y(v)}" y2="${y(v)}"/><text x="${L - 6}" y="${y(v) + 4}" text-anchor="end">${k.f0(v)}</text>`).join('')}
        <polyline class="ln" points="${pts.map((p) => `${x(p.t).toFixed(1)},${y(p.v).toFixed(1)}`).join(' ')}"/>
        ${pts.map((p) => `<circle class="pt" cx="${x(p.t)}" cy="${y(p.v)}" r="3.5"/>`).join('')}
      </svg></div><p class="tiny muted">${e.unit === 'sec' ? 'Tempo migliore per seduta' : '1RM stimato per seduta (formula di Epley: kg × (1 + ripetizioni/30))'}</p>`;
    }
    const tiles = e.unit === 'sec' ? [['Tempo massimo', `${r.sec}″`]] : [['Carico massimo', `${k.fmtKg(r.kg)} kg`], ['1RM stimato ' + k.tip('1rm'), `${k.fmtKg(k.r1(r.e1))} kg`], ['Ripetizioni max', `${r.reps}`], ['Volume max', `${k.f0(r.vol)} kg`]];
    return `<div class="stack">
      <div class="row"><button type="button" class="chip" data-w="exdetail-close">← Indietro</button></div>
      <div><p class="eyebrow">${k.esc(e.m)}${e.sec && e.sec.length ? ' · ' + e.sec.map(k.esc).join(', ') : ''}</p><h1>${k.esc(e.n)}</h1></div>
      <section class="card exanim-card">${anim(e, 'lg')}${muscoli(e)}${e.eqv ? '<p class="tiny muted">Foto di un movimento equivalente: sulla tua macchina la posizione può essere diversa.</p>' : ''}</section>
      <div class="stats">${tiles.map(([l, v]) => `<div class="stat"><div class="lbl">${l}</div><div class="v">${v}</div></div>`).join('')}</div>
      <section class="card stack"><h2>Progressi</h2>${chart}</section>
      <section class="card stack"><h2>Sedute (${sessions.length})</h2>
        <ul class="entries">${sessions.slice().reverse().slice(0, 30).map(({ w, it }) => `<li><span class="muted">${new Date(w.start).toLocaleDateString('it-IT', { day: '2-digit', month: '2-digit' })}</span><span>${it.sets.filter(isWork).map((s) => (e.unit === 'sec' ? `${s.r}″` : `${k.fmtKg(s.kg || 0)}×${s.r}`)).join(' · ')}</span></li>`).join('')}</ul>
      </section>
      ${e.cue ? `<section class="card flat small"><strong>Tecnica:</strong> ${k.esc(e.cue)}</section>` : ''}
    </div>`;
  }

  /* ---------------- vista principale ---------------- */
  W.view = function () {
    const k = K();
    applyGymMode();
    const a = getActive();
    let body;
    if (ui.edit && ui.draft) body = viewEditor();
    else if (ui.exDetail) body = viewExDetail(ui.exDetail);
    else if (ui.detail) { const w = history().find((x) => x.id === ui.detail); body = w ? viewDetail(w) : (ui.detail = null, ''); }
    else if (ui.summary) { const w = history().find((x) => x.id === ui.summary); body = w ? summaryView(w) : (ui.summary = null, ''); }
    if (!body) {
      const tabs = [['routine', a ? 'In corso' : 'Allenamento'], ['carichi', 'Carichi'], ['cronologia', 'Cronologia'], ['statistiche', 'Statistiche']];
      const seg = `<div class="seg" role="tablist" aria-label="Sezioni dell'allenamento">${tabs.map(([t, l]) => `<button type="button" role="tab" data-w="tab" data-tab="${t}" aria-selected="${ui.tab === t}">${l}</button>`).join('')}</div>`;
      const inner = ui.tab === 'cronologia' ? viewHistory() : ui.tab === 'statistiche' ? viewStats() : ui.tab === 'carichi' ? viewLoads() : a ? viewActive(a) : viewRoutines();
      body = `<div class="stack">${a && ui.tab === 'routine' ? '' : '<div><p class="eyebrow">Allenamento · Torso/Limbs 4x</p><h1>Scheda</h1></div>'}${seg}${inner}</div>`;
    }
    return body + (ui.picker ? viewPicker() : '');
  };

  W.isActive = () => !!getActive();
  W.data = { history, exOf, routines, analyze, skipped, e1rm }; // letti dal Coach (coach.js)
  W.weekStats = (a, b) => { const ws = history().filter((w) => w.start >= a && w.start < b); return { n: ws.length, prs: ws.reduce((s, w) => s + ((w.prs || []).length), 0) }; };
  W.doneToday = (rid) => { const k = K(); const today = k.dkey(new Date()); return history().some((w) => w.rid === rid && k.dkey(new Date(w.start)) === today); };

  // barra "allenamento in corso" nelle altre sezioni
  W.banner = function () {
    const a = getActive();
    if (!a) return '';
    return `<a class="wo-banner" href="#/scheda" data-w="resume"><span class="dot-live"></span><b>${K().esc(a.name)}</b><span class="wo-elapsed">${elapsed(a)}</span><span class="spacer"></span><span>Riprendi →</span></a>`;
  };

  /* ---------------- eventi ---------------- */
  W.click = function (t) {
    const k = K();
    const w = t.dataset.w;
    const i = Number(t.dataset.i), j = Number(t.dataset.j);
    const a = getActive();
    switch (w) {
      case 'tab': ui.tab = t.dataset.tab; ui.detail = ui.exDetail = ui.summary = null; k.render(); return true;
      case 'start': start(t.dataset.rid || null); return true;
      case 'sup-off': k.store.set('superserie', false); k.buzz(); k.render(); return true;
      case 'resume': ui.tab = 'routine'; ui.detail = ui.exDetail = ui.summary = ui.edit = null; return false; // lascia navigare il link
      case 'finish': finish(); return true;
      case 'discard': if (confirm("Annullare l'allenamento? Le serie di oggi non verranno salvate.")) { setActive(null); k.stopTimer(); k.render(true); } return true;
      case 'done': {
        const it = a.items[i], s = it.sets[j];
        if (!s.done) {
          const ph = placeholder(it, j);
          if (s.kg == null && exOf(it.ex).unit !== 'sec') s.kg = ph.kg;
          if (s.r == null) s.r = ph.r;
          s.done = true;
          const rest = restOf(a, it);
          if (rest > 0) k.startTimer(rest, nextLabel(a, i, j));
          k.buzz('MEDIUM');
        } else s.done = false;
        setActive(a); k.render(); return true;
      }
      case 'type': { const s = a.items[i].sets[j]; s.type = { n: 'w', w: 'd', d: 'f', f: 'n' }[s.type]; setActive(a); k.render(); return true; }
      case 'addset': { const it = a.items[i]; const last = it.sets[it.sets.length - 1]; it.sets.push({ kg: last ? last.kg : null, r: null, type: 'n', done: false }); setActive(a); k.render(); return true; }
      case 'delset': { const it = a.items[i]; if (it.sets.length > 1) it.sets.pop(); setActive(a); k.render(); return true; }
      case 'note': a.items[i].showNote = !a.items[i].showNote; setActive(a); k.render(); return true;
      case 'remove': if (confirm(`Togliere ${exOf(a.items[i].ex).n} da questo allenamento?`)) { a.items.splice(i, 1); setActive(a); k.render(); } return true;
      case 'move': {
        const to = i + Number(t.dataset.d);
        if (to >= 0 && to < a.items.length) { [a.items[i], a.items[to]] = [a.items[to], a.items[i]]; setActive(a); k.render(); }
        return true;
      }
      case 'gymmode': k.store.set('gymMode', !gymMode()); applyGymMode(); k.render(); return true;
      case 'plates': {
        const it = i >= 0 && a ? a.items[i] : null;
        const kg = it ? (it.sets.find((x) => !x.done && x.kg != null) || {}).kg ?? placeholder(it, 0).kg : null;
        openPlates(kg, it ? exOf(it.ex).n : ''); return true;
      }
      case 'exanim': showAnim(t.dataset.ex); return true;
      case 'coach-workout': if (window.RCC) window.RCC.ask(`Analizza il mio allenamento ${(history().find((x) => x.id === t.dataset.id) || {}).name || ''} del ${new Date((history().find((x) => x.id === t.dataset.id) || {}).start || Date.now()).toLocaleDateString('it-IT')}: cosa è andato bene e cosa cambio la prossima volta?`); return false;
      case 'pick-add': ui.picker = { ctx: 'add' }; ui.muscle = ''; k.render(); return true;
      case 'pick-swap': ui.picker = { ctx: 'swap', i }; ui.muscle = exOf(a.items[i].ex).m; k.render(); return true;
      case 'pick-edit': ui.picker = { ctx: 'edit' }; ui.muscle = ''; k.render(); return true;
      case 'pick-close': ui.picker = null; k.render(); return true;
      case 'pick-muscle': ui.muscle = t.dataset.m; k.render(); return true;
      case 'pick': pickDone(t.dataset.ex); k.render(); return true;
      case 'pick-create': {
        const name = document.getElementById('nxName').value.trim();
        const err = document.getElementById('nxErr');
        if (!name) { err.textContent = "Scrivi il nome dell'esercizio."; return true; }
        const inc = k.num(document.getElementById('nxInc').value) || 2.5;
        const id = uid('c');
        const custom = k.store.get('exlib', {});
        custom[id] = { id, n: name, m: document.getElementById('nxMuscle').value, sec: [], inc, unit: document.getElementById('nxUnit').value, eq: 'Personalizzato', cue: '', t: Date.now() };
        k.store.set('exlib', custom);
        pickDone(id); k.render(); return true;
      }
      case 'summary-close': ui.summary = null; ui.tab = 'routine'; k.render(true); return true;
      case 'detail': ui.detail = t.dataset.id; ui.summary = null; k.render(true); return true;
      case 'detail-close': ui.detail = null; k.render(true); return true;
      case 'delete-workout': {
        if (!confirm('Eliminare questo allenamento dalla cronologia?')) return true;
        const all = k.store.get('workouts', []).filter((x) => x.id !== t.dataset.id);
        all.push({ id: t.dataset.id, del: 1, t: Date.now() });
        k.store.set('workouts', all); ui.detail = null; k.render(true); return true;
      }
      case 'exdetail': ui.exDetail = t.dataset.ex; k.render(true); return true;
      case 'exdetail-close': ui.exDetail = null; k.render(true); return true;
      case 'month': {
        const now = new Date();
        const [y, m] = (ui.month || `${now.getFullYear()}-${now.getMonth() + 1}`).split('-').map(Number);
        const d = new Date(y, m - 1 + Number(t.dataset.d), 1);
        ui.month = `${d.getFullYear()}-${d.getMonth() + 1}`; k.render(); return true;
      }
      case 'edit': { const r = routineOf(t.dataset.rid); ui.edit = r.id; ui.draft = clone(r); k.render(true); return true; }
      case 'new-routine': { const id = uid('r'); ui.edit = id; ui.draft = { id, name: 'Nuova routine', day: '', focus: '', items: [], custom: true }; k.render(true); return true; }
      case 'edit-cancel': ui.edit = ui.draft = null; k.render(true); return true;
      case 'edit-save': {
        const saved = k.store.get('routines', {});
        const d = ui.draft;
        d.items.forEach((it) => { it.s = Math.max(1, Math.min(10, it.s | 0)); it.lo = Math.max(1, it.lo | 0); it.hi = Math.max(it.lo, it.hi | 0); it.rest = Math.max(0, it.rest | 0); });
        saved[d.id] = { ...d, reset: 0, t: Date.now() };
        k.store.set('routines', saved); ui.edit = ui.draft = null; k.render(true); return true;
      }
      case 'edit-reset': {
        if (!confirm('Ripristinare la routine originale della scheda?')) return true;
        const saved = k.store.get('routines', {}); saved[ui.edit] = { id: ui.edit, reset: 1, t: Date.now() };
        k.store.set('routines', saved); ui.edit = ui.draft = null; k.render(true); return true;
      }
      case 'edit-delete': {
        if (!confirm('Eliminare questa routine?')) return true;
        const saved = k.store.get('routines', {}); saved[ui.edit] = { id: ui.edit, custom: true, del: 1, t: Date.now() };
        k.store.set('routines', saved); ui.edit = ui.draft = null; k.render(true); return true;
      }
      case 'r-up': case 'r-down': {
        const it = ui.draft.items; const to = w === 'r-up' ? i - 1 : i + 1;
        if (to >= 0 && to < it.length) [it[i], it[to]] = [it[to], it[i]];
        k.render(); return true;
      }
      case 'r-del': ui.draft.items.splice(i, 1); k.render(); return true;
      default: return false;
    }
  };

  // digitazione: salva senza ridisegnare (il cursore resta nel campo)
  W.input = function (t) {
    const k = K();
    const f = t.dataset.wi, i = Number(t.dataset.i), j = Number(t.dataset.j);
    if (f === 'pick-search') {
      const q = t.value.trim().toLowerCase();
      document.querySelectorAll('.picklist li').forEach((li) => li.classList.toggle('hidden', !!q && !li.dataset.n.includes(q)));
      return;
    }
    if (ui.edit && ui.draft) {
      if (f === 'rname') ui.draft.name = t.value;
      else if (f === 'rfocus') ui.draft.focus = t.value;
      else { const key = { rs: 's', rlo: 'lo', rhi: 'hi', rrest: 'rest' }[f]; if (key) ui.draft.items[i][key] = k.num(t.value) || 0; }
      return;
    }
    const a = getActive();
    if (!a || !a.items[i]) return;
    if (f === 'note') a.items[i].note = t.value;
    else if (f === 'kg' || f === 'r') {
      const v = k.num(t.value);
      a.items[i].sets[j][f] = v == null ? null : f === 'r' ? Math.round(v) : v;
    }
    setActive(a);
  };

  /* ---------------- dal vecchio diario (rc.log) alla cronologia ---------------- */
  W.migrate = function () {
    const k = K();
    if (k.store.get('logMigrated', false)) return;
    const log = k.store.get('log', {});
    const map = {};
    k.D.workouts.forEach((w) => w.ex.forEach((e, idx) => { map[e.id] = { rid: w.id, name: w.name, lib: e.lib, idx }; }));
    const byKey = {};
    Object.entries(log).forEach(([oldId, recs]) => {
      const m = map[oldId]; if (!m) return;
      (recs || []).forEach((rec) => {
        const sets = (rec.sets || []).filter((s) => s && (s[0] != null || s[1] != null)).map((s) => ({ kg: s[0], r: s[1], type: 'n' }));
        if (!sets.length) return;
        const key = m.rid + '|' + rec.d;
        const w = byKey[key] || (byKey[key] = { id: `mig-${m.rid}-${rec.d}`, rid: m.rid, name: m.name, start: k.fromKey(rec.d).getTime() + 16.5 * 3600000, items: [] });
        w.end = w.start + 75 * 60000; w.t = rec.t || Date.now();
        w.items.push({ ex: m.lib, sets, note: '', idx: m.idx });
      });
    });
    const add = Object.values(byKey).map((w) => { w.items.sort((x, y) => x.idx - y.idx).forEach((it) => delete it.idx); w.prs = []; return w; });
    if (add.length) {
      const all = k.store.get('workouts', []);
      const have = new Set(all.map((w) => w.id));
      k.store.set('workouts', all.concat(add.filter((w) => !have.has(w.id))));
    }
    k.store.set('logMigrated', true);
  };
})();
