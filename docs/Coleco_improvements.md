# Final Fantasy — Coleco Port Improvements vs NES Original

Catalogo delle modifiche/migliorie introdotte rispetto al Final Fantasy NES (USA) nel
porting per ColecoVision. Vivono **assieme** alla parity NES per le meccaniche di
gameplay; sono aggiunte non-distruttive che sfruttano hardware/UX della Coleco o
correggono bug ROM oggettivi.

Aggiornato: 2026-05-08 (sessione 6).

---

## 1. UX / input

### 1.1 Numpad keypad come direct-select
- **Cosa:** Tasti `1`-`4` del keypad Coleco saltano direttamente al CHR
  corrispondente nello schermo party / class-select / (in futuro) target di battle.
- **Perché:** Il keypad è un upgrade hardware Coleco assente sul NES. Sfruttarlo
  evita navigation paddy-style D-pad (slow). Coerente con `design_input.md`.
- **Status:** ✅ implementato in slice22b (class select); da estendere a battle
  command target select e menu inventario.

### 1.2 Tasto `*` come "confirm party"
- **Cosa:** Pulsante dedicato `*` nel keypad per confermare il party post-class-select
  e procedere allo start del gioco. Distinto dai tasti 1-4 (jump CHR).
- **Perché:** Su NES il flow lineare auto-procedeva. Con jump 1-4 serve un
  trigger esplicito. `*` riservato per "commit/done", `#` libero per future use
  (es. cancel/back globale).
- **Status:** ✅ implementato in slice22b. Richiede tutti e 4 CHR named.

### 1.3 Nomi CHR a 6 caratteri (vs NES 4)
- **Cosa:** Buffer nome personaggio aumentato da 4 → 6 char.
- **Perché:** Su NES la limitazione era display/cart constraint (4-char box nel
  battle status). Coleco mode 2 ha più spazio cella (14 col vs ~10 NES). Permette
  nomi più descrittivi (es. "GANDLF" vs "GAND").
- **Costo:** +8 byte save state (4 CHR × 2 byte extra) → ~+1 char nella password
  finale. Trascurabile.
- **Status:** ✅ implementato in slice22b.

### 1.4 NES-parity flow + non-NES enhancements coexist
- **Cosa:** Il flow class-select segue la NES-parity (D-pad cycle, FIRE1 name,
  FIRE2 cycle backward) **+** add-on Coleco (1-4 jump, * confirm).
- **Why:** Player NES-faithful può ignorare il keypad e usare solo joystick →
  esperienza identica al NES. Player Coleco-savvy usa keypad → UX più rapida.

### 1.5 Il negozio: l'acquisto EQUIPAGGIA
- **Cosa:** comprata un'arma o un'armatura, se la classe puo' portarla e il
  posto e' libero (una sola arma; una corazza, uno scudo, un elmo, un guanto)
  viene **indossata subito**. Se il posto e' occupato resta nello zaino, con il
  bit 7 spento, esattamente come sul NES.
- **Perche':** sul NES l'acquisto mette l'oggetto nell'inventario e per
  indossarlo si passa dal MENU (`ReadjustEquipStats`). Il menu qui non esiste
  ancora: senza il passo automatico, comprare non cambierebbe **un solo numero
  visibile** e il gruppo resterebbe disarmato — cioe' meta' delle formule del
  turno fisico continuerebbe a girare su zeri.
- **Le condizioni sono quelle del NES**, non piu' larghe: `IsEquipLegal`
  (bank_0E.asm:9060) prova il permesso di classe e un pezzo per tipo. Cio' che
  NON facciamo e' il "togli l'altro": togliere qualcosa che il giocatore ha
  scelto di indossare non e' compito di un acquisto.
- **Reversibile:** quando arrivera' il menu di equipaggiamento, potra' disfare —
  e a quel punto la scelta si potra' anche rimettere in discussione.
- **DISFACIBILE DA slice74.** Il menu di equipaggiamento c'e' (§1.11): quello
  che il negozio mette addosso si toglie, si passa a un altro e si butta. La
  deviazione resta — comprare equipaggia — ma da comodita', non da condanna.
- **Status:** implementato in slice66 (armi e armature). Validato a MAME,
  44 controlli su 44.

### 1.6 Il divieto di classe si vede PRIMA di comprare
- **Cosa:** nella schermata "a chi lo do?" i personaggi che non possono portare
  la voce puntata sono marcati `NO`.
- **Perche':** sul NES il divieto si scopre solo dal menu, dopo aver pagato: la
  spada comprata al mago resta nello zaino a non servire a niente, e nessuna
  schermata lo dice mai. L'informazione c'e' gia' (i permessi viaggiano col
  listino), mostrarla non costa niente e non toglie nulla a chi vuole comprare
  lo stesso — l'acquisto resta permesso, come sul NES.
- **Status:** implementato in slice66.

### 1.6bis Il negozio di magia dice PERCHE' no
- **Cosa:** nella riga di ogni personaggio il negozio di magia mostra il
  livello dell'incantesimo puntato, quante magie di quel livello quel
  personaggio conosce gia' (`2/3`), e una di tre etichette: `NO` (la classe non
  puo' impararla), `KNOWN` (la sa gia'), `FULL` (i tre posti del livello sono
  occupati).
- **Perche':** sono esattamente i tre rifiuti di `MagicShop_AssertLearn`, e sul
  NES si scoprono **uno alla volta e solo provando** — si sceglie il
  personaggio, si conferma, e solo allora una finestra dice di no. Il conto per
  saperlo prima e' lo stesso che il negozio fa comunque per decidere: mostrarlo
  non aggiunge informazione al gioco, toglie tentativi a vuoto. I rifiuti
  restano tutti al loro posto e con i loro messaggi: chi preme lo stesso vede
  la stessa risposta del NES.
