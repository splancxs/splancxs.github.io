'use strict';
// Coach: un riepilogo calcolato dai dati registrati nell'app e le risposte di un'AI collegata con la tua chiave.
// Claude è il servizio principale: legge tutti i dati, guarda le foto dei pasti, ricorda le cose importanti
// e propone modifiche (scambi di pasti, pasti mangiati, carichi) che applichi tu con «Applica».
// Google Gemini e Groq restano come riserva gratuita, solo per le domande: rispondono se Claude non è collegato
// o non è disponibile. Usa le utilità di app.js (window.RCK) e di allenamento.js (window.RCW.data).
(function () {
  const C = {};
  window.RCC = C;
  const K = () => window.RCK;
  const WD = () => window.RCW.data;

  // SDK ufficiale di Anthropic, caricato solo quando fai la prima domanda a Claude
  const SDK_URL = 'https://cdn.jsdelivr.net/npm/@anthropic-ai/sdk@0.129.0/+esm';
  const CLAUDE = {
    name: 'Claude', keyUrl: 'https://console.anthropic.com/settings/keys', keyHint: 'sk-ant-…',
    models: { 'claude-opus-5-5': 'Claude Opus 5.5 · il più capace', 'claude-sonnet-5-5': 'Claude Sonnet 5.5 · circa metà prezzo' },
    // dollari per milione di token: lettura, scrittura, scrittura in cache, lettura dalla cache (per la stima dei costi)
    price: { 'claude-opus-5-5': [4, 20, 5, 0.2], 'claude-sonnet-5-5': [2, 10, 2.5, 0.2] },
  };
  // Riserva gratuita. «short» = il piano gratuito accetta richieste piccole: invio solo le ultime 4 settimane.
  const FREE = {
    gemini: {
      name: 'Google Gemini', keyUrl: 'https://aistudio.google.com/apikey', keyHint: 'AIza…',
      models: { 'gemini-3.8-flash': 'Gemini 3.8 Flash', 'gemini-3.7-flash': 'Gemini 3.7 Flash', 'gemini-3.5-flash': 'Gemini 3.5 Flash', 'gemini-3.5-flash-lite': 'Gemini 3.5 Flash-Lite' },
      how: 'Gratis con un account Google (servono 18 anni). Apri aistudio.google.com/apikey, tocca «Create API key» e incolla qui la chiave. Non serve una carta.',
      privacy: 'Con il piano gratuito Google può usare domande e risposte per migliorare i suoi servizi, e dei revisori possono leggerle.',
    },
    groq: {
      name: 'Groq', keyUrl: 'https://console.groq.com/keys', keyHint: 'gsk_…', short: true,
      models: { 'openai/gpt-oss-120b': 'GPT-OSS 120B', 'llama-3.3-70b-versatile': 'Llama 3.3 70B' },
      how: 'Gratis con un account Groq. Apri console.groq.com/keys, crea una chiave e incollala qui. Non serve una carta.',
      privacy: 'Groq dichiara di non conservare il contenuto delle richieste. Riceve solo le ultime 4 settimane di dati.',
    },
  };
  const DAY = 86400000;
  const GIORNI = ['lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato', 'domenica'];
  const DIET_START = '2026-10-03'; // da qui segue la dieta dell'app; prima mangiava a occhio
  const PRESETS = [
    ['progress', 'Sto progredendo bene?'],
    ['kcal', 'Devo cambiare le calorie?'],
    ['recomp', 'Come sta andando la ricomposizione?'],
    ['best', 'Quale esercizio sto migliorando di più?'],
    ['today', 'L’allenamento di oggi è stato sufficiente?'],
    ['stall', 'Il peso è fermo: cosa conviene fare?'],
  ];
  const CHECKIN = 'Fammi il check-in della settimana: gli ultimi 7 giorni, oggi compreso.\n'
    + 'Struttura: **Peso** (media della settimana contro quella prima e ritmo rispetto al piano), **Dieta** (giorni con i pasti segnati, kcal e proteine medie contro il target; conta solo i giorni da quando segui la dieta dell’app), '
    + '**Allenamento** (sedute fatte su previste, esercizi in crescita o fermi), poi **Da fare** con 1-3 azioni concrete. '
    + 'Se un’azione si può fare nell’app (scambio di un pasto, carico della prossima seduta), proponila con lo strumento giusto.';
  const PHOTO_Q = 'Quanto vale questo pasto? Confrontalo con il pasto del mio piano più vicino.';
  const ui = { busy: false, draft: '', err: '', live: '', status: '', all: false, photo: null, prov: '', free: '', copied: '' };

  // Chiavi per servizio, solo su questo dispositivo (rc.aiKeys non viene sincronizzato né messo nel backup).
  // Le versioni precedenti avevano una sola chiave (rc.aiKey + rc.aiProv): la sposto qui la prima volta.
  function getKeys() {
    const k = K();
    const keys = k.store.get('aiKeys', {});
    const old = k.store.get('aiKey', '');
    if (old) {
      const p = k.store.get('aiProv', '');
      const pid = FREE[p] ? p : 'claude';
      if (!keys[pid]) keys[pid] = old;
      k.store.set('aiKeys', keys);
      k.store.set('aiKey', '');
    }
    return keys;
  }
  function setKey(pid, v) { const keys = getKeys(); if (v) keys[pid] = v; else delete keys[pid]; K().store.set('aiKeys', keys); }
  const hasClaude = () => !!getKeys().claude;
  const freeProv = () => { const keys = getKeys(); return Object.keys(FREE).find((p) => keys[p]) || ''; };
  const claudeModel = () => { const m = K().store.get('aiModel', ''); return CLAUDE.models[m] ? m : 'claude-opus-5-5'; };
  const short = (label) => label.split(' · ')[0];
  const getChat = () => K().store.get('coachChat', []);
  const setChat = (c) => K().store.set('coachChat', c.slice(-20)); // al massimo le ultime 10 domande con risposta

  // memoria del coach (rc.coachMem, sincronizzata): { id: { x: testo, c: creata, t: modificata } }, le cancellate restano come { del, t }
  const mem = () => Object.entries(K().store.get('coachMem', {})).filter(([, m]) => m && !m.del && m.x)
    .map(([id, m]) => ({ id, x: m.x, c: m.c || m.t })).sort((a, b) => a.c - b.c);
  function remember(x) {
    const all = K().store.get('coachMem', {});
    const id = 'm' + Date.now().toString(36);
    all[id] = { x, c: Date.now(), t: Date.now() };
    K().store.set('coachMem', all);
    return id;
  }
  function forget(id) {
    const all = K().store.get('coachMem', {});
    if (!all[id] || all[id].del) return false;
    all[id] = { del: 1, t: Date.now() };
    K().store.set('coachMem', all);
    return true;
  }
  // spesa stimata per mese (rc.aiSpend, solo su questo dispositivo)
  const monthKey = () => K().dkey(new Date()).slice(0, 7);
  function addSpend(usd) { const s = K().store.get('aiSpend', {}); s[monthKey()] = (s[monthKey()] || 0) + usd; K().store.set('aiSpend', s); }
  const usd = (x) => (x < 0.01 ? '< 0,01' : x.toFixed(2).replace('.', ',')) + ' $';

  /* ---------------- fatti calcolati dai dati ---------------- */
  function facts() {
    const k = K();
    const D = k.D;
    const now = new Date();
    const today = k.dkey(now);
    const t0 = k.fromKey(today).getTime();
    const ago = (key) => Math.round((t0 - k.fromKey(key).getTime()) / DAY);
    const sinceStart = ago(k.START.d);

    // peso
    const ws = k.weights();
    const wk = k.weekly(ws);
    const full = wk.filter((w) => w.n >= 3);
    const last = ws[ws.length - 1] || null;
    const l7 = last ? ws.filter((w) => (k.fromKey(last.d) - k.fromKey(w.d)) / DAY < 7) : [];
    const avg7 = l7.length ? l7.reduce((a, w) => a + w.kg, 0) / l7.length : null;
    const d1 = full.length >= 2 ? full[full.length - 1].kg - full[full.length - 2].kg : null;
    const d2 = full.length >= 3 ? full[full.length - 2].kg - full[full.length - 3].kg : null;
    const waists = ws.filter((w) => w.w != null);
    const waistD = waists.length >= 2 ? waists[waists.length - 1].w - waists[0].w : null;

    // dieta: diario delle spunte degli ultimi 14 giorni
    const dlog = k.store.get('dlog', {});
    const span = Math.max(1, Math.min(14, sinceStart + 1));
    const days = Object.keys(dlog).filter((d) => ago(d) >= 0 && ago(d) < span).sort().map((d) => ({ d, ...dlog[d] }));
    const okDays = days.filter((x) => x.of && x.n >= Math.ceil(x.of * 0.8));
    const mean = (arr, f) => (arr.length ? arr.reduce((a, x) => a + f(x), 0) / arr.length : null);

    // allenamento: ultime 4 settimane (o dall'inizio del percorso)
    const hist = WD().history();
    const win = Math.max(1, Math.min(28, sinceStart + 1));
    let expected = 0;
    for (let i = 0; i < win; i++) { const d = new Date(t0 - i * DAY); if (D.week[k.dayIdx(d)].wo) expected++; }
    const done = hist.filter((w) => w.start >= t0 - (win - 1) * DAY).length;
    const sk = WD().skipped();
    const skipped = Object.keys(sk).filter((d) => ago(d) >= 0 && ago(d) < win).length;
    // progresso per esercizio nelle ultime 8 settimane: valore migliore di ogni seduta (1RM stimato o secondi)
    const byEx = {};
    hist.filter((w) => w.start >= t0 - 56 * DAY).slice().reverse().forEach((w) => w.items.forEach((it) => {
      const e = WD().exOf(it.ex);
      const work = it.sets.filter((s) => s.type !== 'w' && s.r != null);
      if (!work.length) return;
      const v = e.unit === 'sec' ? Math.max(...work.map((s) => s.r)) : Math.max(...work.map((s) => WD().e1rm(s.kg, s.r)));
      if (v > 0) (byEx[it.ex] = byEx[it.ex] || []).push({ v, t: w.start, txt: e.unit === 'sec' ? `${Math.max(...work.map((s) => s.r))}″` : `${k.fmtKg(Math.max(...work.map((s) => s.kg || 0)))} kg × ${work.map((s) => s.r).join('·')}` });
    }));
    const prog = Object.keys(byEx).filter((id) => byEx[id].length >= 2).map((id) => {
      const a = byEx[id];
      return { id, n: WD().exOf(id).n, pct: (a[a.length - 1].v - a[0].v) / a[0].v * 100, from: a[0].txt, to: a[a.length - 1].txt, sessions: a.length };
    }).sort((x, y) => y.pct - x.pct);
    const stalls = Object.keys(byEx).filter((id) => { const a = byEx[id]; const n = a.length; return n >= 3 && a[n - 1].v <= a[n - 2].v * 1.005 && a[n - 2].v <= a[n - 3].v * 1.005; }).map((id) => WD().exOf(id).n);
    const todayW = hist.find((w) => k.dkey(new Date(w.start)) === today) || null;

    const crea = k.store.get('creatina', {});
    const creaDays = Object.keys(crea).filter((d) => crea[d].on && ago(d) >= 0 && ago(d) < span).length;

    return { today, sinceStart, ws, wk, full, last, avg7, d1, d2, waistD, span, days, okDays, mean, win, expected, done, skipped, prog, stalls, todayW, hist, creaDays };
  }

  const s2 = (x) => K().sign(Math.round(x * 100) / 100, K().f2);
  const pc = (x) => `${x >= 0 ? '+' : '−'}${K().f1(Math.abs(x))}%`;

  function tWeight(f) {
    const k = K();
    if (!f.ws.length) return 'Nessuna pesata registrata. Segna il peso in Progressi almeno 4 mattine a settimana: senza, non posso dire se il ritmo è giusto.';
    const head = `Ultima pesata ${k.f2(f.last.kg)} kg (${k.shortDate(f.last.d)}), media degli ultimi 7 giorni ${k.f2(f.avg7)} kg, ${s2(f.avg7 - k.START.kg)} kg dalla partenza.`;
    if (f.full.length < 2) return `${head} Hai ${f.ws.length} pesat${f.ws.length === 1 ? 'a' : 'e'}: servono 2 settimane con almeno 3 pesate ciascuna per giudicare il ritmo.`;
    return `${head} ${k.advice(f.wk)}`;
  }
  function tDiet(f) {
    const k = K();
    if (!f.days.length) return `Negli ultimi ${f.span} giorni non hai spuntato nessun pasto in Oggi: senza spunte non posso valutare quanto segui il piano.`;
    const kc = f.mean(f.okDays, (x) => x.k), tk = f.mean(f.okDays, (x) => x.tk), p = f.mean(f.okDays, (x) => x.p);
    return `Negli ultimi ${f.span} giorni hai spuntato pasti in ${f.days.length} giorn${f.days.length === 1 ? 'o' : 'i'}; in ${f.okDays.length} hai seguito almeno l’80% del piano.`
      + (f.okDays.length ? ` In quei giorni: in media ${k.f0(kc)} kcal spuntate su ${k.f0(tk)} previste e ${k.f0(p)} g di proteine (obiettivo 140).` : '')
      + (f.creaDays ? ` Creatina presa ${f.creaDays} giorn${f.creaDays === 1 ? 'o' : 'i'} su ${f.span}.` : '');
  }
  function tTrain(f) {
    if (!f.hist.length) return `Nessun allenamento registrato finora${f.expected ? ` (ne erano previsti ${f.expected} negli ultimi ${f.win} giorni)` : ''}. Avvia l’allenamento dalla Scheda e spunta le serie: da lì calcolo carichi e progressi.`;
    const up = f.prog.filter((x) => x.pct > 0.5).length;
    return `Negli ultimi ${f.win} giorni erano previsti ${f.expected} allenamenti: ne hai registrati ${f.done}${f.skipped ? `, ${f.skipped} segnat${f.skipped === 1 ? 'o' : 'i'} come saltat${f.skipped === 1 ? 'o' : 'i'}` : ''}.`
      + (f.prog.length ? ` Su ${f.prog.length} esercizi con almeno 2 sedute, ${up} sono in crescita.` : ' Per vedere i progressi servono almeno 2 sedute dello stesso esercizio.')
      + (f.stalls.length ? ` Fermi da 3 sedute: ${f.stalls.join(', ')}.` : '');
  }

  // risposte alle domande pronte, calcolate dai dati (senza AI)
  function localAnswer(id) {
    const k = K();
    const f = facts();
    if (id === 'progress') {
      const enough = f.full.length >= 2 && f.hist.length >= 2;
      const wOk = f.d1 != null && f.d1 <= -0.15 && f.d1 > -0.6;
      const tOk = f.expected ? f.done >= Math.ceil(f.expected * 0.75) : true;
      const verdict = !enough ? '**Troppo presto per un giudizio**: servono almeno 2 settimane di pesate e 2 allenamenti registrati.'
        : wOk && tOk ? '**Sì, stai andando bene**: il peso scende al ritmo giusto e ti alleni con costanza.'
          : `**Da sistemare**: ${[wOk ? '' : 'il ritmo del peso non è quello previsto', tOk ? '' : 'hai saltato troppi allenamenti'].filter(Boolean).join(' e ')}.`;
      return `${verdict}\n- Peso: ${tWeight(f)}\n- Allenamento: ${tTrain(f)}\n- Dieta: ${tDiet(f)}`;
    }
    if (id === 'kcal' || id === 'stall') {
      if (f.full.length < 2) return `**Per ora non cambiare niente.** ${tWeight(f)}\nLe calorie si toccano solo guardando la media settimanale del peso, mai un singolo giorno.`;
      const flat = f.d1 > -0.15 && f.d1 < 0.2;
      const lead = id === 'stall' && !flat ? `Dai dati il peso non è fermo: l’ultima media settimanale è ${s2(f.d1)} kg rispetto alla precedente.\n` : '';
      return `${lead}${k.advice(f.wk)}\n- Ultima variazione settimanale: ${s2(f.d1)} kg${f.d2 != null ? `, quella prima ${s2(f.d2)} kg` : ''}.\n- Ritmo previsto dal piano: da −0,2 a −0,5 kg a settimana.${f.waistD != null ? `\n- Girovita: ${k.sign(k.r1(f.waistD))} cm dalla prima misura.` : ''}\n- Dieta: ${tDiet(f)}`;
    }
    if (id === 'recomp') {
      const str = f.prog.length ? f.mean(f.prog, (x) => x.pct) : null;
      const lines = [
        f.avg7 != null ? `Peso: ${s2(f.avg7 - k.START.kg)} kg dalla partenza (media 7 giorni ${k.f2(f.avg7)} kg, partenza ${k.f2(k.START.kg)} kg).` : 'Peso: nessuna pesata registrata.',
        f.waistD != null ? `Girovita: ${k.sign(k.r1(f.waistD))} cm dalla prima misura.` : 'Girovita: servono almeno 2 misure (ogni lunedì).',
        str != null ? `Forza: in media ${pc(str)} di forza stimata su ${f.prog.length} esercizi.` : 'Forza: servono almeno 2 sedute per esercizio.',
      ];
      const ok = f.avg7 != null && f.avg7 < k.START.kg && str != null && str >= 0;
      const verdict = f.sinceStart < 14 ? `Sei al giorno ${f.sinceStart + 1} del percorso: una ricomposizione si giudica su 3–4 settimane.`
        : ok ? '**La ricomposizione sta funzionando**: il peso scende mentre la forza tiene o sale, quindi stai perdendo grasso e non muscolo.'
          : 'I segnali non sono ancora tutti nella direzione giusta: guarda i punti sotto.';
      return `${verdict}\n${lines.map((l) => `- ${l}`).join('\n')}`;
    }
    if (id === 'best') {
      if (!f.prog.length) return 'Per confrontare gli esercizi servono almeno 2 sedute registrate dello stesso esercizio. Per ora non ce ne sono.';
      return `**${f.prog[0].n}** è quello che cresce di più.\n${f.prog.slice(0, 3).map((x) => `- ${x.n}: ${pc(x.pct)} di forza stimata in ${x.sessions} sedute (da ${x.from} a ${x.to})`).join('\n')}${f.stalls.length ? `\nFermi da 3 sedute: ${f.stalls.join(', ')}.` : ''}`;
    }
    if (id === 'today') {
      const plan = k.D.week[k.dayIdx(new Date())];
      if (!f.todayW) return `Oggi non risulta nessun allenamento registrato${plan.wo ? ` (era previsto ${k.D.workouts.find((x) => x.id === plan.wo).name})` : ': è un giorno di riposo'}.`;
      const rows = WD().analyze(f.todayW);
      const r = f.todayW.rid ? WD().routines().find((x) => x.id === f.todayW.rid) : null;
      const planned = r ? r.items.reduce((a, it) => a + it.s, 0) : 0;
      const sets = rows.reduce((a, x) => a + x.cur.n, 0);
      const cnt = (st) => rows.filter((x) => x.st === st).length;
      const enough = !planned || sets >= Math.ceil(planned * 0.85);
      return `${enough ? '**Sì, hai fatto il lavoro previsto.**' : '**Seduta incompleta.**'} ${f.todayW.name}: ${sets} serie allenanti${planned ? ` su ${planned} previste` : ''}.\n- In progresso: ${cnt('up')} · stabili: ${cnt('same')} · in calo: ${cnt('down')}${cnt('new') ? ` · prima volta: ${cnt('new')}` : ''}\n${rows.filter((x) => x.next).slice(0, 6).map((x) => `- ${x.n}: ${x.next}`).join('\n')}`;
    }
    return '';
  }

  /* ---------------- dati dell'app in forma di testo per l'AI ---------------- */
  function context(short) {
    const k = K();
    const D = k.D;
    const P = k.plan;
    const f = facts();
    const now = new Date();
    const L = [];
    const dk = (ts) => k.dkey(new Date(ts));
    const T = D.targets;
    const onDays = D.week.filter((d) => d.type === 'ON').map((d) => d.name).join(', ');
    const nOn = D.week.filter((d) => d.type === 'ON').length;
    L.push(`Dati aggiornati al ${f.today} (${GIORNI[k.dayIdx(now)]}), giorno ${f.sinceStart + 1} del percorso.`);
    L.push('', 'PROFILO',
      `Maschio, 18 anni, 173 cm. Partenza ${k.START.d}: ${k.START.kg} kg, ${k.START.bf}% di grasso (bilancia a impedenza, errore ±3-5 punti), massa magra 53.26 kg.`,
      `Obiettivo: ricomposizione corporea (meno grasso su addome e fianchi, più muscolo su dorsali e deltoidi, carichi in salita). Traguardo indicativo ${k.GOAL.kg} kg entro ${k.GOAL.d}, poi mantenimento.`,
      `Segue la dieta dell'app dal ${DIET_START}; prima mangiava a occhio, quindi i giorni precedenti non dicono niente su quanto segue il piano. Pesa il cibo: ragiona in grammi.`);
    L.push('', 'PIANO ALIMENTARE',
      `Giorni ON (allenamento: ${onDays}): ${T.ON.k} kcal, proteine ${T.ON.p} g, carboidrati ${T.ON.c} g, grassi ${T.ON.f} g.`,
      `Giorni OFF (riposo): ${T.OFF.k} kcal, proteine ${T.OFF.p} g, carboidrati ${T.OFF.c} g, grassi ${T.OFF.f} g.`,
      `Media pianificata: ${Math.round((nOn * T.ON.k + (7 - nOn) * T.OFF.k) / 7)} kcal al giorno. Consumo stimato: 2450 kcal nei giorni ON, 2100 nei giorni OFF, media 2300 (stima: passi e attività non sono registrati nell'app).`,
      'Ritmo atteso: da -0.2 a -0.5 kg a settimana. Pasto libero la domenica a pranzo, non conteggiato (stima 800-1000 kcal).',
      'Regole di correzione del piano: calo oltre 0.6 kg a settimana per 2 settimane -> +150 kcal; peso e girovita fermi per 2 settimane -> -100/150 kcal oppure +2000 passi; carichi in calo per 2 settimane -> +100 kcal nei giorni ON e più sonno. Nelle prime 2-3 settimane di creatina 0.5-1 kg in più è acqua.');
    const tp = P.todayPlan();
    const eaten = P.eatenToday();
    L.push('', `OGGI (${GIORNI[k.dayIdx(now)]}, giorno ${tp.conv ? `${tp.conv === 'ON' ? 'ON' : 'OFF'}, cambiato oggi` : tp.day.type}): pasti del piano. Numero, ora, pasto, ricetta, kcal e macro; [mangiato] = già segnato.`);
    tp.meals.forEach((m) => L.push(m.free ? `${m.si} ${m.time} ${m.label}: pasto libero` : `${m.si} ${m.time} ${m.label}: ${m.code} ${D.recipes[m.code].name}, ${m.tot.k} kcal, P ${m.tot.p} C ${m.tot.c} G ${m.tot.fa}${eaten.includes(m.si) ? ' [mangiato]' : ''}`));
    L.push('Settimana tipo, ricette attuali con gli scambi (per ingredienti e alternative usa piano_giorno): '
      + D.week.map((d, di) => `${GIORNI[di]} ${d.type}: ${P.dayPlan(di).meals.map((m) => (m.free ? 'libero' : m.code)).join(' ')}`).join('; '));
    const bw = k.blockWeek();
    L.push('', `SCHEDA (id dell'esercizio tra parentesi quadre). Torso/Limbs 4 volte a settimana, blocco di 7 settimane: ora settimana ${bw.n} (${bw.phase}). Progressione: quando tutte le serie arrivano al massimo del range si aumenta il carico.`);
    WD().routines().forEach((r) => L.push(`${r.name}${r.day ? ` (${r.day})` : ''}: ${r.items.map((it) => `${WD().exOf(it.ex).n} [${it.ex}] ${it.s}x${it.lo}-${it.hi}`).join('; ')}`));

    L.push('', `PESO (${f.ws.length} pesate registrate; data, kg, girovita in cm se misurato)`);
    if (!f.ws.length) L.push('Nessuna pesata registrata.');
    f.ws.slice(short ? -28 : -60).forEach((w) => L.push(`${w.d} ${w.kg}${w.w != null ? ` vita ${w.w}` : ''}`));
    if (f.wk.length) L.push('Medie settimanali (lunedì della settimana, numero di pesate, media kg): ' + f.wk.slice(-10).map((w) => `${w.wk} n=${w.n} ${w.kg.toFixed(2)}`).join('; '));

    const dlog = k.store.get('dlog', {});
    const dkeys = Object.keys(dlog).sort().slice(short ? -14 : -28);
    L.push('', `DIETA - diario dei pasti segnati (ultimi ${short ? 14 : 28} giorni). Un giorno assente significa che non è stato segnato niente nell'app, non che non ha mangiato.`);
    if (!dkeys.length) L.push('Nessun pasto segnato finora.');
    dkeys.forEach((d) => { const x = dlog[d]; L.push(`${d} ${x.on ? 'ON' : 'OFF'}${x.free ? ' (con pasto libero non conteggiato)' : ''}: pasti ${x.n}/${x.of}, kcal ${x.k}/${x.tk}, P ${x.p} C ${x.c} G ${x.f}`); });

    const crea = k.store.get('creatina', {});
    const cDays = Object.keys(crea).filter((d) => crea[d].on).sort();
    L.push('', 'CREATINA', cDays.length ? `Prima spunta ${cDays[0]}; presa ${f.creaDays} giorni negli ultimi ${f.span}.` : 'Nessuna spunta registrata.');

    const weeks = short ? 4 : 8;
    const hist = f.hist.filter((w) => w.start >= now.getTime() - weeks * 7 * DAY).slice().reverse();
    L.push('', `ALLENAMENTI registrati nelle ultime ${weeks} settimane: ${hist.length} (serie: kg x ripetizioni; R = riscaldamento)`);
    if (!hist.length) L.push('Nessun allenamento registrato.');
    hist.forEach((w) => {
      const vol = w.items.reduce((a, it) => a + it.sets.filter((s) => s.type !== 'w').reduce((b, s) => b + (s.kg > 0 && s.r > 0 ? s.kg * s.r : 0), 0), 0);
      L.push(`${dk(w.start)} ${w.name} (${Math.round((w.end - w.start) / 60000)} min, volume ${Math.round(vol)} kg): ` + w.items.map((it) => `${WD().exOf(it.ex).n}: ${setsTxt(it)}`).join(' | '));
    });
    const sk = Object.keys(WD().skipped()).sort();
    L.push(`Allenamenti segnati come saltati: ${sk.length ? sk.join(', ') : 'nessuno'}.`);
    L.push(`Ultimi ${f.win} giorni: previsti ${f.expected}, registrati ${f.done}.`);
    if (f.prog.length) L.push('Variazione della forza stimata per esercizio (prima e ultima seduta nelle 8 settimane): ' + f.prog.map((x) => `${x.n} ${x.pct >= 0 ? '+' : ''}${x.pct.toFixed(1)}% (${x.sessions} sedute)`).join('; '));

    const tg = Object.entries(k.store.get('loadNext', {})).filter(([id, x]) => x && !x.del && x.kg > 0 && !f.hist.some((w) => w.start > x.t && w.items.some((it) => it.ex === id && it.sets.length)));
    if (tg.length) L.push('', "CARICHI PROPOSTI DAL COACH E ACCETTATI (l'app li suggerisce alla prossima seduta di quell'esercizio): " + tg.map(([id, x]) => `${WD().exOf(id).n} [${id}] ${x.kg} kg x ${x.r} (dal ${dk(x.t)})`).join('; '));
    const ms = mem();
    L.push('', 'MEMORIA DEL COACH (note salvate nelle conversazioni precedenti; id tra parentesi quadre)');
    L.push(ms.length ? ms.map((m) => `[${m.id}] ${m.x} (${dk(m.c)})`).join('\n') : 'Nessuna nota.');
    return L.join('\n');
  }
  function setsTxt(it) {
    const e = WD().exOf(it.ex);
    return it.sets.map((s) => (e.unit === 'sec' ? `${s.r}s` : `${s.kg ?? '?'}x${s.r ?? '?'}`) + (s.type === 'w' ? 'R' : '')).join(', ') + (it.note ? ` [nota: ${it.note}]` : '');
  }

  const SYSTEM = `Sei il coach dentro "Recomp", l'app personale di un ragazzo di 18 anni che fa ricomposizione corporea. Rispondi in italiano, dandogli del tu, in modo diretto e pratico.

Regole:
- Basati sui dati dell'app riportati tra i tag <dati_app> e su quello che lui ti dice o ti mostra. Non inventare pesate, allenamenti, calorie o tendenze che non ci sono.
- Se i dati non bastano per rispondere (poche pesate, nessun allenamento registrato, pasti non segnati), dillo chiaramente e spiega cosa deve registrare e per quanto tempo prima di poter concludere qualcosa.
- Quando dai un giudizio, cita i numeri su cui lo basi (date, kg, ripetizioni, kcal).
- Per le calorie segui le regole di correzione del piano riportate nei dati; non proporre cambi più grandi senza un motivo che emerge dai dati.
- Le porzioni devono avere senso a tavola (un panino ha 2 fette, niente 30 g di riso): lui pesa il cibo, quindi parla in grammi.
- Non sei un medico: per dolori, infortuni o problemi di salute suggerisci di sentire un professionista.
- Rispondi in breve: lo leggerà sul telefono. Frasi corte o un elenco puntato di pochi punti, niente tabelle. Se serve, chiudi con 1-3 cose concrete da fare.`;

  const CLAUDE_NOTE = `

Strumenti:
- piano_giorno: ingredienti e alternative dei pasti di un giorno della settimana tipo. Usalo prima di proporre uno scambio o per confrontare una foto con un pasto che non è di oggi.
- storico_esercizio: tutte le sedute registrate di un esercizio, anche quelle più vecchie di 8 settimane.
- proponi_scambio_pasto, proponi_pasti_mangiati, proponi_carico: non cambiano niente da sole. Mostrano sotto la tua risposta una scheda con «Applica» e decide lui. Proponi solo quando c'è un motivo nei dati o quando te lo chiede, al massimo 3 proposte per risposta, e nel testo di' in una riga cosa hai proposto e perché.
- ricorda e dimentica: la tua memoria tra una conversazione e l'altra (sezione MEMORIA DEL COACH nei dati). Salva solo fatti utili e stabili che ti dice lui (un dolore, una preferenza, un orario, un obiettivo), una frase per nota. Non salvare quello che l'app registra già (pesate, allenamenti, pasti). Se una nota non è più vera, cancellala.

Foto: se ti manda la foto di un piatto, stima ingredienti e grammi, poi kcal e macro, dicendo quanto sei incerto; se è un'etichetta, usa i valori scritti. Poi confronta con il pasto del piano più vicino e digli come sistemare il resto della giornata, se serve.`;

  /* ---------------- strumenti di Claude ---------------- */
  const obj = (props, req) => ({ type: 'object', properties: props, required: req, additionalProperties: false });
  const TOOLS = [
    { name: 'piano_giorno', description: 'Pasti di un giorno della settimana tipo: per ogni pasto numero, ora, nome, ricetta attuale con ingredienti in grammi, kcal e macro, e le ricette alternative possibili per quel pasto con kcal e proteine.',
      input_schema: obj({ giorno: { type: 'integer', description: '0 = lunedì, 1 = martedì, … 6 = domenica' } }, ['giorno']) },
    { name: 'storico_esercizio', description: "Tutte le sedute registrate di un esercizio, dalla più recente: data e serie (kg x ripetizioni, R = riscaldamento). L'id è quello tra parentesi quadre nella SCHEDA.",
      input_schema: obj({ esercizio: { type: 'string', description: "id dell'esercizio" } }, ['esercizio']) },
    { name: 'proponi_scambio_pasto', description: 'Propone di sostituire la ricetta di un pasto in un giorno della settimana tipo; lo scambio vale tutte le settimane finché lui non lo cambia. Non applica niente: mostra una scheda con «Applica». Prima leggi le alternative con piano_giorno: la ricetta deve essere una di quelle.',
      input_schema: obj({ giorno: { type: 'integer', description: '0 = lunedì … 6 = domenica' }, pasto: { type: 'integer', description: 'numero del pasto, come in piano_giorno' }, ricetta: { type: 'string', description: 'codice della ricetta alternativa, per esempio P-F' }, motivo: { type: 'string', description: 'perché, in una frase breve' } }, ['giorno', 'pasto', 'ricetta', 'motivo']) },
    { name: 'proponi_pasti_mangiati', description: 'Propone di segnare come mangiati alcuni pasti di OGGI (numeri dei pasti di oggi nei dati), per esempio quando ti dice cosa ha mangiato. Non applica niente: mostra una scheda con «Applica».',
      input_schema: obj({ pasti: { type: 'array', items: { type: 'integer' }, description: 'numeri dei pasti di oggi' }, motivo: { type: 'string', description: 'in una frase breve' } }, ['pasti', 'motivo']) },
    { name: 'proponi_carico', description: "Propone carico e ripetizioni per la prossima seduta di un esercizio: l'app li suggerirà durante l'allenamento al posto del solito consiglio, solo per quella seduta. Non applica niente: mostra una scheda con «Applica».",
      input_schema: obj({ esercizio: { type: 'string', description: "id dell'esercizio" }, kg: { type: 'number', description: 'carico in kg che esiste davvero su quell’attrezzo (di solito passi di 2,5 kg; per i manubri il peso di un manubrio)' }, ripetizioni: { type: 'integer', description: 'ripetizioni da cercare su ogni serie' }, motivo: { type: 'string', description: 'perché, in una frase breve' } }, ['esercizio', 'kg', 'ripetizioni', 'motivo']) },
    { name: 'ricorda', description: 'Salva una nota nella tua memoria: la vedrai in tutte le prossime conversazioni. Una frase, solo fatti utili e stabili che ti ha detto lui.',
      input_schema: obj({ testo: { type: 'string' } }, ['testo']) },
    { name: 'dimentica', description: 'Cancella una nota dalla memoria (id tra parentesi quadre nella sezione MEMORIA DEL COACH), per esempio quando non è più vera.',
      input_schema: obj({ id: { type: 'string' } }, ['id']) },
  ].map((t) => ({ ...t, eager_input_streaming: true }));
  const STATUS = {
    piano_giorno: 'Guardo il piano dei pasti…', storico_esercizio: 'Guardo lo storico dell’esercizio…',
    proponi_scambio_pasto: 'Preparo una proposta…', proponi_pasti_mangiati: 'Preparo una proposta…', proponi_carico: 'Preparo una proposta…',
    ricorda: 'Me lo segno…', dimentica: 'Aggiorno la memoria…',
  };

  // Esegue uno strumento chiesto da Claude. L'input arriva dal modello: ogni campo viene controllato prima di usarlo.
  // Le proposte non toccano i dati: finiscono in «acts» e diventano schede con «Applica» sotto la risposta.
  function runTool(name, x, acts) {
    const k = K();
    const D = k.D;
    const P = k.plan;
    const int = (v, lo, hi) => Number.isInteger(v) && v >= lo && v <= hi;
    const text = (v, max) => typeof v === 'string' && v.trim().length > 0 && v.trim().length <= max;
    const bad = (out) => ({ err: true, out });
    const sent = 'Proposta mostrata sotto la tua risposta: la applica lui con un tocco, se vuole.';
    const exOk = (id) => typeof id === 'string' && (WD().exOf(id).n !== id || WD().history().some((w) => w.items.some((it) => it.ex === id)));
    const meal = (m) => `${m.code} ${D.recipes[m.code].name} (${m.tot.k} kcal, P ${m.tot.p})`;
    if (!x || typeof x !== 'object') return bad('input non valido');
    switch (name) {
      case 'piano_giorno': {
        if (!int(x.giorno, 0, 6)) return bad('giorno: intero da 0 (lunedì) a 6 (domenica)');
        const p = P.dayPlan(x.giorno);
        const unit = (f) => (f === 'latte_ps' || f === 'spremuta' ? 'ml' : 'g');
        return { out: [`${GIORNI[x.giorno]}, giorno ${p.day.type}: totale ${p.tot.k} kcal, P ${p.tot.p} C ${p.tot.c} G ${p.tot.fa}`].concat(p.meals.map((m) => (m.free
          ? `pasto ${m.si}, ${m.time} ${m.label}: pasto libero (fuori dai conti)`
          : `pasto ${m.si}, ${m.time} ${m.label}: ${meal(m)}${m.code !== m.def ? ` [scambio; di base ${m.def}]` : ''}, C ${m.tot.c} G ${m.tot.fa}. Ingredienti: ${m.lines.map((l) => `${D.foods[l.f].n} ${l.g} ${unit(l.f)}`).join(', ')}.\n  Alternative: ${P.mealOptions(m.slot).filter((o) => o.code !== m.code).map((o) => `${o.code} ${o.name} (${o.k} kcal, P ${o.p})`).join('; ') || 'nessuna'}`))).join('\n') };
      }
      case 'storico_esercizio': {
        if (!exOk(x.esercizio)) return bad('esercizio sconosciuto: usa un id tra parentesi quadre della SCHEDA');
        const rows = WD().history().filter((w) => w.items.some((it) => it.ex === x.esercizio && it.sets.length)).slice(0, 40)
          .map((w) => `${k.dkey(new Date(w.start))} ${w.name}: ${setsTxt(w.items.find((it) => it.ex === x.esercizio))}`);
        return { out: `${WD().exOf(x.esercizio).n}: ${rows.length ? `${rows.length} sedute\n${rows.join('\n')}` : 'nessuna seduta registrata'}` };
      }
      case 'proponi_scambio_pasto': {
        if (!int(x.giorno, 0, 6)) return bad('giorno: intero da 0 (lunedì) a 6 (domenica)');
        const p = P.dayPlan(x.giorno);
        const m = p.meals.find((y) => y.si === x.pasto);
        if (!m || m.free) return bad('pasto: usa il numero di un pasto di quel giorno (non il pasto libero), come in piano_giorno');
        if (typeof x.ricetta !== 'string' || !D.variants[m.slot][x.ricetta]) return bad(`ricetta: per questo pasto vanno bene solo ${Object.keys(D.variants[m.slot]).join(', ')}`);
        if (x.ricetta === m.code) return bad('è già la ricetta di quel pasto');
        const o = P.mealOptions(m.slot).find((y) => y.code === x.ricetta);
        acts.push({ kind: 'swap', di: x.giorno, si: m.si, code: x.ricetta, title: `Scambio: ${GIORNI[x.giorno]}, ${m.label}`,
          sub: `${meal(m)} → ${o.code} ${o.name} (${o.k} kcal, P ${o.p})`, why: text(x.motivo, 300) ? x.motivo.trim() : '' });
        return { out: sent };
      }
      case 'proponi_pasti_mangiati': {
        const tp = P.todayPlan();
        if (!Array.isArray(x.pasti) || !x.pasti.length) return bad('pasti: elenco dei numeri dei pasti di oggi');
        const ms = [...new Set(x.pasti)].map((si) => tp.meals.find((m) => m.si === si));
        if (ms.some((m) => !m || m.free)) return bad('pasti: usa i numeri dei pasti di oggi riportati nei dati (non il pasto libero)');
        const todo = ms.filter((m) => !P.eatenToday().includes(m.si));
        if (!todo.length) return bad('questi pasti sono già segnati come mangiati');
        acts.push({ kind: 'eat', sis: todo.map((m) => m.si), title: 'Segna come mangiati (oggi)',
          sub: todo.map((m) => `${m.label}: ${D.recipes[m.code].name}`).join(' · '), why: text(x.motivo, 300) ? x.motivo.trim() : '' });
        return { out: sent };
      }
      case 'proponi_carico': {
        if (!exOk(x.esercizio)) return bad('esercizio sconosciuto: usa un id tra parentesi quadre della SCHEDA');
        if (typeof x.kg !== 'number' || !(x.kg > 0 && x.kg <= 400)) return bad('kg: numero tra 0 e 400');
        if (!int(x.ripetizioni, 1, 60)) return bad('ripetizioni: intero da 1 a 60');
        const kg = Math.round(x.kg * 2) / 2;
        acts.push({ kind: 'load', ex: x.esercizio, kg, r: x.ripetizioni, title: `Prossima seduta: ${WD().exOf(x.esercizio).n}`,
          sub: `${k.fmtKg(kg)} kg × ${x.ripetizioni} su ogni serie`, why: text(x.motivo, 300) ? x.motivo.trim() : '' });
        return { out: sent };
      }
      case 'ricorda': {
        if (!text(x.testo, 300)) return bad('testo: una frase, al massimo 300 caratteri');
        if (mem().length >= 40) return bad('memoria piena (40 note): prima cancellane una che non serve più con dimentica');
        const id = remember(x.testo.trim());
        acts.push({ kind: 'mem', id, title: 'Ricordato', sub: x.testo.trim() });
        return { out: `nota salvata con id ${id}` };
      }
      case 'dimentica': {
        const m = mem().find((y) => y.id === x.id);
        if (!m || !forget(m.id)) return bad('id sconosciuto: usa un id della sezione MEMORIA DEL COACH');
        acts.push({ kind: 'forget', title: 'Tolto dalla memoria', sub: m.x });
        return { out: 'nota cancellata' };
      }
      default: return bad('strumento sconosciuto');
    }
  }

  // applica una proposta confermata con «Applica»
  function applyAct(a) {
    const k = K();
    const P = k.plan;
    if (a.kind === 'swap') { P.setSwap(a.di, a.si, a.code); if (a.di === k.dayIdx(new Date())) P.logDay(); }
    else if (a.kind === 'eat') a.sis.forEach((si) => P.markEaten(si));
    else if (a.kind === 'load') { const all = k.store.get('loadNext', {}); all[a.ex] = { kg: a.kg, r: a.r, why: a.why || '', t: Date.now() }; k.store.set('loadNext', all); }
  }

  /* ---------------- chiamate all'AI ---------------- */
  function showLive() {
    const el = document.getElementById('coLive');
    if (!el) return;
    el.innerHTML = (ui.live ? fmt(ui.live) : '') + (ui.status || !ui.live ? `<p class="co-status">${K().esc(ui.status || 'Sto leggendo i tuoi dati…')}</p>` : '');
    el.parentElement.classList.toggle('wait', !ui.live);
  }
  // Cronologia per l'AI: solo il testo degli ultimi scambi (le risposte calcolate dall'app restano fuori).
  // Il ragionamento di Claude delle domande precedenti non viene rimandato: i dati in <dati_app> cambiano da una domanda all'altra.
  function turns() {
    let m = getChat().filter((x) => x.src !== 'dati').map((x) => ({
      role: x.role === 'user' ? 'user' : 'assistant',
      content: x.role === 'user' ? (x.img ? '[foto allegata] ' : '') + (x.send || x.text)
        : x.text + (x.acts && x.acts.some((a) => a.kind === 'swap' || a.kind === 'eat' || a.kind === 'load')
          ? `\n[Proposte: ${x.acts.filter((a) => a.sub && a.kind !== 'mem' && a.kind !== 'forget').map((a) => `${a.title}, ${a.sub} (${a.st === 'ok' ? 'applicata' : a.st === 'no' ? 'scartata' : 'in attesa'})`).join('; ')}]` : ''),
    }));
    m = m.slice(-7); // ultima domanda + i tre scambi precedenti
    while (m.length && m[0].role !== 'user') m.shift();
    return m;
  }
  function costOf(model, u) {
    const p = CLAUDE.price[model] || CLAUDE.price['claude-opus-5-5'];
    return ((u.input_tokens || 0) * p[0] + (u.output_tokens || 0) * p[1] + (u.cache_creation_input_tokens || 0) * p[2] + (u.cache_read_input_tokens || 0) * p[3]) / 1e6;
  }

  let sdk = null;
  // Claude con gli strumenti: ripete finché Claude chiede strumenti (al massimo 8 giri), poi restituisce
  // il testo, le proposte e il costo stimato. Sistema, dati e strumenti restano identici per tutta la domanda.
  async function askClaude(content, effort) {
    let Anthropic;
    try { Anthropic = sdk || (sdk = (await import(SDK_URL)).default); } catch (e) { throw Object.assign(new Error('Non riesco a caricare il componente di Claude: controlla la connessione e riprova.'), { fallback: true }); }
    const client = new Anthropic({ apiKey: getKeys().claude, dangerouslyAllowBrowser: true }); // la chiave è dell'utente e resta sul suo dispositivo
    const model = claudeModel();
    const system = [
      { type: 'text', text: SYSTEM + CLAUDE_NOTE },
      { type: 'text', text: `<dati_app>\n${context()}\n</dati_app>`, cache_control: { type: 'ephemeral' } },
    ];
    const messages = turns();
    if (messages.length && messages[messages.length - 1].role === 'user') messages.pop();
    messages.push({ role: 'user', content });
    const acts = [];
    let text = '', cost = 0, retries = 0, done = false;
    const fail = (msg, fallback) => Object.assign(new Error(msg), { fallback: !!fallback });
    try {
      for (let round = 0; round < 8 && !done; round++) {
        if (ui.live.trim() && !/\n\n$/.test(ui.live)) ui.live += '\n\n';
        const mark = ui.live.length;
        const stream = client.beta.messages.stream({
          model,
          max_tokens: 16000,
          betas: ['server-side-fallback-2026-07-01'],
          fallbacks: 'default', // se il modello declina la richiesta, l'API la ripete da sola sul modello di riserva
          thinking: { type: 'adaptive' },
          output_config: { effort },
          cache_control: { type: 'ephemeral' }, // in cache anche la conversazione, utile tra un giro di strumenti e l'altro
          system,
          tools: TOOLS,
          messages,
        });
        stream.on('text', (delta) => { ui.live += delta; ui.status = ''; showLive(); });
        let msg;
        try {
          msg = await stream.finalMessage();
          retries = 0;
        } catch (e) {
          // l'input di uno strumento non si legge (JSON spezzato): ripeto il giro al massimo 2 volte
          if (e instanceof Anthropic.APIError || retries++ >= 2) throw e;
          ui.live = ui.live.slice(0, mark);
          round--;
          continue;
        }
        cost += costOf(model, msg.usage || {});
        if (msg.stop_reason === 'refusal') { text = 'Claude non ha potuto rispondere a questa domanda. Prova a riformularla.'; acts.length = 0; break; }
        const said = msg.content.filter((b) => b.type === 'text').map((b) => b.text).join('').trim();
        if (said) text += (text ? '\n\n' : '') + said;
        const uses = msg.content.filter((b) => b.type === 'tool_use');
        if (msg.stop_reason === 'pause_turn') { messages.push({ role: 'assistant', content: msg.content }); continue; }
        if (!uses.length) {
          if (msg.stop_reason === 'max_tokens') text += '\n\n(risposta interrotta: era troppo lunga)';
          done = true;
          break;
        }
        if (msg.stop_reason === 'max_tokens') throw fail('La risposta di Claude si è interrotta a metà: riprova.');
        messages.push({ role: 'assistant', content: msg.content });
        ui.status = STATUS[uses[0].name] || 'Controllo i dati…';
        showLive();
        messages.push({ role: 'user', content: uses.map((u) => {
          const r = runTool(u.name, u.input, acts);
          return r.err ? { type: 'tool_result', tool_use_id: u.id, is_error: true, content: r.out } : { type: 'tool_result', tool_use_id: u.id, content: r.out };
        }) });
      }
    } catch (e) {
      if (cost) addSpend(cost);
      if (e.fallback !== undefined) throw e;
      if (e instanceof Anthropic.AuthenticationError) throw fail('La chiave di Claude non è valida: controllala in fondo alla pagina.');
      if (e instanceof Anthropic.PermissionDeniedError) throw fail('Questa chiave non ha accesso al modello scelto.');
      if (e instanceof Anthropic.RateLimitError) throw fail('Troppe richieste a Claude in poco tempo: riprova tra un minuto.', true);
      if (e instanceof Anthropic.BadRequestError) {
        const credit = /credit/i.test(e.message || '');
        throw fail(credit ? 'Il credito di Claude è finito: ricaricalo su console.anthropic.com, alla voce Billing.' : `Richiesta rifiutata da Anthropic: ${e.message}`, credit);
      }
      if (e instanceof Anthropic.APIConnectionError) throw fail('Connessione non riuscita: controlla la rete e riprova.', true);
      if (e instanceof Anthropic.APIError) throw fail(`Claude non è disponibile in questo momento (errore ${e.status || 'sconosciuto'}): riprova tra poco.`, true);
      throw e;
    }
    addSpend(cost);
    if (!done && !text) text = 'Claude non è arrivato a una risposta: riprova con una domanda più precisa.';
    return { text: text.trim() || (acts.length ? 'Fatto: trovi tutto qui sotto.' : 'Claude non ha dato una risposta: riprova.'), acts, cost };
  }

  // legge una risposta «a flusso» (una riga "data: {...}" per ogni pezzo) e passa ogni pezzo a onData
  async function readStream(res, onData) {
    const reader = res.body.getReader();
    const dec = new TextDecoder();
    let buf = '';
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i).trim();
        buf = buf.slice(i + 1);
        if (!line.startsWith('data:')) continue;
        const d = line.slice(5).trim();
        if (!d || d === '[DONE]') continue;
        try { onData(JSON.parse(d)); } catch (e) { /* riga incompleta: ignoro */ }
      }
    }
  }
  // richiesta con tempo massimo e messaggi d'errore comprensibili
  async function post(url, headers, body, name) {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 90000);
    let res;
    try {
      res = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body), signal: ctl.signal });
    } catch (e) {
      clearTimeout(timer);
      throw new Error(e.name === 'AbortError' ? `${name} non ha risposto in tempo: riprova.` : 'Connessione non riuscita: controlla la rete e riprova.');
    }
    if (!res.ok) {
      clearTimeout(timer);
      let msg = '';
      try { const j = await res.json(); msg = (j.error && (j.error.message || j.error.status)) || ''; } catch (e) { /* risposta senza dettagli */ }
      const detail = ` (${res.status}${msg ? ': ' + msg.slice(0, 140) : ''})`;
      const fail = (text, retry) => Object.assign(new Error(text), { status: res.status, retry: !!retry });
      if (res.status === 401 || res.status === 403 || /api key/i.test(msg)) throw fail(`La chiave di ${name} non è valida: controllala in fondo alla pagina.`);
      if (res.status === 429) throw fail(`Hai raggiunto il limite gratuito di ${name}: riprova tra un minuto (o domani, se è il limite giornaliero).${detail}`, true);
      if (res.status === 413) throw fail(`La richiesta è troppo grande per il piano gratuito di ${name}.`);
      if (res.status >= 500) throw fail(`${name} è sovraccarico in questo momento: riprova tra poco.${detail}`, true);
      throw fail(`Richiesta rifiutata da ${name}${detail}`);
    }
    return { res, done: () => clearTimeout(timer) };
  }
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  // Riserva gratuita: se il servizio è sovraccarico o ha finito le richieste al minuto riprovo una volta dopo una pausa,
  // poi passo agli altri modelli gratuiti. Mi fermo appena una risposta ha iniziato ad arrivare.
  async function askFree(pid) {
    const P = FREE[pid];
    const models = Object.keys(P.models);
    const order = [models[0]].concat(models);
    const key = getKeys()[pid];
    const sys = `${SYSTEM}\n\n<dati_app>\n${context(P.short)}\n</dati_app>`;
    let last = null;
    for (let i = 0; i < order.length; i++) {
      const label = P.models[order[i]];
      if (i) { ui.status = i === 1 ? `${label} è occupato: riprovo tra un attimo…` : `Provo con ${label}…`; showLive(); await sleep(i === 1 ? 2500 : 900); }
      try {
        const text = await (pid === 'gemini' ? geminiOnce : groqOnce)(order[i], key, sys);
        ui.free = i ? label : P.name;
        return text;
      } catch (e) {
        if (!e.retry || ui.live) throw e;
        last = e;
      }
    }
    throw last;
  }
  async function geminiOnce(model, key, sys) {
    const { res, done } = await post(`https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse`, { 'x-goog-api-key': key }, {
      system_instruction: { parts: [{ text: sys }] },
      contents: turns().map((m) => ({ role: m.role === 'user' ? 'user' : 'model', parts: [{ text: m.content }] })),
    }, 'Gemini');
    let blocked = '', finish = '';
    await readStream(res, (j) => {
      if (j.promptFeedback && j.promptFeedback.blockReason) blocked = j.promptFeedback.blockReason;
      const cand = j.candidates && j.candidates[0];
      if (!cand) return;
      if (cand.finishReason) finish = cand.finishReason;
      ((cand.content && cand.content.parts) || []).forEach((p) => { if (p.text && !p.thought) { ui.live += p.text; ui.status = ''; showLive(); } });
    });
    done();
    if (!ui.live.trim()) return blocked || finish === 'SAFETY' ? 'Gemini non ha potuto rispondere a questa domanda. Prova a riformularla.' : 'Gemini non ha dato una risposta: riprova.';
    return ui.live.trim() + (finish === 'MAX_TOKENS' ? '\n\n(risposta interrotta: era troppo lunga)' : '');
  }
  async function groqOnce(model, key, sys) {
    const { res, done } = await post('https://api.groq.com/openai/v1/chat/completions', { Authorization: `Bearer ${key}` }, {
      model, stream: true,
      messages: [{ role: 'system', content: sys }].concat(turns()),
    }, 'Groq');
    let finish = '';
    await readStream(res, (j) => {
      const ch = j.choices && j.choices[0];
      if (!ch) return;
      if (ch.finish_reason) finish = ch.finish_reason;
      if (ch.delta && ch.delta.content) { ui.live += ch.delta.content; ui.status = ''; showLive(); }
    });
    done();
    if (!ui.live.trim()) return 'Groq non ha dato una risposta: riprova.';
    return ui.live.trim() + (finish === 'length' ? '\n\n(risposta interrotta: era troppo lunga)' : '');
  }

  // Claude se collegato; se non risponde (sovraccarico, credito finito, rete) e c'è una riserva gratuita, risponde quella
  async function ask(text, photo, effort) {
    const fp = freeProv();
    if (hasClaude()) {
      try {
        const content = photo ? [{ type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: photo.data } }, { type: 'text', text }] : text;
        const r = await askClaude(content, effort);
        return { ...r, by: short(CLAUDE.models[claudeModel()]) };
      } catch (e) {
        if (!e.fallback || !fp || photo || ui.live) throw e;
        ui.status = `${e.message} Rispondo con ${FREE[fp].name}…`;
        showLive();
      }
    }
    ui.free = '';
    const t = await askFree(fp);
    return { text: t, acts: [], by: `${ui.free || FREE[fp].name}${hasClaude() ? ' (riserva)' : ''}` };
  }

  async function send(text, preset, extra) {
    const k = K();
    const q = (text || '').trim() || (ui.photo && hasClaude() ? PHOTO_Q : '');
    if (!q || ui.busy) return;
    const photo = hasClaude() ? ui.photo : null;
    const chat = getChat();
    const msg = { role: 'user', text: q, t: Date.now() };
    if (extra) msg.send = extra.prompt;
    if (photo) msg.img = 1;
    chat.push(msg);
    ui.err = ''; ui.draft = ''; ui.all = false;
    if (!hasClaude() && !freeProv()) {
      // senza AI collegata: alle domande pronte rispondo con i calcoli sui dati, alle altre spiego come collegarla
      chat.push(preset ? { role: 'coach', src: 'dati', text: localAnswer(preset), t: Date.now() }
        : { role: 'coach', src: 'dati', text: 'Per le domande libere tocca «Chiedi a Claude gratis» qui sotto: si apre Claude con i tuoi dati e la domanda già copiati. Qui rispondo alle domande pronte, calcolate dai tuoi dati.', t: Date.now() });
      setChat(chat); k.render(); scrollChat();
      return;
    }
    setChat(chat);
    ui.busy = true; ui.live = ''; ui.status = '';
    k.render(); scrollChat();
    try {
      const r = await ask(msg.send || q, photo, extra ? 'high' : 'medium');
      const c = getChat();
      c.push({ role: 'coach', src: 'ai', by: r.by, text: r.text, acts: r.acts.length ? r.acts : undefined, cost: r.cost || undefined, t: Date.now() });
      setChat(c);
      ui.photo = null;
      if (extra) k.store.set('coachCheckin', k.dkey(new Date()));
    } catch (e) {
      ui.err = e.message || 'Qualcosa non ha funzionato: riprova.';
      const c = getChat(); if (c.length && c[c.length - 1].role === 'user') { const u = c.pop(); ui.draft = u.send ? '' : u.text; setChat(c); } // la domanda torna nel campo
    }
    ui.busy = false; ui.live = ''; ui.status = '';
    if (location.hash.indexOf('coach') >= 0) { k.render(); scrollChat(); }
  }
  const scrollChat = () => requestAnimationFrame(() => { const q = document.querySelectorAll('.co-msg.me'); const el = q[q.length - 1] || document.getElementById('coForm'); if (el) el.scrollIntoView({ block: 'start', behavior: 'smooth' }); });

  // foto del piatto o dell'etichetta: ridotta a 1280 px e JPEG prima di partire (meno dati, risposta più veloce)
  function readPhoto(file) {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => {
        const s = Math.min(1, 1280 / Math.max(img.naturalWidth, img.naturalHeight));
        const cv = document.createElement('canvas');
        cv.width = Math.round(img.naturalWidth * s); cv.height = Math.round(img.naturalHeight * s);
        cv.getContext('2d').drawImage(img, 0, 0, cv.width, cv.height);
        URL.revokeObjectURL(url);
        const du = cv.toDataURL('image/jpeg', 0.82);
        resolve({ url: du, data: du.slice(du.indexOf(',') + 1) });
      };
      img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('Non riesco a leggere questa foto: prova con un’altra.')); };
      img.src = url;
    });
  }

  // testo -> HTML minimo: paragrafi, elenchi puntati e **grassetto**
  function fmt(t) {
    const e = K().esc(t).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    const out = [];
    let ul = [];
    const flush = () => { if (ul.length) { out.push(`<ul>${ul.map((x) => `<li>${x}</li>`).join('')}</ul>`); ul = []; } };
    e.split('\n').forEach((line) => {
      const m = line.match(/^\s*(?:[-•*]|\d+[.)])\s+(.*)$/);
      if (m) { ul.push(m[1]); return; }
      flush();
      const h = line.match(/^\s*#+\s*(.*)$/);
      if (h) out.push(`<p><strong>${h[1]}</strong></p>`); else if (line.trim()) out.push(`<p>${line}</p>`);
    });
    flush();
    return out.join('');
  }

  /* ---------------- pagina ---------------- */
  function actHtml(a, mi, ai) {
    const esc = K().esc;
    const ref = `data-mi="${mi}" data-ai="${ai}"`;
    let foot = '';
    if (a.kind === 'mem') foot = a.st === 'no' ? '<span class="tiny muted">Annullato</span>' : `<button type="button" class="co-link" data-c="act-undo" ${ref}>Annulla</button>`;
    else if (a.kind !== 'forget') {
      foot = a.st === 'ok' ? '<span class="badge sync-ok">Applicata</span>' : a.st === 'no' ? '<span class="badge">Scartata</span>'
        : `<button type="button" class="btn" data-c="act-ok" ${ref}>Applica</button><button type="button" class="chip" data-c="act-no" ${ref}>No, grazie</button>`;
    }
    return `<div class="co-act${a.st ? ` is-${a.st}` : ''}${a.kind === 'mem' || a.kind === 'forget' ? ' is-note' : ''}">
      <p class="co-act-t">${esc(a.title)}</p>${a.sub ? `<p class="co-act-s">${esc(a.sub)}</p>` : ''}${a.why ? `<p class="tiny muted">${esc(a.why)}</p>` : ''}
      ${foot ? `<div class="row">${foot}</div>` : ''}</div>`;
  }

  C.view = function () {
    const k = K();
    const keys = getKeys();
    const cl = !!keys.claude;
    const fp = freeProv();
    const ai = cl || !!fp;
    const chat = getChat();
    const f = facts();
    const bubble = (m, i) => (m.role === 'user'
      ? `<div class="co-msg me">${m.img ? `<span class="co-tag">${k.I.camera} Foto</span>` : ''}<p>${k.esc(m.text)}</p></div>`
      : `<div class="co-msg co">${fmt(m.text)}${m.acts ? `<div class="co-acts">${m.acts.map((a, j) => actHtml(a, i, j)).join('')}</div>` : ''}<span class="co-src">${m.src === 'ai' ? `${k.esc(m.by || 'Claude')}, dai tuoi dati${m.cost ? ` · ≈ ${usd(m.cost)}` : ''}` : 'calcolato dai tuoi dati'}</span></div>`);
    // in pagina resta solo l'ultimo scambio (domanda + risposta); i precedenti si aprono a richiesta
    const lastQ = chat.map((m) => m.role).lastIndexOf('user');
    const from = ui.all || lastQ < 0 ? 0 : lastQ;
    const older = from;
    const shownMin = lastQ < 0 ? chat.length : chat.length - lastQ;
    const lastCheck = k.store.get('coachCheckin', '');
    const due = !lastCheck || (k.fromKey(k.dkey(new Date())) - k.fromKey(lastCheck)) / DAY >= 6;
    const notes = mem();
    const spent = k.store.get('aiSpend', {})[monthKey()] || 0;
    const modelSel = `<div class="field"><label for="coModel">Modello</label><select id="coModel" class="search" data-c="model">${Object.entries(CLAUDE.models).map(([id, l]) => `<option value="${id}"${id === claudeModel() ? ' selected' : ''}>${l}</option>`).join('')}</select></div>`;
    const copyRow = '<div class="row"><button type="button" class="chip" data-c="copy">Copia i miei dati</button><span class="tiny muted" id="coCopied" role="status"></span></div>';
    const claudeCard = cl
      ? `<details class="card co-setup"><summary><span>Claude collegato</span><span class="badge sync-ok">Attivo</span></summary><div class="stack">
          ${modelSel}
          <p class="small">Speso questo mese: <strong>≈ ${usd(spent)}</strong> <span class="muted">(stima dell’app; il conto vero è su console.anthropic.com, alla voce Billing)</span></p>
          <p class="tiny muted">La chiave resta solo su questo dispositivo (niente sincronizzazione, niente backup). I dati dell’app e le foto partono verso Anthropic solo quando invii una domanda.</p>
          ${copyRow}
          <div class="row"><button type="button" class="chip" data-c="unlink" data-p="claude">Scollega Claude</button></div></div></details>`
      : `<section class="card stack"><h2>Claude</h2>
          <p class="small"><strong>Gratis, nella finestra di Claude.</strong> Scrivi la domanda qui sopra e tocca «Chiedi a Claude gratis»: copio i tuoi dati con la domanda e si apre Claude dentro l’app. La prima volta accedi con il tuo account Claude gratuito, poi tieni premuto nel campo del messaggio e scegli Incolla. La risposta resta lì: niente «Applica», foto o memoria qui.</p>
          <h3>Risposte qui dentro, a consumo</h3>
          <p class="small">Per avere le risposte in questa pagina, con le proposte da applicare, le foto e la memoria, serve una <strong>chiave API</strong> di Anthropic con un po’ di credito prepagato: è un servizio a consumo, separato dall’eventuale abbonamento a Claude, e non ha un piano gratuito. Una domanda costa circa 2–6 centesimi di dollaro con Opus 5.5, circa la metà con Sonnet 5.5. <a href="${CLAUDE.keyUrl}" target="_blank" rel="noopener">Crea la chiave su console.anthropic.com</a></p>
          <div class="field"><label for="coKey">Chiave di Claude</label><input id="coKey" type="password" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="${CLAUDE.keyHint}"></div>
          ${modelSel}
          <div class="row"><button type="button" class="btn" data-c="save-key" data-p="claude">Salva su questo dispositivo</button></div>
          <p class="tiny muted">La chiave resta solo su questo dispositivo: non viene sincronizzata né messa nel backup. Senza nessuna chiave puoi copiare il riepilogo dei tuoi dati e incollarlo nell’app di Claude.</p>
          ${copyRow}</section>`;
    const pick = FREE[ui.prov] ? ui.prov : 'gemini';
    const freeCard = fp
      ? `<details class="card co-setup"><summary><span>Riserva gratuita: ${k.esc(FREE[fp].name)}</span><span class="badge sync-ok">Gratis</span></summary><div class="stack">
          <p class="small">${cl ? `Risponde solo se Claude non è disponibile (sovraccarico, credito finito, rete). Fa solo domande: niente foto, proposte né memoria.` : 'Risponde alle domande finché non colleghi Claude. Foto, proposte e memoria funzionano solo con Claude.'}</p>
          <p class="tiny muted">${k.esc(FREE[fp].privacy)} La chiave resta solo su questo dispositivo.</p>
          <div class="row"><button type="button" class="chip" data-c="unlink" data-p="${fp}">Scollega ${k.esc(FREE[fp].name)}</button></div></div></details>`
      : `<details class="card co-setup"><summary><span>Riserva gratuita</span><span class="badge">Facoltativa</span></summary><div class="stack">
          <p class="small">Un servizio gratuito che risponde alle domande quando Claude non è disponibile (o finché non lo colleghi). Niente foto, proposte né memoria.</p>
          <div class="field"><label for="coProv">Servizio</label><select id="coProv" class="search" data-c="prov">${Object.entries(FREE).map(([id, x]) => `<option value="${id}"${id === pick ? ' selected' : ''}>${x.name}</option>`).join('')}</select></div>
          <p class="small">${k.esc(FREE[pick].how)} <a href="${FREE[pick].keyUrl}" target="_blank" rel="noopener">Apri la pagina delle chiavi</a></p>
          <div class="field"><label for="coFreeKey">Chiave di ${k.esc(FREE[pick].name)}</label><input id="coFreeKey" type="password" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="${FREE[pick].keyHint}"></div>
          <div class="row"><button type="button" class="btn ghost" data-c="save-key" data-p="${pick}">Salva su questo dispositivo</button></div>
          <p class="tiny muted">${k.esc(FREE[pick].privacy)}</p></div></details>`;
    const memCard = cl || notes.length
      ? `<details class="card co-setup"><summary><span>Cosa ricorda il coach</span><span class="badge">${notes.length}</span></summary><div class="stack">
          ${notes.length ? `<ul class="co-mem">${notes.map((m) => `<li><span>${k.esc(m.x)}</span><button type="button" class="x-btn" data-c="mem-del" data-id="${m.id}" aria-label="Cancella questa nota">${k.I.trash}</button></li>`).join('')}</ul>` : '<p class="small muted">Ancora niente. Scrivi per esempio «ricorda che la spalla sinistra mi dà fastidio alla panca».</p>'}
          <p class="tiny muted">Le note si sincronizzano tra telefono e PC e Claude le legge a ogni domanda.</p></div></details>`
      : '';
    const footTxt = cl ? `Risponde ${k.esc(short(CLAUDE.models[claudeModel()]))}${fp ? `, con ${k.esc(FREE[fp].name)} di riserva` : ''}.`
      : fp ? `Risponde ${k.esc(FREE[fp].name)} (solo domande: foto, proposte e memoria richiedono Claude).` : 'Senza un’AI collegata rispondo alle domande pronte con calcoli sui tuoi dati.';
    return `<div class="stack coach">
      <div><p class="eyebrow">Solo sui dati che hai registrato</p><h1>Coach</h1></div>
      <section class="card stack"><div class="row"><h2>Punto della situazione</h2></div>
        <ul class="co-facts">
          <li><b>Peso</b><span>${k.esc(tWeight(f))}</span></li>
          <li><b>Allenamento</b><span>${k.esc(tTrain(f))}</span></li>
          <li><b>Dieta</b><span>${k.esc(tDiet(f))}</span></li>
        </ul>
        ${ai ? `<div class="row co-check"><button type="button" class="btn${due ? '' : ' ghost'}" data-c="checkin"${ui.busy ? ' disabled' : ''}>Check-in della settimana</button><span class="tiny muted">${lastCheck ? `Ultimo: ${k.esc(k.shortDate(lastCheck))}` : 'Mai fatto: uno a settimana basta'}</span></div>` : ''}</section>
      <section class="card stack"><h2>Chiedi al coach</h2>
        <div class="co-presets" role="group" aria-label="Domande pronte">${PRESETS.map(([id, q]) => `<button type="button" class="chip" data-c="preset" data-id="${id}"${ui.busy ? ' disabled' : ''}>${q}</button>`).join('')}</div>
        ${chat.length || ui.busy ? `${older && !ui.busy ? `<button type="button" class="co-older" data-c="older">Mostra ${older === 1 ? 'il messaggio precedente' : `i ${older} messaggi precedenti`}</button>` : ''}
        <div class="co-chat" aria-live="polite">${chat.slice(from).map((m, j) => bubble(m, from + j)).join('')}${ui.busy ? `<div class="co-msg co${ui.live ? '' : ' wait'}"><div id="coLive">${ui.live ? fmt(ui.live) : ''}${ui.status || !ui.live ? `<p class="co-status">${k.esc(ui.status || 'Sto leggendo i tuoi dati…')}</p>` : ''}</div></div>` : ''}</div>` : ''}
        ${ui.err ? `<p class="err" role="alert">${k.esc(ui.err)}</p>` : ''}
        ${ui.photo && cl ? `<div class="co-photo"><img src="${ui.photo.url}" alt="Foto da inviare"><button type="button" class="x-btn" data-c="photo-x" aria-label="Togli la foto">✕</button><span class="tiny muted">Aggiungi una domanda o invia così.</span></div>` : ''}
        <form id="coForm" class="co-form${cl ? ' has-cam' : ''}" novalidate>
          ${cl ? `<label class="x-btn co-cam" for="coPhoto" aria-label="Allega la foto di un piatto o di un’etichetta">${k.I.camera}</label><input id="coPhoto" class="sr" type="file" accept="image/*" data-c="photo">` : ''}
          <label class="sr" for="coQ">La tua domanda</label>
          <textarea id="coQ" rows="2" placeholder="${cl ? 'Chiedi o allega una foto…' : 'Scrivi la tua domanda…'}">${k.esc(ui.draft)}</textarea>
          <button type="submit" class="btn"${ui.busy ? ' disabled' : ''}>Invia</button></form>
        ${cl ? '' : `<div class="row co-free"><button type="button" class="btn ghost" data-c="claude-free"${ui.busy ? ' disabled' : ''}>Chiedi a Claude gratis</button><span class="tiny muted" role="status">${k.esc(ui.copied || 'Si apre Claude con i tuoi dati già copiati.')}</span></div>`}
        <div class="co-foot"><span class="tiny muted">${footTxt}</span>
          ${chat.length && !ui.busy ? `${ui.all && chat.length > shownMin ? '<button type="button" class="co-link" data-c="older">Nascondi i precedenti</button>' : ''}<button type="button" class="co-link" data-c="clear">Nuova conversazione</button>` : ''}</div>
      </section>
      ${memCard}
      ${claudeCard}
      ${freeCard}
    </div>`;
  };

  C.click = function (t) {
    const k = K();
    const c = t.dataset.c;
    if (c === 'preset') { const p = PRESETS.find((x) => x[0] === t.dataset.id); send(p[1], p[0]); return true; }
    if (c === 'checkin') { send('Check-in della settimana', null, { prompt: CHECKIN }); return true; }
    if (c === 'clear') { setChat([]); ui.err = ''; ui.all = false; k.render(); return true; }
    if (c === 'older') { ui.all = !ui.all; k.render(); return true; }
    if (c === 'photo-x') { ui.photo = null; k.render(); return true; }
    if (c === 'act-ok' || c === 'act-no' || c === 'act-undo') {
      const chat = getChat();
      const m = chat[Number(t.dataset.mi)];
      const a = m && m.acts && m.acts[Number(t.dataset.ai)];
      if (!a || a.st) return true;
      if (c === 'act-ok') { applyAct(a); a.st = 'ok'; k.buzz('MEDIUM'); }
      else if (c === 'act-undo') { forget(a.id); a.st = 'no'; k.buzz(); }
      else a.st = 'no';
      setChat(chat); k.render(); return true;
    }
    if (c === 'mem-del') { forget(t.dataset.id); k.buzz(); k.render(); return true; }
    if (c === 'save-key') {
      const pid = t.dataset.p;
      const el = document.getElementById(pid === 'claude' ? 'coKey' : 'coFreeKey');
      const v = (el && el.value || '').trim();
      if (!v) { if (el) el.focus(); return true; }
      setKey(pid, v);
      if (pid === 'claude') { const ms = document.getElementById('coModel'); if (ms) k.store.set('aiModel', ms.value); }
      ui.err = ''; ui.prov = ''; k.buzz('MEDIUM'); k.render(); return true;
    }
    if (c === 'unlink') {
      const pid = t.dataset.p;
      const name = pid === 'claude' ? CLAUDE.name : FREE[pid].name;
      if (confirm(`Scollegare ${name} da questo dispositivo? La chiave salvata qui verrà cancellata.`)) { setKey(pid, ''); k.render(); }
      return true;
    }
    if (c === 'claude-free') {
      // Claude gratis: dati e domanda negli appunti, poi la pagina di Claude in una finestra dentro l'app
      const el = document.getElementById('coQ');
      const q = (el ? el.value : ui.draft || '').trim();
      const txt = `${SYSTEM}

<dati_app>
${context()}
</dati_app>

La mia domanda: ${q || '(scrivila qui)'}`;
      const done = (ok) => { ui.copied = ok ? 'Copiato: in Claude tieni premuto nel campo del messaggio e scegli Incolla.' : 'Copia non riuscita: usa «Copia i miei dati» qui sotto.'; k.render(); };
      const copying = navigator.clipboard && navigator.clipboard.writeText ? navigator.clipboard.writeText(txt) : Promise.reject();
      k.openWeb('https://claude.ai/new'); // subito, dentro il tocco: dopo un'attesa il browser bloccherebbe la nuova scheda
      copying.then(() => done(true), () => done(false));
      return true;
    }
    if (c === 'copy') {
      const txt = `${SYSTEM}\n\n<dati_app>\n${context()}\n</dati_app>\n\nLa mia domanda: `;
      const done = () => { const el = document.getElementById('coCopied'); if (el) el.textContent = 'Copiato: incollalo nell’app di AI.'; else alert('Copiato: incollalo nell’app di AI.'); };
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(txt).then(done, () => alert('Copia non riuscita.'));
      else { const ta = document.createElement('textarea'); ta.value = txt; document.body.appendChild(ta); ta.select(); try { document.execCommand('copy'); done(); } catch (e) { alert('Copia non riuscita.'); } ta.remove(); }
      return true;
    }
    return false;
  };
  C.change = function (t) {
    const c = t.dataset.c;
    if (c === 'prov') { ui.prov = t.value; K().render(); }
    else if (c === 'model') { if (hasClaude()) { K().store.set('aiModel', t.value); K().render(); } }
    else if (c === 'photo' && t.files && t.files[0]) {
      const file = t.files[0];
      t.value = '';
      readPhoto(file).then((p) => { ui.photo = p; ui.err = ''; }, (e) => { ui.err = e.message; }).then(() => K().render());
    }
  };
  C.draft = (v) => { ui.draft = v; };
  C.submit = function () { const el = document.getElementById('coQ'); send(el ? el.value : ui.draft, null); };
  // usato da altre pagine (per esempio l'analisi di un allenamento): prepara la domanda e apre il Coach
  C.ask = function (q) { ui.draft = q; ui.err = ''; };
})();
