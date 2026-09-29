# -*- coding: utf-8 -*-
"""
Generatore + verificatore del piano alimentare.

- Database alimenti (valori per 100 g, fonte dichiarata).
- Ricette scelte dall'utente, con ingredienti "regolabili" (range e passo).
- Per ogni fascia (slot) e tipo di giornata cerca le grammature che centrano il target
  di kcal (±10) e si avvicinano il più possibile ai macro del target.
- Calcola i totali ESATTAMENTE come li calcola il sito (stesso arrotondamento):
  kcal riga = round(kcal100 * g / 100) a intero, macro riga = round(x * 10) / 10;
  totale pasto = somma delle righe arrotondate; totale giorno = somma dei pasti.
- Scrive assets/js/data.js e stampa il report di verifica.

Uso:  python tools/genera_piano.py
"""
import itertools
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def r0(x):  # arrotondamento identico a Math.round (x >= 0)
    return int(math.floor(x + 0.5))


def r1(x):
    return math.floor(x * 10 + 0.5) / 10


# ---------------------------------------------------------------------------
# DATABASE ALIMENTI  (kcal, proteine, carboidrati, grassi per 100 g)
# cat: categoria per la lista della spesa · src: fonte · u: unità pratica (g per pezzo)
# ---------------------------------------------------------------------------
F = {}


def food(id, name, cat, k, p, c, f, src, u=None, note=None):
    F[id] = dict(id=id, n=name, cat=cat, k=k, p=p, c=c, f=f, src=src)
    if u:
        F[id]['u'] = u
    if note:
        F[id]['note'] = note


C_CARNE, C_AFF, C_LATT, C_CARB, C_FRUT, C_VERD, C_COND, C_INT = (
    'Carne e pesce', 'Affettati', 'Latticini e uova', 'Pane, pasta e cereali',
    'Frutta', 'Verdura cruda', 'Condimenti e dispensa', 'Integratori e snack')

# Carne e pesce (pesi da CRUDO)
food('pollo', 'Petto di pollo (crudo)', C_CARNE, 100, 23.3, 0, 0.8, 'CREA')
food('tacchino', 'Fesa di tacchino (cruda)', C_CARNE, 107, 24.0, 0, 1.2, 'CREA')
food('manzo5', 'Macinato di manzo 5% (crudo)', C_CARNE, 129, 21.0, 0, 5.0, 'Media etichette')
food('lonza', 'Lonza di maiale magra (cruda)', C_CARNE, 135, 21.0, 0, 5.5, 'Media etichette')
food('vitello', 'Fesa di vitello (cruda)', C_CARNE, 92, 20.7, 0, 1.0, 'CREA')
food('salmone', 'Salmone fresco (crudo)', C_CARNE, 185, 18.4, 0, 12.0, 'CREA')
food('orata', 'Orata, filetto (crudo)', C_CARNE, 121, 19.7, 0, 4.7, 'Media allevamento')
food('merluzzo', 'Merluzzo, filetto (crudo)', C_CARNE, 71, 17.0, 0, 0.3, 'CREA')
food('trota', 'Trota (cruda)', C_CARNE, 141, 20.8, 0, 6.2, 'USDA')
food('tonno_fresco', 'Tonno fresco pinne gialle (crudo)', C_CARNE, 108, 24.4, 0, 1.0, 'USDA')
food('tonno_nat', 'Tonno al naturale (sgocciolato)', C_CARNE, 103, 25.1, 0, 0.3, 'CREA')
food('sgombro_nat', 'Sgombro al naturale (sgocciolato)', C_CARNE, 160, 21.0, 0, 8.5, 'Media etichette')

# Affettati
food('bresaola', 'Bresaola', C_AFF, 151, 32.0, 0, 2.6, 'CREA')
food('cotto', 'Prosciutto cotto magro (sgrassato)', C_AFF, 126, 20.0, 1.0, 4.7, 'Media etichette')
food('tacchino_arrosto', 'Fesa di tacchino arrosto (affettato)', C_AFF, 104, 21.0, 1.5, 1.5, 'Media etichette')
food('roastbeef', 'Roast beef (affettato)', C_AFF, 120, 22.0, 0.5, 3.4, 'Media etichette')
food('speck', 'Speck', C_AFF, 301, 28.3, 0.5, 20.9, 'CREA')

# Latticini e uova
food('uovo', 'Uovo intero', C_LATT, 128, 12.4, 0, 8.7, 'CREA', u=50, note='1 uovo medio ≈ 50 g senza guscio')
food('albume', 'Albume (brick)', C_LATT, 43, 10.7, 0, 0, 'CREA')
food('yogurt', 'Yogurt greco 0%', C_LATT, 54, 10.3, 3.0, 0, 'Etichetta Fage Total 0%')
food('latte_ps', 'Latte parzialmente scremato', C_LATT, 46, 3.5, 5.0, 1.5, 'CREA')
food('fiocchi', 'Fiocchi di latte', C_LATT, 98, 11.0, 3.2, 4.5, 'Media etichette')
food('phila', 'Philadelphia Light', C_LATT, 182, 8.4, 3.7, 15.0, 'Etichetta (FatSecret)')
food('mozz_light', 'Mozzarella light', C_LATT, 163, 19.0, 1.0, 9.0, 'Media etichette')
food('sottiletta', 'Sottilette Light', C_LATT, 174, 16.0, 8.0, 6.8, 'Etichetta Sottilette.it', u=20,
     note='1 fetta ≈ 20 g')
food('parmigiano', 'Parmigiano Reggiano', C_LATT, 387, 33.5, 0, 28.1, 'CREA')

# Pane, pasta e cereali (pesi da CRUDO per pasta e riso)
food('pasta', 'Pasta di semola (cruda)', C_CARB, 359, 12.5, 71.2, 2.0, 'Etichetta Barilla')
food('riso', 'Riso basmati (crudo)', C_CARB, 350, 7.8, 78.0, 0.6, 'Media etichette')
food('patate', 'Patate (crude)', C_CARB, 77, 2.0, 16.0, 0.1, 'USDA')
food('pane_int', 'Pane integrale', C_CARB, 240, 9.0, 41.0, 3.0, 'Media etichette')
food('pane_segale', 'Pane di segale', C_CARB, 220, 7.0, 40.0, 2.0, 'Media etichette')
food('pancarre', 'Pancarré integrale', C_CARB, 258, 10.0, 42.0, 4.3, 'Media etichette', u=27,
     note='1 fetta ≈ 27 g')
food('piadina', 'Piadina integrale', C_CARB, 305, 9.0, 46.0, 8.0, 'Media etichette')
food('crackers', 'Crackers integrali', C_CARB, 410, 11.0, 64.0, 10.5, 'Media etichette', u=25,
     note='1 pacchetto ≈ 25 g')
food('fette_bisc', 'Fette biscottate integrali', C_CARB, 382, 12.0, 66.0, 5.5, 'Media etichette', u=10,
     note='1 fetta ≈ 10 g')
