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
    camera: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/></svg>',
    reset: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/></svg>',
    trash: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 6h18M8 6V4h8v2M6 6l1 14h10l1-14"/></svg>',
    down: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12M7 10l5 5 5-5M5 21h14"/></svg>',
    up: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 21V9M7 14l5-5 5 5M5 3h14"/></svg>',
    sun: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
    moon: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9z"/></svg>',
    play: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 4.5v15l12-7.5z"/></svg>',
    arrow: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6"/></svg>',
    pill: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m10.5 20.5 10-10a4.95 4.95 0 1 0-7-7l-10 10a4.95 4.95 0 1 0 7 7Z"/><path d="m8.5 8.5 7 7"/></svg>',
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
  const N = { notif: plugin('LocalNotifications'), haptics: plugin('Haptics'), status: plugin('StatusBar'), live: plugin('RestActivity') }; // RestActivity: plugin di Recomp (app-ios/native)
  const safe = (p) => { try { return Promise.resolve(p).catch(() => null); } catch (e) { return Promise.resolve(null); } };
  const buzz = (style = 'LIGHT') => { if (N.haptics) safe(N.haptics.impact({ style })); };
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
  const REM = { merenda: 'Merenda di domani (21:00)', peso: 'Pesata del mattino', palestra: 'Palestra (16:00 nei giorni ON)', creatina: 'Creatina, se non l’hai ancora segnata' };
  const CREA_AT = '20:30';
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
        const sn = p.meals.filter((m) => /^m[12]/.test(m.slot)) // merende di scuola (m1/m2 e le versioni dei giorni OFF).map((m) => `${m.code} ${D.recipes[m.code].name}`);
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
        const whey = dayPlan(di).meals.some((m) => m.slot === 'pw' && m.code === 'PW-A');
        list.push({ id: 120 + di, title: `Alle 16:30: ${w.name}`, body: `${w.focus}. Borraccia e asciugamano${whey ? ', shaker con 30 g di whey' : ''}.`, schedule: { on: { weekday: wd(di), hour: 16, minute: 0 }, allowWhileIdle: true } });
      });
    }
    if (list.length) await safe(N.notif.schedule({ notifications: list }));
  }
  // Creatina: una notifica al giorno per i prossimi 14 giorni, ciascuna con il suo numero fisso (140–153):
  // riprogrammarle non crea doppioni. Il giorno in cui la spunti, la notifica di quel giorno viene tolta.
  async function scheduleCreatine() {
    if (!N.notif) return;
    await safe(N.notif.cancel({ notifications: Array.from({ length: 14 }, (_, i) => ({ id: 140 + i })) }));
    const prefs = store.get('reminders', {});
    if (!prefs.creatina) return;
    const [h, m] = (prefs.creatinaAt || CREA_AT).split(':').map(Number);
    const taken = store.get('creatina', {});
    const list = [];
    for (let i = 0; i < 14; i++) {
      const at = new Date(); at.setDate(at.getDate() + i); at.setHours(h, m, 0, 0);
      const o = taken[dkey(at)];
      if (at.getTime() <= Date.now() + 30000 || (o && o.on)) continue; // orario già passato oppure già presa
      list.push({ id: 140 + i, title: 'Creatina', body: 'Oggi non l’hai ancora segnata: 3–5 g con un bicchiere d’acqua.', schedule: { at, allowWhileIdle: true } });
    }
    if (list.length) await safe(N.notif.schedule({ notifications: list }));
  }
  let creaT = 0;
  const creatineSoon = () => { if (!isNative) return; clearTimeout(creaT); creaT = setTimeout(scheduleCreatine, 800); };
  async function setReminder(key, on) {
    if (on && N.notif) {
      const perm = await safe(N.notif.requestPermissions());
      if (!perm || perm.display !== 'granted') { store.set('reminders', { ...store.get('reminders', {}), [key]: false }); alert('Per i promemoria consenti le notifiche a Recomp in Impostazioni → Notifiche.'); return; }
    }
    store.set('reminders', { ...store.get('reminders', {}), [key]: on });
    await scheduleReminders();
    await scheduleCreatine();
    if (key === 'creatina') render();
  }

  function nativeCards() {
    if (!isNative) return '';
    const rem = store.get('reminders', {});
    const notif = N.notif ? `<section class="card stack"><h2>Promemoria</h2>
      ${Object.entries(REM).map(([k, l]) => `<label class="row small" style="justify-content:space-between;cursor:pointer"><span>${l}</span><input type="checkbox" data-act="rem" data-k="${k}"${rem[k] ? ' checked' : ''} style="width:22px;height:22px;accent-color:var(--ink)"></label>`).join('')}
      ${rem.creatina ? `<div class="field"><label for="creaAt">Ora del promemoria creatina</label><input id="creaAt" type="time" data-act="crea-time" value="${esc(rem.creatinaAt || CREA_AT)}"></div>` : ''}
      <p class="tiny muted">La creatina avvisa solo se a quell’ora non l’hai ancora spuntata in Oggi. La merenda arriva la sera prima dei giorni di scuola con i nomi delle merende (scambi compresi). Il timer di recupero manda una notifica anche a schermo bloccato.</p>
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
  // Giorni «modificati»: rc.dayov = { 'AAAA-MM-GG': { skip, rid, type: 'ON' | 'OFF' | '', keep: [pasti già mangiati], t } }
  const dayOv = (key) => { const o = store.get('dayov', {})[key]; return o && !o.del ? o : null; };
  function setDayOv(key, v) {
    const all = store.get('dayov', {});
    all[key] = v ? { ...v, t: Date.now() } : { del: 1, t: Date.now() };
    store.set('dayov', all);
  }
  // conv = { type: 'ON' | 'OFF_S', keep: [...] }: la giornata usa le fasce dell'altro tipo (stessi orari, 5 pasti).
  // I pasti in keep erano già stati mangiati al momento del cambio e restano nella versione originale.
  function dayPlan(di, conv) {
    const day = D.week[di];
    const base = D.daytypes[day.type];
    const other = conv && conv.type !== day.type ? D.daytypes[conv.type] : null;
    const alt = other && other.slots.length === base.slots.length ? other : null;
    const model = alt ? D.week.find((d) => d.type === conv.type) : null; // giorno-modello: da lì il pasto di default delle fasce nuove
    const swaps = store.get('swaps', {});
    const meals = base.slots.map((s0, si) => {
      const useAlt = alt && !(conv.keep || []).includes(si);
      const [time, label, slot] = useAlt ? alt.slots[si] : s0;
      if (slot === 'free') return { si, time, label, slot, free: true };
      const def = D.variants[slot][day.pick[si]] ? day.pick[si] : model.pick[si];
      const sw = swaps[di + ':' + si];
      const code = sw && D.variants[slot][sw] ? sw : def;
      const lines = mealLines(slot, code);
      return { si, time, label, slot, code, def, lines, tot: sumLines(lines) };
    });
    let k = 0, p = 0, c = 0, fa = 0;
    for (const m of meals) if (!m.free) { k += m.tot.k; p += m.tot.p; c += m.tot.c; fa += m.tot.fa; }
    return { di, day, dt: alt || base, conv: alt ? conv.type : '', meals, tot: { k, p: r1(p), c: r1(c), fa: r1(fa) }, hasFree: meals.some((m) => m.free) };
  }
  // il piano di oggi tiene conto di un eventuale cambio fatto oggi; le altre pagine mostrano la settimana tipo
  function todayPlan() {
    const now = new Date();
    const ov = dayOv(dkey(now));
    return dayPlan(dayIdx(now), ov && ov.type ? { type: ov.type === 'ON' ? 'ON' : 'OFF_S', keep: ov.keep || [] } : null);
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

  // nomi delle unità pratiche: confezioni, fette e pezzi (il peso di una unità è f.u nel database)
  const UNITS = {
    uovo: ['uovo', 'uova'], sottiletta: ['fetta', 'fette'], kiwi: ['kiwi', 'kiwi'], crackers: ['pacchetto', 'pacchetti'],
    fette_bisc: ['fetta', 'fette'], pancarre: ['fetta', 'fette'], barretta: ['barretta', 'barrette'], gallette: ['galletta', 'gallette'],
    // le confezioni dicono sempre quanto pesano: chi pesa il cibo guarda i grammi, la confezione è solo un aiuto
    bresaola: ['vaschetta da 80 g', 'vaschette da 80 g'], cotto: ['vaschetta da 100 g', 'vaschette da 100 g'], tacchino_arrosto: ['vaschetta da 100 g', 'vaschette da 100 g'],
    tonno_nat: ['scatoletta da 80 g', 'scatolette da 80 g'], mozz_light: ['mozzarella da 125 g', 'mozzarelle da 125 g'],
    pane_int: ['fetta', 'fette'], pane_segale: ['fetta', 'fette'], piadina: ['piadina', 'piadine'], banana: ['banana', 'banane'], mela: ['mela', 'mele'], pera: ['pera', 'pere'],
  };
  const YOGURT_PACK = { 100: '⅔ di vasetto da 150 g', 150: '1 vasetto da 150 g', 170: '1 vasetto da 170 g', 200: '1 vasetto da 200 g', 250: 'mezza confezione da 500 g', 300: '2 vasetti da 150 g', 340: '2 vasetti da 170 g' };
  const SPOONS = { avena: [10, 'cucchiaio', 'cucchiai'], miele: [5, 'cucchiaino', 'cucchiaini'], parmigiano: [5, 'cucchiaino', 'cucchiaini'], pesto: [20, 'cucchiaio', 'cucchiai'], phila: [15, 'cucchiaio', 'cucchiai'], marmellata0: [10, 'cucchiaino', 'cucchiaini'], crema_proteica: [15, 'cucchiaino colmo', 'cucchiaini colmi'] };
  const PIECES = { mandorle: [1.2, 'mandorle'], nocciole: [1.3, 'nocciole'], noci: [5, 'noci'], cioccolato85: [10, 'quadratini'] };
  // shop = lista della spesa: lì servono le confezioni intere da comprare, non i cucchiai
  function unitHint(fid, g, shop) {
    if (fid === 'whey') {
      const n = g / 30;
      return Math.abs(n - 0.5) < 0.05 ? 'mezzo scoop' : `${Math.abs(n - Math.round(n)) < 0.05 ? f0(Math.round(n)) : '≈ ' + f1(n)} scoop`;
    }
    if (fid === 'olio') return shop ? '' : g < 4 ? 'un filo' : g % 10 === 0 ? `${g / 10} ${g === 10 ? 'cucchiaio' : 'cucchiai'}` : `${f0(g / 5)} ${g <= 7 ? 'cucchiaino' : 'cucchiaini'}`;
    if (fid === 'yogurt') return shop ? `≈ ${Math.ceil(g / 170)} vasetti da 170 g` : (YOGURT_PACK[g] || '');
    if (!shop && SPOONS[fid]) { const [u, one, many] = SPOONS[fid]; const n = Math.max(1, Math.round(g / u)); return `${Math.abs(g / u - n) < 0.1 ? '' : '≈ '}${n} ${n === 1 ? one : many}`; }
    if (!shop && PIECES[fid]) return `≈ ${Math.round(g / PIECES[fid][0])} ${PIECES[fid][1]}`;
    const f = D.foods[fid];
    if (!f.u || !UNITS[fid]) return '';
    const n = g / f.u;
    if (shop) { const c = Math.max(1, Math.ceil(n - 0.1)); return `≈ ${c} ${c === 1 ? UNITS[fid][0] : UNITS[fid][1]}`; }
    if (/^(mela|pera|banana)$/.test(fid) && n > 1.15 && n < 1.45) return `1 ${UNITS[fid][0]} grande`;
    const h = Math.max(0.5, Math.round(n * 2) / 2); // mezze unità: ½ vaschetta, 1 e ½ fette…
    const txt = h === 0.5 ? '½' : h % 1 ? `${Math.floor(h)} e ½` : String(h);
    return `${Math.abs(n - h) < 0.08 ? '' : '≈ '}${txt} ${h <= 1 ? UNITS[fid][0] : UNITS[fid][1]}`;
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
      ${opt.swap ? `<div class="meal-f"><button type="button" class="btn ghost" data-act="meal-open" data-di="${plan.di}" data-si="${m.si}">${I.swap} Scambia pasto</button></div>` : ''}
    </article>`;
  }

  function typeBadge(day, plan) {
    if (plan && plan.conv) return plan.conv === 'ON' ? '<span class="badge on">ON · recupero</span>' : '<span class="badge off">OFF · palestra saltata</span>';
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
    profTab: 'impostazioni',
  };

  // Oggi: anello grande delle calorie e tre anelli piccoli per proteine, carboidrati e grassi
  function arc(r, c0, v, t, cls) {
    const c = 2 * Math.PI * r;
    const pct = Math.max(0, Math.min(1, t ? v / t : 0));
    return `<circle class="rg-bg" cx="${c0}" cy="${c0}" r="${r}"/><circle class="rg ${cls}" cx="${c0}" cy="${c0}" r="${r}" stroke-dasharray="${c.toFixed(1)}" stroke-dashoffset="${(c * (1 - pct)).toFixed(1)}" transform="rotate(-90 ${c0} ${c0})"/>`;
  }
  const rings = (k, kt) => `<svg class="rings" viewBox="0 0 140 140" role="img" aria-label="Calorie ${f0(k)} di ${f0(kt)}">${arc(60, 70, k, kt, 'k')}</svg>`;
  const macroRing = (cls, name, v, t) => `<div class="mring"><svg viewBox="0 0 44 44" role="img" aria-label="${name}: ${f0(v)} di ${f0(t)} grammi">${arc(17, 22, v, t, cls)}</svg>
    <div class="mring-t"><span>${name}</span><b>${f0(v)}<small> / ${f0(t)} g</small></b></div></div>`;
  const toMin = (t) => { const [h, m] = t.split(':').map(Number); return h * 60 + m; };
  const inMin = (d) => (d <= 0 ? (d > -15 ? 'adesso' : `${Math.abs(d)} min fa`) : d < 60 ? `tra ${d} min` : `tra ${Math.floor(d / 60)} h ${String(d % 60).padStart(2, '0')}`);

  // card "Adesso": la prossima cosa da fare, in base all'ora e a cosa hai già segnato
  function adessoCard(plan, eaten, w) {
    const now = new Date();
    const nm = now.getHours() * 60 + now.getMinutes();
    const items = plan.meals.filter((m) => !m.free).map((m) => ({ t: toMin(m.time), meal: m, done: eaten.includes(m.si) }));
    const gymDone = w && window.RCW && window.RCW.doneToday(w.id);
    if (w) items.push({ t: toMin('16:30'), gym: true, done: gymDone });
    items.sort((a, b) => a.t - b.t);
    const next = items.find((x) => !x.done && x.t >= nm - 60) || items.find((x) => !x.done);
    if (!next) {
      return `<section class="card adesso done"><p class="eyebrow">Adesso</p><h2>Giornata completata 🎉</h2><p class="small muted">Hai segnato tutti i pasti${w ? " e fatto l'allenamento" : ''}. Domani si continua.</p></section>`;
    }
    const late = next.t - nm < -15;
    const when = late ? 'da segnare' : inMin(next.t - nm);
    if (next.gym) {
      const active = window.RCW && window.RCW.isActive();
      return `<section class="card adesso gym"><p class="eyebrow">${late ? 'Allenamento di oggi' : when === 'adesso' ? 'Adesso' : 'Adesso · ' + when}</p><h2>16:30 · ${esc(w.name)}</h2><p class="small">${esc(w.focus)} · pesi ~60′ + tapis 15–20′</p>
        <div class="row"><button type="button" class="btn" data-w="start" data-rid="${w.id}">${I.play} ${active ? 'Riprendi' : 'Inizia'} l'allenamento</button>${active ? '' : '<button type="button" class="chip" data-act="skip-open">Oggi la salto</button>'}</div></section>`;
    }
    const m = next.meal;
    return `<section class="card adesso"><p class="eyebrow">${late ? 'Da segnare · era alle ' + m.time : when === 'adesso' ? 'Adesso' : 'Adesso · ' + when}</p><h2>${m.time} · ${esc(m.label)}</h2>
      <p class="small">${esc(D.recipes[m.code].name)} · <strong>${m.tot.k} kcal</strong> · P ${f1(m.tot.p)}</p>
      <div class="row"><button type="button" class="btn" data-act="eat" data-si="${m.si}">${I.check} Segna come mangiato</button><button type="button" class="chip" data-act="meal-open" data-td="1" data-di="${plan.di}" data-si="${m.si}">Dettagli</button></div></section>`;
  }

  // riga compatta di un pasto: tocco = dettagli, scorri a destra = mangiato
  function mealRow(plan, m, eaten) {
    if (m.free) {
      return `<li class="mrow free"><button type="button" class="mrow-main" data-act="meal-open" data-td="1" data-di="${plan.di}" data-si="${m.si}"><span class="mrow-t">${m.time}</span><span class="mrow-n"><b>Pasto libero</b><small>1 porzione normale · non conteggiato</small></span></button></li>`;
    }
    const on = eaten.includes(m.si);
    return `<li class="mrow${on ? ' done' : ''}" data-swipe="eat" data-si="${m.si}">
      <span class="mrow-bg" aria-hidden="true">${I.check}</span>
      <div class="mrow-fg">
        <button type="button" class="mrow-main" data-act="meal-open" data-td="1" data-di="${plan.di}" data-si="${m.si}">
          <span class="mrow-t">${m.time}</span>
          <span class="mrow-n"><b>${esc(m.label)}</b><small>${esc(D.recipes[m.code].name)}</small></span>
          <span class="mrow-k"><b>${m.tot.k}</b><small>P ${f1(m.tot.p)}</small></span>
        </button>
        <button type="button" class="check" data-act="eat" data-si="${m.si}" aria-pressed="${on}" aria-label="Segna ${esc(m.label)} come mangiato">${I.check}</button>
      </div>
    </li>`;
  }

  // pannello di un pasto: ingredienti, preparazione e scambio a schede
  // td = aperto dalla pagina Oggi: vale il piano di oggi (anche se la giornata è stata cambiata)
  function mealSheetHtml(di, si, td) {
    const plan = td ? todayPlan() : dayPlan(di);
    const m = plan.meals[si];
    const isToday = di === dayIdx(new Date());
    if (m.free) {
      return `<div class="stack"><p class="eyebrow">${m.time} · ${esc(plan.day.name)}</p><h2>Pasto libero</h2>
        <p>Una porzione normale di quello che vuoi: pizza, hamburger con patatine piccole, sushi (12–16 pezzi)… Niente antipasto + primo + dolce e niente bis. Stima 800–1000 kcal, fuori dai totali: il resto della giornata è già più leggero per lasciargli spazio.</p>
        <button type="button" class="btn" data-act="sheet-close">Chiudi</button></div>`;
    }
    const r = D.recipes[m.code];
    const on = (store.get('eaten', {})[dkey(new Date())] || []).includes(si);
    const alts = Object.keys(D.variants[m.slot]).map((code) => {
      const t = sumLines(mealLines(m.slot, code));
      const d = t.k - m.tot.k;
      return `<button type="button" class="alt${code === m.code ? ' cur' : ''}" data-act="sheet-swap" data-td="${td ? 1 : ''}" data-di="${di}" data-si="${si}" data-code="${code}"${code === m.code ? ' aria-current="true"' : ''}>
        <span class="alt-c">${code}${code === m.def ? ' · originale' : ''}</span>
        <b>${esc(D.recipes[code].name)}</b>
        <span class="alt-m">${t.k} kcal${code === m.code ? '' : ` <em>${d > 0 ? '+' : d < 0 ? '−' : '±'}${Math.abs(d)}</em>`} · P ${f1(t.p)} · C ${f1(t.c)} · G ${f1(t.fa)}</span>
      </button>`;
    }).join('');
    return `<div class="stack">
      <div><p class="eyebrow">${m.time} · ${esc(m.label)} · ${esc(plan.day.name)}</p><h2><span class="code">${m.code}</span> ${esc(r.name)}</h2></div>
      <div class="mtot"><div><b>${m.tot.k}</b><span>kcal</span></div><div><b>${f1(m.tot.p)}</b><span>proteine</span></div><div><b>${f1(m.tot.c)}</b><span>carbo</span></div><div><b>${f1(m.tot.fa)}</b><span>grassi</span></div></div>
      <ul class="items" style="padding:0">${itemsHtml(m.lines)}</ul>
      ${r.how ? `<p class="small"><strong>Come si prepara:</strong> ${esc(r.how)}</p>` : ''}
      ${isToday ? `<button type="button" class="btn${on ? ' ghost' : ''}" data-act="sheet-eat" data-si="${si}">${I.check} ${on ? 'Togli la spunta' : 'Segna come mangiato'}</button>` : ''}
      <div class="row"><h3>Scambia con</h3>${tip('scambio')}</div>
      <div class="alts">${alts}</div>
      <button type="button" class="chip" data-act="sheet-close">Chiudi</button>
    </div>`;
  }
  function openMeal(di, si, td) { openSheet(mealSheetHtml(di, si, td)); }

  function toggleEaten(si) {
    const key = dkey(new Date());
    const all = store.get('eaten', {});
    const arr = new Set(all[key] || []);
    if (arr.has(si)) arr.delete(si); else arr.add(si);
    all[key] = Array.from(arr);
    Object.keys(all).forEach((k) => { if ((fromKey(key) - fromKey(k)) / 86400000 > 60) delete all[k]; });
    store.set('eaten', all);
    logDay();
    buzz(arr.has(si) ? 'MEDIUM' : 'LIGHT');
  }
  // Diario: per ogni giorno salva quanto hai davvero spuntato (kcal e macro) rispetto al piano di quel giorno.
  // Serve al riepilogo e al Coach per parlare di aderenza con i numeri reali, anche se poi cambi gli scambi.
  function logDay() {
    const key = dkey(new Date());
    const plan = todayPlan();
    const eaten = store.get('eaten', {})[key] || [];
    const e = { k: 0, p: 0, c: 0, fa: 0 };
    let n = 0, of = 0;
    plan.meals.forEach((m) => { if (m.free) return; of++; if (eaten.includes(m.si)) { n++; e.k += m.tot.k; e.p += m.tot.p; e.c += m.tot.c; e.fa += m.tot.fa; } });
    const all = store.get('dlog', {});
    all[key] = { k: e.k, p: r1(e.p), c: r1(e.c), f: r1(e.fa), n, of, tk: plan.tot.k, on: plan.dt === D.daytypes.ON ? 1 : 0, free: plan.hasFree ? 1 : 0, t: Date.now() };
    Object.keys(all).forEach((k) => { if ((fromKey(key) - fromKey(k)) / 86400000 > 200) delete all[k]; });
    store.set('dlog', all);
  }

  /* ---------------- creatina ---------------- */
  const creaOn = (key) => { const o = store.get('creatina', {})[key]; return !!(o && o.on); };
  function toggleCreatine() {
    const key = dkey(new Date());
    const all = store.get('creatina', {});
    all[key] = { on: creaOn(key) ? 0 : 1, t: Date.now() };
    Object.keys(all).forEach((k) => { if ((fromKey(key) - fromKey(k)) / 86400000 > 200) delete all[k]; });
    store.set('creatina', all);
    buzz(all[key].on ? 'MEDIUM' : 'LIGHT');
    creatineSoon();
  }
  function creatineRow(key) {
    const on = creaOn(key);
    let streak = 0;
    for (let d = fromKey(key), first = true; ; d.setDate(d.getDate() - 1), first = false) {
      if (creaOn(dkey(d))) streak++; else if (!first) break; // oggi può essere ancora da prendere
      if (streak > 400) break;
    }
    const prefs = store.get('reminders', {});
    const [h, m] = (prefs.creatinaAt || CREA_AT).split(':').map(Number);
    const now = new Date();
    const late = !on && now.getHours() * 60 + now.getMinutes() >= h * 60 + m;
    return `<button type="button" class="supp${on ? ' done' : ''}${late ? ' late' : ''}" data-act="crea" aria-pressed="${on}">
      <span class="supp-ic">${I.pill}</span>
      <span class="supp-t"><b>Creatina · 3–5 g</b><small>${on ? 'Presa oggi' : late ? 'Da prendere: non l’hai ancora segnata' : 'Ogni giorno, a qualsiasi ora'}${streak > 1 ? ` · ${streak} giorni di fila` : ''}</small></span>
      <span class="check" aria-hidden="true">${I.check}</span></button>`;
  }

  /* ---------------- palestra saltata / recupero ---------------- */
  function skipSheetHtml() {
    const now = new Date();
    const di = dayIdx(now);
    const day = D.week[di];
    const w = D.workouts.find((x) => x.id === day.wo);
    const eaten = store.get('eaten', {})[dkey(now)] || [];
    const on = dayPlan(di), off = dayPlan(di, { type: 'OFF_S', keep: eaten });
    const changed = off.meals.filter((m, i) => !m.free && (m.slot !== on.meals[i].slot)).map((m) => `${m.time} ${esc(D.recipes[m.code].name)} (${m.tot.k} kcal)`);
    return `<div class="stack"><div><p class="eyebrow">Oggi · ${esc(w.name)}</p><h2>Allenamento saltato</h2></div>
      <p>Lo segno nella cronologia come saltato: non conta tra gli allenamenti fatti e non cambia i tuoi record.</p>
      <div class="row"><h3>E i pasti di oggi?</h3></div>
      <div class="alts">
        <button type="button" class="alt" data-act="skip-do" data-diet="off"><span class="alt-c">Consigliato</span><b>Mangia come in un giorno di riposo</b>
          <span class="alt-m">Senza allenamento i carboidrati in più non servono. ${eaten.length ? 'I pasti già mangiati restano come sono; cambiano solo i prossimi' : 'Le merende diventano quelle più leggere dei giorni di riposo e cambiano pranzo, merenda e cena'}: <em>${off.tot.k} kcal</em> invece di ${on.tot.k}.</span>
          ${changed.length ? `<span class="alt-m">${changed.join(' · ')}</span>` : ''}</button>
        <button type="button" class="alt" data-act="skip-do" data-diet="on"><span class="alt-c">Nessun cambio</span><b>Tieni il piano ON</b>
          <span class="alt-m">Se hai già mangiato quasi tutto o è un caso isolato: ${on.tot.k} kcal. Una giornata così non rovina la settimana.</span></button>
      </div>
      <button type="button" class="chip" data-act="sheet-close">Annulla</button></div>`;
  }
  function recoverSheetHtml() {
    const now = new Date();
    const di = dayIdx(now);
    const eaten = store.get('eaten', {})[dkey(now)] || [];
    const off = dayPlan(di), on = dayPlan(di, { type: 'ON', keep: eaten });
    return `<div class="stack"><div><p class="eyebrow">Oggi · giorno di riposo</p><h2>Recuperi un allenamento?</h2></div>
      <p>Se oggi vai in palestra al posto di un giorno saltato, conviene mangiare come in un giorno ON: più carboidrati a pranzo e il post-allenamento al posto della merenda.</p>
      <div class="alts">
        <button type="button" class="alt" data-act="recover-do"><span class="alt-c">Oggi mi alleno</span><b>Passa al piano ON</b>
          <span class="alt-m">${eaten.length ? 'I pasti già mangiati restano come sono. ' : ''}Totale di oggi: <em>${on.tot.k} kcal</em> invece di ${off.tot.k}.</span></button>
      </div>
      <p class="small muted">Poi apri la Scheda e avvia l’allenamento che vuoi recuperare.</p>
      <button type="button" class="chip" data-act="sheet-close">Annulla</button></div>`;
  }

  /* ================= OGGI ================= */
  function viewOggi() {
    const now = new Date();
    const di = dayIdx(now);
    const key = dkey(now);
    const plan = todayPlan();
    const ov = dayOv(key);
    const eaten = store.get('eaten', {})[key] || [];
    const T = plan.dt.target;
    const e = { k: 0, p: 0, c: 0, fa: 0 };
    plan.meals.forEach((m) => { if (!m.free && eaten.includes(m.si)) { e.k += m.tot.k; e.p += m.tot.p; e.c += m.tot.c; e.fa += m.tot.fa; } });
    e.p = r1(e.p); e.c = r1(e.c); e.fa = r1(e.fa);
    const w0 = plan.day.wo ? D.workouts.find((x) => x.id === plan.day.wo) : null;
    const skipped = !!(w0 && ov && ov.skip && !(window.RCW && window.RCW.doneToday(w0.id)));
    const w = skipped ? null : w0;
    const planned = plan.tot.k;
    const school = di <= 4;

    const rows = [];
    if (school) rows.push({ t: '07:40', html: '<li class="evrow"><span class="mrow-t">07:40</span><span>Scuola fino alle 14:05 · merende nello zaino</span></li>' });
    if (w) rows.push({ t: '16:30', html: `<li class="evrow gym"><span class="mrow-t">16:30</span><span><b>Palestra · ${esc(w.name)}</b> · ${esc(w.focus)}</span></li>` });
    else if (skipped) rows.push({ t: '16:30', html: `<li class="evrow skipped"><span class="mrow-t">16:30</span><span><s>Palestra · ${esc(w0.name)}</s> · saltata</span></li>` });
    else if (plan.conv === 'ON') rows.push({ t: '16:30', html: '<li class="evrow gym"><span class="mrow-t">16:30</span><span><b>Palestra · recupero</b> · scegli l’allenamento nella Scheda</span></li>' });
    plan.meals.forEach((m) => rows.push({ t: m.time, html: mealRow(plan, m, eaten) }));
    rows.sort((a, b) => (a.t < b.t ? -1 : a.t > b.t ? 1 : 0));

    const tomorrow = (di + 1) % 7;
    return `
      <div class="grid-main">
        <div class="stack">
          ${installCard()}
          <section class="card hero">
            <div class="hero-top">
              <div><p class="eyebrow">${esc(now.toLocaleDateString('it-IT', { day: 'numeric', month: 'long' }))}</p><h1>${esc(plan.day.name)}</h1></div>
              <span class="row hero-badge">${typeBadge(plan.day, plan)}${tip(plan.dt === D.daytypes.ON ? 'on' : 'off')}</span>
            </div>
            <div class="dash">
              <div class="rings-wrap">${rings(e.k, planned)}<div class="rings-c"><b>${f0(e.k)}</b><span>di ${f0(planned)} kcal</span></div></div>
              <div class="mrings">${macroRing('p', 'Proteine', e.p, T[1])}${macroRing('c', 'Carboidrati', e.c, T[2])}${macroRing('g', 'Grassi', e.fa, T[3])}</div>
            </div>
            <p class="dash-left"><b>${f0(Math.max(0, planned - e.k))} kcal</b> ancora da mangiare oggi ${tip('kcal')}</p>
            ${plan.hasFree ? '<p class="tiny muted" style="margin-top:10px">Il pasto libero non è conteggiato negli anelli.</p>' : ''}
          </section>
          ${adessoCard(plan, eaten, w)}
          ${creatineRow(key)}
          <div class="row sec-title" style="margin-bottom:0"><h2>La tua giornata</h2><span class="tiny muted">tocca per i dettagli · scorri a destra per segnare</span></div>
          <ol class="mlist">${rows.map((x) => x.html).join('')}</ol>
        </div>
        <aside class="stack sticky-col">
          ${dayTotalsCard(plan)}
          ${w ? workoutMini(w) : skipped ? skipCard(w0, plan) : restCard(plan.day, plan)}
          ${tomorrow <= 4 ? prepCard(tomorrow) : ''}
        </aside>
      </div>`;
  }

  function prepCard(di) {
    const p = dayPlan(di);
    const snacks = p.meals.filter((m) => /^m[12]/.test(m.slot));
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
      <div class="row"><button type="button" class="btn" data-w="start" data-rid="${w.id}">${I.play} Inizia l'allenamento</button><a class="chip" href="#/scheda">Apri la scheda</a>${window.RCW && (window.RCW.isActive() || window.RCW.doneToday(w.id)) ? '' : '<button type="button" class="chip" data-act="skip-open">Oggi la salto</button>'}</div>
    </section>`;
  }

  function skipCard(w, plan) {
    return `<section class="card stack">
      <p class="eyebrow">Palestra saltata oggi</p>
      <h2>${esc(w.name)} <span class="muted" style="font-weight:600">· non fatto</span></h2>
      <p class="small">${plan.conv ? `Oggi mangi come in un giorno di riposo: <strong>${plan.tot.k} kcal</strong>.` : 'Il piano dei pasti di oggi resta quello ON.'} Capita: l’importante è tornare al prossimo allenamento.</p>
      <div class="row"><button type="button" class="chip" data-act="skip-undo">Annulla: oggi mi alleno</button></div>
    </section>`;
  }
  function restCard(day, plan) {
    if (plan && plan.conv === 'ON') {
      return `<section class="card stack"><p class="eyebrow">Recupero allenamento</p>
        <p class="small">Oggi mangi come in un giorno ON: <strong>${plan.tot.k} kcal</strong>. Apri la Scheda e avvia l’allenamento che vuoi recuperare.</p>
        <div class="row"><a class="btn" href="#/scheda">Apri la Scheda</a><button type="button" class="chip" data-act="skip-undo">Torna al piano OFF</button></div></section>`;
    }
    const next = (() => { for (let i = 1; i <= 7; i++) { const d = D.week[(dayIdx(new Date()) + i) % 7]; if (d.wo) return d; } return null; })();
    const w = next && D.workouts.find((x) => x.id === next.wo);
    return `<section class="card stack">
      <p class="eyebrow">Giorno di riposo</p>
      <p class="small">Recupero attivo: punta a <strong>8–10 mila passi</strong>. ${day.type === 'FREE' ? 'Oggi c\'è il pasto libero: goditelo senza sensi di colpa.' : ''}</p>
      ${w ? `<p class="small muted">Prossimo allenamento: <strong>${esc(next.name)} · ${esc(w.name)}</strong></p>` : ''}
      ${day.type === 'OFF_S' ? '<div class="row"><button type="button" class="chip" data-act="recover-open">Oggi recupero un allenamento</button></div>' : ''}
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
      <div class="row"><h2>Totale ${esc(plan.day.name.toLowerCase())}</h2>${tip('macro')}<span class="spacer"></span>${typeBadge(plan.day, plan)}</div>
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
          <p class="small muted">${esc(plan.dt.label)}${w ? ` · palestra 16:30 (${esc(w.name)})` : ''}. Tocca «Scambia» per cambiare un pasto con un'alternativa equivalente ${tip('scambio')}</p>
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
      <p class="tiny muted">* Domenica: solo i pasti pianificati, senza il pasto libero. Target: ON 2050 · OFF 1750 · media 1921.</p>
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
        const h = unitHint(id, g, true);
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
          <li><strong>Un pasto intero:</strong> usa il menu "scambia" sotto ogni pasto. Le opzioni della stessa fascia sono già calcolate su calorie quasi uguali (entro 30 kcal circa), quindi il totale del giorno resta giusto.</li>
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
  const timer = { start: 0, end: 0, id: 0, hide: 0, ctx: null, total: 1 };
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
    const ring = $('#timerRing');
    if (ring) ring.style.strokeDashoffset = (125.66 * (1 - Math.max(0, (timer.end - Date.now()) / 1000) / timer.total)).toFixed(2);
    if (left <= 0) {
      clearInterval(timer.id); tEl.classList.add('done'); beep();
      if (navigator.vibrate) navigator.vibrate([200, 100, 200]);
      if (N.haptics) safe(N.haptics.notification({ type: 'SUCCESS' }));
      timer.hide = setTimeout(stopTimer, 30000); // «Via!» resta mezzo minuto, poi il timer si chiude da solo
    }
  }
  // chiude il timer e toglie la notifica programmata: usato dal pulsante ✕ e a fine allenamento
  function stopTimer() {
    clearInterval(timer.id); clearTimeout(timer.hide);
    timer.end = 0; tEl.hidden = true; tEl.classList.remove('done');
    if (N.notif) safe(N.notif.cancel({ notifications: [{ id: TIMER_ID }] }));
    if (N.live) liveCall(() => N.live.end());
  }
  // App nativa: Live Activity del recupero (conto alla rovescia sulla schermata di blocco). Avvio, +15 e −15 la aggiornano.
  function liveCall(fn) { // un errore della Live Activity non deve mai fermare timer e notifiche
    try { return Promise.resolve(fn()).catch(() => null); } catch (e) { return Promise.resolve(null); }
  }
  // «Prossima: Leg Press · serie 2 · 118 kg × 8» → esercizio «Leg Press» e dettaglio «Serie 2 · 118 kg × 8»
  function liveLabel(label) {
    const txt = String(label || 'Recupero').replace(/^(Prossima|Poi):\s*/, '');
    const k = txt.indexOf(' · serie ');
    return k < 0 ? { exercise: txt, detail: '' } : { exercise: txt.slice(0, k), detail: 'Serie ' + txt.slice(k + 9) };
  }
  function liveSync() {
    if (!N.live || !timer.end) return;
    const a = store.get('active', null);
    const l = liveLabel($('#timerNext').textContent);
    liveCall(() => N.live.start({ start: timer.start || Date.now(), end: timer.end, exercise: l.exercise, detail: l.detail, workout: (a && a.name) || 'Allenamento' }));
  }
  // App nativa: notifica di fine recupero, arriva anche a schermo bloccato o con l'app in background
  function timerNotify() {
    liveSync();
    if (!N.notif) return;
    safe(N.notif.cancel({ notifications: [{ id: TIMER_ID }] })).then(() => safe(N.notif.schedule({ notifications: [{
      id: TIMER_ID, title: 'Recupero finito', body: 'Via con la prossima serie.', schedule: { at: new Date(timer.end), allowWhileIdle: true },
    }] })));
  }
  function startTimer(sec, next) {
    timer.total = sec;
    $('#timerNext').textContent = next || 'Recupero';
    try { if (!timer.ctx) { const AC = window.AudioContext || window.webkitAudioContext; if (AC) timer.ctx = new AC(); } if (timer.ctx && timer.ctx.state === 'suspended') timer.ctx.resume(); } catch (e) { /* ignora */ }
    timer.start = Date.now(); timer.end = timer.start + sec * 1000; tEl.hidden = false; tEl.classList.remove('done');
    clearInterval(timer.id); clearTimeout(timer.hide); tick(); timer.id = setInterval(tick, 250);
    buzz(); timerNotify();
  }
  $('#timerPlus').addEventListener('click', () => { if (tEl.classList.contains('done')) startTimer(15, $('#timerNext').textContent); else { timer.end += 15000; timer.total += 15; tick(); timerNotify(); } buzz(); });
  $('#timerMinus').addEventListener('click', () => {
    if (tEl.classList.contains('done')) return;
    timer.end = Math.max(Date.now() + 1000, timer.end - 15000); tick(); timerNotify(); buzz();
  });
  $('#timerStop').addEventListener('click', stopTimer);
  // rientrando nell'app: un recupero scaduto da più di un minuto, o rimasto senza allenamento in corso, non riparte
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible' || !timer.end) return;
    if (Date.now() > timer.end + 60000 || !(window.RCW && window.RCW.isActive())) stopTimer();
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
    const crea = Object.keys(store.get('creatina', {})).sort()[0];
    const creaNew = crea && (fromKey(dkey(new Date())) - fromKey(crea)) / 86400000 <= 21;
    const water = creaNew ? ' Hai iniziato la creatina da poco: 0,5–1 kg in più nelle prime 2–3 settimane è acqua nei muscoli, non grasso.' : '';
    if (full.length < 2) {
      return 'Pesati almeno 4 mattine a settimana, a digiuno e dopo il bagno. Dopo 2 settimane complete ti dico se il ritmo è giusto: l’obiettivo è scendere di 0,2–0,5 kg a settimana.' + water;
    }
    const a = full[full.length - 1], b = full[full.length - 2];
    const d = a.kg - b.kg;
    const c = full.length >= 3 ? full[full.length - 3] : null;
    const d2 = c ? b.kg - c.kg : null;
    const waistDown = a.waist != null && b.waist != null && a.waist < b.waist;
    const dd = (x) => sign(Math.round(x * 100) / 100, f2);
    if (d <= -0.6 && d2 != null && d2 <= -0.6) return `Stai scendendo troppo in fretta (${dd(d)} kg e ${dd(d2)} kg nelle ultime due settimane): così rischi di perdere muscolo. Aggiungi circa 150 kcal: +40 g di pasta o riso al pranzo dei giorni ON.`;
    if (d <= -0.6) return `Calo di ${f2(Math.abs(d))} kg in una settimana: un po' veloce. Se si ripete la prossima settimana, aggiungi 150 kcal.`;
    if (d <= -0.15) return `Perfetto: ${dd(d)} kg rispetto alla settimana prima. È il ritmo giusto (0,2–0,5 kg a settimana): non cambiare niente.`;
    if (d < 0.2) {
      if (d2 != null && d2 > -0.15 && !waistDown) return 'Peso fermo da 2 settimane e girovita che non scende: togli 100–150 kcal (per esempio −30 g di pasta o riso a cena) oppure aggiungi 2000 passi al giorno. Prima controlla il pasto libero e i condimenti «a occhio».' + water;
      return `Peso stabile (${dd(d)} kg). Una settimana ferma capita (acqua, sale, intestino): se i carichi salgono e il girovita scende va bene. Se resta fermo anche la prossima settimana, si tolgono 100–150 kcal.` + water;
    }
    return `Peso in salita (${dd(d)} kg). Controlla le porzioni del pasto libero e i condimenti «a occhio».` + water;
  }
  // grafico del peso interattivo: punti = pesate, linea = media 7 giorni, tratteggio verde = percorso ideale verso l'obiettivo
  const GOAL = { d: '2026-11-23', kg: 62.5 }; // 8 settimane a circa −0,3 kg: intorno al 14% di grasso
  function chart(ws) {
    if (ws.length < 2) return '<p class="small muted">Il grafico compare dal secondo peso registrato.</p>';
    const data = ws.slice(-90);
    const W = 640, H = 230, L = 40, R = 14, Tp = 14, B = 26;
    const t0 = Math.min(fromKey(data[0].d).getTime(), fromKey(START.d).getTime());
    const t1 = fromKey(data[data.length - 1].d).getTime();
    const span = Math.max(1, t1 - t0);
    const gs = fromKey(START.d).getTime(), ge = fromKey(GOAL.d).getTime();
    const ideal = (t) => START.kg + (GOAL.kg - START.kg) * Math.max(0, Math.min(1, (t - gs) / (ge - gs)));
    const vals = data.map((w) => w.kg).concat([START.kg, ideal(t1)]);
    const lo = Math.min(...vals) - 0.4, hi = Math.max(...vals) + 0.4;
    const xt = (t) => L + ((t - t0) / span) * (W - L - R);
    const x = (k) => xt(fromKey(k).getTime());
    const y = (v) => Tp + (1 - (v - lo) / (hi - lo)) * (H - Tp - B);
    const avg = data.map((w) => {
      const to = fromKey(w.d).getTime();
      const win = ws.filter((z) => { const t = fromKey(z.d).getTime(); return t >= to - 6 * 86400000 && t <= to; });
      return [w.d, win.reduce((a, z) => a + z.kg, 0) / win.length];
    });
    const ticks = [lo + 0.4, (lo + hi) / 2, hi - 0.4];
    const pts = data.map((w, i) => [+(x(w.d) / W * 100).toFixed(2), +(y(w.kg) / H * 100).toFixed(2), `${shortDate(w.d)} · ${f2(w.kg)} kg`, `media 7 gg ${f2(avg[i][1])} · ideale ${f2(ideal(fromKey(w.d).getTime()))}`]);
    return `<div class="wchart" data-pts='${esc(JSON.stringify(pts))}'>
      <svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Andamento del peso con media a 7 giorni e percorso ideale verso ${GOAL.kg} kg">
        ${ticks.map((v) => `<line class="ax" x1="${L}" x2="${W - R}" y1="${y(v)}" y2="${y(v)}"/><text x="${L - 6}" y="${y(v) + 4}" text-anchor="end">${f1(v)}</text>`).join('')}
        <line class="ideal" x1="${xt(t0)}" y1="${y(ideal(t0))}" x2="${xt(t1)}" y2="${y(ideal(t1))}"/>
        ${data.map((w) => `<circle class="pt" cx="${x(w.d)}" cy="${y(w.kg)}" r="3.2"/>`).join('')}
        <polyline class="ln" points="${avg.map(([d, v]) => `${x(d).toFixed(1)},${y(v).toFixed(1)}`).join(' ')}"/>
        <text x="${L}" y="${H - 6}">${shortDate(data[0].d)}</text><text x="${W - R}" y="${H - 6}" text-anchor="end">${shortDate(data[data.length - 1].d)}</text>
      </svg>
      <div class="wc-cursor" hidden><span class="wc-line"></span><span class="wc-dot"></span><div class="wc-tip"><b></b><span></span></div></div>
    </div>`;
  }

  // riepilogo della settimana scorsa (lunedì–domenica) e di quella in corso
  function weekSummary(ws) {
    const today = fromKey(dkey(new Date()));
    const mon = new Date(today); mon.setDate(mon.getDate() - dayIdx(mon));
    const prevMon = new Date(mon); prevMon.setDate(prevMon.getDate() - 7);
    const prev2 = new Date(prevMon); prev2.setDate(prev2.getDate() - 7);
    const avgIn = (a, b) => { const v = ws.filter((w) => { const t = fromKey(w.d).getTime(); return t >= a.getTime() && t < b.getTime(); }); return v.length ? v.reduce((s, w) => s + w.kg, 0) / v.length : null; };
    const dlog = store.get('dlog', {});
    const dayov = store.get('dayov', {});
    const mealsDays = (a, b) => { // giorni con almeno l'80% dei pasti spuntati
      let n = 0;
      for (let d = new Date(a); d < b; d.setDate(d.getDate() + 1)) { const x = dlog[dkey(d)]; if (x && x.of && x.n >= Math.ceil(x.of * 0.8)) n++; }
      return n;
    };
    const skips = (a, b) => Object.keys(dayov).filter((k) => dayov[k].skip && !dayov[k].del && fromKey(k) >= a && fromKey(k) < b).length;
    const rows = [['Settimana scorsa', prevMon, mon, prev2], ['Questa settimana', mon, new Date(today.getTime() + 86400000), prevMon]].map(([title, a, b, before]) => {
      const kg = avgIn(a, b), kgBefore = avgIn(before, a);
      const st = window.RCW ? window.RCW.weekStats(a.getTime(), b.getTime()) : { n: 0, prs: 0 };
      const days = Math.round((Math.min(b.getTime(), today.getTime() + 86400000) - a.getTime()) / 86400000);
      return `<div class="wsum">
        <p class="eyebrow">${title}</p>
        <div class="wsum-g">
          <div><span>Peso medio</span><b>${kg != null ? f2(kg) : '—'}</b><small>${kg != null && kgBefore != null ? sign(Math.round((kg - kgBefore) * 100) / 100, f2) + ' kg' : 'servono 2 settimane'}</small></div>
          <div><span>Allenamenti</span><b>${st.n}<small style="display:inline"> / 4</small></b><small>${[skips(a, b) ? `${skips(a, b)} saltat${skips(a, b) === 1 ? 'o' : 'i'}` : '', st.prs ? `🏆 ${st.prs} record` : ''].filter(Boolean).join(' · ') || 'nessun record'}</small></div>
          <div><span>Pasti rispettati</span><b>${mealsDays(a, b)}<small style="display:inline"> / ${Math.min(7, days)}</small></b><small>giorni ≥ 80% spuntati</small></div>
        </div>
      </div>`;
    }).join('');
    return `<section class="card stack"><h2>Riepilogo</h2>${rows}</section>`;
  }

  /* ---------- foto dei progressi (solo su questo dispositivo, in IndexedDB) ---------- */
  const PH = { db: null };
  function phDb() {
    if (PH.db) return Promise.resolve(PH.db);
    return new Promise((res, rej) => {
      if (!('indexedDB' in window)) { rej(new Error('IndexedDB non disponibile')); return; }
      const rq = indexedDB.open('recomp-foto', 1);
      rq.onupgradeneeded = () => rq.result.createObjectStore('foto', { keyPath: 'id' });
      rq.onsuccess = () => { PH.db = rq.result; res(PH.db); };
      rq.onerror = () => rej(rq.error);
    });
  }
  const phTx = (mode, fn) => phDb().then((db) => new Promise((res, rej) => { const tx = db.transaction('foto', mode); const st = tx.objectStore('foto'); const out = fn(st); tx.oncomplete = () => res(out && out.result !== undefined ? out.result : out); tx.onerror = () => rej(tx.error); }));
  const phAll = () => phTx('readonly', (st) => st.getAll());
  const phPut = (rec) => phTx('readwrite', (st) => st.put(rec));
  const phDel = (id) => phTx('readwrite', (st) => st.delete(id));
  const urls = [];
  const blobUrl = (b) => { const u = URL.createObjectURL(b); urls.push(u); return u; };
  function shrink(file) {
    return new Promise((res, rej) => {
      const img = new Image();
      img.onload = () => {
        const s = Math.min(1, 1200 / Math.max(img.width, img.height));
        const c = document.createElement('canvas'); c.width = Math.round(img.width * s); c.height = Math.round(img.height * s);
        c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
        URL.revokeObjectURL(img.src);
        c.toBlob((b) => (b ? res(b) : rej(new Error('conversione non riuscita'))), 'image/jpeg', 0.82);
      };
      img.onerror = () => rej(new Error('immagine non leggibile'));
      img.src = URL.createObjectURL(file);
    });
  }
  function photosCard() {
    return `<section class="card stack"><div class="row"><h2>Foto dei progressi</h2><span class="spacer"></span>
      <label class="btn ghost" for="photoIn">${I.up} Aggiungi</label><input id="photoIn" type="file" accept="image/*" class="sr"></div>
      <p class="tiny muted">Stessa luce, stessa posa, ogni 4 settimane. Le foto restano solo su questo dispositivo: non vengono sincronizzate né pubblicate.</p>
      <div id="photoGrid" class="pgrid"><p class="small muted">Caricamento…</p></div></section>`;
  }
  let photoCache = [];
  function hydratePhotos() {
    const box = document.getElementById('photoGrid');
    if (!box) return;
    urls.splice(0).forEach((u) => URL.revokeObjectURL(u));
    phAll().then((list) => {
      photoCache = list.sort((a, b) => (a.d < b.d ? -1 : 1));
      const el = document.getElementById('photoGrid');
      if (!el) return;
      if (!photoCache.length) { el.innerHTML = '<p class="small muted">Nessuna foto ancora. La prima è il tuo punto di partenza.</p>'; return; }
      el.innerHTML = photoCache.map((p) => `<button type="button" class="pthumb" data-act="photo-open" data-id="${p.id}"><img src="${blobUrl(p.blob)}" alt="Foto del ${shortDate(p.d)}"><span>${shortDate(p.d)}</span></button>`).join('')
        + (photoCache.length >= 2 ? '<button type="button" class="btn" data-act="photo-compare" style="grid-column:1/-1">Confronta prima e dopo</button>' : '');
    }).catch(() => { const el = document.getElementById('photoGrid'); if (el) el.innerHTML = '<p class="small muted">Le foto non sono disponibili in questo browser.</p>'; });
  }
  function photoAdd(file) {
    shrink(file).then((blob) => phPut({ id: 'p' + Date.now(), d: dkey(new Date()), blob })).then(() => { buzz('MEDIUM'); hydratePhotos(); })
      .catch((e) => alert('Foto non salvata: ' + e.message));
  }
  function photoOpen(id) {
    const p = photoCache.find((x) => x.id === id);
    if (!p) return;
    openSheet(`<div class="stack"><p class="eyebrow">${esc(cap(fromKey(p.d).toLocaleDateString('it-IT', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })))}</p>
      <img class="pfull" src="${blobUrl(p.blob)}" alt="Foto del ${shortDate(p.d)}">
      <div class="row"><button type="button" class="btn ghost" data-act="photo-del" data-id="${p.id}">${I.trash} Elimina</button><span class="spacer"></span><button type="button" class="btn" data-act="sheet-close">Chiudi</button></div></div>`);
  }
  function photoCompare() {
    if (photoCache.length < 2) return;
    const a = photoCache[0], b = photoCache[photoCache.length - 1];
    openSheet(`<div class="stack"><h2>Prima e dopo</h2>
      <div class="pcmp" style="--cut:50%"><img src="${blobUrl(b.blob)}" alt="Dopo, ${shortDate(b.d)}"><img class="pcmp-a" src="${blobUrl(a.blob)}" alt="Prima, ${shortDate(a.d)}"><span class="pcmp-l">${shortDate(a.d)}</span><span class="pcmp-r">${shortDate(b.d)}</span><i class="pcmp-h" aria-hidden="true"></i></div>
      <label class="sr" for="pcmpRange">Sposta il confronto</label><input id="pcmpRange" type="range" min="0" max="100" value="50" data-cmp="1">
      <button type="button" class="btn" data-act="sheet-close">Chiudi</button></div>`);
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
      <div><p class="eyebrow">Monitoraggio</p><h1>Progressi</h1><p class="muted">Punto di partenza: ${f2(START.kg)} kg · ${f1(START.bf)}% di grasso (bilancia) · ${shortDate(START.d)}/2026 · obiettivo ≈ ${f1(GOAL.kg)} kg a fine novembre</p></div>
      ${weekSummary(ws)}
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
        ${stat('Media 7 giorni ' + tip('media'), avg7 != null ? f2(avg7) : '—')}
        ${stat('Settimana vs prec.', dWeek != null ? sign(Math.round(dWeek * 100) / 100, f2) : '—', dWeek == null ? '' : dWeek > 0.05 ? 'up' : dWeek < -0.05 ? 'down' : '')}
        ${stat('Dal via', avg7 != null ? sign(Math.round((avg7 - START.kg) * 100) / 100, f2) : '—', avg7 == null ? '' : avg7 > START.kg ? 'up' : 'down')}
      </div>
      <section class="card advice"><p class="eyebrow">Cosa fare adesso</p><p style="margin-top:6px">${esc(advice(wk))}</p>
        <div class="row" style="margin-top:12px"><a class="chip" href="#/coach">Chiedi al Coach</a></div></section>
      <section class="card chart stack"><div class="row"><h2>Andamento</h2><span class="spacer"></span><span class="tiny muted">punti = pesate · linea = media 7 giorni · verde = percorso ideale · passa il dito sul grafico</span></div>${chart(ws)}</section>
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
      ${photosCard()}
    </div>`;
  }

  /* ---------------- sincronizzazione (stato fornito da sync.js) ---------------- */
  function syncCard() {
    const S = window.RCSync;
    const st = S ? S.state : { status: 'loading' };
    // stato reale in una parola: Connessione… · Sincronizzato · Errore · Offline
    const offline = st.status === 'offline' || st.net === false;
    const [cls, label] = st.status === 'nocfg' ? ['off', 'Non attiva']
      : offline ? ['off', 'Offline']
        : st.status === 'error' || st.fail ? ['bad', 'Errore']
          : st.status === 'loading' || st.busy ? ['off', 'Connessione…']
            : st.status === 'in' ? ['ok', 'Sincronizzato'] : ['off', 'Non collegato'];
    const head = `<div class="row"><h2>Sincronizzazione</h2><span class="spacer"></span><span class="badge sync-${cls}">${label}</span></div>`;
    const msg = st.msg ? `<p class="err" role="alert">${esc(st.msg)}</p>` : '';
    if (st.status === 'nocfg') {
      return `<section class="card stack">${head}<p class="small muted">Manca la configurazione di Firebase (<code>assets/js/firebase-config.js</code>). Quando è pronta, qui compare l'accesso.</p></section>`;
    }
    if (st.status === 'loading') {
      return `<section class="card stack">${head}<p class="small muted">Sto contattando il servizio: di solito bastano un paio di secondi.</p>${msg}</section>`;
    }
    if (st.status === 'offline') {
      return `<section class="card stack">${head}<p class="small muted">Sei offline: i dati restano salvati qui e si sincronizzano appena torna la connessione.</p></section>`;
    }
    if (st.status === 'error') {
      return `<section class="card stack">${head}${msg}<p class="small muted">I tuoi dati sono al sicuro su questo dispositivo. Controlla la connessione e riprova.</p>
        <div class="row"><button type="button" class="btn ghost" data-act="sync-retry">${I.reset} Riprova</button></div></section>`;
    }
    if (st.status === 'in') {
      const when = st.last ? new Date(st.last).toLocaleTimeString('it-IT', { hour: '2-digit', minute: '2-digit' }) : '—';
      return `<section class="card stack">${head}
        <p class="small">Collegato come <strong>${esc(st.email || '')}</strong>. Pesi, allenamenti, spunte, scambi e lista della spesa si allineano da soli tra telefono e PC.</p>
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

  /* ================= PROFILO (impostazioni + guida) ================= */
  function viewProfilo() {
    const tabs = [['impostazioni', 'Impostazioni'], ['target', 'Target'], ['alimenti', 'Alimenti'], ['regole', 'Regole']];
    const seg = `<div class="seg" role="tablist" aria-label="Sezioni del profilo">${tabs.map(([k, l]) => `<button type="button" role="tab" data-act="ptabp" data-tab="${k}" aria-selected="${ui.profTab === k}">${l}</button>`).join('')}</div>`;
    const body = ui.profTab === 'alimenti' ? guidaAlimenti() : ui.profTab === 'regole' ? guidaRegole() : ui.profTab === 'target' ? guidaTarget() : profiloImpostazioni();
    return `<div class="stack"><div><p class="eyebrow">Tu e il metodo</p><h1>Profilo</h1></div>${seg}${body}</div>`;
  }

  function profiloImpostazioni() {
    const ws = weights();
    const last = ws[ws.length - 1];
    const theme = store.get('theme', 'auto') || 'auto';
    const wk = blockWeek();
    return `<div class="grid2">
      <section class="card stack profile-card">
        <div class="row"><span class="avatar" aria-hidden="true">R</span><div><h2>Il tuo percorso</h2><p class="small muted">Ricomposizione corporea · dal 28/09/2026</p></div></div>
        <dl class="kv" style="margin:0">
          <div><dt>Peso attuale</dt><dd>${last ? f2(last.kg) : '64,70'} kg</dd></div>
          <div><dt>Obiettivo fine novembre</dt><dd>≈ 62,5 kg</dd></div>
          <div><dt>Blocco scheda</dt><dd>Sett. ${wk.n}/7</dd></div>
          <div><dt>Allenamenti</dt><dd>4 a settimana</dd></div>
        </dl>
        <div class="row"><button type="button" class="btn ghost" data-act="onboard">Rivedi la mini-guida</button></div>
      </section>
      <section class="card stack">
        <h2>Aspetto</h2>
        <div class="seg seg-static" role="radiogroup" aria-label="Tema">${[['auto', 'Automatico'], ['light', 'Chiaro'], ['dark', 'Scuro']].map(([v, l]) => `<button type="button" role="radio" data-act="theme" data-v="${v}" aria-checked="${theme === v}" aria-selected="${theme === v}">${l}</button>`).join('')}</div>
        <p class="tiny muted">Automatico segue il tema dell'iPhone.</p>
      </section>
      <section class="card stack">
        <h2>Superserie</h2>
        <label class="row small" style="justify-content:space-between;cursor:pointer"><span>Braccia in superserie nei giorni Limbs</span><input type="checkbox" data-act="superserie"${store.get('superserie', true) !== false ? ' checked' : ''} style="width:22px;height:22px;accent-color:var(--ink)"></label>
        <p class="tiny muted">Spento: bicipiti e tricipiti si fanno separati, prima tutte le serie di uno poi dell’altro, con 60–75″ di recupero (timer e Live Activity partono anche lì). Circa 6–7 minuti in più.</p>
      </section>
      ${syncCard()}
      ${nativeCards()}
      <section class="card stack">
        <h2>Backup dei dati</h2>
        <p class="small muted">Pesi, allenamenti, scambi dei pasti e lista della spesa sono salvati sul dispositivo (e sincronizzati se hai fatto l'accesso). Esporta un file per sicurezza.</p>
        <div class="row"><button type="button" class="btn ghost" data-act="export">${I.down} Esporta backup</button>
        <label class="btn ghost" for="importFile">${I.up} Importa backup</label><input id="importFile" type="file" accept="application/json,.json" class="sr"></div>
        <p class="err" id="impMsg" role="status"></p>
      </section>
    </div>`;
  }

  /* ---------------- spiegazioni ⓘ ---------------- */
  const GLOSSARIO = {
    on: ['Giorno ON', 'Giorno con la palestra (lunedì, martedì, giovedì, venerdì). Mangi di più, 2050 kcal, soprattutto carboidrati, per allenarti bene e recuperare.'],
    off: ['Giorno OFF', 'Giorno senza palestra (mercoledì, sabato, domenica). 1750 kcal, meno carboidrati per stare in deficit.'],
    kcal: ['Calorie', 'L’energia del cibo. Il piano ti tiene circa 380 kcal sotto il tuo consumo medio: perdi circa 0,35 kg di grasso a settimana tenendo le proteine alte per non perdere muscolo.'],
    macro: ['P · C · G', 'Proteine (P): costruiscono e proteggono il muscolo, obiettivo 140 g al giorno. Carboidrati (C): benzina per l’allenamento, più alti nei giorni ON. Grassi (G): servono agli ormoni e saziano, circa 55–58 g.'],
    scambio: ['Scambiare un pasto', 'Tutte le opzioni della stessa fascia (per esempio le merende delle 9:30) hanno quasi le stesse calorie (differenze entro 30 kcal circa): puoi scambiarle quando vuoi senza sballare la giornata.'],
    rir: ['RIR · ripetizioni in riserva', 'Quante ripetizioni avresti ancora potuto fare prima di non farcela più. RIR 2 vuol dire che ti fermi quando ne avresti ancora 2 nel serbatoio.'],
    block: ['Blocco di 7 settimane', 'Settimane 1–2: adattamento (RIR 2–3). Settimane 3–6: progressione (RIR 1–2). Settimana 7: scarico, con metà delle serie per recuperare. Poi si ricomincia.'],
    progressione: ['Doppia progressione', 'Prima aumenti le ripetizioni fino al massimo del range (per esempio 3×10), poi aumenti il peso e riparti dal minimo. L’app ti dice quando salire.'],
    volume: ['Volume', 'La somma di kg × ripetizioni di tutte le serie allenanti (il riscaldamento non conta). Se nel tempo sale, stai progredendo.'],
    '1rm': ['1RM stimato', 'Il peso massimo che potresti sollevare una volta sola, calcolato dalle tue serie con la formula di Epley: kg × (1 + ripetizioni/30). Serve a confrontare serie con pesi e ripetizioni diversi.'],
    superserie: ['Superserie', 'Due esercizi fatti uno dopo l’altro senza pausa (per esempio bicipiti e poi tricipiti), poi recuperi. Risparmi tempo senza togliere lavoro ai muscoli.'],
    serie: ['Tipi di serie', 'Numero = serie normale. R = riscaldamento (non conta per volume e record). D = drop set (abbassi il peso e continui subito). C = serie a cedimento. Tocca il numero della serie per cambiarlo.'],
    media: ['Media 7 giorni', 'Il peso del singolo giorno oscilla di mezzo chilo o più per acqua, sale e cibo. La media della settimana mostra la tendenza vera: è quella che conta.'],
    tdee: ['TDEE', 'Le calorie che consumi in un giorno: metabolismo a riposo + movimento + allenamento + digestione. Il tuo è circa 2450 kcal nei giorni ON e 2100 nei giorni OFF.'],
  };
  const tip = (k) => `<button type="button" class="tip" data-act="tip" data-k="${k}" aria-label="Cos’è: ${esc(GLOSSARIO[k][0])}">i</button>`;

  /* ---------------- pannello dal basso (fuori da main: non si perde quando la pagina si ridisegna) ---------------- */
  const sheetEl = document.createElement('div');
  sheetEl.className = 'gsheet'; sheetEl.hidden = true;
  sheetEl.innerHTML = '<div class="gsheet-bg" data-act="sheet-close"></div><div class="gsheet-in" role="dialog" aria-modal="true"><div class="gsheet-grab" aria-hidden="true"></div><div class="gsheet-body"></div></div>';
  document.body.appendChild(sheetEl);
  let sheetOnClose = null;
  // pagina ferma mentre è aperto un pannello (quello globale o la scelta esercizio dentro main)
  const modalBox = () => (!sheetEl.hidden && sheetEl.classList.contains('open') ? sheetEl : main.querySelector('.sheet'));
  const syncLock = () => document.documentElement.classList.toggle('no-scroll', !!modalBox());
  function openSheet(html, onClose) {
    sheetEl.querySelector('.gsheet-body').innerHTML = html;
    sheetEl.hidden = false; sheetOnClose = onClose || null;
    sheetEl.querySelector('.gsheet-in').scrollTop = 0;
    void sheetEl.offsetWidth; sheetEl.classList.add('open'); // classe messa subito (non al fotogramma dopo): il blocco dello scorrimento vale dal primo tocco
    syncLock();
  }
  function closeSheet() {
    if (sheetEl.hidden) return;
    sheetEl.classList.remove('open');
    syncLock();
    setTimeout(() => { if (!sheetEl.classList.contains('open')) { sheetEl.hidden = true; sheetEl.querySelector('.gsheet-body').innerHTML = ''; } }, 280);
    const cb = sheetOnClose; sheetOnClose = null; if (cb) cb();
  }
  function showTip(k) {
    const [t, d] = GLOSSARIO[k] || ['', ''];
    openSheet(`<div class="stack"><h2>${esc(t)}</h2><p>${esc(d)}</p><button type="button" class="btn" data-act="sheet-close">Ho capito</button></div>`);
  }

  /* ---------------- mini-guida al primo avvio ---------------- */
  const GUIDA_SLIDES = [
    ['M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z', 'Benvenuto in Recomp', 'Il tuo piano per perdere la pancia e mettere muscolo: pasti calcolati al grammo, scheda di allenamento e progressi, tutto in un posto.'],
    ['M12 3a9 9 0 1 0 9 9M12 7v5l3 2', 'Oggi', 'Trovi la giornata con gli orari. La card «Adesso» ti dice cosa viene dopo. Segna i pasti con ✓ oppure scorrendoli verso destra, e guarda gli anelli di calorie, proteine, carboidrati e grassi riempirsi.'],
    ['M3 4.5h18v16.5H3zM8 2.5v4M16 2.5v4M3 10h18', 'Piano e spesa', 'Tocca un pasto per vedere ingredienti e preparazione e per scambiarlo con un’alternativa equivalente. In «Lista spesa» hai le quantità esatte della settimana.'],
    ['M6.5 7v10M17.5 7v10M3.5 9.5v5M20.5 9.5v5M6.5 12h11', 'Scheda', 'Premi «Inizia» e segui l’allenamento: vedi cosa hai fatto la volta scorsa, spunti le serie e parte il recupero. Alla fine ti mostra i record battuti.'],
    ['M3 3v18h18M7 14l4-4 3 3 6-7', 'Progressi, Coach e Profilo', 'Pesati 4 mattine a settimana: l’app ti dice se il ritmo è giusto. Il Coach (stellina in alto) risponde alle tue domande usando solo i dati che hai registrato. In Profilo trovi impostazioni, sincronizzazione e la guida.'],
  ];
  let slide = 0;
  function onboardHtml() {
    const [path, t, d] = GUIDA_SLIDES[slide];
    const last = slide === GUIDA_SLIDES.length - 1;
    return `<div class="onboard stack">
      <div class="ob-ic"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="${path}"/></svg></div>
      <h2>${esc(t)}</h2><p>${esc(d)}</p>
      <div class="ob-dots" aria-label="Pagina ${slide + 1} di ${GUIDA_SLIDES.length}">${GUIDA_SLIDES.map((_, i) => `<i class="${i === slide ? 'on' : ''}"></i>`).join('')}</div>
      <div class="row">${slide ? '<button type="button" class="btn ghost" data-act="ob-prev">Indietro</button>' : '<button type="button" class="chip" data-act="ob-skip">Salta</button>'}<span class="spacer"></span>
        <button type="button" class="btn" data-act="${last ? 'ob-done' : 'ob-next'}">${last ? 'Inizia' : 'Avanti'}</button></div>
    </div>`;
  }
  function showOnboarding() { slide = 0; openSheet(onboardHtml(), () => store.set('onboarded', true)); }

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
        <section class="card stack"><div class="row"><h2>Dispendio giornaliero</h2>${tip('tdee')}</div>
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
        <div class="tbl-wrap"><table><thead><tr><th></th><th class="r">kcal</th><th class="r">P</th><th class="r">C</th><th class="r">G</th></tr></thead><tbody>
          <tr><td><span class="badge on">ON</span> Lun Mar Gio Ven</td><td class="r">2050</td><td class="r">140 g</td><td class="r">249 g</td><td class="r">55 g</td></tr>
          <tr><td><span class="badge off">OFF</span> Mer Sab Dom</td><td class="r">1750</td><td class="r">140 g</td><td class="r">167 g</td><td class="r">58 g</td></tr>
        </tbody><tfoot><tr><td>Media settimanale</td><td class="r">1921</td><td colspan="3" class="small muted">−16% dal TDEE, circa −380 kcal al giorno</td></tr></tfoot></table></div>
        <div class="prose small">
          <p>Proteine a 2,2 g/kg per proteggere e costruire muscolo mentre perdi grasso. Carboidrati concentrati nei giorni in cui ti alleni. Per il grasso conta la media della settimana.</p>
          <p><strong>Perché questi numeri:</strong> un deficit di circa 380 kcal al giorno fa perdere circa 0,35 kg di grasso a settimana, cioè lo 0,5% del peso: è la fascia (0,5–0,7%) in cui chi si allena con i pesi perde grasso senza perdere muscolo. Con 2100/1900 il deficit sarebbe 286 kcal e il ritmo 0,26 kg a settimana: un quarto più lento senza vantaggi. Sotto le 1900/1600 (−23%) i carichi si fermerebbero e avresti fame a scuola.</p>
          <p><strong>Cosa aspettarti:</strong> la bilancia dovrebbe scendere di 0,2–0,5 kg a settimana, con il girovita che cala e i carichi che salgono. A fine novembre 2026 circa 62,5 kg, cioè −2,5/−3 kg di grasso e intorno al 14% sulla bilancia. Da lì si passa al mantenimento (circa 2300 kcal) per costruire muscolo.</p>
          <p class="muted">I passi non sono registrati nell’app: il consumo è stimato con 300 kcal di movimento quotidiano. Per questo conta la verifica sul peso reale: se la media settimanale non scende per 2 settimane, si tolgono 100–150 kcal.</p>
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
        <li>Il resto della giornata è già più leggero (circa 1050 kcal) per lasciargli spazio.</li></ul></section>
      <section class="card prose small"><h2>Recupero</h2>
        <ul><li><strong>Sonno:</strong> 8 ore (22:30 → 6:30). È metà della ricomposizione.</li>
        <li><strong>Acqua:</strong> 2,5–3 litri al giorno, +0,5 litri nei giorni di palestra.</li>
        <li><strong>Passi:</strong> 7–8 mila al giorno, 8–10 mila nei giorni OFF.</li>
        <li><strong>Creatina monoidrato:</strong> 3–5 g al giorno, tutti i giorni (anche di riposo), a qualsiasi ora: spuntala in Oggi. Nelle prime 2–3 settimane aggiunge 0,5–1 kg d'acqua nei muscoli sulla bilancia: non è grasso.</li></ul></section>
      <section class="card prose small"><h2>Se salti la palestra</h2>
        <ul><li>In Oggi tocca <strong>«Oggi la salto»</strong>: l'allenamento viene segnato come saltato e non conta tra quelli fatti.</li>
        <li>L'app ti propone di mangiare come in un giorno di riposo (−300 kcal circa, soprattutto carboidrati): sei tu a scegliere, non cambia niente da sola.</li>
        <li>Se recuperi l'allenamento in un giorno OFF di scuola, in Oggi tocca <strong>«Oggi recupero un allenamento»</strong> per passare al piano ON.</li>
        <li>Un allenamento saltato ogni tanto non cambia niente. Se ne salti 2 nella stessa settimana, tieni comunque le proteine a 140 g.</li></ul></section>
      <section class="card prose small"><h2>Misure e correzioni</h2>
        <ul><li>Peso almeno 4 mattine a settimana: conta la <strong>media settimanale</strong>, non il singolo giorno.</li>
        <li>Girovita all'ombelico ogni lunedì, foto ogni 4 settimane, bilancia BIA sempre nelle stesse condizioni.</li>
        <li>Calo oltre 0,6 kg a settimana per 2 settimane → +150 kcal.</li>
        <li>Peso e girovita fermi per 2 settimane → −100/150 kcal oppure +2000 passi.</li>
        <li>Carichi in calo per 2 settimane → +100 kcal nei giorni ON e più sonno.</li></ul></section>
    </div>`;
  }

  /* ================= ROUTER & EVENTI ================= */
  const routes = { oggi: viewOggi, piano: viewPiano, scheda: () => (window.RCW ? window.RCW.view() : ''), progressi: viewProgressi, profilo: viewProfilo, guida: viewProfilo, coach: () => (window.RCC ? window.RCC.view() : '') };
  const titles = { oggi: 'Oggi', piano: 'Piano', scheda: 'Scheda', progressi: 'Progressi', profilo: 'Profilo', guida: 'Profilo', coach: 'Coach' };
  let current = '';
  function render(scrollTop) {
    const name = (location.hash.replace(/^#\/?/, '').split('/')[0]) || 'oggi';
    const r = name === 'guida' ? 'profilo' : routes[name] ? name : 'oggi';
    if (r !== 'scheda' && wake.want) wakeOff();
    const navRoute = r === 'coach' ? 'progressi' : r; // il Coach vive accanto ai Progressi
    const cb = $('#coachBtn'); if (cb) cb.classList.toggle('on', r === 'coach');
    $$('.nav a').forEach((a, i) => {
      if (a.dataset.route === navRoute) { a.setAttribute('aria-current', 'page'); a.parentElement.style.setProperty('--i', i); } else a.removeAttribute('aria-current');
    });
    const y = window.scrollY;
    main.classList.remove('page-in'); // l'animazione di comparsa solo quando si cambia sezione, non a ogni aggiornamento
    main.innerHTML = (r !== 'scheda' && window.RCW ? window.RCW.banner() : '') + routes[r]();
    document.title = `${titles[r]} · Recomp`;
    watchTitle(titles[r]);
    if (r === 'progressi') hydratePhotos();
    if (r !== current && current) main.classList.add('page-in');
    if (scrollTop || r !== current) { window.scrollTo(0, 0); if (r !== current && current) main.focus({ preventScroll: true }); }
    else window.scrollTo(0, y);
    current = r;
    syncLock();
  }
  window.addEventListener('hashchange', () => render(true));

  main.addEventListener('click', (ev) => {
    if (ev.target.classList.contains('sheet') && window.RCW) { window.RCW.click({ dataset: { w: 'pick-close' } }); return; }
    const tw = ev.target.closest('[data-w]');
    if (tw && window.RCW && window.RCW.click(tw)) { ev.preventDefault(); return; }
    const tc = ev.target.closest('[data-c]');
    if (tc && window.RCC && window.RCC.click(tc)) { ev.preventDefault(); return; }
    const t = ev.target.closest('[data-act]');
    if (!t) return;
    const act = t.dataset.act;
    if (commonAct(t, act)) return;
    if (act === 'eat') { toggleEaten(Number(t.dataset.si)); render(); }
    else if (act === 'crea') { toggleCreatine(); render(); }
    else if (act === 'skip-open') { openSheet(skipSheetHtml()); }
    else if (act === 'recover-open') { openSheet(recoverSheetHtml()); }
    else if (act === 'skip-undo') { setDayOv(dkey(new Date()), null); logDay(); buzz(); render(); }
    else if (act === 'meal-open') { openMeal(Number(t.dataset.di), Number(t.dataset.si), !!t.dataset.td); }
    else if (act === 'ptab') { ui.pianoTab = t.dataset.tab; render(); }
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
      try { for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); if (k.startsWith('rc.') && k !== 'rc.aiKey') out[k] = localStorage.getItem(k); } } catch (e) { /* ignora */ }
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
    else if (act === 'sync-retry' && window.RCSync) { window.RCSync.retry(); }
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
    if (t.dataset.c && window.RCC) { window.RCC.change(t); return; }
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
    } else if (t.dataset.act === 'superserie') {
      store.set('superserie', t.checked);
    } else if (t.dataset.act === 'rem') {
      setReminder(t.dataset.k, t.checked);
    } else if (t.dataset.act === 'crea-time') {
      if (t.value) { store.set('reminders', { ...store.get('reminders', {}), creatinaAt: t.value }); creatineSoon(); }
    } else if (t.id === 'photoIn' && t.files && t.files[0]) {
      photoAdd(t.files[0]); t.value = '';
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
    if (t.id === 'coQ' && window.RCC) { window.RCC.draft(t.value); return; }
    if (t.id === 'foodSearch') {
      const q = t.value.trim().toLowerCase();
      $$('#foodTable tbody tr').forEach((tr) => { tr.classList.toggle('hidden', !!q && !tr.dataset.n.includes(q)); });
    }
  });

  main.addEventListener('submit', (ev) => {
    if (ev.target.id === 'coForm') { ev.preventDefault(); if (window.RCC) window.RCC.submit(); return; }
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
      if (idx !== drag.idx || !links[idx].classList.contains('lens')) {
        links.forEach((a, k) => a.classList.toggle('lens', k === idx));
        if (idx !== drag.idx && N.haptics) safe(N.haptics.selectionChanged());
        drag.idx = idx;
      }
    }
    const schedule = () => { if (drag && !drag.raf) drag.raf = requestAnimationFrame(frame); };
    function beginDrag() {
      if (!drag || drag.active) return;
      clearTimeout(drag.hold);
      drag.active = true;
      nav.classList.add('dragging');
      frame();
      if (N.haptics) safe(N.haptics.selectionStart());
    }
    // apre la sezione dopo che la bolla ha iniziato a muoversi: la pagina nuova si disegna al fotogramma successivo
    function go(idx) {
      swallowClick = true; setTimeout(() => { swallowClick = false; }, 400);
      nav.style.setProperty('--i', idx);
      bubble.style.transform = '';
      bubble.classList.remove('moving'); void bubble.offsetWidth; bubble.classList.add('moving');
      const href = links[idx].getAttribute('href');
      if (location.hash === href) return;
      buzz();
      requestAnimationFrame(() => setTimeout(() => { location.hash = href; }, 0));
    }
    nav.addEventListener('pointerdown', (e) => {
      if (!mobile.matches || (e.pointerType === 'mouse' && e.button !== 0)) return;
      const a = e.target.closest('a');
      if (!a) return;
      const r = nav.getBoundingClientRect();
      drag = { id: e.pointerId, x0: e.clientX, x: e.clientX, left: r.left, w: (r.width - 2 * PAD) / links.length, idx: links.indexOf(a), raf: 0, active: false };
      try { nav.setPointerCapture(e.pointerId); } catch (err) { /* ignora */ }
      // tenendo premuto un attimo la bolla si "stacca" e segue il dito anche senza muoverlo
      drag.hold = setTimeout(beginDrag, 220);
    });
    nav.addEventListener('pointermove', (e) => {
      if (!drag || e.pointerId !== drag.id) return;
      drag.x = e.clientX;
      if (!drag.active && Math.abs(drag.x - drag.x0) > 8) beginDrag();
      if (drag.active) schedule();
    });
    function end(e, ok) {
      if (!drag || (e && e.pointerId !== drag.id)) return;
      clearTimeout(drag.hold);
      if (drag.raf) cancelAnimationFrame(drag.raf);
      const { idx, active } = drag;
      drag = null;
      if (active) {
        nav.classList.remove('dragging');
        links.forEach((a) => a.classList.remove('lens'));
        if (N.haptics) safe(N.haptics.selectionEnd());
      }
      if (!ok || idx < 0) { bubble.style.transform = ''; return; }
      go(idx);
    }
    nav.addEventListener('pointerup', (e) => end(e, true));
    nav.addEventListener('pointercancel', (e) => end(e, false));
    nav.addEventListener('lostpointercapture', (e) => { if (drag) end(e, false); });
    // il "click" che segue il rilascio è già gestito sopra
    nav.addEventListener('click', (e) => { if (swallowClick) e.preventDefault(); });
  })();

  /* ---------------- scorri a destra per segnare un pasto ---------------- */
  (function swipeRows() {
    let sw = null;
    let blockClick = false;
    main.addEventListener('pointerdown', (e) => {
      const row = e.target.closest('[data-swipe]');
      if (!row || e.target.closest('.check') || (e.pointerType === 'mouse' && e.button !== 0)) return;
      const dir = row.dataset.swipe === 'del' ? -1 : 1; // pasti: a destra; serie: a sinistra per eliminare
      sw = { row, dir, fg: row.querySelector('.mrow-fg, .wset'), id: e.pointerId, x0: e.clientX, y0: e.clientY, dx: 0, on: false };
    });
    main.addEventListener('pointermove', (e) => {
      if (!sw || e.pointerId !== sw.id) return;
      const dx = e.clientX - sw.x0, dy = e.clientY - sw.y0;
      if (!sw.on) {
        if (Math.abs(dy) > 10 && Math.abs(dy) > Math.abs(dx)) { sw = null; return; } // sta scorrendo la pagina
        if (dx * sw.dir > 10 && Math.abs(dx) > Math.abs(dy) * 1.2) { sw.on = true; sw.row.classList.add('swiping'); try { sw.row.setPointerCapture(e.pointerId); } catch (err) { /* ignora */ } }
        else return;
      }
      sw.dx = Math.max(0, Math.min(140, dx * sw.dir));
      sw.fg.style.transform = `translate3d(${sw.dx * sw.dir}px, 0, 0)`;
      sw.row.classList.toggle('armed', sw.dx > 80);
    });
    function end() {
      if (!sw) return;
      const s0 = sw; sw = null;
      if (!s0.on) return;
      blockClick = true; setTimeout(() => { blockClick = false; }, 350);
      s0.row.classList.remove('swiping', 'armed');
      s0.fg.style.transform = '';
      if (s0.dx > 80) {
        if (s0.dir < 0) { if (window.RCW) window.RCW.delSet(Number(s0.row.dataset.i), Number(s0.row.dataset.j)); }
        else { toggleEaten(Number(s0.row.dataset.si)); setTimeout(render, 180); }
      }
    }
    main.addEventListener('pointerup', end);
    main.addEventListener('pointercancel', () => { if (sw && sw.on) { sw.row.classList.remove('swiping', 'armed'); sw.fg.style.transform = ''; } sw = null; });
    main.addEventListener('click', (e) => { if (blockClick) { e.stopPropagation(); e.preventDefault(); } }, true);
  })();

  /* ---------------- grafico del peso: cursore che segue il dito ---------------- */
  (function chartScrub() {
    function show(e) {
      const box = e.target.closest && e.target.closest('.wchart');
      if (!box) return;
      const pts = JSON.parse(box.dataset.pts || '[]');
      if (!pts.length) return;
      const r = box.getBoundingClientRect();
      const px = ((e.clientX - r.left) / r.width) * 100;
      let best = pts[0];
      pts.forEach((p) => { if (Math.abs(p[0] - px) < Math.abs(best[0] - px)) best = p; });
      const cur = box.querySelector('.wc-cursor');
      cur.hidden = false;
      cur.style.setProperty('--x', best[0] + '%'); cur.style.setProperty('--y', best[1] + '%');
      cur.querySelector('b').textContent = best[2]; cur.querySelector('.wc-tip span').textContent = best[3];
      cur.classList.toggle('right', best[0] > 60);
    }
    main.addEventListener('pointermove', show);
    main.addEventListener('pointerdown', show);
    main.addEventListener('pointerleave', (e) => { if (e.target.classList && e.target.classList.contains('wchart')) e.target.querySelector('.wc-cursor').hidden = true; }, true);
  })();

  /* ---------------- azioni comuni (pagina + pannello dal basso) ---------------- */
  function commonAct(t, act) {
    switch (act) {
      case 'tip': showTip(t.dataset.k); return true;
      case 'sheet-close': closeSheet(); return true;
      case 'onboard': showOnboarding(); return true;
      case 'ob-next': slide = Math.min(GUIDA_SLIDES.length - 1, slide + 1); sheetEl.querySelector('.gsheet-body').innerHTML = onboardHtml(); return true;
      case 'ob-prev': slide = Math.max(0, slide - 1); sheetEl.querySelector('.gsheet-body').innerHTML = onboardHtml(); return true;
      case 'ob-skip': case 'ob-done': closeSheet(); return true;
      case 'ptabp': ui.profTab = t.dataset.tab; render(); return true;
      case 'theme': setTheme(t.dataset.v); render(); return true;
      case 'photo-open': photoOpen(t.dataset.id); return true;
      case 'photo-compare': photoCompare(); return true;
      case 'photo-del': if (confirm('Eliminare questa foto?')) phDel(t.dataset.id).then(() => { closeSheet(); hydratePhotos(); }); return true;
      default: return false;
    }
  }
  sheetEl.addEventListener('click', (ev) => {
    const t = ev.target.closest('[data-act]');
    if (!t) return;
    if (commonAct(t, t.dataset.act)) return;
    if (window.RC && window.RC.sheetAct) window.RC.sheetAct(t, t.dataset.act);
  });
  sheetEl.addEventListener('input', (ev) => {
    if (ev.target.dataset.cmp) { const c = sheetEl.querySelector('.pcmp'); if (c) c.style.setProperty('--cut', ev.target.value + '%'); return; }
    if (window.RCW && window.RCW.sheetInput) window.RCW.sheetInput(ev.target);
  });
  sheetEl.addEventListener('change', (ev) => { if (window.RCW && window.RCW.sheetInput) window.RCW.sheetInput(ev.target); });
  document.addEventListener('keydown', (ev) => { if (ev.key === 'Escape') closeSheet(); });
  // iPhone: con un pannello aperto il dito deve scorrere solo il pannello. Fuori dal pannello il gesto viene
  // annullato; dentro, viene annullato quando il contenuto è già in cima o in fondo (altrimenti Safari
  // "passa" lo scorrimento alla pagina sotto). Su desktop basta overscroll-behavior + html.no-scroll.
  (function scrollGuard() {
    let x0 = 0, y0 = 0;
    document.addEventListener('touchstart', (e) => { const t = e.touches[0]; x0 = t.clientX; y0 = t.clientY; }, { passive: true });
    document.addEventListener('touchmove', (e) => {
      if (!modalBox() || e.touches.length > 1) return;
      const tg = e.target;
      if (tg.closest && tg.closest('input[type="range"]')) return;
      const sc = tg.closest && tg.closest('.gsheet-in, .sheet-in');
      if (!sc) { e.preventDefault(); return; }
      const dx = e.touches[0].clientX - x0, dy = e.touches[0].clientY - y0;
      if (Math.abs(dx) > Math.abs(dy)) { if (!tg.closest('.seg, .pill-list, .tbl-wrap')) e.preventDefault(); return; }
      const top = sc.scrollTop <= 0, bottom = sc.scrollTop + sc.clientHeight >= sc.scrollHeight - 1;
      if ((dy > 0 && top) || (dy < 0 && bottom)) e.preventDefault();
    }, { passive: false });
  })();

  /* ---------------- titolo grande che si compatta nella barra in alto (come iOS) ---------------- */
  const topTitle = document.getElementById('topTitle');
  const topbar = document.querySelector('.topbar');
  let titleObs = null;
  function watchTitle(text) {
    if (!topTitle) return;
    topTitle.textContent = text;
    topbar.classList.remove('compact');
    if (titleObs) titleObs.disconnect();
    const h1 = main.querySelector('h1');
    if (!h1 || !('IntersectionObserver' in window)) return;
    titleObs = new IntersectionObserver(([e]) => topbar.classList.toggle('compact', !e.isIntersecting && e.boundingClientRect.top < 80), { rootMargin: '-64px 0px 0px 0px' });
    titleObs.observe(h1);
  }

  /* ---------------- tema ---------------- */
  const themeBtn = $('#themeBtn');
  const mq = window.matchMedia('(prefers-color-scheme: dark)');
  function effectiveTheme() { const t = document.documentElement.getAttribute('data-theme'); return t || (mq.matches ? 'dark' : 'light'); }
  function paintThemeBtn() { const dark = effectiveTheme() === 'dark'; themeBtn.innerHTML = dark ? I.sun : I.moon; themeBtn.setAttribute('aria-label', dark ? 'Passa al tema chiaro' : 'Passa al tema scuro');
    // striscia sotto l'orologio: stesso colore della barra in alto. Nell'app nativa cambio anche il colore di orologio e batteria;
    // nell'app installata da Safari l'orologio è sempre bianco, quindi in tema chiaro la striscia resta scura.
    document.documentElement.classList.toggle('strip-dark', !isNative && !dark);
    if (N.status) safe(N.status.setStyle({ style: dark ? 'DARK' : 'LIGHT' }));
  }
  function setTheme(v) {
    if (v === 'light' || v === 'dark') { document.documentElement.setAttribute('data-theme', v); store.set('theme', v); }
    else { document.documentElement.removeAttribute('data-theme'); store.set('theme', 'auto'); }
    paintThemeBtn();
  }
  themeBtn.addEventListener('click', () => { setTheme(effectiveTheme() === 'dark' ? 'light' : 'dark'); if (current === 'profilo') render(); });
  if (mq.addEventListener) mq.addEventListener('change', paintThemeBtn);
  paintThemeBtn();

  /* ---------------- ponte con sync.js ---------------- */
  // I dati arrivati dall'altro dispositivo ridisegnano la pagina, ma non mentre stai scrivendo in un campo.
  let pendingRefresh = false;
  const typing = () => { const a = document.activeElement; return !!(a && main.contains(a) && /^(INPUT|SELECT|TEXTAREA)$/.test(a.tagName)); };
  function setSwap(di, si, code) {
    const sw = store.get('swaps', {});
    const k = di + ':' + si;
    if (code === D.week[di].pick[si]) delete sw[k]; else sw[k] = code;
    store.set('swaps', sw);
  }
  // per il Coach: le ricette possibili per una fascia e i pasti spuntati oggi
  const mealOptions = (slot) => Object.keys(D.variants[slot]).map((code) => ({ code, name: D.recipes[code].name, ...sumLines(mealLines(slot, code)) }));
  const eatenToday = () => store.get('eaten', {})[dkey(new Date())] || [];
  function markEaten(si) { if (!eatenToday().includes(si)) toggleEaten(si); }
  window.RC = {
    sheetAct(t, act) {
      const body = sheetEl.querySelector('.gsheet-body');
      if (act === 'sheet-swap') {
        const di = Number(t.dataset.di), si = Number(t.dataset.si);
        setSwap(di, si, t.dataset.code); buzz();
        body.innerHTML = mealSheetHtml(di, si, !!t.dataset.td); render();
      } else if (act === 'sheet-eat') {
        const si = Number(t.dataset.si);
        toggleEaten(si); render(); closeSheet();
      } else if (act === 'skip-do' || act === 'recover-do') {
        const now = new Date();
        const key = dkey(now);
        const keep = store.get('eaten', {})[key] || [];
        if (act === 'recover-do') setDayOv(key, { type: 'ON', keep });
        else setDayOv(key, { skip: 1, rid: D.week[dayIdx(now)].wo, type: t.dataset.diet === 'off' ? 'OFF' : '', keep });
        logDay(); buzz('MEDIUM'); closeSheet(); render();
      }
    },
    refresh(force) { creatineSoon(); if (!force && typing()) { pendingRefresh = true; return; } pendingRefresh = false; render(); },
  };
  main.addEventListener('focusout', () => { if (pendingRefresh) setTimeout(() => { if (!typing()) { pendingRefresh = false; render(); } }, 0); });

  /* ---------------- ponte con allenamento.js ---------------- */
  window.RCK = {
    D, store, esc, f0, f1, f2, sign, r1, num, dkey, fromKey, shortDate, dayIdx, I, cap, restTxt, fmtKg,
    weights, weekly, advice, START, GOAL,
    startTimer, stopTimer, buzz, blockWeek, wakeChip, tip, openSheet, closeSheet, render: (top) => render(top),
    // piano dei pasti per il Coach: lo legge e applica le proposte che confermi con «Applica»
    plan: { dayPlan, todayPlan, setSwap, logDay, mealOptions, eatenToday, markEaten },
  };
  if (window.RCW) window.RCW.migrate();

  /* ---------------- avvio ---------------- */
  render(true);
  if (!store.get('onboarded', false)) setTimeout(showOnboarding, 400);
  if (isNative) {
    if (!(window.RCW && window.RCW.isActive())) stopTimer(); // nessuna notifica di recupero rimasta da una sessione chiusa
    scheduleReminders();
    scheduleCreatine();
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') creatineSoon(); });
    let remT = 0;
    window.addEventListener('rc-change', (e) => { if (e.detail === 'rc.swaps') { clearTimeout(remT); remT = setTimeout(scheduleReminders, 1500); } });
  }
  // App installata: chiede al sistema di non cancellare i dati salvati (pesi, carichi)
  if (isStandalone() && navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});
  if ('serviceWorker' in navigator && location.protocol === 'https:') {
    window.addEventListener('load', () => navigator.serviceWorker.register('sw.js').catch(() => {}));
  }
})();
