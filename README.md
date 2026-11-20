# Recomp · piano personale

Due parti:

- **L'app iPhone + Apple Watch** (`app-ios/`): è quella vera, dove si segnano pasti, pesi e allenamenti. È scritta in SwiftUI
  e si installa dal PC Windows con xtool e un Apple ID gratuito (`app-ios/xtool/README.md`, `app-ios/swiftui/README.md`).
- **Il sito** (GitHub Pages, https://splancxs.github.io): solo da consultare al volo da PC, tablet o telefono. Mostra la dieta
  del nutrizionista (giorni, ricette, scambi, spesa) e la scheda Torso / Limbs. Non registra niente. Nessun framework e
  nessuna build: HTML, CSS e JavaScript.

Foto degli esercizi in `assets/esercizi/`: [free-exercise-db](https://github.com/yuhonas/free-exercise-db), pubblico dominio (Unlicense).

## Il sito

| Percorso | Contenuto |
|---|---|
| `index.html` | Pagina unica con due sezioni: Dieta e Scheda |
| `assets/js/data.js` | **Generato**: alimenti, ricette, grammature, settimana tipo, schede (non modificarlo a mano) |
| `assets/js/app.js` | Le pagine: giorni con i pasti e gli altri piatti della fascia, ricette, tabelle degli scambi, spesa, schede |
| `assets/css/style.css` | Stile (tema chiaro/scuro, prima il telefono) |
| `sw.js` | Si apre anche senza rete (l'ultima versione vista) |

Nel browser restano solo le comodità di consultazione (piatti scambiati per vedere i conti, dosi ON/OFF, spunte della
spesa, tema), con le chiavi `rc.web.*` e `rc.theme`.

## Modificare il piano

1. La dieta arriva dal nutrizionista in `tools/dieta.json`.
2. `python tools/genera_piano.py`: ricalcola le grammature, stampa il report di verifica e riscrive `assets/js/data.js`.
3. `python tools/piano_swift.py`: ne ricava `app-ios/swiftui/Resources/piano.json` per l'app.
4. `python tools/versione.py`: alza `?v=` in `index.html` e `sw.js`, così browser e telefoni scaricano i file nuovi.

## Come sono calcolati i numeri

- Valori per 100 g da tabelle CREA, USDA ed etichette dei prodotti.
- Riga: kcal arrotondate all'intero, macro a 0,1 g. Totale del pasto = somma delle righe; totale del giorno = somma dei
  pasti. Sito, app e script usano lo stesso arrotondamento, quindi i numeri coincidono.
- Il pranzo libero della domenica vale circa 700 kcal ed è già dentro le kcal del giorno.