food('avena', "Fiocchi d'avena", C_CARB, 370, 13.5, 58.7, 7.0, 'Media etichette')
food('special_k', 'Special K Protein (frutti di bosco, granola e semi)', C_CARB, 371, 12.0, 69.0, 3.2,
     'Etichetta (Open Food Facts)')
food('gallette', 'Gallette di riso', C_CARB, 385, 8.0, 81.0, 2.8, 'Media etichette', u=8)

# Frutta
food('banana', 'Banana (polpa)', C_FRUT, 89, 1.1, 20.2, 0.3, 'USDA')
food('mela', 'Mela', C_FRUT, 52, 0.3, 11.4, 0.2, 'USDA')
food('pera', 'Pera', C_FRUT, 57, 0.4, 12.2, 0.1, 'USDA')
food('kiwi', 'Kiwi (polpa)', C_FRUT, 61, 1.1, 12.2, 0.5, 'USDA', u=75, note='1 kiwi ≈ 75 g')
food('arancia', 'Arancia (polpa)', C_FRUT, 47, 0.9, 9.4, 0.1, 'USDA')
food('fragole', 'Fragole', C_FRUT, 32, 0.7, 5.7, 0.3, 'USDA')
food('frutti_bosco', 'Frutti di bosco (anche surgelati)', C_FRUT, 45, 1.0, 7.5, 0.4, 'Media etichette')
food('ananas', 'Ananas', C_FRUT, 50, 0.5, 11.7, 0.1, 'USDA')
food('spremuta', "Spremuta d'arancia", C_FRUT, 45, 0.7, 10.4, 0.2, 'USDA')

# Verdura cruda
food('insalata', 'Insalata mista cruda (lattuga, pomodori, carote, cetrioli)', C_VERD, 20, 1.0, 3.0, 0.2,
     'Media CREA')
food('pomodorini', 'Pomodorini', C_VERD, 18, 0.9, 2.7, 0.2, 'USDA')
food('mais', 'Mais dolce in scatola (sgocciolato)', C_VERD, 90, 3.0, 16.0, 1.2, 'Media etichette')

# Condimenti e dispensa
food('olio', "Olio extravergine d'oliva", C_COND, 899, 0, 0, 99.9, 'CREA', note='1 cucchiaino ≈ 5 g')
food('passata', 'Passata di pomodoro', C_COND, 34, 1.5, 5.2, 0.2, 'Media etichette')
food('pesto', 'Pesto genovese', C_COND, 500, 5.0, 6.0, 50.0, 'Media etichette')
food('ketchup', 'Ketchup', C_COND, 102, 1.2, 23.2, 0.1, 'Etichetta Heinz')
food('bbq', 'Salsa BBQ', C_COND, 160, 1.0, 38.0, 0.3, 'Media etichette')
food('soia', 'Salsa di soia', C_COND, 77, 10.3, 3.2, 0, 'Etichetta Kikkoman')
food('miele', 'Miele', C_COND, 320, 0.4, 80.0, 0, 'Media etichette')
food('marmellata0', 'Marmellata zero zuccheri', C_COND, 60, 0.5, 13.0, 0.2, 'Media etichette (con dolcificanti)')
food('mandorle', 'Mandorle', C_COND, 600, 22.0, 5.0, 52.0, 'Media etichette')
food('nocciole', 'Nocciole', C_COND, 650, 14.0, 6.0, 62.0, 'Media etichette')
food('noci', 'Noci', C_COND, 670, 15.0, 4.0, 65.0, 'Media etichette')
food('burro_arachidi', "Burro d'arachidi 100%", C_COND, 610, 25.0, 12.0, 50.0, 'Media etichette')
food('cioccolato85', 'Cioccolato fondente 85%', C_COND, 590, 12.5, 15.0, 52.0, 'Media etichette')

# Integratori e snack
food('whey', 'Whey Prozis 100% Real Whey (Brownie)', C_INT, 376, 72.0, 7.3, 6.7, 'Etichetta (Open Food Facts)',
     note='1 scoop = 30 g')
food('barretta', 'Barretta proteica (~20 g proteine)', C_INT, 364, 36.4, 29.1, 13.6, 'Media etichette', u=55,
     note='1 barretta ≈ 55 g')
food('crema_proteica', 'Crema proteica alle nocciole', C_INT, 510, 22.0, 25.0, 36.0, 'Media etichette')


# ---------------------------------------------------------------------------
# RICETTE / OPZIONI SCELTE
# item: (food, grammi) oppure (food, grammi_base, min, max, passo)  -> regolabile
# ---------------------------------------------------------------------------
R = {}


def rec(code, kind, name, how, items):
    R[code] = dict(code=code, kind=kind, name=name, how=how, items=items)


# Merenda 1 (09:30)
rec('M1-A', 'm1', 'Panino integrale con bresaola, Philadelphia light e mela',
    'Spalma il Philadelphia sul pane, aggiungi la bresaola. Carta stagnola e mela intera nello zaino.',
    [('pane_int', 100, 80, 130, 5), ('bresaola', 50, 40, 70, 5), ('phila', 20, 15, 25, 5), ('mela', 150)])
rec('M1-B', 'm1', 'Panino integrale con tacchino arrosto, sottiletta light e mandorle',
    'Panino con tacchino e 1 sottiletta; mandorle in un sacchettino.',
    [('pane_int', 100, 80, 130, 5), ('tacchino_arrosto', 70, 60, 90, 10), ('sottiletta', 20),
     ('mandorle', 15, 10, 20, 5)])
rec('M1-C', 'm1', 'Piadina integrale con cotto magro, mozzarella light e kiwi',
    'Piadina scaldata la sera prima, farcita, chiusa a rotolo nella stagnola. Kiwi intero.',
    [('piadina', 80, 70, 110, 5), ('cotto', 60, 50, 80, 10), ('mozz_light', 40, 30, 50, 10), ('kiwi', 75)])
rec('M1-D', 'm1', 'Crackers integrali, bresaola, mandorle e mela',
    'Due pacchetti di crackers, bresaola in un foglio di carta da forno, mandorle a parte, mela intera.',
    [('crackers', 50), ('bresaola', 60, 50, 80, 10), ('mandorle', 15, 10, 20, 5), ('mela', 150)])
rec('M1-E', 'm1', 'Toast freddo di pancarré integrale con cotto, sottiletta e pera',
    '3 fette di pancarré (tostate la sera prima se ti piace), cotto e 1 sottiletta. Pera intera.',
    [('pancarre', 80, 55, 110, 5), ('cotto', 70, 50, 90, 10), ('sottiletta', 20), ('pera', 150)])

# Merenda 2 (12:10)
rec('M2-B', 'm2', 'Crackers integrali, bresaola, pera e nocciole',
    '1 pacchetto di crackers, bresaola, pera intera, nocciole in un sacchettino.',
    [('crackers', 25), ('bresaola', 40, 40, 60, 5), ('pera', 150), ('nocciole', 10, 5, 15, 5)])
rec('M2-E', 'm2', 'Mini panino di segale con tacchino arrosto e 2 kiwi',
    'Panino piccolo di segale con il tacchino; 2 kiwi interi (li sbucci con le mani o li tagli a metà a casa).',
    [('pane_segale', 60, 40, 80, 5), ('tacchino_arrosto', 60, 40, 80, 10), ('kiwi', 150)])
