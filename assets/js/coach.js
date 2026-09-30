'use strict';
// Coach: un riepilogo calcolato dai dati registrati nell'app e, se colleghi Claude con la tua chiave API,
// risposte a domande libere. Claude riceve solo i dati dell'app (peso, pasti spuntati, allenamenti) e ha
// l'istruzione di non inventare niente che non sia lì. Usa le utilità di app.js (window.RCK) e di
// allenamento.js (window.RCW.data).
(function () {
  const C = {};
  window.RCC = C;
  const K = () => window.RCK;
  const WD = () => window.RCW.data;

  // SDK ufficiale di Anthropic, caricato solo quando fai la prima domanda a Claude
  const SDK_URL = 'https://cdn.jsdelivr.net/npm/@anthropic-ai/sdk@0.129.0/+esm';
  const MODELS = { 'claude-opus-5-5': 'Claude Opus 5.5 · il più capace', 'claude-sonnet-5-5': 'Claude Sonnet 5.5 · circa metà prezzo' };
  const DAY = 86400000;
  const GIORNI = ['lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato', 'domenica'];
  const PRESETS = [
    ['progress', 'Sto progredendo bene?'],
    ['kcal', 'Devo cambiare le calorie?'],
    ['recomp', 'Come sta andando la ricomposizione?'],
    ['best', 'Quale esercizio sto migliorando di più?'],
    ['today', 'L’allenamento di oggi è stato sufficiente?'],
    ['stall', 'Il peso è fermo: cosa conviene fare?'],
  ];
  const ui = { busy: false, draft: '', err: '', live: '' };

  const getKey = () => K().store.get('aiKey', '');
  const getModel = () => { const m = K().store.get('aiModel', ''); return MODELS[m] ? m : 'claude-opus-5-5'; };
  const getChat = () => K().store.get('coachChat', []);
  const setChat = (c) => K().store.set('coachChat', c.slice(-30));

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

  /* ---------------- dati dell'app in forma di testo per Claude ---------------- */
  function context() {
    const k = K();
    const D = k.D;
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
      `Obiettivo: ricomposizione corporea (meno grasso su addome e fianchi, più muscolo su dorsali e deltoidi, carichi in salita). Traguardo indicativo ${k.GOAL.kg} kg entro ${k.GOAL.d}, poi mantenimento.`);
    L.push('', 'PIANO ALIMENTARE',
      `Giorni ON (allenamento: ${onDays}): ${T.ON.k} kcal, proteine ${T.ON.p} g, carboidrati ${T.ON.c} g, grassi ${T.ON.f} g.`,
      `Giorni OFF (riposo): ${T.OFF.k} kcal, proteine ${T.OFF.p} g, carboidrati ${T.OFF.c} g, grassi ${T.OFF.f} g.`,
      `Media pianificata: ${Math.round((nOn * T.ON.k + (7 - nOn) * T.OFF.k) / 7)} kcal al giorno. Consumo stimato: 2450 kcal nei giorni ON, 2100 nei giorni OFF, media 2300 (stima: passi e attività non sono registrati nell'app).`,
      'Ritmo atteso: da -0.2 a -0.5 kg a settimana. Pasto libero la domenica a pranzo, non conteggiato (stima 800-1000 kcal).',
      'Regole di correzione del piano: calo oltre 0.6 kg a settimana per 2 settimane -> +150 kcal; peso e girovita fermi per 2 settimane -> -100/150 kcal oppure +2000 passi; carichi in calo per 2 settimane -> +100 kcal nei giorni ON e più sonno. Nelle prime 2-3 settimane di creatina 0.5-1 kg in più è acqua.');
    const bw = k.blockWeek();
    L.push('', 'SCHEDA', `Torso/Limbs 4 volte a settimana, blocco di 7 settimane: ora settimana ${bw.n} (${bw.phase}). Progressione: quando tutte le serie arrivano al massimo del range si aumenta il carico.`);
    WD().routines().forEach((r) => L.push(`${r.name}${r.day ? ` (${r.day})` : ''}: ${r.items.map((it) => `${WD().exOf(it.ex).n} ${it.s}x${it.lo}-${it.hi}`).join('; ')}`));

    L.push('', `PESO (${f.ws.length} pesate registrate; data, kg, girovita in cm se misurato)`);
    if (!f.ws.length) L.push('Nessuna pesata registrata.');
    f.ws.slice(-60).forEach((w) => L.push(`${w.d} ${w.kg}${w.w != null ? ` vita ${w.w}` : ''}`));
    if (f.wk.length) L.push('Medie settimanali (lunedì della settimana, numero di pesate, media kg): ' + f.wk.slice(-10).map((w) => `${w.wk} n=${w.n} ${w.kg.toFixed(2)}`).join('; '));

    const dlog = k.store.get('dlog', {});
    const dkeys = Object.keys(dlog).sort().slice(-28);
    L.push('', 'DIETA - diario dei pasti spuntati (ultimi 28 giorni). Un giorno assente significa che non è stato spuntato niente nell\'app, non che non ha mangiato.');
    if (!dkeys.length) L.push('Nessun pasto spuntato finora.');
    dkeys.forEach((d) => { const x = dlog[d]; L.push(`${d} ${x.on ? 'ON' : 'OFF'}${x.free ? ' (con pasto libero non conteggiato)' : ''}: pasti ${x.n}/${x.of}, kcal ${x.k}/${x.tk}, P ${x.p} C ${x.c} G ${x.f}`); });

    const crea = k.store.get('creatina', {});
    const cDays = Object.keys(crea).filter((d) => crea[d].on).sort();
    L.push('', 'CREATINA', cDays.length ? `Prima spunta ${cDays[0]}; presa ${f.creaDays} giorni negli ultimi ${f.span}.` : 'Nessuna spunta registrata.');

    const hist = f.hist.filter((w) => w.start >= now.getTime() - 56 * DAY).slice().reverse();
    L.push('', `ALLENAMENTI registrati nelle ultime 8 settimane: ${hist.length} (serie: kg x ripetizioni; R = riscaldamento)`);
    if (!hist.length) L.push('Nessun allenamento registrato.');
    hist.forEach((w) => {
      const vol = w.items.reduce((a, it) => a + it.sets.filter((s) => s.type !== 'w').reduce((b, s) => b + (s.kg > 0 && s.r > 0 ? s.kg * s.r : 0), 0), 0);
      L.push(`${dk(w.start)} ${w.name} (${Math.round((w.end - w.start) / 60000)} min, volume ${Math.round(vol)} kg): ` + w.items.map((it) => {
        const e = WD().exOf(it.ex);
        return `${e.n}: ${it.sets.map((s) => (e.unit === 'sec' ? `${s.r}s` : `${s.kg ?? '?'}x${s.r ?? '?'}`) + (s.type === 'w' ? 'R' : '')).join(', ')}${it.note ? ` [nota: ${it.note}]` : ''}`;
      }).join(' | '));
    });
    const sk = Object.keys(WD().skipped()).sort();
    L.push(`Allenamenti segnati come saltati: ${sk.length ? sk.join(', ') : 'nessuno'}.`);
    L.push(`Ultimi ${f.win} giorni: previsti ${f.expected}, registrati ${f.done}.`);
    if (f.prog.length) L.push('Variazione della forza stimata per esercizio (prima e ultima seduta nelle 8 settimane): ' + f.prog.map((x) => `${x.n} ${x.pct >= 0 ? '+' : ''}${x.pct.toFixed(1)}% (${x.sessions} sedute)`).join('; '));
    return L.join('\n');
  }

  const SYSTEM = `Sei il coach dentro "Recomp", l'app personale di un ragazzo di 18 anni che fa ricomposizione corporea. Rispondi in italiano, dandogli del tu, in modo diretto e pratico.

Regole:
- Basati solo sui dati dell'app riportati sotto tra i tag <dati_app>. Non inventare pesate, allenamenti, calorie o tendenze che non sono lì.
- Se i dati non bastano per rispondere (poche pesate, nessun allenamento registrato, pasti non spuntati), dillo chiaramente e spiega cosa deve registrare e per quanto tempo prima di poter concludere qualcosa.
- Quando dai un giudizio, cita i numeri su cui lo basi (date, kg, ripetizioni, kcal).
- Per le calorie segui le regole di correzione del piano riportate nei dati; non proporre cambi più grandi senza un motivo che emerge dai dati.
- Non sei un medico: per dolori, infortuni o problemi di salute suggerisci di sentire un professionista.
- Rispondi in breve: lo leggerà sul telefono. Frasi corte o un elenco puntato di pochi punti, niente tabelle. Se serve, chiudi con 1-3 cose concrete da fare.`;

  /* ---------------- chiamata a Claude ---------------- */
  let sdk = null;
  async function askClaude(question) {
    let Anthropic;
    try { Anthropic = sdk || (sdk = (await import(SDK_URL)).default); } catch (e) { throw new Error('Non riesco a caricare il componente di Claude: controlla la connessione e riprova.'); }
    const client = new Anthropic({ apiKey: getKey(), dangerouslyAllowBrowser: true }); // la chiave è dell'utente e resta sul suo dispositivo
    // cronologia: solo il testo dei turni precedenti; i dati dell'app viaggiano nel prompt di sistema (in cache tra una domanda e l'altra)
    const messages = getChat().filter((m) => m.src !== 'dati').map((m) => ({ role: m.role === 'user' ? 'user' : 'assistant', content: m.text }));
    if (!messages.length || messages[messages.length - 1].role !== 'user') messages.push({ role: 'user', content: question });
    try {
      const stream = client.beta.messages.stream({
        model: getModel(),
        max_tokens: 16000,
        betas: ['server-side-fallback-2026-07-01'],
        fallbacks: 'default', // se il modello declina la richiesta, l'API la ripete da sola sul modello di riserva
        thinking: { type: 'adaptive' },
        output_config: { effort: 'medium' },
        system: [
          { type: 'text', text: SYSTEM },
          { type: 'text', text: `<dati_app>\n${context()}\n</dati_app>`, cache_control: { type: 'ephemeral' } },
        ],
        messages,
      });
      stream.on('text', (delta) => {
        ui.live += delta;
        const el = document.getElementById('coLive');
        if (el) { el.innerHTML = fmt(ui.live); el.parentElement.classList.remove('wait'); }
      });
      const msg = await stream.finalMessage();
      if (msg.stop_reason === 'refusal') return 'Claude non ha potuto rispondere a questa domanda. Prova a riformularla.';
      const text = msg.content.filter((b) => b.type === 'text').map((b) => b.text).join('\n').trim();
      return text + (msg.stop_reason === 'max_tokens' ? '\n\n(risposta interrotta: era troppo lunga)' : '');
    } catch (e) {
      if (e instanceof Anthropic.AuthenticationError) throw new Error('La chiave API non è valida: controllala in fondo alla pagina.');
      if (e instanceof Anthropic.PermissionDeniedError) throw new Error('Questa chiave non ha accesso al modello scelto.');
      if (e instanceof Anthropic.RateLimitError) throw new Error('Troppe richieste in poco tempo: riprova tra un minuto.');
      if (e instanceof Anthropic.BadRequestError) throw new Error(`Richiesta rifiutata da Anthropic: ${e.message}`);
      if (e instanceof Anthropic.APIConnectionError) throw new Error('Connessione non riuscita: controlla la rete e riprova.');
      if (e instanceof Anthropic.APIError) throw new Error(`Errore del servizio (${e.status || 'sconosciuto'}): riprova tra poco.`);
      throw e;
    }
  }

  async function send(text, preset) {
    const k = K();
    const q = (text || '').trim();
    if (!q || ui.busy) return;
    const chat = getChat();
    chat.push({ role: 'user', text: q, t: Date.now() });
    ui.err = ''; ui.draft = '';
    if (!getKey()) {
      // senza Claude: alle domande pronte rispondo con i calcoli sui dati, alle altre spiego come collegarlo
      chat.push(preset ? { role: 'coach', src: 'dati', text: localAnswer(preset), t: Date.now() }
        : { role: 'coach', src: 'dati', text: 'Alle domande libere risponde Claude: collegalo in fondo alla pagina. Senza, posso rispondere alle domande pronte qui sopra, calcolate dai tuoi dati.', t: Date.now() });
      setChat(chat); k.render(); scrollChat();
      return;
    }
    setChat(chat);
    ui.busy = true; ui.live = '';
    k.render(); scrollChat();
    try {
      const answer = await askClaude(q);
      const c = getChat(); c.push({ role: 'coach', src: 'ai', text: answer, t: Date.now() }); setChat(c);
    } catch (e) {
      ui.err = e.message || 'Qualcosa non ha funzionato: riprova.';
      const c = getChat(); if (c.length && c[c.length - 1].role === 'user') { ui.draft = c.pop().text; setChat(c); } // la domanda torna nel campo
    }
    ui.busy = false; ui.live = '';
    if (location.hash.indexOf('coach') >= 0) { k.render(); scrollChat(); }
  }
  const scrollChat = () => requestAnimationFrame(() => { const el = document.getElementById('coForm'); if (el) el.scrollIntoView({ block: 'end', behavior: 'smooth' }); });

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
  C.view = function () {
    const k = K();
    const key = getKey();
    const chat = getChat();
    const f = facts();
    const bubble = (m) => `<div class="co-msg ${m.role === 'user' ? 'me' : 'co'}">${m.role === 'user' ? `<p>${k.esc(m.text)}</p>` : `${fmt(m.text)}<span class="co-src">${m.src === 'ai' ? 'Claude, dai tuoi dati' : 'calcolato dai tuoi dati'}</span>`}</div>`;
    const setup = key
      ? `<section class="card stack"><div class="row"><h2>Claude collegato</h2><span class="spacer"></span><span class="badge sync-ok">Attivo</span></div>
          <div class="field"><label for="coModel">Modello</label><select id="coModel" class="search" data-c="model">${Object.entries(MODELS).map(([id, l]) => `<option value="${id}"${id === getModel() ? ' selected' : ''}>${l}</option>`).join('')}</select></div>
          <p class="tiny muted">La chiave API resta solo su questo dispositivo (niente sincronizzazione, niente backup). I dati dell’app vengono inviati ad Anthropic solo quando premi Invia.</p>
          <div class="row"><button type="button" class="chip" data-c="copy">Copia i miei dati</button><button type="button" class="chip" data-c="unlink">Scollega Claude</button></div></section>`
      : `<section class="card stack"><h2>Collega Claude · facoltativo</h2>
          <p class="small">Per le domande libere il coach usa Claude tramite l’API di Anthropic. Serve una tua chiave API, che crei su <a href="https://console.anthropic.com/settings/keys" target="_blank" rel="noopener">console.anthropic.com</a>: è un servizio a consumo, separato dall’abbonamento a Claude. Costo indicativo: qualche centesimo di dollaro a domanda.</p>
          <div class="field"><label for="coKey">Chiave API</label><input id="coKey" type="password" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="sk-ant-…"></div>
          <div class="field"><label for="coModel">Modello</label><select id="coModel" class="search" data-c="model">${Object.entries(MODELS).map(([id, l]) => `<option value="${id}"${id === getModel() ? ' selected' : ''}>${l}</option>`).join('')}</select></div>
          <div class="row"><button type="button" class="btn" data-c="save-key">Salva su questo dispositivo</button></div>
          <p class="tiny muted">La chiave resta solo su questo dispositivo: non viene sincronizzata né messa nel backup. I dati dell’app vengono inviati ad Anthropic solo quando premi Invia.</p>
          <h3>Alternativa gratuita</h3>
          <p class="small">Copia il riepilogo dei tuoi dati e incollalo nell’app Claude, poi fai lì la tua domanda.</p>
          <div class="row"><button type="button" class="chip" data-c="copy">Copia i miei dati</button><span class="tiny muted" id="coCopied" role="status"></span></div></section>`;
    return `<div class="stack coach">
      <div><p class="eyebrow">Solo sui dati che hai registrato</p><h1>Coach</h1></div>
      <section class="card stack"><div class="row"><h2>Punto della situazione</h2></div>
        <ul class="co-facts">
          <li><b>Peso</b><span>${k.esc(tWeight(f))}</span></li>
          <li><b>Allenamento</b><span>${k.esc(tTrain(f))}</span></li>
          <li><b>Dieta</b><span>${k.esc(tDiet(f))}</span></li>
        </ul></section>
      <section class="card stack"><div class="row"><h2>Chiedi al coach</h2><span class="spacer"></span>${chat.length && !ui.busy ? '<button type="button" class="chip" data-c="clear">Nuova conversazione</button>' : ''}</div>
        <div class="pill-list">${PRESETS.map(([id, q]) => `<button type="button" class="chip" data-c="preset" data-id="${id}"${ui.busy ? ' disabled' : ''}>${q}</button>`).join('')}</div>
        ${chat.length || ui.busy ? `<div class="co-chat" aria-live="polite">${chat.map(bubble).join('')}${ui.busy ? `<div class="co-msg co${ui.live ? '' : ' wait'}"><div id="coLive">${ui.live ? fmt(ui.live) : '<p>Sto leggendo i tuoi dati…</p>'}</div></div>` : ''}</div>` : ''}
        ${ui.err ? `<p class="err" role="alert">${k.esc(ui.err)}</p>` : ''}
        <form id="coForm" class="co-form" novalidate><label class="sr" for="coQ">La tua domanda</label>
          <textarea id="coQ" rows="2" placeholder="${key ? 'Scrivi la tua domanda…' : 'Domande libere: serve Claude collegato (sotto)'}">${k.esc(ui.draft)}</textarea>
          <button type="submit" class="btn"${ui.busy ? ' disabled' : ''}>Invia</button></form>
        <p class="tiny muted">${key ? `Risponde ${MODELS[getModel()].split(' · ')[0]}, solo in base ai dati dell’app.` : 'Senza Claude collegato rispondo alle domande pronte con calcoli sui tuoi dati.'}</p>
      </section>
      ${setup}
    </div>`;
  };

  C.click = function (t) {
    const k = K();
    const c = t.dataset.c;
    if (c === 'preset') { const p = PRESETS.find((x) => x[0] === t.dataset.id); send(p[1], p[0]); return true; }
    if (c === 'clear') { setChat([]); ui.err = ''; k.render(); return true; }
    if (c === 'save-key') {
      const v = (document.getElementById('coKey').value || '').trim();
      if (!v) { document.getElementById('coKey').focus(); return true; }
      k.store.set('aiKey', v); k.store.set('aiModel', document.getElementById('coModel').value);
      ui.err = ''; k.buzz('MEDIUM'); k.render(); return true;
    }
    if (c === 'unlink') { if (confirm('Scollegare Claude da questo dispositivo? La chiave salvata qui verrà cancellata.')) { k.store.set('aiKey', ''); k.render(); } return true; }
    if (c === 'copy') {
      const txt = `${SYSTEM}\n\n<dati_app>\n${context()}\n</dati_app>\n\nLa mia domanda: `;
      const done = () => { const el = document.getElementById('coCopied'); if (el) el.textContent = 'Copiato: incollalo nell’app Claude.'; else alert('Copiato: incollalo nell’app Claude.'); };
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(txt).then(done, () => alert('Copia non riuscita.'));
      else { const ta = document.createElement('textarea'); ta.value = txt; document.body.appendChild(ta); ta.select(); try { document.execCommand('copy'); done(); } catch (e) { alert('Copia non riuscita.'); } ta.remove(); }
      return true;
    }
    return false;
  };
  C.change = function (t) { if (t.dataset.c === 'model' && getKey()) { K().store.set('aiModel', t.value); K().render(); } };
  C.draft = (v) => { ui.draft = v; };
  C.submit = function () { const el = document.getElementById('coQ'); send(el ? el.value : ui.draft, null); };
  // usato da altre pagine (per esempio l'analisi di un allenamento): prepara la domanda e apre il Coach
  C.ask = function (q) { ui.draft = q; ui.err = ''; };
})();
