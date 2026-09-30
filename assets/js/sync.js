// Sincronizzazione automatica PC ↔ telefono con Firebase (Auth email/password + Firestore).
// Tutti i dati dell'app (chiavi "rc.*" di localStorage) finiscono in un unico documento users/{uid}.
// Unione delle modifiche:
//  - pesi e diario della scheda: elemento per elemento (una pesata per data, una sessione per esercizio e data),
//    vince la versione modificata più di recente; le eliminazioni sono "segnaposto" con del/t, quindi si propagano;
//  - tutto il resto (scambi, spunte, spesa, blocco): vince la chiave modificata più di recente (rc._meta).
import { firebaseConfig } from './firebase-config.js';

const V = '11.0.2';
const SKIP = new Set(['rc._meta', 'rc.theme', 'rc.installHidden', 'rc.health', 'rc.reminders', 'rc.active', 'rc.logMigrated']); // preferenze del singolo dispositivo
// stato mostrato in Profilo: status = loading | nocfg | offline | error | out | in; net = rete del dispositivo
const S = {
  state: { status: 'loading', net: navigator.onLine !== false },
  login: () => {}, signup: () => {}, logout: () => {}, now: () => {},
  retry: () => location.reload(),
};
window.RCSync = S;
const refresh = (force) => { if (window.RC) window.RC.refresh(force); };
const setState = (patch, force = true) => { S.state = { ...S.state, ...patch }; refresh(force); };

const ERR = {
  'auth/invalid-credential': 'Email o password sbagliate.',
  'auth/wrong-password': 'Email o password sbagliate.',
  'auth/user-not-found': 'Nessun account con questa email: usa "Crea account".',
  'auth/email-already-in-use': 'Esiste già un account con questa email: usa "Accedi".',
  'auth/weak-password': 'La password deve avere almeno 6 caratteri.',
  'auth/invalid-email': "L'email non è valida.",
  'auth/missing-password': 'Scrivi la password.',
  'auth/too-many-requests': 'Troppi tentativi: riprova tra qualche minuto.',
  'auth/network-request-failed': 'Nessuna connessione: riprova quando sei online.',
  'auth/operation-not-allowed': "L'accesso con email e password non è attivo nel progetto Firebase.",
  'auth/admin-restricted-operation': 'La creazione di nuovi account è disattivata nel progetto Firebase.',
};
// una promessa che non risponde entro ms diventa un errore: niente attese infinite su rete lenta o assente
const withTimeout = (p, ms, code) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(Object.assign(new Error(code), { code })), ms))]);
const isNative = !!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform());
const errMsg = (e) => ERR[e && e.code] || `Errore: ${(e && (e.code || e.message)) || 'sconosciuto'}`;

/* ---------- lettura/scrittura locale ---------- */
const parse = (s, d) => { try { return s == null ? d : JSON.parse(s); } catch (e) { return d; } };
function readMeta() { return parse(localStorage.getItem('rc._meta'), {}); }
function localSnapshot() {
  const meta = readMeta();
  const out = {};
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i);
    if (!k || !k.startsWith('rc.') || SKIP.has(k)) continue;
    out[k] = { v: localStorage.getItem(k), t: meta[k] || 0 };
  }
  return out;
}
function writeLocal(entries) {
  const meta = readMeta();
  let changed = false;
  for (const [k, e] of Object.entries(entries)) {
    if (localStorage.getItem(k) !== e.v) { localStorage.setItem(k, e.v); changed = true; }
    meta[k] = Math.max(meta[k] || 0, e.t || 0);
  }
  localStorage.setItem('rc._meta', JSON.stringify(meta));
  return changed;
}