rec('M2-F', 'm2', 'Barretta proteica e mela',
    'Scegli barrette con circa 20 g di proteine e ≤ 210 kcal.',
    [('barretta', 55), ('mela', 150, 150, 220, 10)])

# Pranzi (14:30)
rec('P-A', 'pranzo', 'Pasta al ragù di manzo 5% + insalata',
    "Rosola il macinato senza olio, aggiungi la passata e cuoci 15'. Olio a crudo sulla pasta, parmigiano sopra.",
    [('pasta', 100, 50, 130, 5), ('manzo5', 100, 90, 140, 10), ('passata', 120), ('olio', 5, 3, 10, 1),
     ('parmigiano', 10), ('insalata', 150)])
rec('P-B', 'pranzo', 'Riso basmati con pollo al curry (o paprika/soia) + verdure crude',
    'Pollo a straccetti in padella antiaderente con curry o paprika, sfuma con la soia. Olio a crudo.',
    [('riso', 100, 50, 130, 5), ('pollo', 140, 120, 180, 10), ('olio', 8, 5, 14, 1), ('soia', 10),
     ('insalata', 150)])
rec('P-C', 'pranzo', 'Pasta al tonno e pomodoro',
    "Passata in padella 5', tonno sgocciolato alla fine, olio a crudo. Pomodorini crudi a parte o nel piatto.",
    [('pasta', 100, 50, 130, 5), ('tonno_nat', 100, 80, 130, 10), ('passata', 120), ('olio', 8, 5, 14, 1),
     ('pomodorini', 100)])
rec('P-D', 'pranzo', 'Burger di manzo fatto in casa nel panino + patate in air fryer',
    "Burger schiacciato sottile, piastra 3' per lato. Patate a spicchi in air fryer 200 °C per 18-20' con spezie, olio a crudo dopo.",
    [('pane_int', 80, 60, 100, 10), ('manzo5', 130, 110, 160, 10), ('sottiletta', 20), ('insalata', 60),
     ('ketchup', 15), ('patate', 200, 100, 320, 10), ('olio', 5, 3, 10, 1)])
rec('P-E', 'pranzo', 'Pollo alla piastra + patate in air fryer + insalata + pane',
    "Patate a cubetti in air fryer 200 °C per 20' con paprika, rosmarino e aglio; olio a crudo alla fine.",
    [('pollo', 150, 130, 190, 10), ('patate', 350, 150, 450, 10), ('olio', 8, 5, 14, 1), ('insalata', 150),
     ('pane_int', 40, 0, 70, 10)])
rec('P-F', 'pranzo', 'Pasta al pesto con pollo e pomodorini',
    'Pollo a cubetti in padella; pasta condita con pesto e pollo, pomodorini crudi tagliati sopra.',
    [('pasta', 100, 50, 130, 5), ('pesto', 20, 20, 25, 5), ('pollo', 120, 100, 160, 10), ('pomodorini', 100),
     ('parmigiano', 5)])
rec('P-G', 'pranzo', 'Piadina integrale con pollo e mozzarella light + banana',
    'Piadina scaldata in padella, pollo alla piastra a straccetti, mozzarella, lattuga e pomodoro.',
    [('piadina', 100, 70, 120, 5), ('pollo', 120, 100, 160, 10), ('mozz_light', 50, 30, 70, 10),
     ('insalata', 80), ('banana', 120, 0, 150, 10)])

# Post-workout (18:00)
rec('PW-A', 'pw', 'Whey in acqua + banana',
    '1 scoop (30 g) di whey Brownie shakerato con 300 ml di acqua, subito dopo il tapis. Banana intera.',
    [('whey', 30), ('banana', 120)])

# Cene (19:00)
rec('C-A', 'cena', 'Salmone al forno + patate in air fryer + insalata',
    "Salmone al forno 180 °C per 15-18' con limone e pepe. Patate in air fryer.",
    [('salmone', 150, 120, 180, 10), ('patate', 250, 100, 400, 10), ('insalata', 150), ('olio', 5, 3, 10, 1)])
rec('C-B', 'cena', 'Pollo BBQ o alla paprika + riso basmati + verdure crude',
    'Pollo a fette alla piastra, salsa BBQ a fine cottura (o paprika dolce). Riso bollito.',
    [('pollo', 180, 140, 210, 10), ('riso', 70, 30, 110, 5), ('insalata', 200), ('olio', 5, 5, 14, 1),
     ('bbq', 15)])
rec('C-C', 'cena', 'Burger di manzo al piatto con sottiletta + patate in air fryer',
    'Burger alla piastra, sottiletta sopra a fuoco spento. Patate in air fryer, ketchup a parte.',
    [('manzo5', 150, 130, 180, 10), ('sottiletta', 20), ('patate', 250, 100, 400, 10), ('insalata', 150),
     ('olio', 5, 3, 12, 1), ('ketchup', 15)])
rec('C-D', 'cena', 'Orata al forno + patate in air fryer + insalata',
    "Filetti di orata in forno 180 °C per 12-15' con prezzemolo e limone.",
    [('orata', 200, 170, 250, 10), ('patate', 250, 100, 400, 10), ('insalata', 150), ('olio', 8, 5, 14, 1)])
rec('C-E', 'cena', 'Merluzzo al forno + pane integrale + insalata',
    "Merluzzo in forno 180 °C per 15' con pomodorini, olive e origano (o al vapore).",
    [('merluzzo', 250, 200, 320, 10), ('pane_int', 100, 30, 130, 10), ('insalata', 150), ('olio', 10, 5, 18, 1)])
rec('C-F', 'cena', 'Uova strapazzate con albumi + pane integrale + pomodorini',
    'Strapazzate in padella antiaderente con un filo d\'olio, parmigiano a fine cottura.',
    [('uovo', 100), ('albume', 150, 100, 250, 10), ('pane_int', 80, 30, 110, 10), ('pomodorini', 150),
     ('parmigiano', 10), ('olio', 5, 3, 10, 1)])
rec('C-G', 'cena', 'Polpette di manzo al sugo + pane integrale + insalata',
    "Polpette con macinato e parmigiano, 12' in air fryer a 190 °C, poi 5' nella passata calda.",
    [('manzo5', 150, 130, 180, 10), ('parmigiano', 10), ('passata', 150), ('pane_int', 70, 30, 110, 10),
     ('insalata', 150), ('olio', 5, 3, 12, 1)])
rec('C-H', 'cena', 'Lonza alla piastra + patate in air fryer + insalata',
    'Fettine di lonza alla piastra ben calda, 2-3 minuti per lato, rosmarino e pepe.',
    [('lonza', 180, 150, 210, 10), ('patate', 250, 100, 400, 10), ('insalata', 150), ('olio', 5, 3, 12, 1)])
rec('C-I', 'cena', 'Tonno fresco alla piastra + riso basmati + verdure crude',
    'Trancio di tonno scottato 1-2 minuti per lato, salsa di soia e sesamo a piacere.',
    [('tonno_fresco', 180, 150, 210, 10), ('riso', 70, 30, 110, 5), ('insalata', 150), ('olio', 5, 5, 14, 1),
     ('soia', 10)])