- **Nota di parita':** il tetto di **tre** magie per livello, la scelta fra
  **otto**, e il fatto che imparare non si possa disfare sono NES-fedeli e non
  si toccano — sono il gioco.
- **Status:** implementato in slice67.

### 1.6ter Sottomenu della magia: livelli col tastierino
- **Cosa:** nel sottomenu della magia in battaglia i tasti `1`-`8` saltano
  direttamente al livello, e la pagina (L1-4 / L5-8) **segue** il livello
  scelto invece di essere un comando a parte.
- **Perche':** sul NES la pagina si cambia con un tasto apposito perche' non
  c'e' altro modo. Con otto livelli e tre caselle, arrivare a una magia di
  livello 7 vuol dire contare i passi del cursore -- che e' esattamente il
  lavoro che il tastierino esiste per evitare (vedi 1.1). Le direzioni
  continuano a funzionare identiche per chi le preferisce.
- **Nota:** le CARICHE di ogni livello (`n/m`) si vedono qui e solo qui, come
  sul NES: la striscia di battaglia mostra nome e HP e basta. Non e' una
  mancanza -- in FF1 gli "MP" non sono un serbatoio ma otto contatori, e un
  numero unico sotto gli HP li rappresenterebbe male.
- **Status:** implementato in slice68.

### 1.7 Tastierino nel negozio
- **Cosa:** i tasti `1`-`5` scelgono la voce del listino, `1`-`4` il
  personaggio, senza passare dal cursore.
- **Perche':** stessa ragione di 1.1 — il tastierino e' hardware che il NES non
  aveva. Il D-pad continua a funzionare identico per chi lo ignora.
- **Status:** implementato in slice66.

### 1.8 Il negozio di oggetti mostra QUANTE ne hai gia'
- **Cosa:** accanto a ogni voce del listino, la colonna `IN PACK` con la
  quantita' gia' in zaino. Sul NES quel numero si vede solo uscendo dal negozio
  e aprendo il menu.
- **Perche':** l'unica domanda che ci si fa davanti a un negozio di pozioni e'
  "quante ne ho gia'". Farla costare due schermate e' un attrito senza contenuto
  di gioco. In piu' rende VISIBILE l'acquisto: la quantita' che sale da 0 a 1 e'
  la conferma che il negozio ha funzionato.
- **Status:** implementato in slice71.

### 1.9 Il menu su FIRE2, e i comandi col tastierino
- **Cosa:** FIRE2 apre il menu dall'overworld e dalla citta'; i tasti `1`-`5`
  scelgono ITEM/MAGIC/WEAPON/ARMOR/STATUS e `1`-`4` il personaggio.
- **Perche':** sul NES il menu si apre con START, che sul Coleco non esiste.
  FIRE2 era libero in tutti e due i cicli di gioco. Il tastierino e' la solita
  scorciatoia di 1.1: sul NES arrivare a STATUS costa quattro pressioni.
- **Status:** implementato in slice73.

### 1.10 La schermata delle statistiche mostra TUTTO, INT compreso
- **Cosa:** una schermata sola con le cinque statistiche base, le cinque
  derivate accanto, gli otto contatori di magia, EXP, quanto MANCA al livello
  dopo, e l'equipaggiamento con l'asterisco su cio' che e' indossato.
- **Perche':** sul NES le stesse informazioni sono sparse fra due schermate, e
  `ch_exptonext` e' un campo che il gioco calcola *e non usa mai*. Da noi INT ha
  smesso di essere una statistica morta (§3.3): una statistica che nessuno puo'
  leggere e una statistica che non esiste si somigliano troppo.
- **Nota di parita':** il **totale** da raggiungere sarebbe il dato del ROM; qui
  si mostra la **differenza**, perche' il totale da solo obbliga a fare la
  sottrazione a mente ogni volta.
- **Status:** implementato in slice73.

### 1.11 WEAPON / ARMOR: i tre modi in un tasto, e niente lampeggio (slice74)
- **Cosa:** la griglia dell'equipaggiamento mostra tutte e sedici le caselle del
  gruppo (come il NES) e i tre modi **EQUIP / TRADE / DROP** si scelgono col
  tastierino `1`-`3`, senza entrare e uscire da un sottomenu. Il cursore resta
  sempre sulla griglia: il tasto decide che cosa fa FIRE1.
- **Perche':** sul NES il modo e' un secondo livello (`eq_modecurs`, A per
  entrare, B per uscire — `EnterEquipMenu`, bank_0E.asm:8845) perche' i tasti
  sono due. Con dodici tasti in piu' quel livello e' solo un costo. E' la stessa
  scorciatoia di §1.1, §1.7 e §1.9.