/* ---------- unione ---------- */
function mergeItems(a, b, idOf) {
  const m = new Map();
  for (const x of [...(a || []), ...(b || [])]) {
    if (!x) continue;
    const id = idOf(x);
    const cur = m.get(id);
    if (!cur || (x.t || 0) > (cur.t || 0)) m.set(id, x);
  }
  return [...m.values()];
}
function mergeKey(k, L, R) {
  if (!L) return R;
  if (!R) return L;
  const t = Math.max(L.t || 0, R.t || 0);
  if (k === 'rc.weights') {
    const v = mergeItems(parse(L.v, []), parse(R.v, []), (x) => x.d).sort((x, y) => (x.d < y.d ? -1 : 1));
    return { v: JSON.stringify(v), t };
  }
  if (k === 'rc.workouts') { // cronologia allenamenti: uno per id, vince il più recente (anche le eliminazioni)
    const v = mergeItems(parse(L.v, []), parse(R.v, []), (x) => x.id).sort((x, y) => (x.start || 0) - (y.start || 0));
    return { v: JSON.stringify(v), t };
  }
  // routine, esercizi creati, creatina, diario e giorni modificati: una voce per id (o per data), vince la più recente
  if (k === 'rc.routines' || k === 'rc.exlib' || k === 'rc.creatina' || k === 'rc.dlog' || k === 'rc.dayov') {
    const a = parse(L.v, {}), b = parse(R.v, {});
    const out = {};
    for (const id of new Set([...Object.keys(a), ...Object.keys(b)])) {
      const x = a[id], y = b[id];
      out[id] = !x ? y : !y ? x : ((y.t || 0) > (x.t || 0) ? y : x);
    }
    return { v: JSON.stringify(out), t };
  }
  if (k === 'rc.log') {
    const a = parse(L.v, {}), b = parse(R.v, {});
    const out = {};
    for (const id of new Set([...Object.keys(a), ...Object.keys(b)])) {
      out[id] = mergeItems(a[id], b[id], (x) => x.d).sort((x, y) => (x.d < y.d ? -1 : 1));
    }
    return { v: JSON.stringify(out), t };
  }
  return (R.t || 0) > (L.t || 0) ? R : L;
}
function mergeAll(local, remote) {
  const out = {};
  for (const k of new Set([...Object.keys(local), ...Object.keys(remote)])) out[k] = mergeKey(k, local[k], remote[k]);
  return out;
}
const same = (a, b) => {
  const ka = Object.keys(a), kb = Object.keys(b);
  return ka.length === kb.length && ka.every((k) => b[k] && b[k].v === a[k].v);
};
// Firestore: niente punti nei nomi dei campi → "rc.weights" diventa "weights"
const toRemote = (o) => Object.fromEntries(Object.entries(o).map(([k, e]) => [k.slice(3), { v: e.v, t: e.t || 0 }]));
const fromRemote = (o) => Object.fromEntries(Object.entries(o || {}).map(([k, e]) => ['rc.' + k, { v: String(e.v), t: Number(e.t) || 0 }]));