rec('C-J', 'cena', '"Piadizza" al forno: piadina, passata, mozzarella light e cotto',
    "Piadina con passata, mozzarella a pezzi e cotto; forno 200 °C per 8-10'. Insalata a parte.",
    [('piadina', 100, 70, 130, 5), ('passata', 60), ('mozz_light', 80, 60, 110, 10), ('cotto', 40, 30, 70, 10),
     ('insalata', 150)])

# Spuntini (merenda OFF / dopocena)
rec('S-A', 'spuntino', 'Yogurt greco 0% con frutti di bosco e miele', 'Anche con frutti di bosco surgelati scongelati.',
    [('yogurt', 170, 150, 250, 10), ('frutti_bosco', 100), ('miele', 5)])
rec('S-B', 'spuntino', 'Yogurt greco 0% con noci', 'Noci spezzettate sopra, un pizzico di cannella se ti va.',
    [('yogurt', 170, 120, 220, 10), ('noci', 15, 10, 20, 5)])
rec('S-C', 'spuntino', 'Fiocchi di latte con ananas', 'Ananas a cubetti (fresco o al naturale sgocciolato).',
    [('fiocchi', 150, 100, 200, 10), ('ananas', 100)])
rec('S-E', 'spuntino', 'Mela e cioccolato fondente 85%', 'Lo sfizio: ha poche proteine, usalo al massimo 1-2 volte a settimana.',
    [('mela', 150, 150, 200, 10), ('cioccolato85', 15, 10, 20, 5)])

# Colazioni weekend
rec('B-B', 'colazione', 'Pancake proteici (avena, albumi, banana) con yogurt e frutti di bosco',
    "Frulla avena, albumi e banana; padella antiaderente unta con l'olio, 2' per lato. Sopra yogurt, frutti di bosco e miele.",
    [('avena', 50, 40, 70, 5), ('albume', 150), ('banana', 60), ('olio', 2), ('yogurt', 100, 80, 150, 10),
     ('frutti_bosco', 80), ('miele', 5, 5, 10, 5)])
rec('B-C', 'colazione', 'Uova strapazzate con albumi + toast integrale + kiwi',
    'Strapazzate morbide con sale e pepe; pane tostato.',
    [('uovo', 100), ('albume', 100, 80, 160, 10), ('olio', 3), ('pane_int', 70, 50, 100, 10), ('kiwi', 150)])
rec('B-D', 'colazione', 'Yogurt bowl con Special K Protein, frutti di bosco, miele e mandorle',
    'Tutto in una ciotola: yogurt alla base, cereali e frutta sopra.',
    [('yogurt', 250, 200, 300, 10), ('special_k', 35, 30, 50, 5), ('frutti_bosco', 100), ('miele', 10),
     ('mandorle', 15, 10, 20, 5)])
rec('B-F', 'colazione', "Colazione all'italiana proteica: latte al brownie + fette biscottate",
    'Whey sciolta nel latte (shaker o frullino). Fette con marmellata zero e crema proteica.',
    [('latte_ps', 250), ('whey', 20, 15, 30, 5), ('fette_bisc', 40, 30, 50, 10), ('marmellata0', 20),
     ('crema_proteica', 15, 10, 20, 5)])
rec('B-G', 'colazione', 'Toast salato con cotto e sottiletta + spremuta',
    '3 fette di pancarré tostate con cotto e sottiletta; spremuta di 2 arance.',
    [('pancarre', 75, 50, 110, 5), ('cotto', 80, 60, 110, 10), ('sottiletta', 20), ('spremuta', 200, 150, 250, 50)])

# Frutto (spuntino del sabato mattina) ~80 kcal
rec('F-A', 'frutto', 'Mela', '', [('mela', 150, 130, 170, 10)])
rec('F-B', 'frutto', 'Pera', '', [('pera', 140, 120, 160, 10)])
rec('F-C', 'frutto', '2 kiwi', '', [('kiwi', 130, 120, 150, 10)])
rec('F-D', 'frutto', 'Arancia', '', [('arancia', 170, 150, 190, 10)])
rec('F-E', 'frutto', 'Fragole', '', [('fragole', 250, 220, 280, 10)])

# ---------------------------------------------------------------------------
# FASCE (slot) con target: kcal, P, C, F
# ---------------------------------------------------------------------------
SLOTS = {
    'm1':          dict(kind='m1', t=(440, 27, 52, 13)),
    'm2':          dict(kind='m2', t=(300, 18, 36, 9)),
    'pranzo_on':   dict(kind='pranzo', t=(590, 35, 80, 15)),
    'pranzo_off':  dict(kind='pranzo', t=(440, 36, 36, 16)),
    'pranzo_we':   dict(kind='pranzo', t=(550, 40, 50, 19)),
    'pw':          dict(kind='pw', t=None),
    'cena':        dict(kind='cena', t=(500, 35, 48, 21)),
    'cena_light':  dict(kind='cena', t=(400, 42, 22, 16)),
    'spuntino':    dict(kind='spuntino', t=(170, 18, 14, 6)),
    'colazione':   dict(kind='colazione', t=(450, 32, 50, 13)),
    'frutto':      dict(kind='frutto', t=(80, 1, 18, 0)),
}


def line(fid, g):
    f = F[fid]
    return dict(f=fid, g=g, k=r0(f['k'] * g / 100), p=r1(f['p'] * g / 100), c=r1(f['c'] * g / 100),
                fa=r1(f['f'] * g / 100))


def totals(lines):
    k = sum(l['k'] for l in lines)
    p = r1(sum(l['p'] for l in lines))
    c = r1(sum(l['c'] for l in lines))
    fa = r1(sum(l['fa'] for l in lines))
    return k, p, c, fa


def tune(code, target):
    items = R[code]['items']
    if target is None:
        return [(it[0], it[1]) for it in items]
    ranges = []
    for it in items:
        if len(it) == 2:
            ranges.append([it[1]])
        else:
            _, base, lo, hi, st = it
            ranges.append(list(range(lo, hi + 1, st)))
    K, P, Cc, Fa = target
    best, best_score = None, None
    for combo in itertools.product(*ranges):
        ls = [line(items[i][0], g) for i, g in enumerate(combo) if g > 0]
        k, p, c, fa = totals(ls)
        dk = abs(k - K)
        score = (dk / 4) ** 2 * (1 if dk <= 8 else 50) + ((p - P) / 4) ** 2 + ((c - Cc) / 8) ** 2 + ((fa - Fa) / 3) ** 2
        # piccola preferenza per restare vicini alla grammatura base
        score += sum(abs(g - (it[1])) for g, it in zip(combo, items)) * 0.0005
        if best_score is None or score < best_score:
            best, best_score = combo, score
    return [(items[i][0], g) for i, g in enumerate(best) if g > 0]


VARIANTS = {}  # (code, slot) -> [(food, g)]
for slot, s in SLOTS.items():
    for code, r in R.items():
        if r['kind'] == s['kind']:
            VARIANTS[(code, slot)] = tune(code, s['t'])

