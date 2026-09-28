# Recomp · piano personale

Sito statico (GitHub Pages) con piano alimentare calcolato al grammo, scheda Torso/Limbs con diario dei carichi, lista della spesa e monitoraggio del peso. Nessun framework, nessuna build: HTML, CSS e JavaScript.

## Struttura

| Percorso | Contenuto |
|---|---|
| `index.html` | Pagina unica (sezioni: Oggi, Piano, Scheda, Progressi, Guida) |
| `assets/js/data.js` | **Generato**: alimenti, ricette, grammature, settimana tipo, scheda |
| `assets/js/app.js` | Logica del sito (calcoli, scambi, diario, timer, grafico) |
| `assets/css/style.css` | Stile (tema chiaro/scuro, mobile first) |
| `tools/genera_piano.py` | Database alimenti, ricette, target, ottimizzazione e verifica |
| `tools/genera_icone.py` | Genera le icone PNG |
| `sw.js`, `manifest.webmanifest` | Uso offline e installazione su telefono |

## Modificare il piano

1. Cambia valori, ricette o target in `tools/genera_piano.py`.
2. Esegui `python tools/genera_piano.py`: ricalcola le grammature, stampa il report di verifica e riscrive `assets/js/data.js`.
3. Aumenta il numero di versione `?v=` in `index.html` e `sw.js` (e il nome `CACHE` in `sw.js`), così telefoni e browser scaricano i file nuovi.

## Come sono calcolati i numeri

- Valori per 100 g da tabelle CREA, USDA ed etichette dei prodotti (la fonte è indicata per ogni alimento nella sezione Guida → Alimenti).
- Riga: kcal arrotondate all'intero, macro a 0,1 g. Totale del pasto = somma delle righe. Totale del giorno = somma dei pasti. Il sito e lo script usano lo stesso identico arrotondamento, quindi i numeri coincidono.
- I dati personali (pesi, carichi, spunte) restano solo nel browser (`localStorage`): non vengono pubblicati.
