'use strict';
(function () {
  const D = window.PIANO;
  const main = document.getElementById('main');

  /* ---------------- utilità ---------------- */
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  // Stesso arrotondamento di tools/genera_piano.py
  const r0 = (x) => Math.round(x);
  const r1 = (x) => Math.round(x * 10) / 10;
  const NF1 = new Intl.NumberFormat('it-IT', { maximumFractionDigits: 1 });
  const NF2 = new Intl.NumberFormat('it-IT', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const NF0 = new Intl.NumberFormat('it-IT', { maximumFractionDigits: 0 });
  const f1 = (x) => NF1.format(x);
  const f0 = (x) => NF0.format(x);
  const f2 = (x) => NF2.format(x);
  const sign = (x, fmt = f1) => (x > 0 ? '+' : x < 0 ? '−' : '±') + fmt(Math.abs(x));

  // Ogni chiave salvata riceve l'ora di modifica in rc._meta: serve alla sincronizzazione (sync.js)
  // per capire quale versione è più recente tra telefono e PC.
  const store = {
    get(k, d) { try { const v = localStorage.getItem('rc.' + k); return v === null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) {
      try {
        localStorage.setItem('rc.' + k, JSON.stringify(v));
        const meta = JSON.parse(localStorage.getItem('rc._meta') || '{}');
        meta['rc.' + k] = Date.now();
        localStorage.setItem('rc._meta', JSON.stringify(meta));
      } catch (e) { /* storage non disponibile */ }
      window.dispatchEvent(new CustomEvent('rc-change', { detail: 'rc.' + k }));
    },
  };

  const pad = (n) => String(n).padStart(2, '0');
  const dkey = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const fromKey = (k) => { const [y, m, d] = k.split('-').map(Number); return new Date(y, m - 1, d); };
  const dayIdx = (d) => (d.getDay() + 6) % 7; // 0 = lunedì
  const DAYS3 = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
  const longDate = (d) => d.toLocaleDateString('it-IT', { weekday: 'long', day: 'numeric', month: 'long' });
  const shortDate = (k) => fromKey(k).toLocaleDateString('it-IT', { day: '2-digit', month: '2-digit' });
  const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
  const mmss = (s) => `${Math.floor(s / 60)}:${pad(s % 60)}`;
  const restTxt = (s) => (s >= 60 ? `${Math.floor(s / 60)}′${s % 60 ? pad(s % 60) + '″' : ''}` : `${s}″`);
  const fmtKg = (x) => f1(x);
  const num = (v) => { const n = Number(String(v).trim().replace(',', '.')); return String(v).trim() === '' || !Number.isFinite(n) ? null : n; };

  const I = {
    check: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 6 9 17l-5-5"/></svg>',
    timer: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2M9 2h6"/></svg>',
    swap: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 16V4M3 8l4-4 4 4M17 8v12M21 16l-4 4-4-4"/></svg>',
    reset: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/></svg>',
    trash: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 6h18M8 6V4h8v2M6 6l1 14h10l1-14"/></svg>',
    down: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12M7 10l5 5 5-5M5 21h14"/></svg>',
    up: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 21V9M7 14l5-5 5 5M5 3h14"/></svg>',
    sun: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
    moon: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9z"/></svg>',
    play: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 4.5v15l12-7.5z"/></svg>',
    arrow: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6"/></svg>',
  };

  /* ---------------- piattaforma (iPhone / app installata) ---------------- */
  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const isStandalone = () => window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  let installEvt = null; // Android/Chrome: prompt di installazione nativo
  window.addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); installEvt = e; if (current === 'oggi') render(); });
  window.addEventListener('appinstalled', () => { installEvt = null; });
  const SHARE_SVG = '<svg class="share-ic" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12M8 7l4-4 4 4"/><path d="M6 11H5a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-8a1 1 0 0 0-1-1h-1"/></svg>';

  /* ---------------- app nativa iPhone (Capacitor) ---------------- */
  // Dentro l'app compilata con app-ios/ esiste window.Capacitor con i plugin nativi; sul sito tutto questo è spento.
  const Cap = window.Capacitor;
  const isNative = !!(Cap && Cap.isNativePlatform && Cap.isNativePlatform());
  const plugin = (name) => {
    if (!isNative) return null;
    try { return (Cap.Plugins && Cap.Plugins[name]) || (Cap.registerPlugin ? Cap.registerPlugin(name) : null); } catch (e) { return null; }
  };
  const N = { notif: plugin('LocalNotifications'), haptics: plugin('Haptics'), status: plugin('StatusBar') };
  const safe = (p) => { try { return Promise.resolve(p).catch(() => null); } catch (e) { return Promise.resolve(null); } };
  const buzz = (style = 'LIGHT') => { if (N.haptics) safe(N.haptics.impact({ style })); };
  if (N.status) safe(N.status.setStyle({ style: 'DARK' })); // testo della barra di stato bianco sulla striscia scura
  if (isNative) {
    // come un'app vera: niente zoom con doppio tocco o pizzico (sfasava la pagina e la spingeva sotto l'orologio)
    const vp = document.querySelector('meta[name="viewport"]');
    if (vp) vp.setAttribute('content', 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover');
    // se iOS non comunica i margini di sicurezza (notch e barra in basso) uso quelli dell'iPhone 14
    const probe = document.createElement('div');
    probe.style.cssText = 'position:fixed;top:0;left:0;width:1px;height:env(safe-area-inset-top,0px);visibility:hidden;pointer-events:none';
    document.body.appendChild(probe);
    const top = probe.getBoundingClientRect().height;
    probe.remove();
    if (top < 1 && Math.max(screen.width, screen.height) >= 812) {
      document.documentElement.style.setProperty('--sat', '47px');
      document.documentElement.style.setProperty('--sab', '34px');
    }
  }

  const TIMER_ID = 9001;
  const REM = { merenda: 'Merenda di domani (21:00)', peso: 'Pesata del mattino', palestra: 'Palestra (16:00 nei giorni ON)' };
  async function scheduleReminders() {
    if (!N.notif) return;
    const prefs = store.get('reminders', {});
    const ids = [];
    for (let i = 100; i < 140; i++) ids.push({ id: i });
    await safe(N.notif.cancel({ notifications: ids }));
    const list = [];
    // weekday nelle notifiche: 1 = domenica … 7 = sabato; di = 0 lunedì … 6 domenica
    const wd = (di) => ((di + 1) % 7) + 1;
    if (prefs.merenda) {
      for (let di = 0; di < 7; di++) {
        const next = (di + 1) % 7;
        if (next > 4) continue; // domani non c'è scuola
        const p = dayPlan(next);
        const sn = p.meals.filter((m) => m.slot === 'm1' || m.slot === 'm2').map((m) => `${m.code} ${D.recipes[m.code].name}`);
        list.push({ id: 100 + di, title: `Prepara le merende per ${p.day.name.toLowerCase()}`, body: sn.join(' · '), schedule: { on: { weekday: wd(di), hour: 21, minute: 0 }, allowWhileIdle: true } });
      }
    }
    if (prefs.peso) {
      for (let di = 0; di < 7; di++) {
        list.push({ id: 110 + di, title: 'Pesata del mattino', body: 'A digiuno, dopo il bagno. Poi segnala in Progressi.' + (di === 0 ? ' Oggi misura anche la vita.' : ''), schedule: { on: { weekday: wd(di), hour: di <= 4 ? 6 : 9, minute: di <= 4 ? 35 : 0 }, allowWhileIdle: true } });
      }
    }
    if (prefs.palestra) {
      D.week.forEach((d, di) => {
        if (!d.wo) return;
        const w = D.workouts.find((x) => x.id === d.wo);
        list.push({ id: 120 + di, title: `Alle 16:30: ${w.name}`, body: `${w.focus}. Borraccia, asciugamano e shaker con 30 g di whey.`, schedule: { on: { weekday: wd(di), hour: 16, minute: 0 }, allowWhileIdle: true } });
      });
    }
    if (list.length) await safe(N.notif.schedule({ notifications: list }));
  }
  async function setReminder(key, on) {
    if (on && N.notif) {
      const perm = await safe(N.notif.requestPermissions());
      if (!perm || perm.display !== 'granted') { store.set('reminders', { ...store.get('reminders', {}), [key]: false }); alert('Per i promemoria consenti le notifiche a Recomp in Impostazioni → Notifiche.'); return; }
    }
    store.set('reminders', { ...store.get('reminders', {}), [key]: on });
    await scheduleReminders();
  }

  function nativeCards() {
    if (!isNative) return '';
    const rem = store.get('reminders', {});
    const notif = N.notif ? `<section class="card stack"><h2>Promemoria</h2>
      ${Object.entries(REM).map(([k, l]) => `<label class="row small" style="justify-content:space-between;cursor:pointer"><span>${l}</span><input type="checkbox" data-act="rem" data-k="${k}"${rem[k] ? ' checked' : ''} style="width:22px;height:22px;accent-color:var(--ink)"></label>`).join('')}
      <p class="tiny muted">La merenda arriva la sera prima dei giorni di scuola con i nomi delle merende (scambi compresi). Il timer di recupero manda una notifica anche a schermo bloccato.</p>
    </section>` : '';
    return notif;
  }

  function installCard() {
    if (isNative || isStandalone() || store.get('installHidden', false)) return '';
    if (isIOS) {
      return `<section class="card install">
        <img class="ic" src="assets/icons/apple-touch-icon.png" alt="">
        <div class="stack" style="flex:1">
          <div><h3>Installa Recomp sull'iPhone</h3>
          <ol><li>Tocca <strong>Condividi</strong> ${SHARE_SVG} nella barra di Safari</li><li>Scegli <strong>Aggiungi alla schermata Home</strong></li><li>Apri Recomp dall'icona: a schermo intero e anche offline</li></ol></div>
          <p class="tiny muted">I dati salvati qui in Safari non passano all'app installata: se hai già registrato qualcosa, prima fai Progressi → Esporta backup.</p>
          <div><button type="button" class="chip" data-act="installhide">Ho capito</button></div>
        </div></section>`;
    }
    if (installEvt) {
      return `<section class="card install">
        <img class="ic" src="assets/icons/icon-192.png" alt="">
        <div class="stack" style="flex:1"><div><h3>Installa Recomp come app</h3><p class="small muted">Icona sulla schermata Home, schermo intero, funziona anche offline.</p></div>
        <div class="row"><button type="button" class="btn" data-act="install">Installa</button><button type="button" class="chip" data-act="installhide">Non ora</button></div></div></section>`;
    }
    return '';
  }

  /* Schermo sempre acceso durante l'allenamento (Screen Wake Lock) */
  const wake = { want: false, lock: null };
  async function wakeOn() {
    try { wake.lock = await navigator.wakeLock.request('screen'); wake.lock.addEventListener('release', () => { wake.lock = null; }); } catch (e) { wake.want = false; }
  }
  function wakeOff() { wake.want = false; if (wake.lock) { wake.lock.release().catch(() => {}); wake.lock = null; } }
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && wake.want && !wake.lock) wakeOn(); });

  /* ---------------- calcolo ---------------- */
  function line(fid, g) {
    const f = D.foods[fid];
    return { f: fid, g, k: r0(f.k * g / 100), p: r1(f.p * g / 100), c: r1(f.c * g / 100), fa: r1(f.f * g / 100) };
  }
  function sumLines(ls) {
    let k = 0, p = 0, c = 0, fa = 0;
    for (const l of ls) { k += l.k; p += l.p; c += l.c; fa += l.fa; }
    return { k, p: r1(p), c: r1(c), fa: r1(fa) };
  }
  const mealLines = (slot, code) => D.variants[slot][code].map(([f, g]) => line(f, g));
  const slotOf = (di, si) => D.daytypes[D.week[di].type].slots[si][2];

  function pickFor(di, si) {
    const sw = store.get('swaps', {});
    const v = sw[di + ':' + si];
    const slot = slotOf(di, si);
    return v && D.variants[slot] && D.variants[slot][v] ? v : D.week[di].pick[si];
  }
  function dayPlan(di) {
    const day = D.week[di];
    const dt = D.daytypes[day.type];
    const meals = dt.slots.map(([time, label, slot], si) => {
      if (slot === 'free') return { si, time, label, slot, free: true };
      const code = pickFor(di, si);
      const lines = mealLines(slot, code);
      return { si, time, label, slot, code, def: day.pick[si], lines, tot: sumLines(lines) };
    });
    let k = 0, p = 0, c = 0, fa = 0;
    for (const m of meals) if (!m.free) { k += m.tot.k; p += m.tot.p; c += m.tot.c; fa += m.tot.fa; }
    return { di, day, dt, meals, tot: { k, p: r1(p), c: r1(c), fa: r1(fa) }, hasFree: meals.some((m) => m.free) };
  }
  const FREE_EST = 850; // stima usata solo per la media settimanale

  function statusOf(kind, v, t) {
    const d = r1(v - t);
    const diff = kind === 'k' ? `${sign(d, f0)} kcal` : `${sign(d)} g`;
    if (kind === 'k') return Math.abs(d) <= 50 ? ['ok', `In target (${diff})`] : ['warn', `Fuori target (${diff})`];
    if (kind === 'p') return v >= t - 10 ? ['ok', `OK (${diff})`] : v >= t - 25 ? ['warn', `Un po' basse (${diff})`] : ['bad', `Basse (${diff})`];
    if (kind === 'c') return Math.abs(d) <= 30 ? ['ok', `OK (${diff})`] : ['warn', `Da sistemare (${diff})`];
    return Math.abs(d) <= 15 ? ['ok', `OK (${diff})`] : ['warn', `Da sistemare (${diff})`];
  }

  const UNITS = {
    uovo: ['uovo', 'uova'], sottiletta: ['fetta', 'fette'], kiwi: ['kiwi', 'kiwi'], crackers: ['pacchetto', 'pacchetti'],
    fette_bisc: ['fetta', 'fette'], pancarre: ['fetta', 'fette'], barretta: ['barretta', 'barrette'], gallette: ['galletta', 'gallette'],
  };
  function unitHint(fid, g) {
    if (fid === 'whey') {
      const s = g / 30;
      const t = Math.abs(s - Math.round(s)) < 0.05 ? f0(Math.round(s)) : '≈ ' + f1(s);
      return `${t} scoop`;
    }
    if (fid === 'olio') return g <= 7 ? '≈ 1 cucchiaino' : `≈ ${f1(g / 10)} cucchiai`;
    const f = D.foods[fid];
    if (!f.u || !UNITS[fid]) return '';
    const n = g / f.u;
    const rn = Math.max(1, Math.round(n));
    const exact = Math.abs(n - rn) < 0.08;
    return `${exact ? '' : '≈ '}${rn} ${rn === 1 ? UNITS[fid][0] : UNITS[fid][1]}`;
  }

  /* ---------------- componenti ---------------- */
  function macroBars(v, t, labels = true) {
    const bar = (cls, name, val, tar, unit) => {
      const pct = Math.max(0, Math.min(100, (val / tar) * 100));
      return `<div class="macro"><div class="lbl"><span>${name}</span><span class="val">${unit === 'kcal' ? f0(val) : f1(val)}<span class="muted"> / ${f0(tar)}${unit === 'kcal' ? '' : ' g'}</span></span></div><div class="bar ${cls}"><i style="width:${pct}%"></i></div></div>`;
    };
    return `<div class="macros">${bar('p', 'Proteine', v.p, t[1])}${bar('c', 'Carboidrati', v.c, t[2])}${bar('g', 'Grassi', v.fa, t[3])}</div>`;
  }

  function itemsHtml(lines) {
    return lines.map((l) => {
      const f = D.foods[l.f];
      const h = unitHint(l.f, l.g);
      const unit = l.f === 'latte_ps' || l.f === 'spremuta' ? 'ml' : 'g';
      return `<li class="it"><div class="it-n">${esc(f.n)}<small>P ${f1(l.p)} · C ${f1(l.c)} · G ${f1(l.fa)}${h ? ' · ' + h : ''}</small></div><div class="it-g">${l.g} ${unit}</div><div class="it-k">${l.k}</div></li>`;
    }).join('');
  }

  function optionsFor(slot, current) {
    return Object.keys(D.variants[slot]).map((code) => {
      const t = sumLines(mealLines(slot, code));
      return `<option value="${code}"${code === current ? ' selected' : ''}>${code} · ${esc(D.recipes[code].name)} — ${t.k} kcal, P ${f1(t.p)}</option>`;
    }).join('');
  }

  function mealCard(plan, m, opt = {}) {
    if (m.free) {
      return `<article class="card free-card stack">
        <div class="row"><span class="badge free">Pasto libero</span><span class="muted small">${m.time}</span></div>
        <h3>Una porzione normale di quello che vuoi</h3>
        <p class="small muted">Pizza, hamburger con patatine piccole, sushi (12–16 pezzi)… Niente antipasto + primo + dolce e niente bis: è <strong>un pasto</strong>, non una giornata libera. Stima 800–1000 kcal, fuori dai totali: il resto della giornata è già più leggero per lasciargli spazio.</p>
      </article>`;
    }
    const r = D.recipes[m.code];
    const swapped = m.code !== m.def;
    const chk = opt.check ? `<button type="button" class="check" data-act="eat" data-si="${m.si}" aria-pressed="${opt.checked ? 'true' : 'false'}" aria-label="Segna ${esc(m.label)} come mangiato">${I.check}</button>` : '';
    return `<article class="card meal${opt.checked ? ' done' : ''}">
      <div class="meal-h">${chk}
        <div class="t"><div class="lbl">${m.time} · ${esc(m.label)}${swapped ? ' · scambiato' : ''}</div>
        <h3><span class="code">${m.code}</span>${esc(r.name)}</h3></div>
        <div class="meal-k"><b>${m.tot.k}</b><span>kcal</span></div>
      </div>
      <ul class="items">${itemsHtml(m.lines)}</ul>
      <div class="meal-tot"><div class="m"><span>P <b>${f1(m.tot.p)}</b></span><span>C <b>${f1(m.tot.c)}</b></span><span>G <b>${f1(m.tot.fa)}</b></span></div><div><b>${m.tot.k}</b> kcal</div></div>
      ${r.how ? `<p class="how" style="padding-top:12px">${esc(r.how)}</p>` : ''}
      ${opt.swap ? `<div class="meal-f"><label class="sr" for="sw-${plan.di}-${m.si}">Scambia ${esc(m.label)}</label>
        <select id="sw-${plan.di}-${m.si}" data-act="swap" data-di="${plan.di}" data-si="${m.si}">${optionsFor(m.slot, m.code)}</select></div>` : ''}
    </article>`;
  }

  function typeBadge(day) {
    if (day.type === 'ON') {
      const w = D.workouts.find((x) => x.id === day.wo);
      return `<span class="badge on">ON · ${esc(w.name)}</span>`;
    }
    if (day.type === 'FREE') return '<span class="badge free">OFF · pasto libero</span>';
    return `<span class="badge off">OFF${day.type === 'OFF_S' ? ' · scuola' : ''}</span>`;
  }

  /* ---------------- stato UI ---------------- */
  const ui = {
    pianoTab: 'settimana',
    pianoDay: dayIdx(new Date()),
    wo: null,
    guidaTab: 'target',
  };

  /* ================= OGGI ================= */
  function viewOggi() {
    const now = new Date();
    const di = dayIdx(now);
    const key = dkey(now);
    const plan = dayPlan(di);
    const eatenAll = store.get('eaten', {});
    const eaten = eatenAll[key] || [];
    const T = plan.dt.target;
    const e = { k: 0, p: 0, c: 0, fa: 0 };
    plan.meals.forEach((m) => { if (!m.free && eaten.includes(m.si)) { e.k += m.tot.k; e.p += m.tot.p; e.c += m.tot.c; e.fa += m.tot.fa; } });
    e.p = r1(e.p); e.c = r1(e.c); e.fa = r1(e.fa);

    const events = [];
    if (di <= 4) {
      events.push({ time: '06:30', html: '<strong>Sveglia</strong> · niente colazione a casa: il primo pasto è la merenda delle 9:30.' });
      events.push({ time: '07:40', html: '<strong>Scuola</strong> fino alle 14:05 · merende 1 e 2 già nello zaino.' });
    }
    const w = plan.day.wo ? D.workouts.find((x) => x.id === plan.day.wo) : null;
    if (w) events.push({ time: '16:30', gym: true, html: `<strong>Palestra · ${esc(w.name)}</strong> — ${esc(w.focus)}. Pesi ~60′ + tapis 15–20′ al 14%. <a href="#/scheda">Apri la scheda →</a>` });

    const rows = [
      ...events.map((ev) => ({ time: ev.time, html: `<li class="tl event${ev.gym ? ' gym' : ''}"><div class="tl-time"><span>${ev.time}</span></div><div class="tl-body"><b class="tl-t">${ev.time}</b>${ev.html}</div></li>` })),
      ...plan.meals.map((m) => ({ time: m.time, html: `<li class="tl"><div class="tl-time"><span>${m.time}</span></div><div>${mealCard(plan, m, { check: !m.free, checked: eaten.includes(m.si), swap: true })}</div></li>` })),
    ].sort((a, b) => (a.time < b.time ? -1 : a.time > b.time ? 1 : 0));

    const planned = plan.tot.k;
    const left = planned - e.k;
    const tomorrow = (di + 1) % 7;
    const prep = tomorrow <= 4 ? prepCard(tomorrow) : '';

    return `
      <div class="grid-main">
        <div class="stack">
          ${installCard()}
          <section class="card hero">
            <div class="hero-top">
              <div><p class="eyebrow">${esc(cap(longDate(now)))}</p><h1>${esc(plan.day.name)}</h1></div>
              ${typeBadge(plan.day)}
            </div>
            <div class="kcal-line"><span class="kcal-big">${f0(e.k)}</span><span class="kcal-of">/ ${f0(planned)} kcal mangiate</span></div>
            <div class="bar k" style="margin-bottom:16px"><i style="width:${Math.min(100, (e.k / planned) * 100)}%"></i></div>
            ${macroBars(e, [planned, T[1], T[2], T[3]])}
            <p class="small muted" style="margin-top:14px">${eaten.length ? `Mancano <strong>${f0(Math.max(0, left))} kcal</strong> ai pasti di oggi.` : 'Spunta i pasti man mano che li mangi.'}${plan.hasFree ? ' Il pasto libero non è conteggiato.' : ''}</p>
          </section>
          <h2 class="sec-title">La tua giornata</h2>
          <ol class="timeline">${rows.map((r) => r.html).join('')}</ol>
        </div>
        <aside class="stack sticky-col">
          ${dayTotalsCard(plan)}
          ${w ? workoutMini(w) : restCard(plan.day)}
          ${prep}
        </aside>
      </div>`;
  }

  function prepCard(di) {
    const p = dayPlan(di);
    const snacks = p.meals.filter((m) => m.slot === 'm1' || m.slot === 'm2');
    return `<section class="card stack">
      <p class="eyebrow">Stasera prepara per ${esc(p.day.name.toLowerCase())}</p>
      ${snacks.map((m) => `<div><h3 style="font-size:15px"><span class="muted">${m.time}</span> · ${esc(D.recipes[m.code].name)}</h3>
        <p class="small muted" style="margin-top:4px">${m.lines.map((l) => `${esc(D.foods[l.f].n.split(' (')[0])} ${l.g} g`).join(' · ')}</p></div>`).join('')}
      <p class="tiny muted">Carta stagnola o sacchetto, frutta intera. Niente tonno, uova o sgombro a scuola.</p>
    </section>`;
  }

  function workoutMini(w) {
    const wk = blockWeek();
    return `<section class="card stack">
      <div class="row"><p class="eyebrow">Allenamento di oggi · 16:30</p></div>
      <h2>${esc(w.name)} <span class="muted" style="font-weight:600">· ${esc(w.focus)}</span></h2>
      <p class="small"><strong>Settimana ${wk.n} del blocco</strong> · ${esc(wk.phase)}</p>
      <ol class="small" style="margin:0;padding-left:20px">${w.ex.map((e) => `<li>${esc(e.n)} <span class="muted">${e.s}×${e.lo}–${e.hi}${e.unit === 'sec' ? '″' : ''}</span></li>`).join('')}</ol>
      <div class="row"><button type="button" class="btn" data-w="start" data-rid="${w.id}">${I.play} Inizia l'allenamento</button><a class="chip" href="#/scheda">Apri la scheda</a></div>
    </section>`;
  }

  function restCard(day) {
    const next = (() => { for (let i = 1; i <= 7; i++) { const d = D.week[(dayIdx(new Date()) + i) % 7]; if (d.wo) return d; } return null; })();
    const w = next && D.workouts.find((x) => x.id === next.wo);
    return `<section class="card stack">
      <p class="eyebrow">Giorno di riposo</p>
      <p class="small">Recupero attivo: punta a <strong>8–10 mila passi</strong>. ${day.type === 'FREE' ? 'Oggi c\'è il pasto libero: goditelo senza sensi di colpa.' : ''}</p>
      ${w ? `<p class="small muted">Prossimo allenamento: <strong>${esc(next.name)} · ${esc(w.name)}</strong></p>` : ''}
    </section>`;
  }

  function dayTotalsCard(plan) {
    const T = plan.dt.target;
    const t = plan.tot;
    const box = (kind, lbl, dot, v, tv, unit) => {
      const [cls, txt] = statusOf(kind, v, tv);
      const barCls = { k: 'k', p: 'p', c: 'c', f: 'g' }[kind];
      return `<div class="tot"><div class="lbl">${dot ? `<i class="dot ${dot}"></i>` : ''}${lbl}</div>
        <div class="v">${kind === 'k' ? f0(v) : f1(v)}<small> / ${f0(tv)}${unit}</small></div>
        <div class="bar ${barCls}"><i style="width:${Math.min(100, (v / tv) * 100)}%"></i></div>
        ${plan.hasFree ? '' : `<div class="status ${cls}">${txt}</div>`}</div>`;
    };
    return `<section class="card stack">
      <div class="row"><h2>Totale ${esc(plan.day.name.toLowerCase())}</h2><span class="spacer"></span>${typeBadge(plan.day)}</div>
      <div class="tot-grid">
        ${box('k', 'Calorie', '', t.k, T[0], ' kcal')}
        ${box('p', 'Proteine', 'p', t.p, T[1], ' g')}
        ${box('c', 'Carboidrati', 'c', t.c, T[2], ' g')}
        ${box('f', 'Grassi', 'g', t.fa, T[3], ' g')}
      </div>
      <p class="tiny muted">${plan.hasFree ? `Pianificate ${t.k} kcal + pasto libero (stima 800–1000): la giornata chiude intorno a ${f0(t.k + 800)}–${f0(t.k + 1000)} kcal.` : 'Ogni totale è la somma esatta delle righe dei pasti (valori arrotondati riga per riga).'}</p>
    </section>`;
  }

  /* ================= PIANO ================= */
  function viewPiano() {
    const tabs = [['settimana', 'Settimana'], ['spesa', 'Lista spesa'], ['sostituzioni', 'Sostituzioni']];
    const seg = `<div class="seg" role="tablist" aria-label="Sezioni del piano">${tabs.map(([k, l]) => `<button type="button" role="tab" data-act="ptab" data-tab="${k}" aria-selected="${ui.pianoTab === k}">${l}</button>`).join('')}</div>`;
    let body = '';
    if (ui.pianoTab === 'spesa') body = viewSpesa();
    else if (ui.pianoTab === 'sostituzioni') body = viewSostituzioni();
    else body = viewSettimana();
    return `<div class="stack"><div><p class="eyebrow">Alimentazione</p><h1>Piano settimanale</h1></div>${seg}${body}</div>`;
  }

  function viewSettimana() {
    const today = dayIdx(new Date());
    const di = ui.pianoDay;
    const plan = dayPlan(di);
    const chips = D.week.map((d, i) => {
      const p = dayPlan(i);
      return `<button type="button" class="day${i === today ? ' today' : ''}" role="tab" data-act="pday" data-di="${i}" aria-selected="${i === di}" aria-label="${d.name}, ${p.tot.k} kcal">
        ${DAYS3[i]}<i class="tp${d.type === 'ON' ? ' on' : ''}"></i><small>${p.tot.k}</small></button>`;
    }).join('');
    const swaps = store.get('swaps', {});
    const hasSw = plan.meals.some((m) => swaps[di + ':' + m.si]);
    const meals = plan.meals.map((m) => mealCard(plan, m, { swap: true })).join('');
    const w = plan.day.wo ? D.workouts.find((x) => x.id === plan.day.wo) : null;

    return `
      <div class="days" role="tablist" aria-label="Giorni">${chips}</div>
      <div class="grid-main">
        <div class="stack">
          <div class="row"><h2>${esc(plan.day.name)}</h2>${typeBadge(plan.day)}<span class="spacer"></span>
          ${hasSw ? `<button type="button" class="chip" data-act="resetday" data-di="${di}">${I.reset} Ripristina</button>` : ''}</div>
          <p class="small muted">${esc(plan.dt.label)}${w ? ` · palestra 16:30 (${esc(w.name)})` : ''}. Usa il menu sotto ogni pasto per scambiarlo: tutte le opzioni della stessa fascia hanno quasi le stesse kcal.</p>
          ${meals}
        </div>
        <aside class="stack sticky-col">
          ${dayTotalsCard(plan)}
          ${weekTable()}
        </aside>
      </div>`;
  }

  function weekTable() {
    let sk = 0;
    const rows = D.week.map((d, i) => {
      const p = dayPlan(i);
      sk += p.tot.k + (p.hasFree ? FREE_EST : 0);
      return `<tr${i === ui.pianoDay ? ' class="tbl-hl"' : ''}><td>${DAYS3[i]}</td><td>${d.type === 'ON' ? 'ON' : 'OFF'}</td><td class="r">${p.tot.k}${p.hasFree ? '*' : ''}</td><td class="r">${f1(p.tot.p)}</td><td class="r">${f1(p.tot.c)}</td><td class="r">${f1(p.tot.fa)}</td></tr>`;
    }).join('');
    return `<section class="card stack">
      <h2>La settimana in numeri</h2>
      <div class="tbl-wrap"><table>
        <thead><tr><th>Giorno</th><th>Tipo</th><th class="r">kcal</th><th class="r">P</th><th class="r">C</th><th class="r">G</th></tr></thead>
        <tbody>${rows}</tbody>
        <tfoot><tr><td colspan="2">Media</td><td class="r">${f0(sk / 7)}</td><td colspan="3" class="muted small">con pasto libero stimato ${FREE_EST} kcal</td></tr></tfoot>
      </table></div>
      <p class="tiny muted">* Domenica: solo i pasti pianificati, senza il pasto libero. Target: ON 2200 · OFF 1900 · media 2071.</p>
    </section>`;
  }

  function shoppingList() {
    const tot = {};
    D.week.forEach((d, di) => dayPlan(di).meals.forEach((m) => { if (!m.free) m.lines.forEach((l) => { tot[l.f] = (tot[l.f] || 0) + l.g; }); }));
    return tot;
  }

  function viewSpesa() {
    const tot = shoppingList();
    const got = store.get('shop', {});
    const cats = ['Carne e pesce', 'Affettati', 'Latticini e uova', 'Pane, pasta e cereali', 'Frutta', 'Verdura cruda', 'Condimenti e dispensa', 'Integratori e snack'];
    const byCat = cats.map((cat) => {
      const ids = Object.keys(tot).filter((id) => D.foods[id].cat === cat).sort((a, b) => D.foods[a].n.localeCompare(D.foods[b].n, 'it'));
      if (!ids.length) return '';
      return `<div class="shop-cat"><p class="eyebrow">${esc(cat)}</p><ul class="shop">${ids.map((id) => {
        const g = tot[id];
        const unit = id === 'latte_ps' || id === 'spremuta' ? 'ml' : 'g';
        const h = unitHint(id, g);
        return `<li class="${got[id] ? 'got' : ''}"><label><input type="checkbox" data-act="shop" data-id="${id}"${got[id] ? ' checked' : ''}><span class="n">${esc(D.foods[id].n)}</span></label>
          <span class="q">${f0(g)} ${unit}${h ? `<small>${h}</small>` : ''}</span></li>`;
      }).join('')}</ul></div>`;
    }).join('');
    const n = Object.keys(tot).length;
    const done = Object.keys(tot).filter((id) => got[id]).length;
    return `<section class="card stack">
      <div class="row"><h2>Lista della spesa</h2><span class="spacer"></span><span class="badge off">${done}/${n}</span>
      <button type="button" class="chip" data-act="shopreset">${I.reset} Azzera</button></div>
      <p class="small muted">Quantità esatte per 7 giorni: sono le somme dei grammi del piano, compresi i tuoi scambi. Pesi da crudo per carne, pesce, pasta, riso e patate. Il pasto libero è escluso.</p>
      ${byCat}
    </section>`;
  }

  function viewSostituzioni() {
    const eq = D.equivalents.map((g) => {
      const ref = D.foods[g.ref];
      const refK = r0(ref.k * g.g / 100);
      return `<section class="card stack"><h3>${esc(g.title)}</h3>
        <div class="tbl-wrap"><table><thead><tr><th>Alimento</th><th class="r">Grammi</th><th class="r">kcal</th></tr></thead><tbody>
        <tr class="tbl-hl"><td>${esc(ref.n)}</td><td class="r">${g.g} g</td><td class="r">${refK}</td></tr>
        ${g.rows.map((r) => `<tr><td>${esc(D.foods[r.f].n)}</td><td class="r">${r.g} g</td><td class="r">${r0(D.foods[r.f].k * r.g / 100)}</td></tr>`).join('')}
        </tbody></table></div></section>`;
    }).join('');
    return `<div class="stack">
      <section class="card prose">
        <h2>Come sostituire senza sbagliare</h2>
        <ul>
          <li><strong>Un pasto intero:</strong> usa il menu "scambia" sotto ogni pasto. Le opzioni della stessa fascia sono già calcolate sulle stesse kcal (±10), quindi il totale del giorno resta giusto.</li>
          <li><strong>Un singolo alimento:</strong> usa le tabelle qui sotto. Le fonti proteiche sono equivalenti per proteine e i carboidrati per carboidrati. Guarda la colonna kcal: se l'alimento nuovo ha più calorie, togline un po' dal condimento.</li>
          <li><strong>Verdura cruda:</strong> libera. Lattuga, pomodori, cetrioli, peperoni, carote e cipolla si scambiano tra loro senza pesarli.</li>
          <li><strong>Frutta:</strong> circa 80 kcal equivalgono a una mela (150 g), una pera (140 g), 2 kiwi (130 g), un'arancia (170 g) o 250 g di fragole.</li>
        </ul>
      </section>
      <div class="grid2">${eq}</div>
    </div>`;
  }

  /* ================= SCHEDA ================= */
  function blockWeek() {
    const start = store.get('blockStart', '2026-09-28');
    const days = Math.floor((fromKey(dkey(new Date())) - fromKey(start)) / 86400000);
    const weeks = Math.max(0, Math.floor(days / 7));
    const n = (weeks % 7) + 1;
    const cycle = Math.floor(weeks / 7) + 1;
    const phase = n <= 2 ? 'Adattamento · 2–3 ripetizioni in riserva (RIR 2–3)'
      : n <= 6 ? 'Progressione · RIR 1–2 (ultima serie di isolamento a RIR 0–1)'
        : 'Scarico · metà delle serie, stessi carichi, RIR 3–4';
    return { n, cycle, phase, start, deload: n === 7, future: days < 0 };
  }

  function defaultWo() {
    const di = dayIdx(new Date());
    for (let i = 0; i < 7; i++) { const d = D.week[(di + i) % 7]; if (d.wo) return d.wo; }
    return 'TA';
  }

  // pulsante "schermo sempre acceso" usato dall'allenamento live (allenamento.js)
  function wakeChip() {
    if (!('wakeLock' in navigator)) return '';
    return `<div class="row"><button type="button" class="chip${wake.want ? ' accent' : ''}" data-act="wake" aria-pressed="${wake.want}">${wake.want ? 'Schermo sempre acceso: attivo' : 'Tieni lo schermo acceso'}</button></div>`;
  }

  /* ---------------- timer recupero ---------------- */
  const timer = { end: 0, id: 0, ctx: null };
  const tEl = document.getElementById('timer');
  function beep() {
    try {
      const ctx = timer.ctx; if (!ctx) return;
      [0, 0.25, 0.5].forEach((t) => {
        const o = ctx.createOscillator(); const g = ctx.createGain();
        o.frequency.value = 880; o.connect(g); g.connect(ctx.destination);
        g.gain.setValueAtTime(0.18, ctx.currentTime + t); g.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + t + 0.18);
        o.start(ctx.currentTime + t); o.stop(ctx.currentTime + t + 0.2);
      });
    } catch (e) { /* audio non disponibile */ }
  }
  function tick() {
    const left = Math.max(0, Math.round((timer.end - Date.now()) / 1000));
    $('#timerTime').textContent = left > 0 ? mmss(left) : 'Via!';
    if (left <= 0) {
      clearInterval(timer.id); tEl.classList.add('done'); beep();
      if (navigator.vibrate) navigator.vibrate([200, 100, 200]);
      if (N.haptics) safe(N.haptics.notification({ type: 'SUCCESS' }));
    }
  }
  // App nativa: notifica di fine recupero, arriva anche a schermo bloccato o con l'app in background
  function timerNotify() {
    if (!N.notif) return;
    safe(N.notif.cancel({ notifications: [{ id: TIMER_ID }] })).then(() => safe(N.notif.schedule({ notifications: [{
      id: TIMER_ID, title: 'Recupero finito', body: 'Via con la prossima serie.', schedule: { at: new Date(timer.end), allowWhileIdle: true },
    }] })));
  }
  function startTimer(sec) {
    try { if (!timer.ctx) { const AC = window.AudioContext || window.webkitAudioContext; if (AC) timer.ctx = new AC(); } if (timer.ctx && timer.ctx.state === 'suspended') timer.ctx.resume(); } catch (e) { /* ignora */ }
    timer.end = Date.now() + sec * 1000; tEl.hidden = false; tEl.classList.remove('done');
    clearInterval(timer.id); tick(); timer.id = setInterval(tick, 250);
    buzz(); timerNotify();
  }
  $('#timerPlus').addEventListener('click', () => { if (tEl.classList.contains('done')) startTimer(15); else { timer.end += 15000; tick(); timerNotify(); } });
  $('#timerStop').addEventListener('click', () => {
    clearInterval(timer.id); tEl.hidden = true;
    if (N.notif) safe(N.notif.cancel({ notifications: [{ id: TIMER_ID }] }));
  });

  /* ================= PROGRESSI ================= */
  const START = { d: '2026-09-28', kg: 64.7, bf: 17.7 };
  // le misure eliminate restano come {d, del: 1, t} così l'eliminazione si propaga anche all'altro dispositivo
  const rawWeights = () => store.get('weights', []);
  function weights() { return rawWeights().filter((w) => !w.del).sort((a, b) => (a.d < b.d ? -1 : 1)); }
  function mondayOf(k) { const d = fromKey(k); d.setDate(d.getDate() - dayIdx(d)); return dkey(d); }
  function weekly(ws) {
    const m = {};
    ws.forEach((w) => { const k = mondayOf(w.d); (m[k] = m[k] || []).push(w); });
    return Object.keys(m).sort().map((k) => {
      const arr = m[k];
      const kg = arr.reduce((a, w) => a + w.kg, 0) / arr.length;
      const wa = arr.filter((w) => w.w != null);
      return { wk: k, n: arr.length, kg, waist: wa.length ? wa.reduce((a, w) => a + w.w, 0) / wa.length : null };
    });
  }
  function advice(wk) {
    const full = wk.filter((w) => w.n >= 3);
    if (full.length < 2) {
      return 'Pesati almeno 4 mattine a settimana, a digiuno e dopo il bagno. Dopo 2 settimane complete ti dico se il ritmo è giusto. Nelle prime 1–2 settimane un +0,3/+0,8 kg è normale: sono glicogeno e acqua dei carboidrati in più, non grasso.';
    }
    const a = full[full.length - 1], b = full[full.length - 2];
    const d = a.kg - b.kg;
    const c = full.length >= 3 ? full[full.length - 3] : null;
    const d2 = c ? b.kg - c.kg : null;
    const waistDown = a.waist != null && b.waist != null && a.waist < b.waist;
    if (d <= -0.4 && d2 != null && d2 <= -0.4) return `Stai scendendo troppo in fretta (${sign(r1(d * 10) / 10, f2)} kg e ${sign(r1(d2 * 10) / 10, f2)} kg nelle ultime due settimane). Aggiungi circa 150 kcal: +40 g di pasta o riso al pranzo dei giorni ON.`;
    if (d <= -0.4) return `Calo di ${f2(Math.abs(d))} kg in una settimana: un po' veloce. Se si ripete la prossima settimana, aggiungi 150 kcal.`;
    if (d <= -0.1) return `Perfetto: ${sign(Math.round(d * 100) / 100, f2)} kg rispetto alla settimana prima. È il ritmo giusto per una ricomposizione: non cambiare niente.`;
    if (d < 0.2) {
      if (d2 != null && Math.abs(d2) < 0.1 && !waistDown) return 'Peso fermo da 3 settimane e girovita che non scende: togli 100–150 kcal (es. −30 g di pasta o riso a cena) oppure aggiungi 2000 passi al giorno.';
      return `Peso stabile (${sign(r1(d * 100) / 100, f2)} kg). Se il girovita scende e i carichi salgono, stai facendo ricomposizione: va benissimo.`;
    }
    return `Peso in salita (${sign(r1(d * 100) / 100, f2)} kg). Se sei nelle prime 2 settimane è glicogeno. Altrimenti controlla le porzioni del pasto libero e i condimenti "a occhio".`;
  }
  function chart(ws) {
    if (ws.length < 2) return '<p class="small muted">Il grafico compare dal secondo peso registrato.</p>';
    const data = ws.slice(-90);
    const W = 640, H = 220, L = 40, R = 12, Tp = 12, B = 26;
    const t0 = fromKey(data[0].d).getTime(), t1 = fromKey(data[data.length - 1].d).getTime();
    const span = Math.max(1, t1 - t0);
    const vals = data.map((w) => w.kg).concat([START.kg]);
    let lo = Math.min(...vals) - 0.4, hi = Math.max(...vals) + 0.4;
    const x = (k) => L + ((fromKey(k).getTime() - t0) / span) * (W - L - R);
    const y = (v) => Tp + (1 - (v - lo) / (hi - lo)) * (H - Tp - B);
    const avg = data.map((w) => {
      const from = fromKey(w.d).getTime() - 6 * 86400000;
      const win = ws.filter((z) => { const t = fromKey(z.d).getTime(); return t >= from && t <= fromKey(w.d).getTime(); });
      return [w.d, win.reduce((a, z) => a + z.kg, 0) / win.length];
    });
    const ticks = [lo + 0.4, (lo + hi) / 2, hi - 0.4];
    return `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Andamento del peso con media mobile a 7 giorni">
      ${ticks.map((v) => `<line class="ax" x1="${L}" x2="${W - R}" y1="${y(v)}" y2="${y(v)}"/><text x="${L - 6}" y="${y(v) + 4}" text-anchor="end">${f1(v)}</text>`).join('')}
      <line class="base" x1="${L}" x2="${W - R}" y1="${y(START.kg)}" y2="${y(START.kg)}"/>
      ${data.map((w) => `<circle class="pt" cx="${x(w.d)}" cy="${y(w.kg)}" r="3"/>`).join('')}
      <polyline class="ln" points="${avg.map(([d, v]) => `${x(d).toFixed(1)},${y(v).toFixed(1)}`).join(' ')}"/>
      <text x="${L}" y="${H - 6}">${shortDate(data[0].d)}</text><text x="${W - R}" y="${H - 6}" text-anchor="end">${shortDate(data[data.length - 1].d)}</text>
    </svg>`;
  }
  function viewProgressi() {
    const ws = weights();
    const wk = weekly(ws);
    const last = ws[ws.length - 1];
    const lastD = last ? fromKey(last.d).getTime() : 0;
    const last7 = ws.filter((w) => fromKey(w.d).getTime() > lastD - 7 * 86400000);
    const avg7 = last7.length ? last7.reduce((a, w) => a + w.kg, 0) / last7.length : null;
    const full = wk.filter((w) => w.n >= 3);
    const dWeek = full.length >= 2 ? full[full.length - 1].kg - full[full.length - 2].kg : null;
    const waists = ws.filter((w) => w.w != null);
    const stat = (lbl, v, cls = '') => `<div class="stat"><div class="lbl">${lbl}</div><div class="v ${cls}">${v}</div></div>`;
    return `<div class="stack">
      <div><p class="eyebrow">Monitoraggio</p><h1>Progressi</h1><p class="muted">Punto di partenza: ${f2(START.kg)} kg · ${f1(START.bf)}% di grasso (bilancia) · ${shortDate(START.d)}/2026</p></div>
      <section class="card stack">
        <h2>Nuova misurazione</h2>
        <form id="wForm" class="form-row" novalidate>
          <div class="field"><label for="wDate">Data</label><input id="wDate" type="date" value="${dkey(new Date())}" required></div>
          <div class="field"><label for="wKg">Peso (kg)</label><input id="wKg" inputmode="decimal" autocomplete="off" placeholder="64,7"></div>
          <div class="field"><label for="wWaist">Vita (cm)</label><input id="wWaist" inputmode="decimal" autocomplete="off" placeholder="facolt."></div>
          <button class="btn" type="submit">Salva</button>
        </form>
        <p class="err" id="wErr" role="alert"></p>
        <p class="tiny muted">Mattina, a digiuno, dopo il bagno. Vita misurata all'altezza dell'ombelico, a fine espirazione, ogni lunedì. I dati restano solo su questo dispositivo: usa il backup qui sotto per spostarli.</p>
      </section>
      <div class="stats">
        ${stat('Ultimo peso', last ? `${f2(last.kg)}` : '—')}
        ${stat('Media 7 giorni', avg7 != null ? f2(avg7) : '—')}
        ${stat('Settimana vs prec.', dWeek != null ? sign(Math.round(dWeek * 100) / 100, f2) : '—', dWeek == null ? '' : dWeek > 0.05 ? 'up' : dWeek < -0.05 ? 'down' : '')}
        ${stat('Dal via', avg7 != null ? sign(Math.round((avg7 - START.kg) * 100) / 100, f2) : '—', avg7 == null ? '' : avg7 > START.kg ? 'up' : 'down')}
      </div>
      <section class="card advice"><p class="eyebrow">Cosa fare adesso</p><p style="margin-top:6px">${esc(advice(wk))}</p></section>
      <section class="card chart stack"><div class="row"><h2>Andamento</h2><span class="spacer"></span><span class="tiny muted">punti = pesate · linea = media 7 giorni · tratteggio = partenza</span></div>${chart(ws)}</section>
      <div class="grid2">
        <section class="card stack"><h2>Medie settimanali</h2>
          ${wk.length ? `<div class="tbl-wrap"><table><thead><tr><th>Settimana dal</th><th class="r">Pesate</th><th class="r">Media</th><th class="r">Δ</th><th class="r">Vita</th></tr></thead><tbody>
          ${wk.slice().reverse().map((w, i, arr) => { const prev = arr[i + 1]; return `<tr><td>${shortDate(w.wk)}</td><td class="r">${w.n}</td><td class="r">${f2(w.kg)}</td><td class="r">${prev ? sign(Math.round((w.kg - prev.kg) * 100) / 100, f2) : '—'}</td><td class="r">${w.waist != null ? f1(w.waist) : '—'}</td></tr>`; }).join('')}
          </tbody></table></div>` : '<p class="small muted">Ancora nessuna pesata.</p>'}
          ${waists.length >= 2 ? `<p class="small">Girovita: <strong>${sign(r1(waists[waists.length - 1].w - waists[0].w))} cm</strong> dalla prima misura.</p>` : ''}
        </section>
        <section class="card stack"><h2>Registro</h2>
          ${ws.length ? `<ul class="entries">${ws.slice().reverse().slice(0, 30).map((w) => `<li><span class="muted">${shortDate(w.d)}</span><strong>${f2(w.kg)} kg</strong>${w.w != null ? `<span class="muted">· vita ${f1(w.w)} cm</span>` : ''}<button type="button" class="x-btn" data-act="wdel" data-d="${w.d}" aria-label="Elimina la misura del ${shortDate(w.d)}">${I.trash}</button></li>`).join('')}</ul>` : '<p class="small muted">Le misure che salvi compaiono qui.</p>'}
        </section>
      </div>
      ${syncCard()}
      ${nativeCards()}
      <section class="card stack">
        <h2>Backup dei dati</h2>
        <p class="small muted">Pesi, carichi della scheda, scambi dei pasti e lista della spesa sono salvati in questo browser. Esporta un file per sicurezza o per spostarli dal PC al telefono.</p>
        <div class="row"><button type="button" class="btn ghost" data-act="export">${I.down} Esporta backup</button>
        <label class="btn ghost" for="importFile">${I.up} Importa backup</label><input id="importFile" type="file" accept="application/json,.json" class="sr"></div>
        <p class="err" id="impMsg" role="status"></p>
      </section>
    </div>`;
  }

  /* ---------------- sincronizzazione (stato fornito da sync.js) ---------------- */
  function syncCard() {
    const S = window.RCSync;
    const st = S ? S.state : { status: 'loading' };
    const head = '<div class="row"><h2>Sincronizzazione PC ↔ telefono</h2></div>';
    const msg = st.msg ? `<p class="err" role="alert">${esc(st.msg)}</p>` : '';
    if (st.status === 'nocfg') {
      return `<section class="card stack">${head}<p class="small muted">Non ancora attiva: manca la configurazione di Firebase (<code>assets/js/firebase-config.js</code>). Quando è pronta, qui compare l'accesso.</p></section>`;
    }
    if (st.status === 'loading') {
      return `<section class="card stack">${head}<p class="small muted">Connessione in corso…</p>${msg}</section>`;
    }
    if (st.status === 'offline') {
      return `<section class="card stack">${head}<p class="small muted">Sei offline: i dati restano salvati qui e si sincronizzano appena torna la connessione.</p></section>`;
    }
    if (st.status === 'in') {
      const when = st.last ? new Date(st.last).toLocaleTimeString('it-IT', { hour: '2-digit', minute: '2-digit' }) : '—';
      return `<section class="card stack">${head}
        <p class="small">Collegato come <strong>${esc(st.email || '')}</strong>. Pesi, carichi, spunte, scambi e lista della spesa si sincronizzano da soli tra i dispositivi.</p>
        <p class="small muted">Ultima sincronizzazione: ${when}${st.busy ? ' · in corso…' : ''}</p>${msg}
        <div class="row"><button type="button" class="btn ghost" data-act="sync-now">${I.reset} Sincronizza ora</button><button type="button" class="chip" data-act="sync-logout">Esci</button></div>
      </section>`;
    }
    return `<section class="card stack">${head}
      <p class="small muted">Accedi con lo stesso account sul telefono e sul PC: i dati si uniranno e resteranno allineati in automatico. La prima volta scegli "Crea account".</p>
      <form id="syncForm" class="stack" novalidate>
        <div class="field"><label for="syncEmail">Email</label><input id="syncEmail" type="email" autocomplete="username" inputmode="email" autocapitalize="off" value="${esc(st.emailDraft || '')}"></div>
        <div class="field"><label for="syncPw">Password (almeno 6 caratteri)</label><input id="syncPw" type="password" autocomplete="current-password"></div>
        ${msg}
        <div class="row"><button type="submit" class="btn">Accedi</button><button type="button" class="btn ghost" data-act="sync-signup">Crea account</button></div>
      </form>
    </section>`;
  }

  /* ================= GUIDA ================= */
  function viewGuida() {
    const tabs = [['target', 'Target & TDEE'], ['alimenti', 'Alimenti'], ['regole', 'Regole']];
    const seg = `<div class="seg" role="tablist" aria-label="Sezioni della guida">${tabs.map(([k, l]) => `<button type="button" role="tab" data-act="gtab" data-tab="${k}" aria-selected="${ui.guidaTab === k}">${l}</button>`).join('')}</div>`;
    const body = ui.guidaTab === 'alimenti' ? guidaAlimenti() : ui.guidaTab === 'regole' ? guidaRegole() : guidaTarget();
    return `<div class="stack"><div><p class="eyebrow">Il metodo</p><h1>Guida</h1></div>${seg}${body}</div>`;
  }

  function guidaTarget() {
    const kv = [['Età', '18 anni'], ['Altezza', '173 cm'], ['Peso', '64,70 kg'], ['BMI', '21,6'], ['Grasso (BIA)', '17,7%'], ['Massa magra', '53,26 kg'], ['Grasso viscerale', '3'], ['Acqua', '55,7%']];
    return `<div class="stack">
      <section class="card stack"><h2>Punto di partenza · 28/09/2026</h2>
        <dl class="kv" style="margin:0">${kv.map(([k, v]) => `<div><dt>${k}</dt><dd>${v}</dd></div>`).join('')}</dl>
        <p class="small muted">Obiettivo: ricomposizione corporea. Meno grasso su basso addome e fianchi, più muscolo (soprattutto dorsali e deltoidi laterali), carichi in salita. La percentuale di grasso della bilancia può sbagliare di ±3–5 punti: usala solo come andamento.</p>
      </section>
      <div class="grid2">
        <section class="card stack"><h2>Metabolismo basale</h2>
          <div class="tbl-wrap"><table><thead><tr><th>Formula</th><th class="r">kcal</th></tr></thead><tbody>
            <tr><td>Mifflin-St Jeor</td><td class="r">1643</td></tr>
            <tr><td>Katch-McArdle (massa magra)</td><td class="r">1520</td></tr>
            <tr><td>Cunningham (massa magra)</td><td class="r">1672</td></tr>
            <tr><td>Tinsley 2019 (chi fa pesi)</td><td class="r">1663</td></tr>
            <tr><td class="muted">Bilancia BIA (esclusa, sottostima)</td><td class="r muted">1449</td></tr>
          </tbody><tfoot><tr><td>BMR di lavoro (media)</td><td class="r">≈ 1625</td></tr></tfoot></table></div>
        </section>
        <section class="card stack"><h2>Dispendio giornaliero</h2>
          <div class="tbl-wrap"><table><thead><tr><th></th><th class="r">ON</th><th class="r">OFF</th></tr></thead><tbody>
            <tr><td>BMR</td><td class="r">1625</td><td class="r">1625</td></tr>
            <tr><td>NEAT (scuola, passi)</td><td class="r">300</td><td class="r">300</td></tr>
            <tr><td>Pesi ~60′ + tapis 14%</td><td class="r">330</td><td class="r">0</td></tr>
            <tr><td>Digestione (TEF ~10%)</td><td class="r">250</td><td class="r">214</td></tr>
            <tr><td>TDEE teorico</td><td class="r">2505</td><td class="r">2139</td></tr>
          </tbody><tfoot><tr><td>TDEE di lavoro</td><td class="r">≈ 2450</td><td class="r">≈ 2100</td></tr></tfoot></table></div>
          <p class="tiny muted">Il calcolo teorico è stato corretto con la tua storia reale: in estate, a 1850 kcal con 3 allenamenti, perdevi ~0,2 kg a settimana. Media di lavoro ≈ 2300 kcal.</p>
        </section>
      </div>
      <section class="card stack"><h2>Target</h2>
        <div class="tbl-wrap"><table><thead><tr><th></th><th class="r">kcal</th><th class="r">Proteine</th><th class="r">Carboidrati</th><th class="r">Grassi</th></tr></thead><tbody>
          <tr><td><span class="badge on">ON</span> Lun Mar Gio Ven</td><td class="r">2200</td><td class="r">140 g</td><td class="r">275 g</td><td class="r">60 g</td></tr>
          <tr><td><span class="badge off">OFF</span> Mer Sab Dom</td><td class="r">1900</td><td class="r">140 g</td><td class="r">191 g</td><td class="r">64 g</td></tr>
        </tbody><tfoot><tr><td>Media settimanale</td><td class="r">2071</td><td colspan="3" class="small muted">−10% dal TDEE, circa −230 kcal al giorno</td></tr></tfoot></table></div>
        <div class="prose small">
          <p>Proteine a 2,2 g/kg per proteggere e costruire muscolo mentre perdi grasso. Carboidrati concentrati nei giorni in cui ti alleni, grassi un po' più alti nei giorni OFF per saziarti. Per il grasso conta la media della settimana.</p>
          <p><strong>Perché non 1850 fisse:</strong> con 4 allenamenti più la scuola sarebbero −450 kcal al giorno (−20%). Scenderesti più in fretta sulla bilancia, ma i carichi si fermerebbero (soprattutto la schiena, che devi costruire) e arriveresti affamato alle 14:30.</p>
          <p><strong>Cosa aspettarti:</strong> nelle prime 1–2 settimane la bilancia può salire di 0,3–0,8 kg (glicogeno e acqua). Poi −0,1/−0,25 kg a settimana, con il girovita che scende e i carichi che salgono. Proiezione a metà gennaio 2027: circa 63 kg, −2,5/−3 kg di grasso, +0,5/+1 kg di massa magra, grasso sulla bilancia intorno al 14%.</p>
        </div>
      </section>
    </div>`;
  }

  function guidaAlimenti() {
    const ids = Object.keys(D.foods).sort((a, b) => D.foods[a].cat.localeCompare(D.foods[b].cat, 'it') || D.foods[a].n.localeCompare(D.foods[b].n, 'it'));
    return `<div class="stack">
      <section class="card stack">
        <div class="row"><h2>Database alimenti</h2><span class="spacer"></span><span class="badge off">${ids.length} alimenti</span></div>
        <p class="small muted">Valori per 100 g (peso da crudo per carne, pesce, pasta, riso e patate). Sono i numeri usati in tutti i calcoli del piano. Se compri una marca con valori diversi, la differenza è di solito entro il ±5%.</p>
        <label class="sr" for="foodSearch">Cerca un alimento</label>
        <input id="foodSearch" class="search" type="search" placeholder="Cerca: pollo, pasta, yogurt…" autocomplete="off">
        <div class="tbl-wrap"><table id="foodTable"><thead><tr><th>Alimento</th><th class="r">kcal</th><th class="r">P</th><th class="r">C</th><th class="r">G</th><th>Fonte</th></tr></thead><tbody>
          ${ids.map((id) => { const f = D.foods[id]; return `<tr data-n="${esc(f.n.toLowerCase())}"><td>${esc(f.n)}${f.note ? `<br><span class="tiny muted">${esc(f.note)}</span>` : ''}</td><td class="r">${f0(f.k)}</td><td class="r">${f1(f.p)}</td><td class="r">${f1(f.c)}</td><td class="r">${f1(f.f)}</td><td class="tiny muted">${esc(f.src)}</td></tr>`; }).join('')}
        </tbody></table></div>
      </section>
      <section class="card stack"><h2>Nota sulla tua whey</h2>
        <p class="small">L'etichetta della Prozis 100% Real Whey gusto Brownie (Open Food Facts) riporta <strong>72 g di proteine ogni 100 g</strong>, cioè <strong>21,6 g per scoop da 30 g</strong>, non 24. Nel piano ho usato il valore dell'etichetta. Se sul tuo barattolo c'è scritto diversamente, va aggiornato.</p>
        <p class="small">Anche lo <strong>Special K "Protein"</strong> ha solo 12 g di proteine per 100 g: le proteine vere della yogurt bowl vengono dallo yogurt greco.</p>
      </section>
      <section class="card stack"><h2>Cibi esclusi dal piano</h2>
        <div class="pill-list no">${['Lenticchie', 'Ceci', 'Fagioli', 'Piselli', 'Verdure cotte', 'Finocchio', 'Cavolo', 'Sedano', 'Rucola', 'Radicchio', 'Avocado', 'Ricotta', 'Patate dolci', 'Couscous', 'Farro'].map((x) => `<span>${x}</span>`).join('')}</div>
        <p class="tiny muted">Unica verdura cotta ammessa: pomodoro in passata o nel sugo.</p>
      </section>
    </div>`;
  }

  function guidaRegole() {
    return `<div class="grid2">
      <section class="card prose small"><h2>Merende a scuola</h2>
        <ul><li>Tutto si prepara <strong>la sera prima in 5 minuti</strong>: panino in carta stagnola, frutta intera, frutta secca in un sacchettino.</li>
        <li>Niente tonno, uova o sgombro a scuola (odore), niente contenitori, niente cucchiaino.</li>
        <li>La merenda delle 9:30 è il tuo primo pasto: non saltarla, altrimenti arrivi affamato al pranzo pre-workout.</li>
        <li>Bevi acqua durante la mattina: almeno 500 ml prima di pranzo.</li></ul></section>
      <section class="card prose small"><h2>Pasto libero</h2>
        <ul><li>1 a settimana, sabato o domenica a pranzo (nel piano è domenica: puoi scambiare i giorni).</li>
        <li>Una porzione normale: pizza, hamburger con patatine piccole, sushi da 12–16 pezzi.</li>
        <li>Niente antipasto + dolce + bis, e non diventa una giornata libera.</li>
        <li>Il resto della giornata è già più leggero (circa 1100 kcal) per lasciargli spazio.</li></ul></section>
      <section class="card prose small"><h2>Recupero</h2>
        <ul><li><strong>Sonno:</strong> 8 ore (22:30 → 6:30). È metà della ricomposizione.</li>
        <li><strong>Acqua:</strong> 2,5–3 litri al giorno, +0,5 litri nei giorni di palestra.</li>
        <li><strong>Passi:</strong> 7–8 mila al giorno, 8–10 mila nei giorni OFF.</li>
        <li><strong>Creatina monoidrato</strong> (facoltativa): 3–5 g al giorno, tutti i giorni. È l'integratore più studiato, ma aggiunge 0,5–1 kg d'acqua sulla bilancia.</li></ul></section>
      <section class="card prose small"><h2>Misure e correzioni</h2>
        <ul><li>Peso almeno 4 mattine a settimana: conta la <strong>media settimanale</strong>, non il singolo giorno.</li>
        <li>Girovita all'ombelico ogni lunedì, foto ogni 4 settimane, bilancia BIA sempre nelle stesse condizioni.</li>
        <li>Calo oltre 0,4 kg a settimana per 2 settimane → +150 kcal.</li>
        <li>Peso e girovita fermi per 3 settimane → −100/150 kcal oppure +2000 passi.</li>
        <li>Carichi in calo per 2 settimane → +100 kcal nei giorni ON e più sonno.</li></ul></section>
    </div>`;
  }

  /* ================= ROUTER & EVENTI ================= */
  const routes = { oggi: viewOggi, piano: viewPiano, scheda: () => (window.RCW ? window.RCW.view() : ''), progressi: viewProgressi, guida: viewGuida };
  const titles = { oggi: 'Oggi', piano: 'Piano', scheda: 'Scheda', progressi: 'Progressi', guida: 'Guida' };
  let current = '';
  function render(scrollTop) {
    const name = (location.hash.replace(/^#\/?/, '').split('/')[0]) || 'oggi';
    const r = routes[name] ? name : 'oggi';
    if (r !== 'scheda' && wake.want) wakeOff();
    $$('.nav a').forEach((a, i) => {
      if (a.dataset.route === r) { a.setAttribute('aria-current', 'page'); a.parentElement.style.setProperty('--i', i); } else a.removeAttribute('aria-current');
    });
    const y = window.scrollY;
    main.classList.remove('page-in'); // l'animazione di comparsa solo quando si cambia sezione, non a ogni aggiornamento
    main.innerHTML = (r !== 'scheda' && window.RCW ? window.RCW.banner() : '') + routes[r]();
    document.title = `${titles[r]} · Recomp`;
    if (r !== current && current) main.classList.add('page-in');
    if (scrollTop || r !== current) { window.scrollTo(0, 0); if (r !== current && current) main.focus({ preventScroll: true }); }
    else window.scrollTo(0, y);
    current = r;
  }
  window.addEventListener('hashchange', () => render(true));

  main.addEventListener('click', (ev) => {
    const tw = ev.target.closest('[data-w]');
    if (tw && window.RCW && window.RCW.click(tw)) { ev.preventDefault(); return; }
    const t = ev.target.closest('[data-act]');
    if (!t) return;
    const act = t.dataset.act;
    if (act === 'eat') {
      const key = dkey(new Date());
      const all = store.get('eaten', {});
      const arr = new Set(all[key] || []);
      const si = Number(t.dataset.si);
      if (arr.has(si)) arr.delete(si); else arr.add(si);
      all[key] = Array.from(arr);
      Object.keys(all).forEach((k) => { if ((fromKey(key) - fromKey(k)) / 86400000 > 10) delete all[k]; });
      store.set('eaten', all); buzz(); render();
    } else if (act === 'ptab') { ui.pianoTab = t.dataset.tab; render(); }
    else if (act === 'gtab') { ui.guidaTab = t.dataset.tab; render(); }
    else if (act === 'pday') { ui.pianoDay = Number(t.dataset.di); render(); }
    else if (act === 'resetday') {
      const sw = store.get('swaps', {}); const di = t.dataset.di;
      Object.keys(sw).forEach((k) => { if (k.split(':')[0] === di) delete sw[k]; });
      store.set('swaps', sw); render();
    } else if (act === 'shopreset') { store.set('shop', {}); render(); }
    else if (act === 'rest') { startTimer(Number(t.dataset.s)); }
    else if (act === 'toggle') {
      const el = document.getElementById(t.dataset.t);
      if (el) { el.classList.toggle('hidden'); t.setAttribute('aria-expanded', String(!el.classList.contains('hidden'))); }
    } else if (act === 'wdel') {
      store.set('weights', rawWeights().filter((w) => w.d !== t.dataset.d).concat([{ d: t.dataset.d, del: 1, t: Date.now() }])); render();
    } else if (act === 'export') {
      const out = {};
      try { for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); if (k.startsWith('rc.')) out[k] = localStorage.getItem(k); } } catch (e) { /* ignora */ }
      const json = JSON.stringify({ app: 'recomp', date: dkey(new Date()), data: out }, null, 2);
      const name = `recomp-backup-${dkey(new Date())}.json`;
      const download = () => {
        const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([json], { type: 'application/json' })); a.download = name;
        document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 500);
      };
      // Su iPhone il foglio Condividi permette "Salva su File", AirDrop o l'invio a te stesso
      let file = null;
      try { file = new File([json], name, { type: 'application/json' }); } catch (e) { file = null; }
      if (file && navigator.canShare && navigator.canShare({ files: [file] })) {
        navigator.share({ files: [file], title: 'Backup Recomp' }).catch((e) => { if (e && e.name !== 'AbortError') download(); });
      } else download();
    } else if (act === 'sync-signup' && window.RCSync) {
      window.RCSync.signup($('#syncEmail').value.trim(), $('#syncPw').value);
    } else if (act === 'sync-logout' && window.RCSync) { window.RCSync.logout(); }
    else if (act === 'sync-now' && window.RCSync) { window.RCSync.now(); }
    else if (act === 'installhide') { store.set('installHidden', true); render(); }
    else if (act === 'install' && installEvt) {
      installEvt.prompt(); installEvt.userChoice.finally(() => { installEvt = null; render(); });
    } else if (act === 'wake') {
      if (wake.want) wakeOff(); else { wake.want = true; wakeOn(); }
      render();
    }
  });

  main.addEventListener('change', (ev) => {
    const t = ev.target;
    if (t.dataset.act === 'swap') {
      const sw = store.get('swaps', {});
      const k = t.dataset.di + ':' + t.dataset.si;
      if (t.value === D.week[Number(t.dataset.di)].pick[Number(t.dataset.si)]) delete sw[k]; else sw[k] = t.value;
      store.set('swaps', sw); render();
    } else if (t.dataset.act === 'shop') {
      const s = store.get('shop', {}); if (t.checked) s[t.dataset.id] = 1; else delete s[t.dataset.id];
      store.set('shop', s); t.closest('li').classList.toggle('got', t.checked);
      const tot = Object.keys(shoppingList()); const b = t.closest('.card').querySelector('.badge');
      if (b) b.textContent = `${tot.filter((id) => s[id]).length}/${tot.length}`;
    } else if (t.dataset.act === 'rem') {
      setReminder(t.dataset.k, t.checked);
    } else if (t.dataset.act === 'blockstart') {
      if (t.value) { store.set('blockStart', t.value); render(); }
    } else if (t.id === 'importFile' && t.files && t.files[0]) {
      const msg = $('#impMsg');
      const rd = new FileReader();
      rd.onload = () => {
        try {
          const j = JSON.parse(rd.result);
          if (!j || j.app !== 'recomp' || typeof j.data !== 'object') throw new Error('formato');
          const meta = JSON.parse(localStorage.getItem('rc._meta') || '{}');
          Object.keys(j.data).forEach((k) => {
            if (k.startsWith('rc.') && k !== 'rc._meta' && typeof j.data[k] === 'string') { localStorage.setItem(k, j.data[k]); meta[k] = Date.now(); }
          });
          localStorage.setItem('rc._meta', JSON.stringify(meta));
          window.dispatchEvent(new CustomEvent('rc-change', { detail: 'import' }));
          render(); const m2 = $('#impMsg'); if (m2) { m2.style.color = 'var(--ok)'; m2.textContent = 'Backup importato.'; }
        } catch (e) { msg.textContent = 'File non valido: scegli un backup esportato da questo sito.'; }
      };
      rd.readAsText(t.files[0]);
    }
  });

  main.addEventListener('input', (ev) => {
    const t = ev.target;
    if (t.dataset.wi && window.RCW) { window.RCW.input(t); return; }
    if (t.id === 'foodSearch') {
      const q = t.value.trim().toLowerCase();
      $$('#foodTable tbody tr').forEach((tr) => { tr.classList.toggle('hidden', !!q && !tr.dataset.n.includes(q)); });
    }
  });

  main.addEventListener('submit', (ev) => {
    if (ev.target.id === 'syncForm') {
      ev.preventDefault();
      if (window.RCSync) window.RCSync.login($('#syncEmail').value.trim(), $('#syncPw').value);
      return;
    }
    if (ev.target.id !== 'wForm') return;
    ev.preventDefault();
    const err = $('#wErr');
    const d = $('#wDate').value;
    const kg = num($('#wKg').value);
    const wRaw = $('#wWaist').value;
    const w = num(wRaw);
    if (!d) { err.textContent = 'Scegli la data.'; return; }
    if (kg == null || kg < 35 || kg > 150) { err.textContent = 'Scrivi un peso valido in kg (es. 64,7).'; $('#wKg').focus(); return; }
    if (wRaw.trim() && (w == null || w < 40 || w > 150)) { err.textContent = 'La vita va in centimetri (es. 78,5) oppure lasciala vuota.'; $('#wWaist').focus(); return; }
    const ws = rawWeights().filter((x) => x.d !== d);
    const e = { d, kg: Math.round(kg * 100) / 100, t: Date.now() };
    if (w != null) e.w = r1(w);
    ws.push(e);
    store.set('weights', ws);
    buzz('MEDIUM');
    render();
  });
  main.addEventListener('input', (ev) => { if (ev.target.closest && ev.target.closest('#wForm')) { const e = $('#wErr'); if (e) e.textContent = ''; } });

  /* ---------------- barra in basso: tieni premuto e trascina (come iOS 26) ---------------- */
  // La bolla segue il dito, la sezione sotto il dito si "ingrandisce" e al rilascio si apre.
  // Per restare fluida: la barra si misura una volta a inizio gesto, la bolla si muove solo con transform
  // (lavoro della GPU) e la posizione si aggiorna al massimo una volta per fotogramma.
  (function navDrag() {
    const nav = $('.nav');
    const links = $$('.nav a');
    const bubble = document.createElement('span');
    bubble.className = 'nav-bubble';
    bubble.setAttribute('aria-hidden', 'true');
    nav.prepend(bubble);
    const mobile = window.matchMedia('(max-width: 899px)');
    const PAD = 6;
    let drag = null;
    let swallowClick = false;
    function frame() {
      if (!drag) return;
      drag.raf = 0;
      const dx = Math.max(0, Math.min((links.length - 1) * drag.w, drag.x - drag.left - PAD - drag.w / 2));
      bubble.style.transform = `translate3d(${dx}px, 0, 0) scale(1.14, 1.2)`;
      const idx = Math.round(dx / drag.w);
      if (idx !== drag.idx) {
        if (drag.idx >= 0) links[drag.idx].classList.remove('lens');
        links[idx].classList.add('lens');
        if (drag.idx >= 0 && N.haptics) safe(N.haptics.selectionChanged());
        drag.idx = idx;
      }
    }
    const schedule = () => { if (drag && !drag.raf) drag.raf = requestAnimationFrame(frame); };
    nav.addEventListener('pointerdown', (e) => {
      if (!mobile.matches || (e.pointerType === 'mouse' && e.button !== 0) || !e.target.closest('a')) return;
      const r = nav.getBoundingClientRect();
      drag = { id: e.pointerId, x0: e.clientX, x: e.clientX, left: r.left, w: (r.width - 2 * PAD) / links.length, idx: -1, raf: 0 };
      try { nav.setPointerCapture(e.pointerId); } catch (err) { /* ignora */ }
      nav.classList.add('dragging');
      frame();
      if (N.haptics) safe(N.haptics.selectionStart());
    });
    nav.addEventListener('pointermove', (e) => {
      if (!drag || e.pointerId !== drag.id) return;
      drag.x = e.clientX;
      schedule();
    });
    function end(e, go) {
      if (!drag || (e && e.pointerId !== drag.id)) return;
      if (drag.raf) cancelAnimationFrame(drag.raf);
      const idx = drag.idx;
      drag = null;
      nav.classList.remove('dragging');
      links.forEach((a) => a.classList.remove('lens'));
      if (N.haptics) safe(N.haptics.selectionEnd());
      if (go && idx >= 0) nav.style.setProperty('--i', idx);
      bubble.style.transform = ''; // torna alla posizione di --i con il rimbalzo del CSS
      if (!go || idx < 0) return;
      swallowClick = true; setTimeout(() => { swallowClick = false; }, 400);
      const href = links[idx].getAttribute('href');
      if (location.hash !== href) location.hash = href;
      buzz();
    }
    nav.addEventListener('pointerup', (e) => end(e, true));
    nav.addEventListener('pointercancel', (e) => end(e, false));
    nav.addEventListener('lostpointercapture', (e) => { if (drag) end(e, false); });
    // il "click" che segue il rilascio è già gestito sopra
    nav.addEventListener('click', (e) => { if (swallowClick) e.preventDefault(); });
  })();

  /* ---------------- tema ---------------- */
  const themeBtn = $('#themeBtn');
  const mq = window.matchMedia('(prefers-color-scheme: dark)');
  function effectiveTheme() { const t = document.documentElement.getAttribute('data-theme'); return t || (mq.matches ? 'dark' : 'light'); }
  function paintThemeBtn() { const dark = effectiveTheme() === 'dark'; themeBtn.innerHTML = dark ? I.sun : I.moon; themeBtn.setAttribute('aria-label', dark ? 'Passa al tema chiaro' : 'Passa al tema scuro'); }
  themeBtn.addEventListener('click', () => {
    const next = effectiveTheme() === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next); store.set('theme', next); paintThemeBtn();
  });
  if (mq.addEventListener) mq.addEventListener('change', paintThemeBtn);
  paintThemeBtn();

  /* ---------------- ponte con sync.js ---------------- */
  // I dati arrivati dall'altro dispositivo ridisegnano la pagina, ma non mentre stai scrivendo in un campo.
  let pendingRefresh = false;
  const typing = () => { const a = document.activeElement; return !!(a && main.contains(a) && /^(INPUT|SELECT|TEXTAREA)$/.test(a.tagName)); };
  window.RC = {
    refresh(force) { if (!force && typing()) { pendingRefresh = true; return; } pendingRefresh = false; render(); },
  };
  main.addEventListener('focusout', () => { if (pendingRefresh) setTimeout(() => { if (!typing()) { pendingRefresh = false; render(); } }, 0); });

  /* ---------------- ponte con allenamento.js ---------------- */
  window.RCK = {
    D, store, esc, f0, f1, f2, sign, r1, num, dkey, fromKey, shortDate, dayIdx, I, cap, restTxt, fmtKg,
    startTimer, buzz, blockWeek, wakeChip, render: (top) => render(top),
  };
  if (window.RCW) window.RCW.migrate();

  /* ---------------- avvio ---------------- */
  render(true);
  if (isNative) {
    scheduleReminders();
    let remT = 0;
    window.addEventListener('rc-change', (e) => { if (e.detail === 'rc.swaps') { clearTimeout(remT); remT = setTimeout(scheduleReminders, 1500); } });
  }
  // App installata: chiede al sistema di non cancellare i dati salvati (pesi, carichi)
  if (isStandalone() && navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});
  if ('serviceWorker' in navigator && location.protocol === 'https:') {
    window.addEventListener('load', () => navigator.serviceWorker.register('sw.js').catch(() => {}));
  }
})();