# ---------------------------------------------------------------------------
# SETTIMANA TIPO (scelte di default; nel sito ogni pasto si può scambiare)
# ---------------------------------------------------------------------------
DAYTYPES = {
    'ON':  dict(label='Giorno ON · scuola + palestra', target=(2050, 140, 249, 55), slots=[
        ('09:30', 'Merenda 1 (intervallo)', 'm1'), ('12:10', 'Merenda 2 (intervallo)', 'm2'),
        ('14:30', 'Pranzo · pre-workout', 'pranzo_on'), ('18:00', 'Post-workout', 'pw'),
        ('19:00', 'Cena', 'cena')]),
    'OFF_S': dict(label='Giorno OFF · scuola', target=(1750, 140, 167, 58), slots=[
        ('09:30', 'Merenda 1 (intervallo)', 'm1'), ('12:10', 'Merenda 2 (intervallo)', 'm2'),
        ('14:30', 'Pranzo', 'pranzo_off'), ('17:30', 'Merenda', 'spuntino'),
        ('19:00', 'Cena', 'cena_light')]),
    'OFF_W': dict(label='Giorno OFF · weekend', target=(1750, 140, 167, 58), slots=[
        ('09:30', 'Colazione', 'colazione'), ('11:30', 'Spuntino', 'frutto'),
        ('13:30', 'Pranzo', 'pranzo_we'), ('17:30', 'Merenda', 'spuntino'), ('20:00', 'Cena', 'cena')]),
    'FREE': dict(label='Giorno OFF · pasto libero', target=(1750, 140, 167, 58), slots=[
        ('09:30', 'Colazione', 'colazione'), ('13:30', 'Pranzo LIBERO', 'free'),
        ('17:30', 'Merenda', 'spuntino'), ('20:00', 'Cena leggera', 'cena_light')]),
}

WEEK = [
    dict(d='lun', name='Lunedì', type='ON', wo='TA', pick=['M1-A', 'M2-B', 'P-A', 'PW-A', 'C-A']),
    dict(d='mar', name='Martedì', type='ON', wo='LA', pick=['M1-B', 'M2-E', 'P-B', 'PW-A', 'C-G']),
    dict(d='mer', name='Mercoledì', type='OFF_S', wo=None, pick=['M1-C', 'M2-F', 'P-C', 'S-A', 'C-F']),
    dict(d='gio', name='Giovedì', type='ON', wo='TB', pick=['M1-D', 'M2-B', 'P-D', 'PW-A', 'C-D']),
    dict(d='ven', name='Venerdì', type='ON', wo='LB', pick=['M1-E', 'M2-E', 'P-F', 'PW-A', 'C-I']),
    dict(d='sab', name='Sabato', type='OFF_W', wo=None, pick=['B-B', 'F-E', 'P-E', 'S-B', 'C-J']),
    dict(d='dom', name='Domenica', type='FREE', wo=None, pick=['B-D', None, 'S-C', 'C-B']),
]


def meal_lines(code, slot):
    return [line(f, g) for f, g in VARIANTS[(code, slot)]]


def report():
    out = []
    ok = True
    for day in WEEK:
        dt = DAYTYPES[day['type']]
        dk = dp = dc = dfa = 0
        out.append(f"\n{day['name'].upper()} — {dt['label']}  target {dt['target']}")
        for (time, label, slot), code in zip(dt['slots'], day['pick']):
            if slot == 'free':
                out.append(f"  {time} {label}: pasto libero (non conteggiato)")
                continue
            ls = meal_lines(code, slot)
            k, p, c, fa = totals(ls)
            dk += k; dp += p; dc += c; dfa += fa
            items = ', '.join(f"{F[l['f']]['n'].split(' (')[0]} {l['g']}g" for l in ls)
            out.append(f"  {time} {code:5s} {k:4d} kcal P{p:5.1f} C{c:5.1f} F{fa:5.1f} | {items}")
        dp, dc, dfa = r1(dp), r1(dc), r1(dfa)
        out.append(f"  TOTALE {dk} kcal · P {dp} · C {dc} · F {dfa}")
        if day['type'] != 'FREE':
            tk = dt['target'][0]
            if abs(dk - tk) > 25:
                ok = False
                out.append('  !!! fuori tolleranza kcal')
    return '\n'.join(out), ok


def swap_ranges():
    """Min/max dei totali giornalieri su TUTTE le combinazioni possibili di scambi."""
    out = []
    for tname, dt in DAYTYPES.items():
        if tname == 'FREE':
            continue
        per_slot = []
        for _, _, slot in dt['slots']:
            kind = SLOTS[slot]['kind']
            per_slot.append([totals(meal_lines(code, slot)) for code in R if R[code]['kind'] == kind])
        ks, ps, cs, fs = [], [], [], []
        for combo in itertools.product(*per_slot):
            ks.append(sum(x[0] for x in combo)); ps.append(sum(x[1] for x in combo))
            cs.append(sum(x[2] for x in combo)); fs.append(sum(x[3] for x in combo))
        out.append(f"{tname:6s} combinazioni {len(ks):6d} | kcal {min(ks)}–{max(ks)} | P {min(ps):.0f}–{max(ps):.0f}"
                   f" | C {min(cs):.0f}–{max(cs):.0f} | F {min(fs):.0f}–{max(fs):.0f}")
    return '\n'.join(out)


# ---------------------------------------------------------------------------
# EQUIVALENZE (sostituzioni) calcolate dai valori del database
# ---------------------------------------------------------------------------
def equivalents():
    groups = [
        ('Fonti proteiche · stesse proteine di 100 g di petto di pollo', 'pollo', 100, 'p',
         ['tacchino', 'vitello', 'lonza', 'manzo5', 'merluzzo', 'orata', 'salmone', 'tonno_fresco', 'tonno_nat',
          'trota', 'albume', 'bresaola', 'tacchino_arrosto']),
        ('Carboidrati · stessi carboidrati di 100 g di pasta (cruda)', 'pasta', 100, 'c',
         ['riso', 'patate', 'pane_int', 'pane_segale', 'piadina', 'pancarre', 'crackers', 'gallette', 'avena']),
        ('Grassi · stessi grassi di 10 g di olio EVO', 'olio', 10, 'f',
         ['mandorle', 'nocciole', 'noci', 'burro_arachidi', 'pesto', 'parmigiano']),
    ]
    res = []
    for title, ref, g, key, lst in groups:
        amount = F[ref][key] * g / 100
        rows = []
        for fid in lst:
            eq = amount / F[fid][key] * 100
            eq = int(5 * math.floor(eq / 5 + 0.5)) if eq >= 20 else r0(eq)
            rows.append(dict(f=fid, g=eq))
        res.append(dict(title=title, ref=ref, g=g, rows=rows))
    return res


# ---------------------------------------------------------------------------
# SCHEDA TORSO / LIMBS
# ---------------------------------------------------------------------------
def ex(id, name, sets, lo, hi, rest, start, inc, cue, sup=None, unit='reps', kg=None):
    d = dict(id=id, n=name, s=sets, lo=lo, hi=hi, rest=rest, start=start, inc=inc, cue=cue, unit=unit)
    if sup:
        d['sup'] = sup
    if kg is not None:
        d['kg'] = kg
    return d