- **Cosa cambia rispetto al NES, in concreto:** togliersi un'arma per darla a un
  altro costava sul NES cinque pressioni (B, giu', A, muovi, A); qui ne costa
  tre.
- **Niente lampeggio:** il NES fa lampeggiare il secondo cursore del TRADE e
  quello della conferma del DROP. Qui i due cursori sono **due caratteri
  diversi** (`>` dove si e', `<` su cio' che si e' preso) e la conferma e'
  scritta a parole. Non e' solo leggibilita': una posizione a schermo che vale
  come prova dev'essere **asseribile** dalla VRAM (regola di slice66), e un
  carattere che c'e' un quadro su due non lo e'.
- **Il resto e' NES-fedele**, comprese le due regole che si notano giocando: un
  pezzo scambiato esce **spento** da tutte e due le parti (il permesso del nuovo
  proprietario non l'ha chiesto nessuno), e **togliersi** qualcosa non passa mai
  dal controllo di classe.
- **Status:** implementato in slice74. Validato a MAME, 64 controlli su 64.

### 1.12 MAGIC fuori dalla battaglia: tre correzioni di intento (slice75)
- **CUR4 rifiuta chi non puo' essere curato.** Sul NES non controlla le
  alterazioni — il disassembly stesso scrive `BUGGED` (bank_0E.asm:6547):
  lanciata su un caduto o un pietrificato ne riempie gli HP, e quello resta
  caduto o pietrificato. Il risultato e' una carica di settimo livello spesa per
  niente **con la schermata che mostra il numero salito**, cioe' il peggior
  genere di bug: quello che sembra aver funzionato. Qui rifiuta come tutta la
  famiglia CURE, e la carica non si consuma.
- **WARP ed EXIT non pagano se non c'e' un posto dove andare.** Sul NES la
  carica si consuma comunque (`DEC ch_magicdata` prima del salto). Da noi il
  rifiuto arriva prima di pagare, come per ogni altro rifiuto del menu.
- **Il tiro non viene piu' dal contatore dei quadri.** Sul NES la quantita'
  curata e' `framecounter` mascherato, un ripiego che il commento del
  disassembly dichiara tale ("make-shift pRNG", bank_0E.asm:6474) perche' fuori
  dalla battaglia il generatore vero non e' inizializzato. Noi uno ce l'abbiamo
  (`svc_battle_rng`). **Gli intervalli restano quelli del NES esatti** — CURE
  16-31, CUR2 32-63, CUR3 64-127, HEAL 16-23, HEL2 32-47, HEL3 64-95: cambia
  solo che il numero non dipende piu' da QUANDO si preme il tasto, che sul NES
  e' sfruttabile per avere sempre la cura massima.
- **Nota di parita', non deviazione:** da una citta' WARP ed EXIT fanno la
  stessa cosa (si torna in overworld alle coordinate d'ingresso), ed e' cosi'
  anche sul NES — con la catena dei teletrasporti corta, WARP salta dentro il
  codice di EXIT (bank_0E.asm:6719).
- **Status:** implementato in slice75. Validato a MAME, 60 controlli su 60.

---

### 1.13 Gli abitanti stanno FERMI (slice76)

**Sul NES gli abitanti di una citta' vagano.** Qui no: stanno dove il ROM li
mette e non si spostano mai.

**Non e' una scelta di gusto, e' il TMS9918.** Il mapman del giocatore e' fatto
di **quattro sprite sovrapposti** (contorno + due colori del corpo +
incarnato), e il TMS ne mostra **quattro per scanline**: un abitante disegnato
come sprite sarebbe il quinto e sparirebbe. E sparirebbe proprio quando lo si
guarda, perche' per parlargli bisogna essergli di fianco -- cioe' sulle sue
stesse scanline.

Gli abitanti sono quindi **tile di fondo**, e le loro quattro tile contengono
il terreno su cui stanno: spostarli vorrebbe dire ricuocerle per ogni casella
calpestabile della mappa.

**Cosa cambia giocando, in concreto:**
- un abitante non si mette mai in mezzo mentre si cammina, e non si perde di
  vista uno con cui si stava parlando. E' una perdita di vita della citta' e un
  guadagno di prevedibilita';
- sul NES un abitante lo si SPINGE (`mapobj_pl`) e si sposta di una casella.
  Qui **blocca**, come un muro. La stessa condizione serve a due cose: rifiuta
  il passo, e "essere girati verso di lui" e' l'unico modo per parlargli.

Reversibile solo con un cambio di tecnica, non di parametro.

### 1.14 Il riquadro di dialogo copre la meta' bassa, sempre (slice76)

Sul NES il riquadro di dialogo si apre in una posizione che dipende dallo
scroll. Qui e' **fisso alle righe 14-23**, sotto il giocatore -- che sta
inchiodato alla cella (15,11) e alto 16 pixel, cioe' righe 11 e 12.

E' una conseguenza del movimento a scatti di macrotile ([[movement-discrete-tile]]):
senza scroll fine, "sotto il giocatore" e' sempre lo stesso posto, e un
riquadro che si sposta non avrebbe niente a cui adattarsi. Chi parla vede
sempre a chi.

Il testo e' **byte per byte quello di FF1**, sciolto dalla compressione DTE del
ROM: 24 colonne e fino a 8 righe, che sono le misure vere dei dialoghi del
gioco (misurate, e l'estrattore si ferma con un errore se un testo le supera).

Tre correzioni al charset rispetto alla tabella del disassembly, tutte
verificate contro cio' che il gioco mostra davvero:
- **$BE e' un APOSTROFO**, non una virgoletta doppia: senza la correzione si
  legge `Lukahn"s` invece di `Lukahn's`;
- **$C3** (non presente nella tabella) e' la tile dei puntini di sospensione,
  che FF1 usa sempre in coppia: diventa un punto, quindi `$C3 $C3` fa `..`;
- **$FF** e' la tile VUOTA, cioe' uno spazio -- lasciarla nulla avrebbe
  spostato a sinistra tutto quel che segue.

## 1bis. Deviazioni dello ZAINO (slice71 + slice73)

### 1bis.1 Le quattro sfere non compaiono nella lista degli oggetti
- **Cosa:** le caselle `$12-$15` esistono nell'inventario ma la schermata ITEM
  le salta.
- **Perche':** nel ROM il loro NOME E' VUOTO (sette spazi, `item_names.h`).
  Elencarle darebbe quattro righe bianche con un `1` a destra, che non si legge
  come "hai una sfera" ma come una lista rotta. Non e' una mancanza dei dati:
  sul NES le sfere si mostrano nel menu principale come quattro gemme accese o
  spente. **Debito dichiarato:** le quattro gemme, quando le sfere saranno
  ottenibili.
- **Status:** implementato in slice73.

### 1bis.2 CASA: le cariche di magia tornano SEMPRE
- **Cosa:** la casa rimette 120 HP a tutti e riempie tutti gli otto contatori
  di magia.
- **Perche':** sul NES lo fa solo a chi SALVA la partita — `MenuRecoverPartyMP`
  e' chiamata dopo `SaveGame`, dentro il ramo "ha salvato" (`bank_0E.asm:7095`,
  e il commento del disassemblatore dice *"some would say this is BUGGED"*).
  Qui un salvataggio non c'e' ancora, quindi non c'e' un ramo a cui appendere
  l'effetto: la casa fa sempre tutto. E' la lettura dell'intento, non una
  scorciatoia — quando il salvataggio arrivera', questa scheda va riletta.
- **Status:** implementato in slice73.

### 1bis.3 SOFT rimette in piedi con UN HP
- **Cosa:** sciogliendo la pietra, se gli HP correnti erano zero diventano 1.
- **Perche':** sul NES `CureOBAilment` toglie il bit e basta, e un pietrificato
  a zero HP torna un vivo a zero HP — uno stato che nel resto del gioco non
  esiste (e che al primo colpo si comporta in modo indefinito). Un HP e' la
  stessa regola con cui la clinica rialza i caduti (`EnterShop_Clinic`).
- **Status:** implementato in slice73.

---

## 2. Audio

### 2.1 Bass line via AY-3-8910 SGM
- **Cosa:** Tutti i brani usano 4 voci (SN76489 SQ1+SQ2+NOISE + AY TRI/triangle-equivalent).
  Sul NES erano 3 (SQ1/SQ2/TRI/NOISE → 4 ma timing-shared).
- **Perché:** SGM aggiunge AY-3-8910 (3 voci extra). Triangle/bass fidelity migliore
  che SN76489 alone. Decisione: usare AY visto che SGM è già hard-required per RAM.
- **Status:** ✅ Prelude, Battle Theme, OW theme — tutti 24 brani via NMI hook.

---

## 3. Bug-fix engine "intent" (vs NES ROM bugs)

Riferimento completo: `memory/ff1_engine_intent_priorities.md` + AstralEsper guide
in `docs/Final Fantasy - Game Mechanics Guide - NES - By AstralEsper - GameFAQs.html`.

Decisione: Coleco port fixa **tutti** i ~50 bug catalogati combat/magic della ROM
NES. Vedi `memory/spell_bugs_ff1nes_to_fix.md` e `ff1_engine_intent_priorities.md`
per dettaglio.

Esempi top-priority:
- CRIT% legge weapon `Crit` byte (no più Excalibur=39%, Masmune=40%)
- Hit% formula: no clamp pre-evasion
- TMPR/SABR/LOK2/HEL2/LOCK effect ID corretti
- Weapon weakness bonus (+4 ATK, +40 BC) realmente applicato
- INT stat utilizzato (era ignorato dalla ROM)
- Status su miss → solo on hit
- Multi-level-up loop (più livelli nella stessa battle se EXP basta)
- Running formula corretta (era leggeva slot stato, non runner level)
- Regen tick (mai eseguito su NES)
- Sleep wake-roll per enemies
- Poison DoT bidirezionale (era solo PC-side)

**Status:** TBD — implementazione differita a battle/magic engine slice (post-slice24).

### 3.1 Palette del gruppo 2 nelle formazioni "mix" — CORRETTA (slice56)

- **Cosa:** su NES, `PrepareEnemyFormation_Mix` (`bank_0B.asm:2576-2583`) fa
  **sei** `LSR` dove ne servono cinque, e per il gruppo 2 legge quindi il bit 6
  del nibble di assegnazione palette — cioè quello del gruppo 1 — invece del
  bit 5. Il nostro `decode_formation` usa la formula corretta per tutti e
  quattro i gruppi.
- **Perché è un refuso e non un comportamento:** nella stessa routine i gruppi
  0, 1 e 3 sono giusti (`ROL`×2, `ROL`×3, `LSR`×4 → bit 7, 6, 4), e la routine
  gemella per 9small/4large fa il gruppo 2 con `ROL`×4, che dà correttamente il
  bit 5. Non esiste una lettura in cui l'autore intendesse il bit 6. Verificato
  ricontando gli shift, non solo sul commento del disassembly.
- **Quanto pesa:** misurato da `tools/census_mix_palette_bug.ps1`. Delle 29
  formazioni mix servono tre condizioni insieme (gruppo 2 esistente, bit 5 ≠
  bit 6, palette diverse fra loro): **una sola** le soddisfa. È la formazione
  `44`, presente in **un solo dominio su 128** (`0x79`), dove il **SeaTROLL**
  uscirebbe con la palette 19 (`$30/$2C/$13`, ciano) invece della 20
  (`$30/$22/$12`, blu).
- **Perché correggere e non preservare:** un quirk preservato è qualcosa che il
  gioco *fa* e che qualcuno cerca apposta — il Finger Point è una tabella di
  incontri che i giocatori vanno a sfruttare. Qui non c'è nulla da preservare:
  nessuna strategia, nessun ricordo e nessuna speedrun dipendono dal colore del
  SeaTROLL in un dominio. Il colore corretto è per giunta più coerente (blu
  marino come il resto della tavolozza). E l'asimmetria di costo chiude la
  questione: il nostro codice è già corretto, mentre preservare il bug
  vorrebbe dire scrivere apposta lo shift sbagliato.
- **Status:** ✅ già così dal codice di slice55, classificato in slice56.

### 3.2 Class change — struttura NES-fedele, due bug corretti (deciso sessione 16)

**La struttura resta quella del NES.** `DoClassChange` (`bank_0E.asm:1744-1766`)
scrive un solo byte per personaggio, `ch_class += 6`, e nient'altro: nessuna
statistica, nessun HP/MP, nessun ricalcolo. La promozione è un **attivatore di
permessi** — equipaggiamento (`equip_bit = $800 >> class_id`,
`bank_0E.asm:9192`) e incantesimi apprendibili (`lut_MagicPermisPtr`,
`bank_0E.asm:6081-6086`). Le tabelle di crescita delle classi promosse puntano
**agli stessi byte** delle basi (`lut_LevelUpDataPtrs`, `bank_0B.asm:1207-1219`),
quindi le statistiche crescono identiche prima e dopo.

Non adottiamo il differenziale di crescita introdotto dai remake (Origins, DoS,
PSP, Pixel Remaster). Là il class change migliora la crescita, e la strategia
ottimale diventa promuoversi al livello minimo possibile (L20) per massimizzare
i livelli passati nella classe superiore. Sul NES il momento della promozione è
irrilevante ai fini delle statistiche, ed è questa la versione che portiamo:
i remake aggiungono bilanciamento, e il nostro mandato è correggere bug di
implementazione, non riprogettare le curve.

Due cose però il NES le sbaglia, e cadono nella categoria "intent vs
implementation" già decisa per gli altri 15 fix.

**(a) Il Master perde difesa magica promuovendosi.**

```
lut_LvlUpMagDefBonus:  3, 2, 4, 2, 2, 2,   3, 2, 1, 2, 2, 2
                      FT TH BB RM WM BM   KN NJ MA RW WW BW
```

`bank_0B.asm:1198`. È l'**unica** voce che differisce fra le due metà della
tabella — hit rate è identico per tutte e sei le coppie, e ogni altra classe
conserva il proprio bonus di MagDef. Il BlackBelt ha +4 per livello, il Master
+1: promuovere il monaco lo peggiora, e in modo invisibile, perché il danno
arriva livello dopo livello e non c'è nessuna schermata che lo mostri. È il
fix #13 di `memory/ff1_engine_intent_priorities.md`, di cui ora conosciamo la
causa: non è un "mismatch BB/MA" astratto, è il class change.

Correzione: **il Master conserva +4**, come tutte le altre classi conservano il
proprio. Nessuna classe deve regredire promuovendosi.

**(b) Le quattro classi promosse "magiche" diventano non-morti.**

`bank_0C.asm:7702-7706` legge la categoria del difensore giocatore dal byte di
classe:

```asm
    LDY #ch_class - ch_stats        ; load category from OB
    LDA (btl_entityptr_obrom), Y    ; BUGGED - usa la classe come categoria
    STA btlmag_defender_category
```

`CATEGORY_UNDEAD` è `$08` (`Constants.inc:28`), testato in `bank_0C.asm:8374`.
Le classi 8-11 — **Master, RedWizard, WhiteWizard, BlackWizard** — hanno il bit
3 acceso e diventano bersagli validi per HARM/HARM2. Nessuna classe base (0-5)
ce l'ha, quindi il difetto **compare solo dopo la promozione**.

Che sia un refuso e non un progetto lo dice il commento stesso del
disassembly, ma soprattutto la semantica: `ch_class` è un identificativo, non
una maschera di categorie, e la coincidenza fra "quarta classe promossa" e
"bit non-morto" non ha lettura sensata. Correzione: la categoria del difensore
giocatore è **nessuna** — i personaggi non appartengono a categorie di
creatura.

- **Status:** decisioni prese, implementazione quando arriverà la magia
  (punto 7 di `docs/battle_engine_design.md`) e la promozione. Oggi non c'è
  ancora né HARM né Bahamut.

### 3.3 INT — da statistica morta ad accuratezza magica (deciso sessione 16)

Sul NES INT non fa **niente**. `ch_int` (`variables.inc:379`) ha tre soli
riferimenti in tutta la ROM: la scrittura iniziale (`bank_0F.asm:1846`), il
ciclo di level-up che lo incrementa (`bank_0B.asm:1014-1048`), e una lettura in
`bank_0E.asm:228` che serve solo a **stamparlo** nella schermata di stato. Non
viene neppure copiato in battaglia — `btl_chstats` non ha un campo INT.

Cresce però con curve accuratamente differenziate: il Black Mage ha l'aumento
garantito a **ogni** livello 2→50, il Fighter in 14 livelli su 49. E il gioco
annuncia `"Int Up!"` a fine battaglia. Era il marchio identitario del mago, ed
è rimasto un guscio.

**Dove va agganciata.** Non lo decidiamo noi: la ROM lascia lo slot cablato e
vuoto. `PreparePlayerMagAttack` (`bank_0C.asm:7795-7847`) carica livello, hit
rate, danno e classe del lanciatore in variabili `btlmag_attacker_*` che
nessuna routine legge. Il commento del disassembly sulla routine gemella dice
che una di quelle "should probably be intelligence".

Le formule del NES:

```
hit_chance = 148 + spell_hitrate - target_magdef   (0 se resiste, +40 se debole)
roll = rand[0,200] ;  colpisce se hit_chance >= roll ;  roll==200 = miss secco

base = spell_effectivity   ( /2 se resiste, *3/2 se debole )
dmg  = rand[base, base*2]
```

Il dettaglio che decide la scelta: per le magie di **danno**, `hit_chance` non
stabilisce se colpiscono — colpiscono sempre — stabilisce se fanno **critico,
cioè danno raddoppiato** (`bank_0C.asm:8285`, `8326-8332`).

**Decisione:**

```
hit_chance = 148 + spell_hitrate + (INT / 4) - target_magdef
```

Un solo aggancio, due effetti: le magie di utilità (SLEP, MUTE, LOCK, XFER)
atterrano più spesso, e le magie d'attacco fanno più danno medio attraverso i
critici. **La formula del danno non si tocca.**

La proprietà che ha motivato la scelta è di bilanciamento: contro bersagli
deboli `hit_chance` sfonda già il tetto di 200, quindi INT non aggiunge nulla;
il beneficio compare **solo contro MagDef alta**. Un mago intelligente perfora
la resistenza magica, non gonfia il danno sui mostri banali. `INT/4` dà +0..+24
ed è deliberatamente conservativo: la costante è un valore da misurare quando
la magia esisterà, il punto di aggancio no.

**INT non è difesa magica**, e non per parity: perché MagDef esiste già come
statistica vera e separata — iniziale per classe (`bank_0F.asm:1858`) più bonus
per livello con cap 200 (`bank_0B.asm:904-909`), e non deriva dall'armatura.
Farci confluire INT conterebbe due volte la stessa cosa. Il motivo strutturale
è più forte ancora: i **nemici hanno MagDef ma non hanno INT**, quindi come
difesa il calcolo sarebbe asimmetrico fra i due lati del campo, mentre come
accuratezza l'asimmetria è voluta e leggibile.

- **Status:** ✅ **implementato in slice69** (`int_bonus` in `src/ovl_btlmagic.c`).
  Vale per gli incantesimi del **gruppo**, in tutte e tre le strade in cui la
  hit chance conta: il critico delle magie di danno, l'atterraggio delle
  alterazioni con l'effetto `$03`, e nient'altro. I mostri non ne hanno: le loro
  venti statistiche in ROM non contengono un'intelligenza, e infatti la gemella
  `magic_damage_on_chr` non prende il parametro.
  Misura sul campo, corsa `mame_drive_ailments.lua`: SLEP del mago nero (INT 20,
  cioè +5) contro un IMP (MagDef 16) dà `148 + 64 + 5 − 16 = 201` su un tiro
  0-200, cioè atterra sempre salvo il 200 secco. Senza INT sarebbe 196: quattro
  volte su duecento SLEP fallirebbe. È poco, ed è esattamente la scala giusta —
  la costante `INT/4` era dichiarata conservativa e lo è.

### 3.3bis Il tiro dell'attaccante non dipende dal sonno del difensore (slice69)

`DoPhysicalAttack` (`bank_0C.asm:4364-4372`) somma il **tiro dell'attaccante**
alla hit chance **solo se il difensore è sveglio**: il ramo `@DefenderMobile` è
l'`else` del bonus del +25% di danno contro chi dorme o è paralizzato. Il
disassembly stesso ci mette sopra un *"This seems strange to me. Shouldn't this
be done even if defender is immobile? Is this BUGGED?"*.

L'effetto in gioco: **addormentare un nemico peggiora la propria mira**. Non è
un compromesso — è un `JMP` che scavalca troppo, circondato da tre bonus che si
sommano tutti senza escludersi.

**Corretto:** il tiro si somma sempre, il +25% resta. Politica delle formule di
combattimento (`memory/ff1_engine_intent_priorities.md`, «combat/magic =
fix-default»). La correzione rende SLEP e HOLD quello che dovevano essere: un
modo per colpire *meglio* chi non si muove, non solo più forte.

### 3.3ter Il silenzio zittisce, non imbavaglia (slice69)

Sul NES `AIL_MUTE` blocca **magie, oggetti e bevande** insieme
(`bank_0C.asm:7201`, con tanto di commento *"You could argue this is BUGGED"*).
Qui blocca **solo le magie**: un personaggio silenziato può ancora bere una
pozione, che è quello che il silenzio significa in ogni gioco che lo usa.

Il divieto si vede **prima** di aprire il sottomenu — `SILENCED` sulla riga dei
messaggi appena si conferma MAGIC — e si ricontrolla al momento del turno: fra
la scelta e l'azione passa mezzo round, e in mezzo può arrivare una MUTE.

### 3.3quater I mostri dormono davvero (slice69, fix #14)

Sul NES un mostro addormentato **si sveglia sempre al primo turno**. Il ramo è
rotto in tre punti nella stessa dozzina di righe (`bank_0C.asm:6710-6730`):
carica in `btl_mathbuf` un campo (`en_unknown12`) che nessuno inizializza,
sottrae il numero casuale dal buffer sbagliato, e poi decide guardando un segno
che `MathBuf_Sub` — che tronca a zero — non può mai produrre.

Il risultato è che SLEP, SLP2 e HOLD contro i mostri valgono **un turno secco**,
sempre lo stesso, indipendentemente da tutto.

**Corretto:** i mostri usano lo stesso tiro dei personaggi, che è quello che il
codice *dichiara* di voler fare — si svegliano se `maxHP > rand[0,80]`. Un IMP
(8 HP massimi) resta giù circa nove turni su dieci; un mostro robusto si sveglia
quasi subito. Misurato nella corsa: dopo due round, **3 IMP su 4 addormentati
sono ancora giù**; col difetto NES sarebbero stati zero.

La paralisi invece conserva l'asimmetria del NES — 25% per i personaggi, ~10%
per i mostri. Sono due routine diverse con due costanti diverse, non un refuso,
e nessuna delle due liste di correzioni la nomina.

### 3.3quinquies L'alterazione si legge nella striscia (slice69)

Ogni blocco della striscia di stato è alto quattro righe e la quarta era vuota.
Adesso porta il nome dell'alterazione per esteso — `POISON`, `SLEEP`, `STONE`,
`CONFUSE` — invece di niente.

Non è informazione in più rispetto al NES: là il nome del personaggio cambia
colore e la finestra di stato la scrive comunque. È che qui il TMS9918 non può
cambiare colore a una singola riga di testo senza spendere una tabella colori,
mentre sette caratteri liberi c'erano già.

Una sola alla volta, la più grave, come sul NES: chi è morto non è anche
«avvelenato».

E `LAMP` su chi ci vede benissimo dice **`INEFFECTIVE`** invece di consumare la
carica in silenzio (`BtlMag_Effect_CureAilment` esce senza dire niente,
`bank_0C.asm:8553`). Stessa regola di 1.6 e 1.6bis: un divieto dichiarato non
somiglia a un difetto.

### 3.3sexies Il blocco IB — e i quattro incantesimi morti che resuscita (slice70)

Sul NES le statistiche esistono in due copie: `ch_stats` (*out-of-battle*, quelle
che si portano in giro) e `btl_chstats` / `btl_enstats` (*in-battle*, che nascono
all'inizio dello scontro e muoiono con lui). Sei effetti di magia su diciotto
scrivono nella seconda copia — FOG l'assorbimento, RUSE l'evasione, TMPR la
forza, LOCK l'evasione di un mostro, FAST i colpi, FEAR il morale.

La ROM quella copia **la risalva male, e in modo diverso sui due lati**:

| routine | dimentica | conseguenza |
|---|---|---|
| `BtlMag_SavePlayerDefenderStats` (`bank_0C.asm:8027`) | la **forza** | TMPR e SABR non fanno niente — e bersagliano sempre un personaggio |
| `BtlMag_SaveEnemyDefenderStats` (`bank_0C.asm:7982`) | la **resistenza elementale** | XFER non fa niente sui mostri (**fix #6**) |

Due routine, due campi dimenticati, due incantesimi morti ciascuna. Qui i campi
sono gli **stessi per le due parti del campo** e si scrivono nello stesso posto
(`src/battle_ibstats.h`): non c'è un posto dove dimenticarne uno.

Con il blocco, **tutti e diciotto gli effetti di battaglia funzionano.** Restano
fuori solo LIFE, LIF2, SOFT, WARP ed EXIT, che hanno effetto `$00` perché sono
magie da usare **fuori** dalla battaglia — e fuori dalla battaglia non c'è
ancora un posto da cui lanciarle. Manca il menu, non il motore.

### 3.3septies LOK2 e HEL2 — le due voci di tabella corrette (slice70)

Le uniche due righe di `lut_MagicData` che il porting non usa alla lettera. La
correzione sta nel motore (`patch_spell` in `src/ovl_btlmagic.c`), non
nell'estrattore: `src/data/magic_data.h` resta byte-exact rispetto al ROM e la
deviazione vive accanto al motivo.

- **LOK2 ($17)** dichiara l'effetto `$10`, che **alza** l'evasione, e bersaglia
  i nemici. È il contrario di quel che il nome dice e di quel che fa LOCK, la
  sua versione debole: così com'è, LOK2 spende una carica di terzo livello per
  rendere un mostro **più difficile** da colpire. Letta come `$0E`.
  Il criterio, che varrebbe anche per un'altra voce dello stesso genere:
  *nessuno potenzia il proprio nemico.*
- **HEL2 ($23)** dichiara effectivity 48, la **stessa** di HEL3 ($33), che sta
  due livelli sopra. 12 / 48 / 48 non è una scala; 12 / **24** / 48 lo è.

Più due correzioni che non toccano la tabella:

- **LOCK** (effetto `$0E`) sul NES **manca sempre**: la routine ha un `JMP` dove
  andava un `BEQ` e salta l'intero corpo (`bank_0C.asm:8662`, annotato nel
  disassembly). Qui il corpo si esegue.
- **SLOW e FAST dicono la verità.** Il NES dichiara il lancio riuscito e *poi*
  disfa l'effetto se il moltiplicatore era già al limite — così SLOW su chi è
  già lento si annuncia come funzionante (`bank_0C.asm:8457`, "this is where the
  'bug' is"). Qui l'esito segue il fatto, e una FAST sprecata dice
  `INEFFECTIVE`.

### 3.4 Mescolamento dell'iniziativa — PRESERVATO com'è (slice59)

`DoBattleRound` (`bank_0C.asm:3211-3244`) mescola le 13 caselle del turno con
**16 scambi** di due posizioni pescate a caso. È un mescolamento debole, e il
disassembly lo annota: una casella ha buone probabilità di non essere mai
toccata, e siccome i personaggi partono in fondo alla lista tendono a
restarci — quindi i nemici agiscono per primi più spesso di quanto un
mescolamento onesto darebbe.

**Lo teniamo così**, ed è l'unico caso finora in cui un difetto riconosciuto
non viene corretto. Tre ragioni, in ordine di peso:

1. **Il numero di estrazioni fa parte della sequenza.** 16 scambi = 32 chiamate
   al generatore. Un Fisher-Yates ne farebbe 12 e sposterebbe *ogni* tiro
   successivo del combattimento. La parity dell'intera battaglia passa di qui,
   e la si perderebbe per un guadagno marginale.
2. **Non è un refuso come LOK2**, che fa il contrario di ciò che dichiara.
   Questo ciclo mescola davvero; mescola male. La distanza fra intento e
   implementazione è di grado, non di segno — e la lista dei fix nasce per il
   secondo caso.
3. **La penalità è distribuita**, non concentrata: incide sul ritmo di tutta la
   partita, non su un incontro o un incantesimo. Toglierla cambierebbe il
   passo del gioco più di quanto lo correggerebbe.

- **Status:** ✅ implementato NES-exact in slice59.

### 3.5 Sconfitta — segnaposto dichiarato (slice59)

Il gruppo può cadere, e `run_defeat` mostra "THE PARTY PERISHED". Poi però
**rimette tutti in piedi con gli HP pieni** e torna in overworld.

Non è una scelta di design: la risposta di FF1 a un massacro è "ricarica il
salvataggio", e un salvataggio non c'è ancora. Qualunque cosa si faccia qui è
un segnaposto, e tanto vale che sia quello dichiarato invece di uno travestito
da meccanica. Sparirà insieme al Continue vero.

Manca anche il **silenzio**: il tema di battaglia continua a suonare sotto la
scritta, perché fermarlo richiederebbe una `svc_` nuova, cioè byte nella
finestra fissa (169 liberi). Va con la sessione dei VFX, insieme allo
scuotimento dello schermo.

**NES quirks PRESERVATI:** vedi `memory/ff1_preserved_quirks.md` (Finger Point/PNEOP,
forced-fight retrigger, ecc — feature beloved che restano byte-exact).

---

## 4. Future / candidati (non ancora implementati)

- **Save:** password system 4-trial (NES non aveva password, solo SRAM batteria).
  Per Coleco senza custom cart, password = uniche scelta mainstream.
- **Optional cart con SRAM:** se community CollectorVision risponde, edition
  dedicata con save full mid-dungeon (NES-parity vera).
- **Phoenix SD detection:** save su SD se Phoenix BIOS rilevato (additivo).
- **Battle target select via keypad:** numpad 1-9 per target diretto (vs cycle).
- **Equipment menu UX:** keypad shortcut per slot equip diretto.
- **Subtle visual effects:** sprite zero-trick non disponibile su Coleco;
  alternative Mode 2 raster effects via NMI ISR per HP-flash, dimming, ecc.

---

## 4bis. Resa dei colori (scelte di porting, non miglioramenti)

Il TMS9918 ha 15 inchiostri fissi contro i 52 del NES, e ne puo' mostrare uno
solo per riga di tile. Le decisioni qui sotto non sono "migliorie": sono il
modo in cui si e' scelto di PERDERE informazione, e vanno ricordate perche' un
purista potrebbe legittimamente preferirne altre.

- **Dominante per riga** (slice30 per i personaggi, slice55 per i nemici): dei
  pixel accesi di ogni riga di tile vince il colore piu' frequente. Le sagome
  restano fedeli, le sfumature orizzontali dentro una riga si perdono.
- **Swap di palette preservato** (slice55): le varianti di nemico del NES
  (IMP/GrIMP, WOLF/GrWOLF, SAHAG/R.SAHAG) restano distinte, perche' si salva
  l'indice di palette e non il colore risolto. Questo e' parity piena.
- **Collisioni di palette sciolte per vicinanza percettiva** (slice55): 13
  palette FF1 su 64 mandano due dei tre colori sullo stesso inchiostro TMS. In
  quei casi una delle due voci viene spostata sull'inchiostro libero piu'
  vicino in redmean. E' una DEVIAZIONE: il colore risultante non e' quello che
  la tabella di conversione darebbe. Senza, pero', l'IMP del primo incontro
  avrebbe due colori invece di tre.

- **Abitanti: sagoma nel fondo, contorno come sprite** (slice76). In Mode 2 una
  riga di tile ha DUE colori e un abitante di FF1 ne usa tre -- terreno, corpo,
  contorno nero. Il fondo porta i primi due, uno sprite 16x16 nero ci mette
  sopra il terzo. Quel che resta fuori e' il DETTAGLIO DI COLORE dentro la
  figura: incarnato e vestito diventano un colore solo per riga (la dominante).
  E se il giocatore si mette di fianco a un abitante, il suo contorno e' il
  quinto sprite della scanline e cade: resta la sagoma piena, leggibile.

- **Il ponte: sagoma nel fondo invece che sprite** (slice78). Sul NES il ponte
  dell'overworld e' uno sprite 2x2 disegnato sopra l'acqua. Qui e' cotto nel
  fondo, sopra il macrotile dell'oceano su cui poggia, per la stessa ragione
  degli abitanti: il mapman occupa gia' i quattro sprite che il TMS mostra per
  scanline, e il ponte sarebbe il quinto -- sparirebbe proprio mentre ci si
  cammina sopra. Il prezzo tipico della cottura (l'oggetto non si muove) qui
  non si paga: il ponte sta fermo in una casella per definizione.
  Le righe di tile interamente sul ponte spendono i due colori sul tavolato e
  sulle assi; quelle che toccano l'acqua tengono separati ponte e mare, quindi
  li' le assi si perdono.

- **La title card della scena del ponte, in modo bitmap** (slice78). E' l'unica
  schermata del progetto in cui ogni cella ha una tile propria (Mode 2: 256
  pattern per terzo di schermo = una per cella). La figura ci sta INTERA e
  senza riuso; quel che si perde e' solo la riduzione a due colori per riga di
  8 pixel. Misurato sul logo di FINAL FANTASY, che e' il punto peggiore: 1,5%
  di pixel di lettera che diventano cielo, 0,3% di cielo che diventa lettera.

### 4ter. Il credito Nintendo NON c'e' (slice78)

Nella title card della scena del ponte il "TM&(C) 1990 NINTENDO" in basso a
sinistra e' **rimosso**; il "(C)1987 SQUARE" in basso a destra **resta**.

Non e' un limite tecnico: sono celle dell'immagine come tutte le altre, e si
tolgono riempiendole col colore che hanno intorno (prato verde a sinistra,
rupe nera a destra -- tinta unita in tutti e due i casi, quindi non si
ricostruisce niente e non si vede la giuntura). E' una scelta, ed e' un
interruttore dell'estrattore (`-DropNintendo` / `-DropSquare`):

- **Nintendo ha pubblicato la versione NES** e con un port ColecoVision non
  c'entra niente. Lasciare il suo marchio sarebbe un'attribuzione falsa --
  suggerirebbe una licenza che non esiste.
- **Square ha scritto il gioco** da cui questo port viene, e quella riga e'
  vera. Toglierla sarebbe cancellare l'attribuzione a chi l'opera l'ha fatta.

## 5. Filosofia

- **Default = NES-parity** (gameplay, balancing, encounter rates, music timing,
  text content, screen layout).
- **Aggiunte =** solo dove la NES era limitata da hardware/cart cost, e Coleco
  permette di togliere quel limite (più RAM con SGM, keypad input, AY voce).
- **Bug-fix =** dove c'è chiaramente "intent vs implementation" gap (AstralEsper
  guide). Non tocchiamo bug-feature beloved (PNEOP, ecc).
- **Stack additivi:** ogni miglioria deve essere disable-able / ignore-able da
  player NES-purist. Niente rimozione di feature NES.
