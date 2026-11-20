/* Recomp sul web: solo da consultare (dieta e scheda), per guardare al volo da PC, tablet o telefono.
   Pasti, pesi e allenamenti si segnano nell'app iPhone. I dati vengono da data.js (tools/genera_piano.py). */
(function () {
  'use strict';

  var P = window.PIANO;
  var main = document.getElementById('main');
  var themeBtn = document.getElementById('themeBtn');

  /* ---------- numeri e testo ---------- */
  function r0(x) { return Math.floor(x + 0.5); }
  function r1(x) { return Math.floor(x * 10 + 0.5) / 10; }
  // 165,3 · 46 (virgola italiana, un decimale solo se serve)
  function fmt(x) { var v = r1(x); return (v % 1 === 0 ? v.toFixed(0) : v.toFixed(1)).replace('.', ','); }
  // 2015 → «2.015» (toLocaleString in italiano non separa i numeri a 4 cifre)
  function fmtInt(x) { return String(r0(x)).replace(/\B(?=(\d{3})+(?!\d))/g, '.'); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function corto(nome) { return String(nome).split(' (')[0]; }

  /* ---------- quello che resta salvato nel browser (solo comodità di consultazione) ---------- */
  function carica(k, base) { try { var v = localStorage.getItem('rc.web.' + k); return v ? JSON.parse(v) : base; } catch (e) { return base; } }
  function salva(k, v) { try { localStorage.setItem('rc.web.' + k, JSON.stringify(v)); } catch (e) {} }

  var LIBERO = 700; // pasto libero della domenica: stima già dentro le kcal del giorno (regola del nutrizionista)
  var oggi = (new Date().getDay() + 6) % 7; // 0 = lunedì … 6 = domenica
  var state = {
    route: 'dieta',
    tab: carica('tab', 'giorni'),          // giorni · ricette · scambi · spesa
    giorno: oggi,
    scambi: carica('scambi', {}),          // «giorno-fascia» → codice del piatto
    dosi: carica('dosi', {}),              // giorno → «ON» | «OFF_S» (vedere le dosi dell'altro tipo di giorno)
    spesa: carica('spesa', {}),            // cibo → già preso
    scheda: (P.week[oggi] && P.week[oggi].wo) || P.workouts[0].id
  };
  if (['giorni', 'ricette', 'scambi', 'spesa'].indexOf(state.tab) < 0) state.tab = 'giorni';

  /* ---------- aiuto pratico accanto ai grammi ---------- */
  var UNITA = {
    pane_bauletto: ['fetta', 'fette'], wrap: ['wrap', 'wrap'], crackers: ['pacchetto da 27 g', 'pacchetti da 27 g'],
    tacchino_fette: ['vaschetta da 100 g', 'vaschette da 100 g'], pollo_fette: ['vaschetta da 100 g', 'vaschette da 100 g'],
    cotto: ['vaschetta da 100 g', 'vaschette da 100 g'], bresaola: ['vaschetta da 100 g', 'vaschette da 100 g'],
    hamburger_pollo: ['hamburger da 100 g', 'hamburger da 100 g'], hamburger: ['hamburger da 100 g', 'hamburger da 100 g'],
    cordon_bleu: ['cordon bleu', 'cordon bleu'], tonno: ['scatoletta da 80 g', 'scatolette da 80 g'], sgombro: ['scatoletta', 'scatolette'],
    uova: ['uovo', 'uova'], fiocchi_latte: ['vasetto da 150 g', 'vasetti da 150 g'], mozz_light: ['busta da 125 g', 'buste da 125 g'],
    formaggio_light: ['vaschetta da 200 g', 'vaschette da 200 g'], biraghini: ['bastoncino', 'bastoncini'], budino: ['vasetto', 'vasetti'],
    latte: ['tazza', 'tazze'], banana: ['banana', 'banane'], kiwi: ['kiwi', 'kiwi'], mela: ['mela', 'mele'],
    frutti_bosco: ['vaschetta da 125 g', 'vaschette da 125 g'], passata: ['brick da 200 g', 'brick da 200 g']
  };
  var CUCCHIAI = {
    avena: [10, 'cucchiaio', 'cucchiai'], miele: [5, 'cucchiaino', 'cucchiaini'], parmigiano: [5, 'cucchiaino', 'cucchiaini'],
    burro_arachidi: [15, 'cucchiaio', 'cucchiai'], formaggio_light: [10, 'cucchiaino', 'cucchiaini']
  };
  function unita(fid) { return fid === 'latte' ? 'ml' : 'g'; }

  function aiuto(fid, g, perSpesa) {
    if (fid === 'olio') {
      if (perSpesa) return '';
      if (g < 4) return 'un filo';
      if (g % 10 === 0) return (g / 10) + (g === 10 ? ' cucchiaio' : ' cucchiai');
      var c = Math.round(g / 5);
      return c + (c === 1 ? ' cucchiaino' : ' cucchiaini');
    }
    if (fid === 'latte' && perSpesa) { var l = Math.max(1, Math.ceil(g / 1000)); return '≈ ' + l + (l === 1 ? ' litro' : ' litri'); }
    if (fid === 'yogurt') {
      if (!perSpesa) return 'dal barattolo da 500 g o 1 kg';
      var b = Math.max(1, Math.ceil(g / 500));
      return '≈ ' + b + (b === 1 ? ' barattolo da 500 g' : ' barattoli da 500 g');
    }
    if (!perSpesa && CUCCHIAI[fid]) {
      var cu = CUCCHIAI[fid], n = Math.max(1, Math.round(g / cu[0]));
      return (Math.abs(g / cu[0] - n) < 0.1 ? '' : '≈ ') + n + ' ' + (n === 1 ? cu[1] : cu[2]);
    }
    if (!perSpesa && fid === 'mandorle') return '≈ ' + Math.round(g / 1.2) + ' mandorle';
    var f = P.foods[fid];
    if (!f || !f.u || !UNITA[fid]) return '';
    var nomi = UNITA[fid], quante = g / f.u;
    if (perSpesa) { var t = Math.max(1, Math.ceil(quante - 0.1)); return '≈ ' + t + ' ' + (t === 1 ? nomi[0] : nomi[1]); }
    var h = Math.max(0.5, Math.round(quante * 2) / 2);
    var testo = h === 0.5 ? '½' : (h % 1 !== 0 ? Math.floor(h) + ' e ½' : String(h));
    return (Math.abs(quante - h) < 0.08 ? '' : '≈ ') + testo + ' ' + (h <= 1 ? nomi[0] : nomi[1]);
  }

  /* ---------- calcoli (stesso arrotondamento di genera_piano.py e dell'app) ---------- */
  function riga(fid, g) {
    var f = P.foods[fid] || { n: fid, k: 0, p: 0, c: 0, f: 0 };
    return { f: fid, n: f.n, g: g, k: r0(f.k * g / 100), p: r1(f.p * g / 100), c: r1(f.c * g / 100), fa: r1(f.f * g / 100) };
  }
  function righe(slot, code) { return ((P.variants[slot] || {})[code] || []).map(function (x) { return riga(x[0], x[1]); }); }
  function somma(ls) {
    var t = { k: 0, p: 0, c: 0, fa: 0 };
    ls.forEach(function (l) { t.k += l.k; t.p += l.p; t.c += l.c; t.fa += l.fa; });
    return { k: t.k, p: r1(t.p), c: r1(t.c), fa: r1(t.fa) };
  }
  function tipoDi(d) { return state.dosi[d] || P.week[d].type; }
  function giornoOn(tipo) { return tipo === 'ON'; }

  function pianoDi(d) {
    var day = P.week[d], tipo = tipoDi(d);
    var dt = P.daytypes[tipo] || P.daytypes[day.type];
    var pasti = dt.slots.map(function (s, si) {
      var m = { si: si, ora: s[0], nome: s[1], slot: s[2], libero: s[2] === 'free' };
      if (m.libero) { m.tot = { k: LIBERO, p: 0, c: 0, fa: 0 }; return m; }
      var vars = P.variants[m.slot] || {};
      var base = vars[day.pick[si]] ? day.pick[si] : Object.keys(vars)[0];
      var scelto = state.scambi[d + '-' + si];
      m.base = base;
      m.code = scelto && vars[scelto] ? scelto : base;
      m.ricetta = P.recipes[m.code] || { name: m.code, how: '' };
      m.righe = righe(m.slot, m.code);
      m.tot = somma(m.righe);
      return m;
    });
    var tot = somma(pasti.map(function (m) { return m.tot; }));
    return { day: day, tipo: tipo, dt: dt, pasti: pasti, tot: tot, libero: pasti.some(function (m) { return m.libero; }) };
  }

  /* ---------- pezzi di pagina ---------- */
  function seg(voci, attiva, attr, etichetta) {
    return '<div class="seg" role="tablist" aria-label="' + esc(etichetta) + '">' + voci.map(function (v) {
      return '<button type="button" role="tab" ' + attr + '="' + v[0] + '" aria-selected="' + (attiva === v[0]) + '">' + esc(v[1]) + '</button>';
    }).join('') + '</div>';
  }
  function barra(classe, valore, obiettivo) {
    return '<div class="bar ' + classe + '"><i style="width:' + Math.min(100, Math.round(valore / obiettivo * 100)) + '%"></i></div>';
  }
  function listaRighe(ls) {
    return '<ul class="items">' + ls.map(function (l) {
      var a = aiuto(l.f, l.g, false);
      return '<li class="it"><div class="it-n">' + esc(l.n) + (a ? '<small>' + esc(a) + '</small>' : '') + '</div>' +
        '<div class="it-g num">' + fmt(l.g) + ' ' + unita(l.f) + '</div><div class="it-k num" title="kcal">' + l.k + '</div></li>';   // colonna stretta: solo il numero, come nel sito di prima
    }).join('') + '</ul>';
  }
  function macro(t) {
    return '<div class="meal-tot"><div class="m"><span>P <b>' + fmt(t.p) + ' g</b></span><span>C <b>' + fmt(t.c) + ' g</b></span><span>G <b>' + fmt(t.fa) + ' g</b></span></div></div>';
  }

  /* ================= DIETA ================= */
  function renderDieta() {
    var corpo = state.tab === 'ricette' ? renderRicette() : state.tab === 'scambi' ? renderScambi() : state.tab === 'spesa' ? renderSpesa() : renderGiorni();
    return '<div class="stack">' + seg([['giorni', 'Giorni'], ['ricette', 'Ricette'], ['scambi', 'Scambi'], ['spesa', 'Spesa']], state.tab, 'data-tab', 'Sezioni della dieta') + corpo + '</div>';
  }

  function renderGiorni() {
    var pl = pianoDi(state.giorno), day = pl.day, dt = pl.dt, tot = pl.tot;
    var on = giornoOn(pl.tipo);
    var obiettivo = dt.target;
    var si_cambia = day.type === 'ON' || day.type === 'OFF_S';
    var wo = day.wo ? P.workouts.filter(function (w) { return w.id === day.wo; })[0] : null;
    var cambiato = Object.keys(state.scambi).some(function (k) { return k.indexOf(state.giorno + '-') === 0; }) || state.dosi[state.giorno];

    var giorni = '<div class="days" role="tablist" aria-label="Giorni della settimana">' + P.week.map(function (d, i) {
      var t = tipoDi(i);
      return '<button type="button" class="day' + (i === oggi ? ' today' : '') + '" role="tab" data-day="' + i + '" aria-selected="' + (i === state.giorno) + '">' +
        '<span>' + esc(d.name.slice(0, 3)) + '</span><small>' + (t === 'ON' ? 'ON' : t === 'FREE' ? 'LIB' : 'OFF') + '</small>' +
        '<i class="tp' + (t === 'ON' ? ' on' : '') + '"></i></button>';
    }).join('') + '</div>';

    var testa = '<section class="card hero">' +
      '<div class="eyebrow">' + esc(dt.label) + (state.giorno === oggi ? ' · oggi' : '') + '</div>' +
      '<h1>' + esc(day.name) + '</h1>' +
      '<div class="kcal-line"><span class="kcal-big num">' + fmtInt(tot.k) + '</span><span class="kcal-of">/ ' + fmtInt(obiettivo[0]) + ' kcal</span></div>' +
      barra('k', tot.k, obiettivo[0]) +
      (pl.libero ? '<p class="small muted" style="margin-top:8px">Compreso il pranzo libero, stimato ~' + LIBERO + ' kcal (senza pesare).</p>' : '') +
      '<div class="macros" style="margin-top:14px">' +
        '<div class="macro"><div class="lbl"><span><i class="dot p"></i> Proteine</span><span class="val">' + fmt(tot.p) + ' / ' + obiettivo[1] + ' g</span></div>' + barra('p', tot.p, obiettivo[1]) + '</div>' +
        '<div class="macro"><div class="lbl"><span><i class="dot c"></i> Carboidrati</span><span class="val">' + fmt(tot.c) + ' / ' + obiettivo[2] + ' g</span></div>' + barra('c', tot.c, obiettivo[2]) + '</div>' +
        '<div class="macro"><div class="lbl"><span><i class="dot g"></i> Grassi</span><span class="val">' + fmt(tot.fa) + ' / ' + obiettivo[3] + ' g</span></div>' + barra('g', tot.fa, obiettivo[3]) + '</div>' +
      '</div>' +
      (pl.libero ? '<p class="tiny muted" style="margin-top:8px">I macro non contano il pranzo libero.</p>' : '') +
      '<div class="row" style="margin-top:14px;flex-wrap:wrap">' +
        (wo && on ? '<a class="chip accent" href="#/scheda" data-vai-scheda="' + wo.id + '">Palestra 16:30 · ' + esc(wo.name) + '</a>' : '') +
        (si_cambia ? '<button type="button" class="chip" data-dosi="' + state.giorno + '">Dosi da giorno ' + (on ? 'OFF' : 'ON') + '</button>' : '') +
        (cambiato ? '<button type="button" class="chip" data-ripristina="' + state.giorno + '">Piano base</button>' : '') +
      '</div>' +
    '</section>';

    var pasti = '<ul class="timeline">' + pl.pasti.map(function (m) {
      if (m.libero) {
        return '<li class="tl"><div class="tl-time"><span>' + esc(m.ora) + '</span></div>' +
          '<article class="card meal free-card"><div class="meal-h"><div class="t"><div class="lbl">' + esc(m.nome) + '</div>' +
          '<h3>Pasto libero</h3></div><div class="meal-k"><b class="num">~' + LIBERO + '</b><span>kcal</span></div></div>' +
          '<p class="how">Un piatto normale a piacere (pizza, pranzo fuori o il piatto di famiglia) senza pesare: è già dentro le kcal del giorno.</p></article></li>';
      }
      var alt = Object.keys(P.variants[m.slot] || {});
      var scambi = alt.length < 2 ? '' :
        '<details class="alt-details"><summary>Altri piatti per questa fascia (' + (alt.length - 1) + ')</summary><div class="alt-list">' +
        alt.map(function (code) {
          var ls = righe(m.slot, code), t = somma(ls), d = t.k - m.tot.k;
          return '<button type="button" class="alt-item' + (code === m.code ? ' active' : '') + '" data-scambio="' + state.giorno + ':' + m.si + ':' + code + '">' +
            '<div><strong>' + esc((P.recipes[code] || { name: code }).name) + '</strong>' + (code === m.base ? ' <span class="tiny muted">(base)</span>' : '') +
            '<div class="tiny muted" style="margin-top:2px">' + esc(ls.map(function (x) { return corto(x.n) + ' ' + fmt(x.g) + ' ' + unita(x.f); }).join(' · ')) + '</div></div>' +
            '<div class="r num" style="white-space:nowrap"><b>' + t.k + ' kcal</b><div class="tiny muted">' +
            (code === m.code ? 'scelto' : (d === 0 ? 'uguale' : (d > 0 ? '+' : '−') + Math.abs(d))) + '</div></div></button>';
        }).join('') + '</div></details>';
      return '<li class="tl"><div class="tl-time"><span>' + esc(m.ora) + '</span></div>' +
        '<article class="card meal"><div class="meal-h"><div class="t"><div class="lbl">' + esc(m.nome) + '</div><h3>' + esc(m.ricetta.name) + '</h3></div>' +
        '<div class="meal-k"><b class="num">' + m.tot.k + '</b><span>kcal</span></div></div>' +
        listaRighe(m.righe) + macro(m.tot) + (m.ricetta.how ? '<p class="how">' + esc(m.ricetta.how) + '</p>' : '') + scambi +
        '</article></li>';
    }).join('') + '</ul>';

    return giorni + testa + pasti;
  }

  // tutte le ricette, fascia per fascia (nell'ordine della giornata); i due panini insieme se sono gli stessi
  function renderRicette() {
    // per ogni fascia: le ore e il nome («14:30 · Pranzo»), e per quali giorni vale
    var ordine = [], ore = {}, nome = {}, giorni = {};
    var quando = { ON: 'giorni ON', OFF_S: 'giorni OFF', OFF_W: 'weekend', FREE: 'weekend' };
    ['ON', 'OFF_S', 'OFF_W', 'FREE'].forEach(function (t) {
      (P.daytypes[t] ? P.daytypes[t].slots : []).forEach(function (s) {
        var slot = s[2];
        if (slot === 'free') return;
        if (ordine.indexOf(slot) < 0) { ordine.push(slot); ore[slot] = []; giorni[slot] = []; nome[slot] = s[1].split(' (')[0]; }
        if (ore[slot].indexOf(s[0]) < 0) ore[slot].push(s[0]);
        if (giorni[slot].indexOf(quando[t]) < 0) giorni[slot].push(quando[t]);
      });
    });
    var firma = function (slot) { return JSON.stringify(Object.keys(P.variants[slot] || {}).map(function (c) { return P.variants[slot][c].map(function (x) { return x[1]; }); })); };
    var giro = ['colazione', 'm1', 'm2', 'pranzo_on', 'pranzo_off', 'cena_on', 'cena_off', 'spuntino'];   // l'ordine della giornata
    ordine.sort(function (a, b) { return (giro.indexOf(a) + 1 || 99) - (giro.indexOf(b) + 1 || 99); });
    ordine.forEach(function (s) { if (giorni[s].length >= 3) giorni[s] = ['tutti i giorni']; });
    var paniniUguali = P.variants.m1 && P.variants.m2 && firma('m1') === firma('m2');
    if (paniniUguali) ordine.splice(ordine.indexOf('m2'), 1);
    return ordine.map(function (slot) {
      var titolo = slot === 'm1' && paniniUguali ? '09:30 e 12:10 · I due panini di scuola'
        : ore[slot].join(' / ') + ' · ' + nome[slot] + ' (' + giorni[slot].join(', ') + ')';
      var carte = Object.keys(P.variants[slot] || {}).map(function (code) {
        var ls = righe(slot, code), t = somma(ls), r = P.recipes[code] || { name: code, how: '' };
        return '<article class="card meal"><div class="meal-h"><div class="t"><h3>' + esc(r.name) + '</h3></div>' +
          '<div class="meal-k"><b class="num">' + t.k + '</b><span>kcal</span></div></div>' + listaRighe(ls) + macro(t) +
          (r.how ? '<p class="how">' + esc(r.how) + '</p>' : '') + '</article>';
      }).join('');
      return '<section class="stack"><div class="card flat"><h2>' + esc(titolo) + '</h2></div><div class="grid2">' + carte + '</div></section>';
    }).join('');
  }

  function renderScambi() {
    var tabelle = (P.equivalents || []).map(function (eq) {
      var tutte = [{ f: eq.ref, g: eq.g, rif: true }].concat(eq.rows);
      return '<section class="card stack"><h2>' + esc(eq.title) + '</h2><div class="tbl-wrap"><table><thead><tr><th>Alimento</th><th class="r">Dose</th><th class="r">kcal</th><th class="r">P</th><th class="r">C</th><th class="r">G</th></tr></thead><tbody>' +
        tutte.map(function (x) {
          var l = riga(x.f, x.g), a = x.rif ? '' : aiuto(x.f, x.g, false);
          return '<tr' + (x.rif ? ' class="tbl-hl"' : '') + '><td>' + (x.rif ? '<b>' + esc(l.n) + '</b> <span class="tiny muted">(riferimento)</span>' : esc(l.n) + (a ? ' <small class="muted">(' + esc(a) + ')</small>' : '')) + '</td>' +
            '<td class="r num"><b>' + fmt(x.g) + ' ' + unita(x.f) + '</b></td><td class="r num">' + l.k + '</td><td class="r num">' + fmt(l.p) + '</td><td class="r num">' + fmt(l.c) + '</td><td class="r num">' + fmt(l.fa) + '</td></tr>';
        }).join('') + '</tbody></table></div></section>';
    }).join('');
    var cibi = Object.keys(P.foods).sort(function (a, b) { return P.foods[a].n.localeCompare(P.foods[b].n, 'it'); });
    var tabella = '<section class="card stack"><div class="row" style="flex-wrap:wrap"><h2>Cibi del piano (per 100 g)</h2><span class="spacer"></span>' +
      '<input type="search" class="search" id="cercaCibo" placeholder="Cerca un cibo…" autocomplete="off" style="max-width:260px"></div>' +
      '<div class="tbl-wrap"><table><thead><tr><th>Alimento</th><th class="r">kcal</th><th class="r">P</th><th class="r">C</th><th class="r">G</th></tr></thead><tbody>' +
      cibi.map(function (id) {
        var f = P.foods[id];
        return '<tr data-cerca="' + esc((f.n + ' ' + f.cat).toLowerCase()) + '"><td><b>' + esc(f.n) + '</b><div class="tiny muted">' + esc(f.cat) + (f.note ? ' · ' + esc(f.note) : '') + '</div></td>' +
          '<td class="r num">' + f.k + '</td><td class="r num">' + fmt(f.p) + '</td><td class="r num">' + fmt(f.c) + '</td><td class="r num">' + fmt(f.f) + '</td></tr>';
      }).join('') + '</tbody></table></div></section>';
    return tabelle + tabella;
  }

  function renderSpesa() {
    var tot = {};
    for (var d = 0; d < 7; d++) pianoDi(d).pasti.forEach(function (m) { (m.righe || []).forEach(function (l) { tot[l.f] = (tot[l.f] || 0) + l.g; }); });
    var cat = ['Carne e pesce', 'Affettati', 'Latticini e uova', 'Pane, pasta e cereali', 'Frutta', 'Verdura cruda', 'Condimenti e dispensa'];
    var altre = Object.keys(tot).map(function (id) { return (P.foods[id] || {}).cat; }).filter(function (c, i, a) { return c && cat.indexOf(c) < 0 && a.indexOf(c) === i; });
    var html = cat.concat(altre).map(function (c) {
      var ids = Object.keys(tot).filter(function (id) { return P.foods[id] && P.foods[id].cat === c; });
      if (!ids.length) return '';
      return '<div class="shop-cat"><h3>' + esc(c) + '</h3><ul class="shop">' + ids.map(function (id) {
        var f = P.foods[id], preso = !!state.spesa[id], a = aiuto(id, tot[id], true);
        return '<li class="' + (preso ? 'got' : '') + '"><label><input type="checkbox" data-spesa="' + id + '"' + (preso ? ' checked' : '') + '>' +
          '<span class="n"><b>' + esc(f.n) + '</b>' + (f.note ? '<div class="tiny muted">' + esc(f.note) + '</div>' : '') + '</span></label>' +
          '<div class="q num">' + fmtInt(tot[id]) + ' ' + unita(id) + (a ? '<small>' + esc(a) + '</small>' : '') + '</div></li>';
      }).join('') + '</ul></div>';
    }).join('');
    return '<section class="card stack"><div class="row" style="flex-wrap:wrap"><div><h2>Spesa della settimana</h2>' +
      '<p class="small muted">I 7 giorni del piano (con i piatti scambiati qui), pesi a crudo. Il pranzo libero non c\'è.</p></div>' +
      '<span class="spacer"></span><button type="button" class="chip" data-azzera-spesa="1">Togli le spunte</button></div>' + html + '</section>';
  }

  /* ================= SCHEDA ================= */
  function recupero(e, w) {
    if (e.rest === 0) {
      // superserie: «4a» senza recupero, poi subito la «4b»
      var compagno = e.sup ? e.sup.slice(0, -1) + 'b' : '';
      return compagno && compagno !== e.sup ? '0″, subito la ' + compagno : '0″';
    }
    var m = Math.floor(e.rest / 60), s = e.rest % 60;
    return m ? m + '′' + (s ? (s < 10 ? '0' : '') + s + '″' : '') : s + '″';
  }

  function renderScheda() {
    var tabs = '<div class="wo-tabs" role="tablist">' + P.workouts.map(function (w) {
      return '<button type="button" class="wo-tab" role="tab" data-scheda="' + w.id + '" aria-selected="' + (state.scheda === w.id) + '">' + esc(w.name) + '<small>' + esc(w.day) + '</small></button>';
    }).join('') + '</div>';
    var w = P.workouts.filter(function (x) { return x.id === state.scheda; })[0] || P.workouts[0];
    var serie = w.ex.reduce(function (a, e) { return a + e.s; }, 0);
    var carte = w.ex.map(function (e, i) {
      var lib = P.exlib[e.lib] || {};
      var sec = e.unit === 'sec';
      var foto = lib.img ? '<div class="ex-photos"><img src="assets/esercizi/' + esc(lib.img) + '-0.jpg" alt="' + esc(e.n) + ', inizio" loading="lazy">' +
        '<img src="assets/esercizi/' + esc(lib.img) + '-1.jpg" alt="' + esc(e.n) + ', fine" loading="lazy"></div>' : '';
      return '<article class="card ex' + (e.sup ? ' sup' : '') + '"><div class="ex-h"><div class="ex-n">' + esc(e.sup || (i + 1)) + '</div>' +
        '<div style="flex:1;min-width:0"><h3>' + esc(e.n) + '</h3><div class="ex-meta">' +
        '<span><b>' + e.s + ' × ' + (e.lo === e.hi ? e.lo : e.lo + '–' + e.hi) + (sec ? '″' : ' rip.') + '</b></span>' +
        '<span>Recupero <b>' + recupero(e, w) + '</b></span>' +
        (e.start ? '<span>Carico di partenza <b>' + esc(e.start) + '</b></span>' : '') +
        (lib.m ? '<span>' + esc(lib.m) + (lib.eq ? ' · ' + esc(lib.eq) : '') + '</span>' : '') +
        '</div></div></div>' +
        (e.sup ? '<div class="sup-note">Superserie ' + esc(e.sup.slice(0, -1)) + ': ' + (e.sup.slice(-1) === 'a' ? 'poi subito la ' + esc(e.sup.slice(0, -1)) + 'b' : 'dopo la ' + esc(e.sup.slice(0, -1)) + 'a') + '.</div>' : '') +
        (e.cue ? '<p class="cue">' + esc(e.cue) + '</p>' : '') + foto + '</article>';
    }).join('');
    var obiettivi = Object.keys(P.muscleTargets || {}).map(function (m) { return '<div><dt>' + esc(m) + '</dt><dd class="num">' + P.muscleTargets[m] + ' serie</dd></div>'; }).join('');
    return '<div class="stack">' + tabs +
      '<section class="card"><div class="eyebrow">' + esc(w.day) + ' · 16:30–18:00</div><h2>' + esc(w.name) + ' · ' + esc(w.focus) + '</h2>' +
      '<p class="small muted" style="margin-top:4px">' + w.ex.length + ' esercizi · ' + serie + ' serie. I carichi veri e i record sono nell\'app.</p></section>' +
      carte +
      '<section class="card stack"><h2>Come si progredisce</h2>' +
      '<p class="small muted"><b>Doppia progressione:</b> prima le ripetizioni fino al massimo dell\'intervallo in tutte le serie (lasciandone 1–2 in riserva), poi il peso sale di un passo e si riparte dal minimo.</p>' +
      (obiettivi ? '<h3 style="margin-top:6px">Serie a settimana per muscolo</h3><dl class="kv">' + obiettivi + '</dl>' : '') + '</section></div>';
  }

  /* ================= navigazione ================= */
  function render(inCima) {
    state.route = (location.hash || '').replace(/^#\/?/, '') === 'scheda' ? 'scheda' : 'dieta';
    document.querySelectorAll('.top-switch a').forEach(function (a) {
      if (a.getAttribute('data-route') === state.route) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
    });
    main.innerHTML = (state.route === 'scheda' ? renderScheda() : renderDieta()) +
      '<p class="tiny muted" style="text-align:center;margin:28px 0 12px">' + esc(P.version) + ' · da consultare: pasti e allenamenti si segnano nell\'app</p>';
    if (inCima) window.scrollTo(0, 0);
  }

  document.addEventListener('click', function (ev) {
    var t = ev.target.closest('[data-tab],[data-day],[data-dosi],[data-scambio],[data-ripristina],[data-azzera-spesa],[data-scheda],[data-vai-scheda]');
    if (!t) return;
    if (t.hasAttribute('data-vai-scheda')) { state.scheda = t.getAttribute('data-vai-scheda'); return; } // il link cambia pagina da solo
    if (t.hasAttribute('data-tab')) { state.tab = t.getAttribute('data-tab'); salva('tab', state.tab); return render(true); }
    if (t.hasAttribute('data-day')) { state.giorno = +t.getAttribute('data-day'); return render(false); }
    if (t.hasAttribute('data-scheda')) { state.scheda = t.getAttribute('data-scheda'); return render(true); }
    if (t.hasAttribute('data-dosi')) {
      var d = +t.getAttribute('data-dosi'), base = P.week[d].type, ora = tipoDi(d), dopo = ora === 'ON' ? 'OFF_S' : 'ON';
      if (dopo === base) delete state.dosi[d]; else state.dosi[d] = dopo;
      salva('dosi', state.dosi);
      return render(false);
    }
    if (t.hasAttribute('data-scambio')) {
      var p = t.getAttribute('data-scambio').split(':'), chiave = p[0] + '-' + p[1];
      if (p[2] === P.week[+p[0]].pick[+p[1]]) delete state.scambi[chiave]; else state.scambi[chiave] = p[2];
      salva('scambi', state.scambi);
      return render(false);
    }
    if (t.hasAttribute('data-ripristina')) {
      var g = t.getAttribute('data-ripristina');
      Object.keys(state.scambi).forEach(function (k) { if (k.indexOf(g + '-') === 0) delete state.scambi[k]; });
      delete state.dosi[g];
      salva('scambi', state.scambi); salva('dosi', state.dosi);
      return render(false);
    }
    if (t.hasAttribute('data-azzera-spesa')) { state.spesa = {}; salva('spesa', state.spesa); return render(false); }
  });

  document.addEventListener('change', function (ev) {
    var c = ev.target.closest('[data-spesa]');
    if (!c) return;
    var id = c.getAttribute('data-spesa');
    if (c.checked) state.spesa[id] = true; else delete state.spesa[id];
    salva('spesa', state.spesa);
    c.closest('li').classList.toggle('got', c.checked);
  });

  // la ricerca dei cibi filtra le righe senza ridisegnare la pagina (il cursore resta dov'è)
  document.addEventListener('input', function (ev) {
    if (ev.target.id !== 'cercaCibo') return;
    var q = ev.target.value.trim().toLowerCase();
    document.querySelectorAll('tr[data-cerca]').forEach(function (r) { r.hidden = !!q && r.getAttribute('data-cerca').indexOf(q) < 0; });
  });

  window.addEventListener('hashchange', function () { render(true); });

  /* ---------- tema chiaro / scuro ---------- */
  function scuro() {
    var t = document.documentElement.getAttribute('data-theme');
    return t === 'dark' || (!t && window.matchMedia('(prefers-color-scheme: dark)').matches);
  }
  function iconaTema() {
    themeBtn.innerHTML = scuro()
      ? '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></svg>'
      : '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>';
  }
  themeBtn.addEventListener('click', function () {
    var t = scuro() ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', t);
    try { localStorage.setItem('rc.theme', JSON.stringify(t)); } catch (e) {}
    iconaTema();
  });
  iconaTema();

  // consultazione anche senza rete (l'ultima versione vista)
  if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(function () {});

  render(false);
})();