WORKOUTS = [
    dict(id='TA', day='Lunedì', name='Torso A', focus='Petto + larghezza dorsali', ex=[
        ex('TA1', 'Chest Press', 3, 6, 10, 150, '29 kg', 2.5,
           'Scapole addotte e basse, schiena incollata allo schienale. 2-3" in discesa, spingi senza bloccare i gomiti.', kg=29),
        ex('TA2', 'Lat Pulldown · presa larga prona', 3, 8, 10, 120, '34–36 kg', 2.5,
           'Petto alto verso la barra, gomiti verso le tasche. Niente slancio col busto, controlla la risalita.', kg=34),
        ex('TA3', 'Pec Deck', 3, 10, 15, 90, 'da testare', 2.5,
           'Gomiti leggermente piegati e fissi, abbraccia un albero. Pausa di 1" a braccia chiuse.'),
        ex('TA4', 'Low Row · presa neutra (triangolo)', 3, 10, 12, 120, '21–23 kg', 2.5,
           'Busto fermo e dritto, tira coi gomiti verso i fianchi, pausa 1" con le scapole strette.', kg=21),
        ex('TA5', 'Alzate laterali al cavo · 1 braccio', 3, 12, 15, 60, '4–5 kg', 1.25,
           'Busto leggermente inclinato, gomito appena piegato, porta il braccio "in fuori" fino all\'altezza della spalla.', kg=4),
        ex('TA6', 'Reverse Pec Deck', 3, 12, 15, 60, 'da testare', 2.5,
           'Braccia quasi tese, pensa ad "allargare" più che a stringere le scapole. Nessuno slancio.'),
    ]),
    dict(id='LA', day='Martedì', name='Limbs A', focus='Quadricipiti + braccia', ex=[
        ex('LA1', 'Leg Press', 3, 6, 10, 165, '118 kg', 5,
           'Piedi a larghezza spalle al centro della pedana. Scendi finché il bacino resta appoggiato, non bloccare le ginocchia.', kg=118),
        ex('LA2', 'Leg Curl', 3, 8, 12, 90, '50–52 kg', 5,
           'Bacino schiacciato sul pad, piega fino in fondo, risalita lenta in 2-3".', kg=50),
        ex('LA3', 'Leg Extension', 3, 10, 15, 90, '27–29 kg', 2.5,
           'Schiena appoggiata, estendi completamente con 1" di pausa in alto, scendi controllato.', kg=27),
        ex('LA4', 'Bayesian Curl al cavo basso', 3, 10, 12, 0, 'test ~5–7,5 kg', 1.25,
           'Di spalle al cavo, braccio dietro il busto: massimo allungamento del bicipite. Gomito fermo.', sup='4a'),
        ex('LA5', 'Triceps Pushdown', 3, 10, 12, 75, '12–13 kg', 2.5,
           'Gomiti incollati ai fianchi, estendi completamente e apri leggermente le mani in fondo.', sup='4b', kg=12),
        ex('LA6', 'Hammer Curl con corda', 2, 10, 12, 0, 'da testare', 2.5,
           'Presa neutra sulla corda, gomiti fermi, sali fino alle spalle senza dondolare.', sup='5a'),
        ex('LA7', 'Overhead Extension con corda', 2, 12, 15, 60, 'da testare', 2.5,
           'Di spalle al cavo, gomiti puntati in avanti e fermi, massimo allungamento dietro la testa.', sup='5b'),
        ex('LA8', 'Cable Crunch', 3, 10, 15, 60, 'da testare', 2.5,
           'In ginocchio, corda vicino alla fronte, arrotola la colonna portando i gomiti verso le cosce. Il bacino non si muove.'),
        ex('LA9', 'Plank frontale', 2, 45, 60, 45, '—', 10,
           'Gomiti sotto le spalle, glutei e addome contratti, corpo in linea. Non far cadere il bacino.', unit='sec'),
    ]),
    dict(id='TB', day='Giovedì', name='Torso B', focus='Spessore schiena + spalle', ex=[
        ex('TB1', 'Panca inclinata 30° con manubri', 3, 8, 12, 150, '8 kg/manubrio', 2,
           'Scapole indietro e in basso, manubri che scendono all\'altezza del petto alto, gomiti a ~45°.', kg=8),
        ex('TB2', 'T-Bar Row con petto in appoggio', 3, 8, 10, 120, 'da testare', 2.5,
           'Petto sempre appoggiato, tira coi gomiti verso il bacino, pausa di 1" in alto.'),
        ex('TB3', 'Shoulder Press Machine', 3, 8, 10, 120, '13 kg (obiettivo 18)', 2.5,
           'Schiena appoggiata, impugnature all\'altezza delle orecchie, spingi senza inarcare la lombare.', kg=13),
        ex('TB4', 'Lat Pulldown · presa neutra stretta', 3, 10, 12, 90, '32–34 kg', 2.5,
           'Tira verso lo sterno con i gomiti vicini al corpo, allunga bene in alto senza perdere la postura.', kg=32),
        ex('TB5', 'Pec Deck', 2, 12, 15, 75, 'come lunedì', 2.5,
           'Stesso gesto del lunedì, più ripetizioni: cerca la contrazione, non il carico.'),
        ex('TB6', 'Alzate laterali alla macchina (o al cavo)', 4, 12, 15, 60, '10–11 kg', 2.5,
           'Spalle basse, sali fino all\'orizzontale guidando coi gomiti, discesa lenta.', kg=10),
        ex('TB7', 'Reverse Pec Deck', 2, 15, 20, 60, 'come lunedì', 2.5,
           'Più ripetizioni del lunedì: tensione continua sui deltoidi posteriori.'),
    ]),
    dict(id='LB', day='Venerdì', name='Limbs B', focus='Femorali + braccia', ex=[
        ex('LB1', 'Leg Curl', 4, 8, 12, 90, '52 kg', 5,
           'Primo esercizio: massima qualità. Risalita lenta, niente colpi di bacino.', kg=52),
        ex('LB2', 'Leg Press · piedi alti e larghi', 3, 10, 12, 150, '100–105 kg', 5,
           'Piedi alti sulla pedana: lavorano di più glutei e femorali. Spingi coi talloni.', kg=100),
        ex('LB3', 'Leg Extension', 3, 12, 15, 75, '25–27 kg', 2.5,
           'Più ripetizioni del martedì, 1" di pausa in alto su ogni ripetizione.', kg=25),
        ex('LB4', 'Preacher Curl alla macchina', 3, 8, 12, 0, '13–15 kg', 2.5,
           'Braccio ben appoggiato al cuscino, scendi fino quasi a distendere, sali senza staccare i gomiti.', sup='4a', kg=13),
        ex('LB5', 'Overhead Extension con corda', 3, 10, 12, 75, 'come martedì', 2.5,
           'Gomiti fermi e puntati in avanti, allungamento completo dietro la testa.', sup='4b'),
        ex('LB6', 'Hammer Curl con corda', 2, 10, 12, 0, 'come martedì', 2.5,
           'Presa neutra, nessun dondolio, discesa in 2".', sup='5a'),
        ex('LB7', 'Triceps Pushdown', 2, 12, 15, 60, '11–12 kg', 2.5,
           'Gomiti ai fianchi, estensione completa, 1" di contrazione in basso.', sup='5b', kg=11),
        ex('LB8', 'Crunch Machine', 3, 10, 15, 60, 'da testare', 2.5,
           'Espira mentre ti chiudi, arrotola la colonna. Movimento controllato, niente strappi con le braccia.'),
        ex('LB9', 'Side Plank', 2, 30, 45, 30, '— (per lato)', 10,
           'Gomito sotto la spalla, corpo in linea, bacino alto. Tempo per ciascun lato.', unit='sec'),
    ]),
]