/* ---------- avvio ---------- */
async function start() {
  if (!firebaseConfig || !firebaseConfig.apiKey) { setState({ status: 'nocfg' }); return; }
  window.addEventListener('online', () => setState({ net: true }, false));
  window.addEventListener('offline', () => setState({ net: false }, false));
  let fb;
  try {
    const [app, auth, fs] = await withTimeout(Promise.all([
      import(`https://www.gstatic.com/firebasejs/${V}/firebase-app.js`),
      import(`https://www.gstatic.com/firebasejs/${V}/firebase-auth.js`),
      import(`https://www.gstatic.com/firebasejs/${V}/firebase-firestore.js`),
    ]), 15000, 'timeout');
    fb = { app, auth, fs };
  } catch (e) {
    // senza rete la libreria non si scarica: riprovo da solo appena torna la connessione
    setState({ status: navigator.onLine === false ? 'offline' : 'error', msg: navigator.onLine === false ? '' : 'Il servizio di sincronizzazione non risponde.' }, false);
    window.addEventListener('online', () => location.reload(), { once: true });
    return;
  }
  let auth, db;
  try {
    const app = fb.app.initializeApp(firebaseConfig);
    // Nell'app iPhone (Capacitor) getAuth() resta in attesa per sempre: prova a caricare il componente dei popup,
    // che dentro l'app non esiste. Con initializeAuth + salvataggio su IndexedDB l'accesso parte subito.
    auth = isNative ? fb.auth.initializeAuth(app, { persistence: fb.auth.indexedDBLocalPersistence }) : fb.auth.getAuth(app);
    db = fb.fs.getFirestore(app);
  } catch (e) {
    setState({ status: 'error', msg: `Avvio non riuscito (${e.code || e.message}).` }, false);
    return;
  }
  // se Firebase non comunica lo stato dell'accesso entro 12 secondi, lo dico invece di restare su «Connessione…»
  const authWatch = setTimeout(() => {
    if (S.state.status === 'loading') setState({ status: 'error', msg: navigator.onLine === false ? '' : 'Il collegamento non risponde.' }, false);
  }, 12000);

  let unsub = null, ref = null, remote = {}, pushTimer = 0, pushing = false;

  async function push() {
    if (!ref) return;
    clearTimeout(pushTimer);
    pushing = true; setState({ busy: true }, false);
    try {
      const merged = mergeAll(localSnapshot(), remote);
      if (writeLocal(merged)) refresh(false);
      if (!same(merged, remote)) {
        // senza rete setDoc non risponde mai: dopo 15 secondi smetto di aspettare (Firestore la invia comunque appena può)
        await withTimeout(fb.fs.setDoc(ref, { data: toRemote(merged), at: fb.fs.serverTimestamp() }), 15000, 'timeout');
        remote = merged;
      }
      setState({ busy: false, fail: false, last: Date.now(), msg: '' }, false);
    } catch (e) {
      const off = e.code === 'timeout' || e.code === 'unavailable' || navigator.onLine === false;
      setState({ busy: false, fail: !off, msg: off ? 'Rete assente o lenta: i dati sono salvati qui e partono appena torna la connessione.' : `Sincronizzazione non riuscita (${e.code || e.message}). Riprovo alla prossima modifica.` }, false);
    } finally { pushing = false; }
  }
  const schedulePush = () => { if (!ref) return; clearTimeout(pushTimer); pushTimer = setTimeout(push, 1200); };

  window.addEventListener('rc-change', schedulePush);
  window.addEventListener('online', schedulePush);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden' && ref) push(); });

  fb.auth.onAuthStateChanged(auth, (user) => {
    clearTimeout(authWatch);
    if (unsub) { unsub(); unsub = null; }
    if (!user) { ref = null; remote = {}; setState({ status: 'out', email: '', busy: false }); return; }
    ref = fb.fs.doc(db, 'users', user.uid);
    setState({ status: 'in', email: user.email, msg: '' });
    unsub = fb.fs.onSnapshot(ref, (snap) => {
      if (snap.metadata.hasPendingWrites) return; // è la nostra scrittura, già applicata
      remote = fromRemote(snap.exists() ? snap.data().data : {});
      const merged = mergeAll(localSnapshot(), remote);
      const changed = writeLocal(merged);
      setState({ last: Date.now(), fail: false, msg: '' }, false);
      if (changed) refresh(false);
      if (!same(merged, remote) && !pushing) schedulePush(); // qui c'erano dati più nuovi: li carico
    }, (e) => setState({ fail: true, msg: `Lettura non riuscita (${e.code || e.message}). Controlla le regole di Firestore.` }));
  }, (e) => { clearTimeout(authWatch); setState({ status: 'error', msg: errMsg(e) }); });

  S.login = async (email, pw) => {
    setState({ emailDraft: email, msg: '' });
    try { await fb.auth.signInWithEmailAndPassword(auth, email, pw); } catch (e) { setState({ msg: errMsg(e) }); }
  };
  S.signup = async (email, pw) => {
    setState({ emailDraft: email, msg: '' });
    try { await fb.auth.createUserWithEmailAndPassword(auth, email, pw); } catch (e) { setState({ msg: errMsg(e) }); }
  };
  S.logout = async () => { await push(); await fb.auth.signOut(auth); };
  S.now = () => push();
}

start();