# ---------------------------------------------------------------------------
# LIBRERIA ESERCIZI (allenamento live stile Hevy)
# id: (nome, muscolo principale, muscoli secondari, incremento kg, unità, attrezzo)
# ---------------------------------------------------------------------------
EXLIB_BASE = {
    'chest_press': ('Chest Press', 'Petto', ['Tricipiti', 'Deltoidi anteriori'], 2.5, 'reps', 'Macchina'),
    'lat_pulldown_wide': ('Lat Pulldown · presa larga prona', 'Dorsali', ['Bicipiti'], 2.5, 'reps', 'Cavo'),
    'pec_deck': ('Pec Deck', 'Petto', [], 2.5, 'reps', 'Macchina'),
    'low_row': ('Low Row · presa neutra', 'Dorsali', ['Bicipiti', 'Deltoidi posteriori'], 2.5, 'reps', 'Cavo'),
    'lateral_raise_cable': ('Alzate laterali al cavo', 'Deltoidi laterali', [], 1.25, 'reps', 'Cavo'),
    'reverse_pec_deck': ('Reverse Pec Deck', 'Deltoidi posteriori', ['Dorsali'], 2.5, 'reps', 'Macchina'),
    'leg_press': ('Leg Press', 'Quadricipiti', ['Glutei'], 5, 'reps', 'Macchina'),
    'leg_curl': ('Leg Curl', 'Femorali', [], 5, 'reps', 'Macchina'),
    'leg_extension': ('Leg Extension', 'Quadricipiti', [], 2.5, 'reps', 'Macchina'),
    'bayesian_curl': ('Bayesian Curl al cavo', 'Bicipiti', [], 1.25, 'reps', 'Cavo'),
    'triceps_pushdown': ('Triceps Pushdown', 'Tricipiti', [], 2.5, 'reps', 'Cavo'),
    'hammer_curl_rope': ('Hammer Curl con corda', 'Bicipiti', [], 2.5, 'reps', 'Cavo'),
    'overhead_ext_rope': ('Overhead Extension con corda', 'Tricipiti', [], 2.5, 'reps', 'Cavo'),
    'cable_crunch': ('Cable Crunch', 'Addome', [], 2.5, 'reps', 'Cavo'),
    'plank': ('Plank frontale', 'Addome', [], 10, 'sec', 'Corpo libero'),
    'incline_db_press': ('Panca inclinata 30° con manubri', 'Petto', ['Deltoidi anteriori', 'Tricipiti'], 2, 'reps', 'Manubri'),
    'tbar_row': ('T-Bar Row con petto in appoggio', 'Dorsali', ['Bicipiti', 'Deltoidi posteriori'], 2.5, 'reps', 'Macchina'),
    'shoulder_press_machine': ('Shoulder Press Machine', 'Deltoidi anteriori', ['Tricipiti', 'Deltoidi laterali'], 2.5, 'reps', 'Macchina'),
    'lat_pulldown_neutral': ('Lat Pulldown · presa neutra stretta', 'Dorsali', ['Bicipiti'], 2.5, 'reps', 'Cavo'),
    'lateral_raise_machine': ('Alzate laterali alla macchina', 'Deltoidi laterali', [], 2.5, 'reps', 'Macchina'),
    'leg_press_high': ('Leg Press · piedi alti e larghi', 'Glutei', ['Femorali', 'Quadricipiti'], 5, 'reps', 'Macchina'),
    'preacher_curl_machine': ('Preacher Curl alla macchina', 'Bicipiti', [], 2.5, 'reps', 'Macchina'),
    'crunch_machine': ('Crunch Machine', 'Addome', [], 2.5, 'reps', 'Macchina'),
    'side_plank': ('Side Plank', 'Addome', [], 10, 'sec', 'Corpo libero'),
    # esercizi in più, da aggiungere alle routine quando vuoi
    'bench_press_bb': ('Panca piana con bilanciere', 'Petto', ['Tricipiti', 'Deltoidi anteriori'], 2.5, 'reps', 'Bilanciere'),
    'db_bench': ('Panca piana con manubri', 'Petto', ['Tricipiti'], 2, 'reps', 'Manubri'),
    'cable_fly': ('Croci ai cavi', 'Petto', [], 2.5, 'reps', 'Cavo'),
    'pullup': ('Trazioni alla sbarra', 'Dorsali', ['Bicipiti'], 2.5, 'reps', 'Corpo libero'),
    'db_row': ('Rematore con manubrio', 'Dorsali', ['Bicipiti'], 2, 'reps', 'Manubri'),
    'straight_arm_pulldown': ('Pulldown a braccia tese', 'Dorsali', [], 2.5, 'reps', 'Cavo'),
    'face_pull': ('Face Pull', 'Deltoidi posteriori', [], 2.5, 'reps', 'Cavo'),
    'db_shoulder_press': ('Military press con manubri', 'Deltoidi anteriori', ['Tricipiti'], 2, 'reps', 'Manubri'),
    'db_lateral_raise': ('Alzate laterali con manubri', 'Deltoidi laterali', [], 1, 'reps', 'Manubri'),
    'squat_bb': ('Squat con bilanciere', 'Quadricipiti', ['Glutei'], 2.5, 'reps', 'Bilanciere'),
    'hack_squat': ('Hack Squat', 'Quadricipiti', ['Glutei'], 5, 'reps', 'Macchina'),
    'rdl_db': ('Stacco rumeno con manubri', 'Femorali', ['Glutei'], 2, 'reps', 'Manubri'),
    'hip_thrust': ('Hip Thrust', 'Glutei', ['Femorali'], 5, 'reps', 'Bilanciere'),
    'lunges_db': ('Affondi con manubri', 'Quadricipiti', ['Glutei'], 2, 'reps', 'Manubri'),
    'calf_leg_press': ('Calf alla Leg Press', 'Polpacci', [], 5, 'reps', 'Macchina'),
    'calf_standing': ('Calf in piedi', 'Polpacci', [], 5, 'reps', 'Macchina'),
    'db_curl': ('Curl con manubri', 'Bicipiti', [], 1, 'reps', 'Manubri'),
    'incline_db_curl': ('Curl su panca inclinata', 'Bicipiti', [], 1, 'reps', 'Manubri'),
    'dips': ('Dip alle parallele', 'Tricipiti', ['Petto'], 2.5, 'reps', 'Corpo libero'),
    'ez_skullcrusher': ('French press con bilanciere EZ', 'Tricipiti', [], 2.5, 'reps', 'Bilanciere'),
}
# esercizio della scheda → voce della libreria
EX_MAP = {
    'TA1': 'chest_press', 'TA2': 'lat_pulldown_wide', 'TA3': 'pec_deck', 'TA4': 'low_row', 'TA5': 'lateral_raise_cable',
    'TA6': 'reverse_pec_deck', 'LA1': 'leg_press', 'LA2': 'leg_curl', 'LA3': 'leg_extension', 'LA4': 'bayesian_curl',
    'LA5': 'triceps_pushdown', 'LA6': 'hammer_curl_rope', 'LA7': 'overhead_ext_rope', 'LA8': 'cable_crunch', 'LA9': 'plank',
    'TB1': 'incline_db_press', 'TB2': 'tbar_row', 'TB3': 'shoulder_press_machine', 'TB4': 'lat_pulldown_neutral',
    'TB5': 'pec_deck', 'TB6': 'lateral_raise_machine', 'TB7': 'reverse_pec_deck', 'LB1': 'leg_curl', 'LB2': 'leg_press_high',
    'LB3': 'leg_extension', 'LB4': 'preacher_curl_machine', 'LB5': 'overhead_ext_rope', 'LB6': 'hammer_curl_rope',
    'LB7': 'triceps_pushdown', 'LB8': 'crunch_machine', 'LB9': 'side_plank',
}
# foto free-exercise-db (pubblico dominio, Unlicense) in assets/esercizi/<nome>-0.jpg e <nome>-1.jpg
EX_IMG = {
    'chest_press': 'Leverage_Chest_Press', 'lat_pulldown_wide': 'Wide-Grip_Lat_Pulldown', 'pec_deck': 'Butterfly',
    'low_row': 'Seated_Cable_Rows', 'lateral_raise_cable': 'Cable_Seated_Lateral_Raise', 'reverse_pec_deck': 'Reverse_Machine_Flyes',
    'leg_press': 'Leg_Press', 'leg_curl': 'Lying_Leg_Curls', 'leg_extension': 'Leg_Extensions',
    'bayesian_curl': 'Standing_One-Arm_Cable_Curl', 'triceps_pushdown': 'Triceps_Pushdown_-_Rope_Attachment', 'hammer_curl_rope': 'Cable_Hammer_Curls_-_Rope_Attachment',
    'overhead_ext_rope': 'Cable_Rope_Overhead_Triceps_Extension', 'cable_crunch': 'Cable_Crunch', 'plank': 'Plank',
    'incline_db_press': 'Incline_Dumbbell_Press', 'tbar_row': 'Lying_T-Bar_Row', 'shoulder_press_machine': 'Machine_Shoulder_Military_Press',
    'lat_pulldown_neutral': 'V-Bar_Pulldown', 'lateral_raise_machine': 'Side_Lateral_Raise', 'leg_press_high': 'Leg_Press',
    'preacher_curl_machine': 'Machine_Preacher_Curls', 'crunch_machine': 'Ab_Crunch_Machine', 'side_plank': 'Side_Bridge',
    'bench_press_bb': 'Barbell_Bench_Press_-_Medium_Grip', 'db_bench': 'Dumbbell_Bench_Press', 'cable_fly': 'Cable_Crossover',
    'pullup': 'Pullups', 'db_row': 'One-Arm_Dumbbell_Row', 'straight_arm_pulldown': 'Straight-Arm_Pulldown',
    'face_pull': 'Face_Pull', 'db_shoulder_press': 'Dumbbell_Shoulder_Press', 'db_lateral_raise': 'Side_Lateral_Raise',
    'squat_bb': 'Barbell_Squat', 'hack_squat': 'Hack_Squat', 'rdl_db': 'Stiff-Legged_Dumbbell_Deadlift',
    'hip_thrust': 'Barbell_Hip_Thrust', 'lunges_db': 'Dumbbell_Lunges', 'calf_leg_press': 'Calf_Press_On_The_Leg_Press_Machine',
    'calf_standing': 'Standing_Calf_Raises', 'db_curl': 'Dumbbell_Bicep_Curl', 'incline_db_curl': 'Incline_Dumbbell_Curl',
    'dips': 'Dips_-_Triceps_Version', 'ez_skullcrusher': 'EZ-Bar_Skullcrusher',
}
# foto di un movimento equivalente (la tua macchina può essere diversa)
EX_EQV = {'lateral_raise_machine', 'bayesian_curl', 'leg_press_high'}
# serie dirette a settimana previste dalla scheda (per le statistiche)
MUSCLE_TARGETS = {'Petto': 11, 'Dorsali': 12, 'Deltoidi laterali': 7, 'Deltoidi posteriori': 5, 'Quadricipiti': 12,
                  'Femorali': 7, 'Bicipiti': 10, 'Tricipiti': 10, 'Addome': 6}


def build_exlib():
    cues = {}
    for w in WORKOUTS:
        for e in w['ex']:
            e['lib'] = EX_MAP[e['id']]
            cues.setdefault(e['lib'], e['cue'])
    lib = {}
    for k, (n, m, sec, inc, unit, eq) in EXLIB_BASE.items():
        lib[k] = dict(id=k, n=n, m=m, sec=sec, inc=inc, unit=unit, eq=eq, cue=cues.get(k, ''))
        if k in EX_IMG:
            lib[k]['img'] = EX_IMG[k]
        if k in EX_EQV:
            lib[k]['eqv'] = 1
    return lib


EXLIB = build_exlib()

TARGETS = dict(ON=dict(k=2050, p=140, c=249, f=55), OFF=dict(k=1750, p=140, c=167, f=58))


def build_data():
    variants = {}
    for (code, slot), items in VARIANTS.items():
        variants.setdefault(slot, {})[code] = [[f, g] for f, g in items]
    recipes = {code: dict(name=r['name'], how=r['how'], kind=r['kind']) for code, r in R.items()}
    return dict(
        version='2026-09-28',
        foods=F,
        recipes=recipes,
        variants=variants,
        daytypes={k: dict(label=v['label'], target=v['target'], slots=v['slots']) for k, v in DAYTYPES.items()},
        week=WEEK,
        workouts=WORKOUTS,
        exlib=EXLIB,
        muscleTargets=MUSCLE_TARGETS,
        targets=TARGETS,
        equivalents=equivalents(),
    )


if __name__ == '__main__':
    txt, ok = report()
    print(txt)
    print('\nIntervalli con qualsiasi scambio:')
    print(swap_ranges())
    data = build_data()
    js = '/* File generato da tools/genera_piano.py — non modificare a mano */\nwindow.PIANO = ' + \
         json.dumps(data, ensure_ascii=False, separators=(',', ':')) + ';\n'
    out = os.path.join(ROOT, 'assets', 'js', 'data.js')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as fh:
        fh.write(js)
    print('\nScritto', out, f'({len(js)} byte)')
    print('VERIFICA:', 'OK' if ok else 'ERRORI')
