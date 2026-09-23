// =====================================================================
//  slice78 -- il PONTE, e la scena che ci sta sopra
// =====================================================================
// La quest ha una fine che si vede. Il Re ordina il ponte, il ponte COMPARE
// in overworld, ci si cammina sopra e parte la title card di FINAL FANTASY
// con il Prologue -- sng42, che stava nel banco 1 da slice62 e non era mai
// stato suonato.
//
// LE QUATTRO COSE NUOVE
//   1. IL PONTE SI VEDE. Quattro tile cotte sopra il macrotile dell'oceano
//      (tools/extract_bridge_tile.ps1), caricate negli slot 236-239 che il
//      tileset OW lascia liberi, e disegnate DOPO la vista -- come gli
//      abitanti di slice76 e per la stessa ragione: da sprite sarebbe il
//      quinto sulla scanline del mapman e sparirebbe mentre ci si sta sopra.
//   2. IL PONTE SI ATTRAVERSA. Non e' un cambio di attributo: e'
//      un'ECCEZIONE consultata DOPO il rifiuto, come `IsOnBridge` sul NES
//      (bank_0F.asm:1542). Il macrotile sotto resta oceano, e resta
//      impraticabile per chiunque non sia sulla casella del ponte.
//   3. GLI INCONTRI SI SPENGONO li' sopra. Sul NES `tileprop+1` viene
//      azzerato prima del controllo: senza, si prenderebbe una battaglia
//      NAVALE a piedi, perche' sotto il ponte il tile e' acqua.
//   4. LA SCENA, una volta sola. `bridgescene` fa 0 -> 1 (calpestato) -> 2
//      (vista), come il 00/01/$80 del NES.
//
// DOVE STA LA SCENA: banco 27, `src/ovl_bridge.c`, OTTAVO overlay. Non e' il
// codice a chiedere un banco, e' l'IMMAGINE: 12288 byte di pattern e colore.
// La title card e' una figura a schermo intero e in Mode 2 ogni cella puo'
// avere una tile tutta sua -- un terzo di schermo e' 8x32 = 256 celle e la
// tabella dei pattern ne tiene 256 per terzo. E' il "modo bitmap" del TMS9918,
// e questa e' la prima schermata del progetto che lo usa.
//
// --- eredita' di slice77 ---------------------------------------------
//  slice77 -- il castello e il tempio: esiste un ALTROVE
// =====================================================================
// Quattro mappe standard invece di una, e la prima quest di FF1 percorribile
// per intero: Re -> Garland -> principessa -> LUTE -> ponte.
//
// LE QUATTRO COSE NUOVE, tutte motore (i DATI c'erano gia' da fine sess. 24):
//   1. LA SELEZIONE DELLA MAPPA. `cur_map_slot` + una tabella di descrittori
//      nella rodata della slice (banco 0): banco, dodici indirizzi di simboli
//      (diversi per banco: li sceglie il linker), conteggio tile, ingresso,
//      canzone. All'ingresso in mappa la riga si copia in `TD` (RAM, finestra
//      fissa): i descrittori si leggono col banco 0 mappato, PRIMA delle
//      escursioni nel banco della mappa. Tabella PIATTA, non struct[]: un
//      aggregato const multi-dim finirebbe in DATA ([[rodata-trap]]).
//   2. I TELETRASPORTI. `TP_TELE_NORM` cambia mappa restando dentro (le scale
//      del castello, il ritorno della principessa); `TP_TELE_EXIT` torna in
//      overworld a coordinate PROPRIE (lut_ExitTele). Le otto fette di
//      lut_*Tele stanno nel banco 11 (tabella 12 di svc_fetch_btl, un
//      `else if`: [[svc-generalize-rule]]).
//   3. GLI INGRESSI DALL'OVERWORLD. `main()` non confronta piu' `tele_id==1`:
//      qualunque casella ENTR consulta lut_EntrTele e cerca la mappa nella
//      tabella dei descrittori. 1 = Coneria, 9 = castello 1F, 13 = tempio.
//   4. LE ROUTINE DI DIALOGO CHE CAMBIANO QUALCOSA (banco 26): il Re che
//      accende il ponte, la principessa che da' il LUTE, Garland che apre la
//      battaglia $7F, la principessa rapita che si fa salvare. Gli effetti che
//      il banco 26 non puo' produrre da solo -- fanfara, battaglia,
//      teletrasporto -- tornano come BIT ALTI del valore di ritorno
//      dell'overlay, e li esegue `town_talk` al rientro.
//
// LA MUSICA SEGUE LA MAPPA: sng47 (banco 1) per la citta', sng48 (banco 10)
// per i due piani del castello, sng4C (banco 10) per il tempio. La fanfara
// dei dialoghi e' sng54, il "got an important item!" del NES (track $54).
//
// --- eredita' di slice76 ---------------------------------------------
//  slice76 -- Coneria ha degli abitanti, e gli abitanti parlano
// =====================================================================
// La citta' smette di essere un fondale. Otto persone stanno dove il ROM le
// mette, bloccano il passo, e rispondono con il loro testo vero -- quello di
// FF1, byte per byte, sciolto dal DTE del ROM. Piu' il dialogo dei MACROTILE,
// che sul NES e' la stessa funzione: parlare a un muro dice "Nothing here".
//
// LA DECISIONE CHE DECIDE TUTTO IL RESTO: gli abitanti sono TILE DI FONDO,
// non sprite. Il mapman del giocatore occupa QUATTRO sprite sovrapposti
// ([[mapman-4layer]]) e il TMS9918 ne mostra quattro per scanline: un abitante
// di fianco al giocatore sarebbe il quinto e sparirebbe -- e "di fianco" e'
// l'unica posizione da cui gli si puo' parlare. Sarebbe un difetto che si
// manifesta esattamente quando si usa la funzione.
//
// Come tile di fondo invece non c'e' nessun limite, il colore e' quello vero,
// e la griglia coincide con il passo discreto del movimento. Le quattro tile
// di ogni abitante sono cotte a monte SOPRA il terreno su cui sta
// (tools/extract_sm_colors.ps1), e da li' viene l'unico prezzo: **non
// camminano**. Sul NES vagano. Deviazione dichiarata in
// docs/Coleco_improvements.md.
//
// LA MAPPA DEI 256 TILE DELLA CITTA', che e' il vero vincolo del pezzo:
//     0 - 92    il tileset di Coneria (93 coppie tile/palette, misurate)
//    96 - 155   4 tile per slot abitante (15 slot, come il NES)
//   159         la barra verticale del riquadro di dialogo
//   160 - 254   il font del BIOS, caratteri $20-$7E
// Ci sta tutto perche' il tileset ne usa 93 su 256 -- e l'extractor si ferma
// con un errore se una mappa futura supera i 96.
//
// DOVE STA IL RESTO: banco 26, `src/ovl_talk.c`, SETTIMO overlay. Non e' il
// codice a chiederlo, e' il TESTO: 3113 byte gia' decompressi contro i 657
// liberi nella finestra fissa. E un blocco nuovo di RAM condivisa a $6500
// (`src/world_state.h`) per i 208 flag di gioco, che sono la memoria di tutto
// cio' che nel gioco succede una volta sola.
//
// DI QUA CAMBIANO CINQUE COSE:
//   1. `load_town_chr_palette` carica anche abitanti, barra e font;
//   2. `redraw_town_view` chiama `draw_npcs`, che li scrive DOPO la vista --
//      dentro il ciclo delle righe sarebbero 24x15 confronti per passo;
//   3. il passo si rifiuta se davanti c'e' qualcuno (`npc_at`);
//   4. FIRE1 apre il dialogo, a fronte come il menu;
//   5. i flag di gioco nascono nell'overlay dell'intro, dove nasce il gruppo.
//
// --- eredita' di slice75 ---------------------------------------------
//  slice75 -- la magia fuori dalla battaglia
// =====================================================================
// La voce MAGIC del menu smette di dire NOT YET, e con lei sparisce l'ULTIMA
// voce rimasta nella lista dei "NOTHING HAPPENS" dichiarati: le tredici magie
// che FF1 permette di lanciare fuori dallo scontro (CURE CUR2 CUR3 CUR4, HEAL
// HEL2 HEL3, LIFE LIF2, PURE, SOFT, WARP, EXIT).
//
// Stanno nel banco 25 (`src/ovl_magic.c`), SESTO overlay del progetto e
// SECONDO annidato: ci si entra dal menu, che e' gia' un overlay. Il perche'
// di un banco nuovo invece del 24: quello aveva 3328 byte liberi e questa
// schermata ne chiede piu' o meno altrettanti -- ci starebbe *a pelo*, che e'
// il modo in cui il problema si scopre a meta' lavoro.
//
// DI QUA CAMBIA UNA COSA SOLA: il valore di ritorno del menu adesso si legge.
// WARP ed EXIT riportano il gruppo in overworld, e uscire da una citta' e'
// l'unica cosa che l'overlay non puo' fare da solo -- vuol dire ridisegnare
// tutto. Il menu lo dice tornando 1, e la citta' riusa la strada che ha gia'
// per la casella di prato (`town_warp_out`).
//
// --- eredita' di slice74 ---------------------------------------------
//  slice74 -- l'equipaggiamento si mette e si toglie a mano
// =====================================================================
// Le voci WEAPON e ARMOR del menu smettono di dire NOT YET. Sono la meta' che
// mancava a slice66: da allora comprare EQUIPAGGIA da solo (deviazione 1.5 di
// Coleco_improvements), e quella scelta era senza rimedio -- un'arma finita
// addosso alla persona sbagliata ci restava per sempre, perche' non c'era
// nessuna schermata da cui toglierla. Adesso c'e', e la deviazione torna a
// essere una comodita' invece che una condanna.
//
// DI QUA CAMBIA UNA COSA SOLA, e sta in `svc_fetch_btl`: le tabelle 6 e 7, i
// permessi di equipaggiamento di armi e armature. Il menu deve sapere se una
// classe puo' portare quello che ha nello zaino, e la risposta sta nel banco
// 16, che l'overlay non vede. Il negozio quel problema ce l'aveva gia' e l'ha
// risolto facendosi portare i permessi INSIEME al listino (`SHOP.perm[]`), ma
// li' le voci sono cinque e le sceglie il negozio: qui l'oggetto puo' essere
// una qualunque delle 80 armi e armature, e la domanda arriva a schermata gia'
// aperta.
//
// Le due tabelle sono passate nel banco 11 (btldata_bank.c, +160 byte di dati
// e +640 in tutto con le statistiche che vengono dallo stesso header), dove
// `svc_fetch_btl` gia' andava: due `else if` invece di una svc_ nuova, che al
// prezzo misurato in slice60 sarebbe stata ~166 byte di finestra fissa. E' la
// stessa mossa dei nomi degli oggetti in slice68, la quarta volta che paga --
// [[svc-generalize-rule]].
//
// --- eredita' di slice73 ---------------------------------------------
//  slice73 -- il menu: lo zaino si apre, e le statistiche si guardano
// =====================================================================
// slice71 ha dato un posto agli oggetti; qui ci si arriva. FIRE2 apre il menu
// dall'overworld e dalla citta' -- il tasto era libero in tutte e due da
// quando l'uscita dalla citta' e' diventata la casella di prato (slice64).
//
// COSA C'E' DENTRO (banco 24, `src/ovl_menu.c`, quinto overlay del progetto):
// le cinque voci del NES nello stesso ordine -- ITEM, MAGIC, WEAPON, ARMOR,
// STATUS -- di cui questa slice ne apre due, ITEM e STATUS. Le altre tre
// dicono NOT YET: dichiarato, non silenzioso.
//
// PERCHE' STATUS PRIMA DI TUTTO IL RESTO. Da slice59 INT non e' piu' una
// statistica morta -- decide l'accuratezza della magia -- e da slice54 i
// livelli fanno crescere i numeri con tiri casuali. Nessuna delle due cose
// aveva un posto dove guardarsi: la battaglia mostra gli HP, la scelta dei
// personaggi mostra i valori di partenza, che dopo il primo livello sono gia'
// scaduti. Una statistica che nessuno puo' leggere e una statistica che non
// esiste si somigliano troppo.
//
// DI QUA CAMBIANO TRE COSE, tutte piccole -- il menu sta nel banco 24:
//   1. FIRE2 apre il menu, nei due cicli di gioco, e A FRONTE (vedi
//      `menu_pressed`: a livello il menu non si chiuderebbe piu');
//   2. al ritorno si rimette la grafica -- in citta' come dal negozio, e per
//      questo le due strade sono diventate una funzione sola;
//   3. `svc_fetch_btl` impara la tabella 5, la curva degli EXP del banco 11.
//      Serve alla riga NEXT delle statistiche, ed e' l'unica cosa che la
//      finestra fissa doveva imparare: un `else if` in una funzione che quel
//      banco lo mappava gia'. La regola di slice67, la terza volta che paga.
//
// SENZA slice72 QUESTA SLICE NON ESISTEVA: quelle tre cose costano 172 byte e
// la finestra fissa ne aveva 147 liberi.
//
// --- eredita' di slice72 ---------------------------------------------
//  slice72 -- il gruppo nasce nell'overlay (e la finestra fissa respira)
// =====================================================================
// SLICE DI IMPIANTO, non di gioco: a schermo non cambia un pixel, e la prova
// che e' andata bene e' proprio quella -- stesse statistiche iniziali, stesse
// corse di validazione, stessi numeri.
//
// PERCHE' ADESSO. Il menu (slice73) non ci stava: la finestra fissa aveva 147
// byte liberi e le tre righe che servono per aprirlo ne chiedevano 172. Il
// sintomo NON e' un errore di compilazione -- e' la riga
// `CODE sfora la finestra fissa di 25 byte` in cima alla build, e poi schermo
// blu ore dopo, quando la overworld mappa un quadrante e quei 25 byte
// smettono di esistere ([[fixed-window-full]]).
//
// COSA SI E' SPOSTATO: `party_init_from_classes`, **842 byte** che giravano
// UNA VOLTA SOLA, subito dopo la selezione dei personaggi. E' il rapporto
// peggiore possibile fra quanto costa una cosa e quanto la si usa -- la stessa
// diagnosi che in slice62 aveva fatto uscire le scene di apertura, e lo stesso
// posto dove va: l'overlay dell'intro (banco 21), che le classi ce le ha gia'
// in mano e i quattro nomi predefiniti li aveva gia' come rodata.
//
// LE TRE COSE CHE NON SONO POTUTE ANDARE DI LA', e perche', stanno scritte
// sopra `party_new_game` piu' sotto. In due parole: le classi forzate dalle
// build di prova (`-Defines` non arriva agli overlay), la sonda
// `party_chr_size`, e i semi delle build di prova, che vanno scritti DOPO.
//
// UN OVERLAY CON DUE INGRESSI. `svc_run_overlay` passa un argomento a 16 bit e
// l'intro ne restituiva 12 pieni di classi: il bit 15 dell'ARGOMENTO era
// libero, perche' entrata e uscita non si sovrappongono. Acceso vuol dire
// "costruisci il gruppo", spento "corri le scene di apertura". Un banco nuovo
// per una funzione che gira una volta sola e legge quegli stessi dati sarebbe
// stato uno spreco; una `svc_` in piu' avrebbe rimesso nella finestra fissa
// proprio i byte che questa slice ne toglie.
//
// --- eredita' di slice71 ---------------------------------------------
//  slice71 -- l'inventario, e il negozio di oggetti che lo riempie
// =====================================================================
// Il motore di battaglia e' finito. Quello che manca non e' motore, e' il
// pezzo su cui l'interfaccia poggia: **un posto dove tenere gli oggetti**.
// Senza, cinque cose dichiarate non possono nemmeno cominciare -- il comando
// DRINK, il comando ITEM, il negozio di oggetti (che diceva ancora NOT YET),
// l'equipaggiamento manuale e le cinque magie che si lanciano solo fuori dalla
// battaglia. Tutte e cinque aspettano lo stesso array.
//
// DOV'E' E CHE FORMA HA: `PARTY.item[]`, 28 byte in coda al blocco del gruppo
// (party_state.h). Una casella per id-oggetto, il contenuto e' la quantita' --
// cioe' `items` del NES, byte per byte. Il perche' di quella forma invece di
// una lista di coppie sta accanto alla dichiarazione.
//
// DI QUA CAMBIA POCHISSIMO, ed e' voluto: la finestra fissa ha 198 byte liberi
// e non puo' ospitare un negozio nuovo. Qui dentro c'e' solo l'AZZERAMENTO
// dell'inventario a nuova partita -- che non e' pignoleria: la RAM SGM
// all'accensione vale spazzatura, e un byte a caso in `item[ITEM_HEAL]` vuol
// dire pozioni gratis o, peggio, 200 pozioni che il negozio rifiuta di
// vendere senza spiegare perche'. Tutto il resto sta nel banco 22, accanto
// agli altri negozi: `svc_shop_fetch` portava gia' nomi, prezzi e icone anche
// per i consumabili (i permessi valgono zero, che per una pozione e' la
// risposta giusta), quindi l'overlay aveva gia' in mano tutto.
//
// --- eredita' di slice70 ---------------------------------------------
//  slice70 -- le statistiche di battaglia
// =====================================================================
// slice67 ha riempito `ch_spells`; adesso serve a qualcosa. Il comando MAGIC
// del menu di battaglia smette di dire NOT YET.
//
// DI QUA NON CAMBIA QUASI NIENTE, ed e' il punto: il motore sta nel banco 23,
// un SECONDO overlay di battaglia, e l'overlay di battaglia (banco 20) ci
// entra con `svc_run_overlay` mentre e' lui stesso dentro una chiamata --
// annidamento, cioe' esattamente il caso per cui quella primitiva e' stata
// scritta in slice61. Il banco 20 aveva 886 byte liberi e il sottomenu piu' i
// lanci non ci stavano; il 23 e' vuoto.
//
// L'unica aggiunta nella finestra fissa e' `svc_fetch_item_name`: i nomi delle
// magie stanno nel banco 16 e nessuno dei due overlay lo vede. Servira' anche
// all'inventario e al menu, che dei nomi hanno lo stesso bisogno e nessun
// listino da cui prenderli.
//
// --- eredita' di slice67 ---------------------------------------------
//  slice67 -- si imparano le magie: i due negozi di Coneria
// =====================================================================
// I negozi di magia bianca e nera mostravano il listino e dicevano
// "BUYING: NOT YET". Adesso si compra, e `ch_spells` smette di essere un
// campo che nessuno scrive: e' il prerequisito della magia del giocatore in
// battaglia, che non esiste per QUESTO -- non per mancanza di motore. Il
// nucleo (`magic_roll`, `magic_damage_on_chr`) e' scritto e provato dal lato
// nemico da slice60; a nuova partita, semplicemente, nessuno conosce niente.
//
// DI QUA CAMBIA UNA COSA SOLA, ed e' di nuovo dentro `svc_shop_fetch`: per i
// due negozi di magia si fa una SECONDA escursione, nel banco 11, e si copiano
// i 96 byte di `lut_MagicPermissions` nel blocco condiviso. Non si riduce alle
// 5 voci del listino: ridurre vuol dire fare il conto qui, dove restano 247
// byte, mentre copiare e' un ciclo e il conto lo fa l'overlay, che di byte ne
// ha 8793. La regola e' quella di sempre -- di qua COME si leggono i dati, di
// la' COME si decidono.
//
// PERCHE' I PERMESSI DI MAGIA NON SONO QUELLI DI slice66. Quelli dipendono
// dall'OGGETTO: una parola per voce, un bit per classe. Questi dipendono dalla
// coppia CLASSE x LIVELLO -- 12 x 8 byte -- e dentro il byte il bit lo sceglie
// l'incantesimo (bit 7-4 = bianca 0-3, bit 3-0 = nera 0-3, acceso VIETA).
// Sono due tabelle diverse per due domande diverse, e provare a farne una sola
// vuol dire perdere una delle due dimensioni.
//
// --- eredita' di slice66 ---------------------------------------------
// Il negozio di slice65 mostrava il listino e diceva "BUYING: NOT YET".
// Adesso si compra davvero, e il gruppo smette di essere disarmato -- che era
// il motivo per cui meta' delle formule del turno fisico girava su zeri.
//
// QUESTO FILE CAMBIA POCHISSIMO, ed e' il risultato voluto: il negozio sta nel
// banco 22, la finestra fissa aveva 461 byte liberi e non ne poteva spendere
// centinaia. L'unica aggiunta di qua sono i **permessi** dentro
// `svc_shop_fetch`: due byte per voce, letti dal banco 16 insieme a nome,
// prezzo e icona. Costano una manciata di byte qui e fanno risparmiare una
// svc_ intera -- l'alternativa era `svc_can_equip(classe, oggetto)`, cioe' una
// escursione nel banco 16 per ogni voce e per ogni personaggio, ~166 byte al
// prezzo misurato in slice60.
//
// La regola dei permessi (`IsEquipLegal`, bank_0E.asm:9060):
//     bit_di_classe = $800 >> class_id      (FT=$800, TH=$400, ... BW=$001)
//     non puo' equipaggiare  <=>  (permessi_oggetto & bit_di_classe) != 0
// Il bit ACCESO vieta. E' l'inverso di quello che verrebbe da scrivere, ed e'
// il tipo di errore che a occhio sembra "il negozio non vende niente a
// nessuno" oppure, peggio, "vende tutto a tutti".
//
// DOVE STA IL RESTO. Scelta della voce, del personaggio, prova dell'oro,
// riempimento della casella, locanda e clinica: tutto in src/ovl_shop.c. Sono
// RAM (PARTY sta in SGM, che non dipende dal banco) e disegno, cioe' le due
// cose che un overlay sa fare da solo. L'unico servizio che il negozio chiama
// dopo aver scritto una casella e' `svc_equip_recalc`, che c'era gia'.
//
// L'ACQUISTO EQUIPAGGIA -- e' una deviazione dal NES, la prima di questa
// sessione, ed e' scritta in docs/Coleco_improvements.md. Sul NES comprare
// mette l'oggetto nello zaino e per indossarlo si passa dal MENU, che qui non
// esiste ancora: senza il passo automatico, comprare non cambierebbe un solo
// numero e non ci sarebbe modo di sapere se ha funzionato. Si equipaggia solo
// se i permessi lo consentono e se il posto e' libero (una sola arma; una
// corazza, uno scudo, un elmo, un guanto), cioe' le stesse condizioni che il
// menu del NES applicherebbe. Quando il menu arrivera' potra' disfare.
//
// --- eredita' di slice64 ---------------------------------------------
//  slice64 -- Coneria smette di essere un fondale: mura, uscita, porte
// =====================================================================
// Fino a slice63 la citta' era disegnata giusta e a colori veri, ma si
// attraversava tutta: case, mura, mare. Si usciva con FIRE2, che non e' un
// tasto del NES ma un'uscita di servizio rimasta da slice40.
//
// Qui i due byte di `SMTilesetProp` cominciano a contare. Erano gia' estratti
// da slice40 e non erano mai stati letti da nessuno.
//
//   byte 0  bit 0     TP_NOMOVE       non si passa
//           bit 1-4   TP_SPEC_MASK    porta / stanza / tesoro / ...
//           bit 6-7   TP_TELE_MASK    %01 = torna alla mappa precedente
//   byte 1            su una PORTA: lo shop_id, se non e' zero
//
// LA REGOLA DEL BLOCCO NON E' `byte0 & NOMOVE`, ed e' la cosa che si sbaglia
// per prima. Sul NES (`CanPlayerMoveSM`, bank_0F.asm:2448) e'
//     (byte0 & (TP_SPEC_MASK | TP_NOMOVE)) == TP_NOMOVE
// cioe' NOMOVE blocca SOLO se i bit di specialita' sono spenti. Le sette
// porte dei negozi di Coneria hanno NOMOVE acceso INSIEME a TP_SPEC_DOOR:
// lette col solo bit NOMOVE sarebbero muri, e la citta' verrebbe fuori
// perfettamente giocabile e con sette negozi irraggiungibili -- senza un
// errore, senza un sintomo, solo un gioco piu' povero di quello vero.
//
// L'ORDINE DELLE TRE COSE NON E' CASUALE: prima le collisioni, poi l'uscita.
// Nel tileset 0 le caselle `TP_TELE_EXIT` sono ZERO: l'uscita di Coneria e'
// il prato `$47` che circonda la citta', marcato `TP_TELE_WARP` ("torna alla
// mappa precedente"), e sono 3447 macrotile su 4096. Senza mura si uscirebbe
// da qualunque punto del bordo. Con le mura, l'unico punto di prato che il
// giocatore raggiunge e' il buco sotto la porta sud -- il contenimento lo
// fanno le collisioni, e l'uscita non ha bisogno di nessun caso speciale.
//
// FIRE2 NON ESCE PIU'. Adesso che l'uscita vera c'e', tenere anche quella di
// servizio sarebbe una divergenza dal NES in un tasto che presto servira' al
// menu.
//
// I negozi: questa slice li RICONOSCE e non li apre. Calpestando una porta lo
// shop_id finisce in `town_shop_id`, che la sonda legge -- la conferma che i
// sette id sono 1, 11, 21, 31, 41, 51, 61 arriva da li'. L'interfaccia e' la
// slice dopo, e ha un prerequisito suo: le icone di tipo degli oggetti, senza
// le quali due voci della stessa lista si leggono identiche.
//
// --- eredita' di slice61 ---------------------------------------------
//  slice61 -- svc_run_overlay: entrare in un overlay diventa un servizio
// =====================================================================
// Fino a slice60 il salto in un banco di CODICE esisteva UNA volta sola e
// cablato per un solo banco: quattro righe dentro `run_battle`. Funzionava,
// ma voleva dire che ogni nuova scena fuori dalla finestra fissa -- negozi,
// menu, scene di apertura, un secondo overlay per la magia -- avrebbe dovuto
// ricopiare quelle quattro righe, con la stessa trappola da ricordare ogni
// volta (`main_bank` PRIMA del salto, o la NMI rimappa il banco sbagliato in
// uscita e il `ret` atterra dentro dati).
//
// Qui diventa `svc_run_overlay(bank, arg)`: una funzione sola, esportata
// anche agli overlay, che sa entrare in un banco QUALSIASI e rimettere a
// posto quello di prima. Il banco di ritorno non e' piu' lo zero cablato ma
// `main_bank` com'era all'ingresso -- ed e' questo che rende la primitiva
// annidabile: un overlay puo' chiamarne un altro e ritrovarsi mappato al
// ritorno.
//
// Cosa NON cambia: il comportamento. La battaglia e' l'unico cliente di oggi
// e ci entra per la stessa strada di prima; la prova che il rifacimento non
// ha spostato niente e' che la corsa di validazione deve dare gli stessi
// numeri di slice60, round per round.
//
// --- eredita' di slice60 ---------------------------------------------
//  slice60 -- i nemici lanciano: magia e attacchi speciali
// =====================================================================
// Come slice59, questo file cambia pochissimo: il motore della magia sta
// nell'overlay. Di qua passa solo `svc_fetch_btl`, il prelievo generico dal
// banco 11 -- che adesso ospita, oltre alle statistiche dei nemici e ai dati
// di livello, anche i 92 incantesimi e le 44 voci di IA.
//
// --- eredita' di slice59 ---------------------------------------------
//  slice59 -- i nemici rispondono: IA e ordine di iniziativa
// =====================================================================
// Rispetto a slice58 questo file NON cambia, e la cosa e' significativa: il
// round di battaglia adesso mescola le due parti, i nemici colpiscono, i
// personaggi possono morire e il gruppo puo' cadere -- e tutto questo sta in
// src/ovl_battle.c, dentro il banco 20.
//
// E' esattamente il motivo per cui docs/next_session.md aveva messo l'IA
// nemica in cima alla lista: la finestra fissa ha 169 byte liberi, e questo
// lavoro non ne consuma nemmeno uno. L'unica cosa che passa di qua e' il
// blocco di stato in RAM SGM, cresciuto di 14 byte (la coda dei turni) su 256
// disponibili.
//
// --- eredita' di slice52 ---------------------------------------------
//  slice52 -- la battaglia esce dalla finestra fissa ed entra nel banco 20
// =====================================================================
// PRIMA SLICE DEL BLOCCO B (motore di battaglia). Il comportamento a schermo
// e' quello di slice49: cambia DOVE gira la battaglia.
//
//   slice49: render_battle_screen + battle_tick nel banco FISSO $8000-$BFFF,
//            dove restavano ~1.7KB liberi -- niente spazio per un motore.
//   slice52: tutto in src/ovl_battle.c, compilato per $C000 nel banco 20.
//            Qui restano solo i SERVIZI (svc_*) e la chiamata.
//
// Il confine passa dove deve: nel banco fisso restano il RNG (la sua sequenza
// e' parity col NES ed e' condivisa con l'encounter in overworld), le
// primitive VDP e l'unica funzione che deve mappare il banco 2 per le CHR dei
// personaggi. Nell'overlay va la schermata, e domani il motore.
//
// Lo stato passa per il blocco in RAM SGM a $6000 (src/battle_state.h): la
// RAM non dipende dal banco, la rodata si.
//
// Vedi docs/battle_engine_design.md per il piano delle 8 slice.
//
// --- Original slice44 design notes ---
// slice44 - Full FF1 NES overworld (256x256 macrotiles) with toroidal wrap +
//           collisions, streamed across MegaCart banks 3-6 (4 quadrants).
//
// Aggiunge a slice43b:
//   - Drop ff1_ow_coneria 64x64 window. Use il full 256x256 OW byte-exact
//     dal disasm, splittato in 4 quadranti da 128x128 (16KB each) in bank 3-6:
//        Bank 3: NW (rows   0-127, cols   0-127)
//        Bank 4: NE (rows   0-127, cols 128-255)
//        Bank 5: SW (rows 128-255, cols   0-127)
//        Bank 6: SE (rows 128-255, cols 128-255)
//   - world_player_mx/my = unsigned char (0..255), wrap toroidale via `& 0xFF`.
//   - Spawn al FF1 NES world macro (153, 165) = Coneria castle south entrance.
//   - redraw_ow_view_from_banks(player_mx, player_my): per-cell bank-aware read
//     dal quadrante corretto. Bank changes max 2/row, ~50 totali per redraw, ~50Ãƒâ€šÃ‚Âµs.
//   - Encounter/teleport check bank-aware: select quadrant, read macro_id at
//     player position, restore bank 0.
//   - Audio NMI safety: ogni bank-switched section finisce con mc_select_bank(0)
//     prima di wait_vblank, garantendo che NMI vede bank 0 (sng44 OW theme).
//   - Town/battle/intro flow invariati (banks 1, 2, default 0).
//
// Drop: expand_world + world_cells caching per OW (non piu' necessari, direct
// read from quadrant banks). world_cells resta per TOWN (bank 0 town data).
//
// --- Original slice43b design notes ---
// slice43b - Class selection post-boot-menu (priority 2 di slice43_plan).
//
// Aggiunge a slice43:
//   - run_class_select() chiamato dopo run_boot_menu().
//   - 2x2 grid TEXT-ONLY (primo cut): 4 cell con class label + default name.
//     Sprite + manina cursor deferred a slice43b.1 (polish dopo ROM budget audit).
//   - ASCII '>' cursor a sx del PG attivo (stesso pattern del boot menu).
//   - D-pad cycle class FORWARD (FT->TH->BB->RM->WM->BM), FIRE2 BACKWARD.
//   - Numpad 1-4 jumps direct al PG (Coleco UX bonus from design_input.md).
//   - FIRE1 confirma classe attiva e avanza al next PG (wrap 4->1).
//   - Dopo 4 confirm consecutivi -> esce da class sel a OW handoff.
//   - Bank 1 mai cambiato (Prelude continua seamless, niente CHR da caricare).
//
// Name entry e battle theme deferred a slice43c/d. Sprite rendering ROM-budget
// permitting in slice43b.1.
//
// --- Original slice43 design notes ---
// slice43 - Boot menu post-legend (priority 1 di slice43_plan).
//
// Aggiunge a slice42:
//   - run_boot_menu() chiamato dopo run_legend(), prima dell'handoff a OW.
//   - 3 opzioni: CONTINUE / NEW GAME / RESPOND RATE N (N=1..8)
//   - Cursor '>' su riga corrente, UP/DOWN naviga, FIRE1 agisce.
//   - CONTINUE = inert (no save state implementato ancora). Per NES parity
//     futura, cursor di default su NEW GAME (selected=1).
//   - NEW GAME -> esce dal menu, prosegue a OW (in slice43b: a class sel).
//   - RESPOND RATE -> FIRE1 cicla 1..8, valore salvato in respond_rate
//     (non ancora usato; scroll speed dei message box).
//   - Menu render dentro bank 1 (Prelude continua), strings da intro_menu_lines.
//
// Class sel + name entry + sng50 in bank 2 deferred a slice43b/c/d.
//
// --- Original slice42 design notes ---
// slice42 - MegaCart Phase 2: bank switching + intro scenes integrated.
//
// Aggiunge a slice41:
//   - TITLE screen: Prelude (sng41) suona, FIRE1 per skip a prologue.
//   - PROLOGUE: 13 righe testo rivelate gradualmente con Prologue theme (sng42).
//   - CLASS_SEL: D-pad cicla classi per ognuno dei 4 PG, FIRE1 conferma.
//     Nomi default (no name entry questa slice).
//   - Poi entra in OW (audio sng44) e funziona come slice41.
//
// MegaCart bank layout:
//   - Bank 7 ($8000-$BFFF FIXED): codice, engine, state machine, intro render.
//   - Bank 0 ($C000-$FFFF default): OW + town + battle data + sng44/47.
//   - Bank 1: intro_bank.rom -- sng41 + sng42 + prologue text + class names.
//     Selected solo durante intro scenes; back to bank 0 entrando in OW.
//
// Bank-switch protocol per transizione:
//   silence_audio(); mc_select_bank(N); init_<song>();
//
// Bank 1 symbols extracted via tools/gen_bank_symbols.ps1 -> intro_bank_symbols.h.
// Pointer vars at $CE74-$CE7F vengono dereferenziati per accedere alle song data.
//
// --- Original slice41 / slice40 design notes below ---
//
// slice41 - MegaCart Phase 1: 1MB ROM with restored battle theme.
//
// Identical runtime behavior to slice40 (OW + battle + town + 3 modes audio).
// Difference: output is packaged as MegaCart 1MB ROM by tools/build_megacart.ps1
// instead of the standard 32KB cart. The CPU still sees the same 32KB at
// $8000-$FFFF ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â MegaCart hardware maps last 16KB of ROM file to $8000-$BFFF
// (fixed bank 63) and bank 0 (= first 16KB of file) to $C000-$FFFF at boot.
//
// Phase 1 = NO bank switching at runtime yet. Just file format change. Future
// slices use mc_select_bank(N) to access banks 1..62 for per-zone assets.
//
// Battle theme (sng50) RESTORED: re-added after the factored start_song()
// helper saved enough bytes vs slice40's 3-separate-init pattern.
//
// --- Original slice40 design notes below ---
//
// Estende slice39 aggiungendo Mode_TOWN: quando il player cammina su un OW
// macro con attr1 bit 7 set, si attiva il teleport. Per ora solo teleport
// ID 1 (Coneria Town) e' implementato; gli altri ID stampano un placeholder
// nella message bar e restano in OW.
//
// SGM RAM $2000-$5FFF e' shared tra OW e TOWN: expand_world() / expand_town()
// riscrivono la stessa area (16KB = 128x128 cells per OW, 128x128 per town).
// Transition cost ~16K writes = un quadro di VBlank.
//
// CHR layout (BG):
//   OW    : 128 tiles ff1_owbg_pattern (replicato in 3 banchi)
//   town  : 128 tiles ff1_town_pattern  (idem)
//   battle: BIOS font $20-$7E + class sprites $80-$A3
// Sprite (OAM) handle 0 = player, sempre frame fighter (riusato per town).
//
// Town exit (slice64): NON piu' FIRE2, ma la casella di prato marcata
// TP_TELE_WARP -- "torna alla mappa precedente". Si rientra in overworld alle
// stesse coordinate da cui si era entrati, che sono ancora in
// world_player_mx/my: nessuno le tocca mentre si e' in citta'. Non serve
// lut_ExitTele, che riguarda i teletrasporti di USCITA (TP_TELE_EXIT) -- e nel
// tileset 0 di caselle cosi' non ce n'e' nemmeno una.
//
// BSS resta al default $7000: con DATA solo 1126B (i const grandi finiscono
// in CODE), il default va bene. NON abbassare CRT_ORG_BSS sotto $6000:
// sovrappone world_cells ($2000-$5FFF) e produce schermo nero al boot.

#include <games.h>
#include <video/tms99x8.h>
#include <psg.h>
// slice47: la grafica OW non e' piu' rodata della slice (era ff1_owbg.h,
// 2560 byte di pattern monocromi). Ora vive nel banco 8 a colori veri --
// solo le costanti arrivano dall'header, i dati da owgfx_bank.c.
#include "ff1_owgfx.h"
// slice78: solo le costanti (base delle tile, macrotile di fondo); i 64 byte
// stanno nel banco 8 insieme al resto della grafica OW.
#include "ff1_bridge_tile.h"
#include "owgfx_bank_symbols.h"
#include "ff1_ow_coneria.h"
#include "ff1_encounter.h"
// slice48: il mapman non e' piu' il Fighter bianco di ff1_fighter.h. Ora usa
// gli sprite a colori delle 6 classi (silhouette + accent) dal banco 9.
#include "ff1_mapman_flat.h"
#include "mapman_bank_symbols.h"
#include "ff1_battle_sprites.h"  // declarations only -- DATA gated to gfx_bank.c
// Coneria: da slice63 la mappa e la grafica a colori veri stanno nel banco 15,
// generate insieme da tools/extract_sm_colors.ps1. Qui entrano solo le
// costanti -- i dati si leggono attraverso i simboli del banco.
// ff1_town_coneria.h NON si include piu': conteneva la stessa mappa e il
// pattern monocromo, cioe' una seconda verita' sulla stessa citta'. Da slice64
// non ha piu' nemmeno l'ultima cosa che ci restava dentro: le proprieta' dei
// macrotile sono passate nel banco 15, generate dalla stessa passata di mappa
// e TSA. Averle in un header a parte voleva dire poterle disallineare, e un
// disallineamento fra mappa e proprieta' non da' errore -- da' un muro dove si
// passa e un passaggio dentro una casa.
#include "ff1_towngfx.h"
#include "towngfx_bank_symbols.h"
// slice77: le altre tre mappe standard, stessa forma del banco 15 -- solo le
// costanti (TILE_COUNT, ENTRY, MAP_ID); i dati vivono nei banchi 17/18/19 e
// si raggiungono con i simboli generati da gen_bank_symbols.ps1.
#include "ff1_castle1gfx.h"
#include "castle1gfx_bank_symbols.h"
#include "ff1_castle2gfx.h"
#include "castle2gfx_bank_symbols.h"
#include "ff1_tofgfx.h"
#include "tofgfx_bank_symbols.h"
// Solo le costanti FF1_TELE_*: i 320 byte stanno nel banco 11 (tabella 12
// di svc_fetch_btl).
#include "data/teleport_data.h"
#include "intro_bank_symbols.h"
#include "gfx_bank_symbols.h"   // bank 2 = battle sprite/color/accent data
#include "song_bank_symbols.h"  // bank 10 = sng50 Battle (+ sng53 fanfara)
#include "party_state.h"        // il gruppo, RAM SGM a $6100
#include "battle_state.h"       // blocco condiviso in RAM SGM a $6000
#include "svc_api.h"            // prototipi dei servizi esposti all'overlay
// class_stats.h NON si include piu' qui (slice72): la tabella delle
// statistiche iniziali e' rodata dell'overlay dell'intro, insieme all'unico
// codice che la legge.
#include "data/levelup_data.h"  // solo le costanti: i dati stanno nel banco 11
#include "btldata_bank_symbols.h"
#include "mongfx_bank_symbols.h"  // banco 12 = sagome + dominanti + palette + nomi
#include "ff1_monster_gfx.h"      // solo le costanti: i dati stanno nel banco 12
// Nemici GRANDI, banchi 13/14: la meta' si sceglie dalla pagina CHR della
// formazione. Anche qui solo le costanti; i dati vivono nei rispettivi banchi.
#include "monlg_lo_bank_symbols.h"
#include "monlg_hi_bank_symbols.h"
#include "ff1_monlg_lo.h"
// Solo le COSTANTI (ENROMSTAT_*): i 2560 byte di data_EnemyStats stanno nel
// banco 11, non nella rodata della slice, che e' gia' il collo di bottiglia.
#include "data/enemy_data.h"
// Solo le costanti: i dati di entrambe stanno nel banco 11 (btldata_bank.c).
#include "data/magic_data.h"
#include "data/enemy_ai.h"
// Equipaggiamento (slice65): solo gli offset dei campi e il numero di voci.
// Le tabelle vere stanno nel banco 16 insieme a nomi, prezzi, liste dei negozi
// e icone -- vedi src/itemdata_bank.c.
#include "data/weapon_data.h"
#include "data/armor_data.h"
#include "itemdata_bank_symbols.h"
#include "ff1_item_icons.h"   // solo le costanti: le tile stanno nel banco 16
#include "data/item_names.h"   // solo le macro dello spazio degli id (i nomi stanno nel banco 16)
#include "shop_state.h"        // il listino composto, blocco condiviso a $6300
// slice76: gli abitanti della mappa corrente e i flag di gioco, blocco
// condiviso a $6500. La slice li SCRIVE (all'ingresso in citta') e li LEGGE
// (per disegnare, per bloccare il passo, per capire chi si ha davanti); il
// banco 26 li legge per sapere quale battuta esce.
#include "world_state.h"

// MegaCart bank switch: read from $FFC0+N selects bank N for $C000-$FFFF.
static void mc_select_bank(unsigned char n) {
    (void)*(volatile unsigned char *)(0xFFC0 + n);
}

// Song length/loop constants for sng41 (Prelude) + sng42 (Prologue).
// The actual event arrays live in bank 1; these compile-time constants
// must match songs/sng41.h + sng42.h.
#define SNG41_SQ1_LEN_K   256
#define SNG41_SQ1_LOOP_K  0
#define SNG41_SQ2_LEN_K   258
#define SNG41_SQ2_LOOP_K  2
#define SNG41_TRI_LEN_K   1
#define SNG41_TRI_LOOP_K  0
#define SNG42_SQ1_LEN_K   83
#define SNG42_SQ1_LOOP_K  0
#define SNG42_SQ2_LEN_K   86
#define SNG42_SQ2_LOOP_K  0
#define SNG42_TRI_LEN_K   46
#define SNG42_TRI_LOOP_K  0

extern void ay_write(unsigned int reg_val) __z88dk_fastcall;
extern int nmi_install_isr(void *fn);
extern unsigned int joy_read_p1(void);   // src/joy.asm -- vedi svc_joystick
extern volatile unsigned char _tms9918_status_register;
#define AY_W(r, v) ay_write(((unsigned int)(r) << 8) | (unsigned char)(v))

#define BIOS_FONT_ADDR  ((const void*)0x15A3)
#define BIOS_FONT_LEN   760
#define FONT_TILE_BASE   0x20
#define SPR_TILE_BASE    0x80
// Posa di esultanza: 36 tile subito dopo le 36 della posa in piedi.
#define CHEER_TILE_BASE  0xA4
// Generatori OAM dello strato di accento: 4 per posa, uno per personaggio.
#define ACC_HANDLE_STAND 1
#define ACC_HANDLE_CHEER 5

// FULL FF1 OW = 256x256 macrotiles, toroidal (mod 256 both axes).
// Split across banks 3-6 (NW/NE/SW/SE quadrants, 128x128 each).
#define OW_FULL_MACRO_W  256
#define OW_FULL_MACRO_H  256
#define OW_QUADRANT_NW   3
#define OW_QUADRANT_NE   4
#define OW_QUADRANT_SW   5
#define OW_QUADRANT_SE   6
#define OW_BANK_BASE     ((const unsigned char *)0xC000)
// Banco 8: grafica OW a colori (pattern + color table + TSA rimappate).
// Possibile solo da quando la ROM e' a 512KB: a 128KB il banco 7 era il
// banco fisso e i banchi 1-6 erano tutti occupati.
#define OWGFX_BANK       8
// Banco 9: sprite mapman a colori delle 6 classi.
#define MAPMAN_BANK      9

// Generatori sprite del mapman, per indice di frame (0-7):
//   0-7   meta' alta del corpo   (sotto-palette sprite 0 del NES)
//   8-15  meta' bassa del corpo  (sotto-palette sprite 1)
//   16-23 incarnato
//   24-31 contorno nero
#define MAPMAN_SPR_TOP_BASE     0
#define MAPMAN_SPR_BOT_BASE     8
#define MAPMAN_SPR_ACCENT_BASE  16
#define MAPMAN_SPR_OUTLINE_BASE 24
// slice76: i contorni degli abitanti, uno sprite 16x16 per slot. Il mapman ne
// occupa 32 (4 strati x 8 pose) e il generatore di sprite del TMS in modo
// grande ne tiene 64: da 32 in poi era tutto libero.
#define NPC_SPR_BASE            32
// La prima voce della SAT degli abitanti. Le 0-3 sono il mapman, e restano le
// prime APPOSTA: quando su una scanline ci sono piu' di quattro sprite il
// TMS9918 spegne quelli con indice PIU' ALTO ([[tms9918-oam-priority]]). Cosi'
// il giocatore non sparisce mai, e a cadere e' al massimo il contorno di un
// abitante che gli sta di fianco -- che sotto ha ancora la sagoma di fondo.
#define NPC_SAT_BASE            4
// The last 64 bytes of the switchable window ($FFC0-$FFFF = blob offset
// 16320-16383) are the MegaCart bank-switch trigger range: reading them
// involuntarily re-banks $C000-$FFFF. In a full 16KB quadrant blob those
// offsets correspond to quadrant-local row 127, cols 64-127. We must NOT
// dereference there -- return a fallback ocean macro instead. This costs a
// thin band of fallback tiles at global rows 127/255 (quadrant seams), far
// from the Coneria spawn. Proper fix (relocate those 64 macros) deferred.
#define OW_TRIGGER_OFFSET   0x3FC0
#define OW_FALLBACK_MACRO   23

// LEGACY (preserved per accidente da slice43b -- non piu' usato per OW gameplay
// ma alcuni helper rendering vi fanno ancora reference; rimossi dove sostituiti).
#define MACRO_W       FF1_OW_coneria_W
#define MACRO_H       FF1_OW_coneria_H
#define WORLD_CELL_W  (MACRO_W * 2)
#define WORLD_CELL_H  (MACRO_H * 2)
#define WORLD_MASK_X  (WORLD_CELL_W - 1)
#define WORLD_MASK_Y  (WORLD_CELL_H - 1)

#define TOWN_MACRO_W  64
#define TOWN_MACRO_H  64
#define TOWN_CELL_W   (TOWN_MACRO_W * 2)
#define TOWN_CELL_H   (TOWN_MACRO_H * 2)
#define TOWN_MASK_X   (TOWN_CELL_W - 1)
#define TOWN_MASK_Y   (TOWN_CELL_H - 1)

#define PLAYER_SCREEN_X 120
#define PLAYER_SCREEN_Y 88

#define DIR_DOWN  0
#define DIR_UP    1
#define DIR_LEFT  2
#define DIR_RIGHT 3

// FF1 NES new-game spawn: world macro (153, 165) = south of Coneria castle.
// (Bank_00 unsram init scroll = $92, $9E; player visible at $99, $A5.)
// Punto di partenza: ingresso sud del castello di Coneria, coordinate del NES.
//
// Sovrascrivibili dalla riga di comando (`-DSPAWN_WORLD_MX=...`) SOLO per le
// build di prova. Serve a una cosa sola, ed e' una cosa vera: dal continente
// iniziale non si raggiunge nessun nemico dotato di IA -- lo dice
// tools/find_ai_domains.ps1, i domini 0x2B e 0x2C sono gli unici due della
// riga senza -- e senza incontrarne uno il ramo della magia nemica non si puo'
// osservare. Il binario che si gioca resta questo; quello di prova e' un altro
// file, e va detto quale dei due si sta guardando.
#ifndef SPAWN_WORLD_MX
#define SPAWN_WORLD_MX 153
#endif
#ifndef SPAWN_WORLD_MY
#define SPAWN_WORLD_MY 165
#endif

// Player macro displayed at screen cell (15, 11) (= sprite pixel 120, 88).
// Top-left visible cell maps to world cell (player_mx*2 - 15, player_my*2 - 11).
#define VIEW_PLAYER_CELL_X 15
#define VIEW_PLAYER_CELL_Y 11

#ifdef FORCE_QUEST
// BUILD DI PROVA della quest (slice77, suffisso _t): incontri casuali SPENTI.
// La rotta per il tempio attraversa 32 caselle con l'attributo FIGHT acceso
// (misurate da una BFS sugli stessi byte del gioco) e al 10/256 a passo un
// incontro a meta' strada e' quasi certo -- e spezzerebbe il piano. Gli
// incontri hanno gia' la loro corsa (mame_drive_battle.lua): qui il soggetto
// sono i teletrasporti e la storia.
#define ENCOUNTER_RATE_LAND 0
#else
#define ENCOUNTER_RATE_LAND 10
#endif
#define ENCOUNTER_RATE_SEA   3

// Discrete macrotile movement (slice41 mode): each tap shifts the camera
// by EXACTLY 1 macrotile (2 cells = 16 px) in a SINGLE frame. No half-tile
// intermediate frames. STEP_COOLDOWN_FRAMES gates the rate when holding a
// direction: 0 = max speed (60 macros/sec), 1 = 30/sec, 2 = 20/sec.
// Each step does ONE redraw_view (~6.5ms VRAM), so even cooldown=0 fits
// comfortably in the 16.6ms NTSC frame budget.
#define STEP_COOLDOWN_FRAMES  1

#define MODE_OW     0
#define MODE_TOWN   2

#define N_PARTY 4

// La battaglia e' un overlay di CODICE nel banco 20: la slice lo mappa, salta
// al suo ingresso fisso e riprende quando la battaglia e' finita.
#define BATTLE_BANK   20
// Banco 21: overlay delle scene di apertura (legenda, menu, selezione dei
// personaggi). Girano una volta sola al boot -- e' il motivo per cui sono le
// prime a uscire dalla finestra fissa, dove occupavano 2115 byte per sempre.
#define INTRO_OVL_BANK 21
// Banco 22: l'overlay del negozio. Ci si entra dalla CITTA', cioe' da dentro
// un contesto gia' avviato: e' il primo cliente che sfrutta davvero il fatto
// che svc_run_overlay rimetta il banco LETTO all'ingresso invece dello zero.
#define SHOP_BANK      22
// Il menu (slice73). Banco suo e non il 22 accanto al negozio: il negozio ha
// 5861 byte liberi e oggi il menu ci starebbe, ma deve ancora crescere di due
// sottoschermate -- magia fuori battaglia ed equipaggiamento manuale. Un banco
// costa 16KB su 512 e la ROM non e' un vincolo da slice45; il vincolo sarebbe
// il giorno in cui due scene nello stesso banco smettono di starci insieme.
#define MENU_BANK      24
// Banco 26: il dialogo (slice76). Ci sta perche' ci deve stare il TESTO --
// 3113 byte gia' sciolti dal DTE del ROM, contro i 657 liberi nella finestra
// fissa. Una volta che il testo e' in un banco, chi lo legge conviene che
// stia li' accanto.
#define TALK_BANK      26
// Banco 27: la scena del ponte (slice78). Vedi l'intestazione -- il banco lo
// chiede l'immagine, non il codice.
#define BRIDGE_BANK    27
// Bit 15 dell'argomento del banco 26: acceso vuol dire "sto parlando a un
// MACROTILE" e nel byte basso c'e' gia' l'id di dialogo. Spento vuol dire che
// davanti c'e' un abitante e nel byte basso c'e' il suo id di oggetto.
#define TALK_ARG_TILE  0x8000
// Banco 15: Coneria a colori veri, mappa compresa (slice63).
#define TOWNGFX_BANK  15
// slice77: le altre tre mappe standard, una per banco (stessa forma del 15).
#define CASTLE1GFX_BANK 17
#define CASTLE2GFX_BANK 18
#define TOFGFX_BANK     19

// =====================================================================
//  slice77 -- LA SELEZIONE DELLA MAPPA
// =====================================================================
// Una riga per mappa: banco, id di mappa FF1, ingresso, canzone, e i DODICI
// indirizzi dei simboli del banco -- che sono diversi per banco, perche' li
// sceglie il linker quando impagina i dati. La tabella e' PIATTA e di
// `unsigned int`: un aggregato const a due dimensioni (o di struct) finirebbe
// nella sezione DATA, che con la BSS a $7000 e' gia' oltre il limite
// ([[rodata-trap-small-arrays]], [[coleco-data-section-overflow]]).
//
// LA TABELLA E' RODATA DELLA SLICE, cioe' vive nel banco 0 oltre $C000: si
// legge SOLO col banco 0 mappato. Per questo la riga scelta si COPIA in `TD`
// (RAM, sempre visibile) all'ingresso in mappa: e' cio' che permette a
// town_read_prop di fare la sua escursione nel banco della mappa senza dover
// prima tornare al banco 0 per chiedersi dove stanno le cose.
#define MAP_SLOT_TOWN     0
#define MAP_SLOT_CASTLE1  1
#define MAP_SLOT_CASTLE2  2
#define MAP_SLOT_TOF      3
#define MAP_SLOT_COUNT    4

// Quale tema suona nella mappa. La citta' suona sng47 dal banco 1 (dove sta
// dai tempi di slice43b); castello e tempio suonano dal banco 10, accanto
// alla musica di battaglia, perche' e' il banco che la NMI gia' sa mappare.
#define MAPSONG_TOWN    0
#define MAPSONG_CASTLE  1
#define MAPSONG_TOF     2

// Indici dentro una riga della tabella.
#define MD_BANK        0
#define MD_MAP_ID      1
#define MD_ENTRY_X     2
#define MD_ENTRY_Y     3
#define MD_SONG        4
#define MD_PATTERN     5
#define MD_COLOR       6
#define MD_TSA_UL      7
#define MD_TSA_UR      8
#define MD_TSA_DL      9
#define MD_TSA_DR     10
#define MD_MAP        11
#define MD_PROP       12
#define MD_NPC_PATTERN 13
#define MD_NPC_COLOR  14
#define MD_NPC_SLOTS  15
#define MD_NPC_SPRITE 16
#define MD_STRIDE     17

static const unsigned int map_desc[MAP_SLOT_COUNT * MD_STRIDE] = {
    /* Coneria citta' (mappa 0, tileset 0) */
    TOWNGFX_BANK, FF1_TOWNGFX_MAP_ID,
    FF1_TOWNGFX_ENTRY_X, FF1_TOWNGFX_ENTRY_Y, MAPSONG_TOWN,
    TOWNGFX_PATTERN_ADDR, TOWNGFX_COLOR_ADDR,
    TOWNGFX_TSA_UL_ADDR, TOWNGFX_TSA_UR_ADDR,
    TOWNGFX_TSA_DL_ADDR, TOWNGFX_TSA_DR_ADDR,
    TOWNGFX_MAP_ADDR, TOWNGFX_PROP_ADDR,
    TOWNGFX_NPC_PATTERN_ADDR, TOWNGFX_NPC_COLOR_ADDR,
    TOWNGFX_NPC_SLOTS_ADDR, TOWNGFX_NPC_SPRITE_ADDR,
    /* Coneria Castle 1F (mappa 8, tileset 1) */
    CASTLE1GFX_BANK, FF1_CASTLE1GFX_MAP_ID,
    FF1_CASTLE1GFX_ENTRY_X, FF1_CASTLE1GFX_ENTRY_Y, MAPSONG_CASTLE,
    CASTLE1GFX_PATTERN_ADDR, CASTLE1GFX_COLOR_ADDR,
    CASTLE1GFX_TSA_UL_ADDR, CASTLE1GFX_TSA_UR_ADDR,
    CASTLE1GFX_TSA_DL_ADDR, CASTLE1GFX_TSA_DR_ADDR,
    CASTLE1GFX_MAP_ADDR, CASTLE1GFX_PROP_ADDR,
    CASTLE1GFX_NPC_PATTERN_ADDR, CASTLE1GFX_NPC_COLOR_ADDR,
    CASTLE1GFX_NPC_SLOTS_ADDR, CASTLE1GFX_NPC_SPRITE_ADDR,
    /* Coneria Castle 2F (mappa 24, tileset 1) */
    CASTLE2GFX_BANK, FF1_CASTLE2GFX_MAP_ID,
    FF1_CASTLE2GFX_ENTRY_X, FF1_CASTLE2GFX_ENTRY_Y, MAPSONG_CASTLE,
    CASTLE2GFX_PATTERN_ADDR, CASTLE2GFX_COLOR_ADDR,
    CASTLE2GFX_TSA_UL_ADDR, CASTLE2GFX_TSA_UR_ADDR,
    CASTLE2GFX_TSA_DL_ADDR, CASTLE2GFX_TSA_DR_ADDR,
    CASTLE2GFX_MAP_ADDR, CASTLE2GFX_PROP_ADDR,
    CASTLE2GFX_NPC_PATTERN_ADDR, CASTLE2GFX_NPC_COLOR_ADDR,
    CASTLE2GFX_NPC_SLOTS_ADDR, CASTLE2GFX_NPC_SPRITE_ADDR,
    /* Temple of Fiends (mappa 12, tileset 5) */
    TOFGFX_BANK, FF1_TOFGFX_MAP_ID,
    FF1_TOFGFX_ENTRY_X, FF1_TOFGFX_ENTRY_Y, MAPSONG_TOF,
    TOFGFX_PATTERN_ADDR, TOFGFX_COLOR_ADDR,
    TOFGFX_TSA_UL_ADDR, TOFGFX_TSA_UR_ADDR,
    TOFGFX_TSA_DL_ADDR, TOFGFX_TSA_DR_ADDR,
    TOFGFX_MAP_ADDR, TOFGFX_PROP_ADDR,
    TOFGFX_NPC_PATTERN_ADDR, TOFGFX_NPC_COLOR_ADDR,
    TOFGFX_NPC_SLOTS_ADDR, TOFGFX_NPC_SPRITE_ADDR,
};

// La riga scelta, copiata in RAM. `unsigned int` anche per banco e ingresso:
// tenere la copia della stessa forma della tabella fa della copia un ciclo.
static unsigned int TD[MD_STRIDE];
// La mappa in cui si sta (slot 0-3). Sonda: la legge anche il Lua, perche'
// due mappe col castello sono due schermate che a occhio si somigliano, e
// "sono salito al secondo piano" dalla sola grafica non si asserisce.
static unsigned char cur_map_slot = MAP_SLOT_TOWN;

// Copia la riga `slot` in TD. VA CHIAMATA COL BANCO 0 MAPPATO: la tabella e'
// rodata della slice, che sotto un altro banco e' spazzatura plausibile.
static void town_select_map(unsigned char slot) {
    unsigned char i;
    const unsigned int *row = &map_desc[(unsigned int)slot * MD_STRIDE];
    for (i = 0; i < MD_STRIDE; i++) TD[i] = row[i];
    cur_map_slot = slot;
}

// Lo slot che porta la mappa FF1 `map_id`, o 0xFF se non ce l'abbiamo ancora.
// Anche questa legge la tabella: banco 0 mappato.
static unsigned char map_slot_for(unsigned char map_id) {
    unsigned char s;
    const unsigned int *p = &map_desc[MD_MAP_ID];
    for (s = 0; s < MAP_SLOT_COUNT; s++) {
        if (*p == map_id) return s;
        p += MD_STRIDE;
    }
    return 0xFF;
}
// Banco 16: oggetti e negozi -- armi, armature, prezzi, liste, nomi, icone.
#define ITEMDATA_BANK 16
// Banco 12: sagome dei nemici, dominanti per riga, palette, nomi.
#define MONGFX_BANK   12
// Banchi 13/14: nemici GRANDI, pagine CHR 0-7 e 8-15. Una formazione dichiara
// UNA pagina sola, quindi una battaglia ne mappa uno solo.
#define MONLG_LO_BANK 13
#define MONLG_HI_BANK 14

// Le tile dei nemici partono dove finiva la posa in piedi ($80-$A3) e arrivano
// fino a $FF: 92 tile in tutto. Da slice56 non sono piu' quattro fette fisse da
// 16 -- un tipo grande ne costa 36 -- ma un'allocazione progressiva che decide
// l'overlay in decode_formation e passa in BST.type_tile_base.
//
// 92 BASTANO, e non e' una speranza: tools/census_tile_budget.ps1 misura tutte
// e 256 le varianti di formazione e il massimo e' 72 tile (due tipi grandi e
// nessun piccolo, p.es. TROLL+BULL). Il caso da 104 tile temuto nel piano --
// due grandi piu' due piccoli -- NON ESISTE in tabella: nel tipo "mix" le due
// POSIZIONI grandi sono quasi sempre due esemplari dello stesso gruppo, cioe'
// uno slot grafico solo. Il piu' caro dei misti chiede 68.
// L'unica formazione che sfora e' Chaos (99 tile), che pero' e' un'immagine
// TSA 14x12 con un percorso di disegno tutto suo e non passa di qui.
// MON_TILE_BASE / MON_TILE_END arrivano da battle_state.h (slice69): erano
// scritti qui, nell'overlay di battaglia e -- appena l'allocazione si e' mossa
// nel banco 23 -- sarebbero stati in tre posti.
#define OVERLAY_ENTRY 0xC000
// Banco DATI con la musica di battaglia. Non e' il banco dell'overlay: la NMI
// ci salta dentro a ogni tick e torna subito al banco 20.
#define SONG_BANK     10
// Banco DATI con le tabelle di regole della battaglia (curva EXP, livelli).
#define BTLDATA_BANK  11

#define VOL_SQ1 11
#define VOL_SQ2  9
#define VOL_TRI  8

// SGM cell buffer: 16KB at $2000-$5FFF, reused by TOWN expansion (OW no
// longer uses it -- direct-read from quadrant banks per slice44 redesign).
// MACRO, non `static volatile unsigned char *const`. Sembra la stessa cosa e
// non lo e': un puntatore costante e' una VARIABILE IN RODATA, e la rodata di
// questa slice sconfina oltre $C000, cioe' nella finestra commutabile. In
// slice63 `expand_town` ha cominciato a girare col banco 15 mappato, e
// leggere il puntatore ha restituito byte del banco 15: la mappa espansa
// finiva a un indirizzo a caso.
//
// Il sintomo non assomigliava alla causa. A schermo si vedeva la citta'
// disegnata benissimo ma "dal posto sbagliato", come se fosse sbagliato il
// punto di ingresso -- e infatti la telecamera, misurata, era identica alla
// slice precedente. Le tre cose che il gioco riportava dalla RAM (puntatore
// alla mappa, primi byte, casella d'ingresso) erano tutte GIUSTE: il difetto
// stava a valle, nella destinazione della scrittura.
//
// Come macro l'indirizzo diventa un immediato dentro il codice, che sta nella
// finestra fissa e c'e' sempre. Vedi [[rodata-trap-small-arrays]].
#define world_cells ((volatile unsigned char *)0x2000)

// Cache of the 4 OW TSA tables (UL/UR/DL/DR -> 128 cell IDs each) in slice44
// BSS, so the OW redraw can read them while a quadrant bank (3-6) is selected
// in the upper window. Without this cache, ff1_owbg_tsa_dr (which lives at
// $C011 in slice44's bank-0 rodata) would return garbage when bank != 0.
// 4 x 128 = 512 bytes RAM; populated by load_ow_chr_palette while bank 0 is
// selected. The other 3 tsa tables ARE in bank 7 ($BE91-$BF91 fixed) and
// would be safe to read direct, but caching all 4 keeps the code uniform
// and protects against future linker re-placement.
static unsigned char tsa_ul_cache[128];
static unsigned char tsa_ur_cache[128];
static unsigned char tsa_dl_cache[128];
static unsigned char tsa_dr_cache[128];

// =====================================================================
//  Il gruppo (slice53): statistiche VERE dalla tabella del NES
// =====================================================================
// Prima erano quattro array con HP inventati a mano ({35,28,22,22}) e tre su
// quattro erano anche sbagliati: la tabella del NES da' 35/30/28/25 per
// FT/TH/WM/BM. Ora il gruppo vive in RAM SGM (party_state.h) e viene
// inizializzato replicando NewGame_LoadStartingStats.
//
// party_class[] resta come sorgente per il rendering fuori dalla battaglia
// (mapman, accento) ed e' una comodita': PARTY.chr[i].cls e' la verita'.
static unsigned char party_class[N_PARTY] = { 0, 1, 4, 5 };  // FT/TH/WM/BM
// Velocita' delle finestre di dialogo (1-8), scelta nel menu di boot. La
// sceglie l'overlay dell'intro e torna nel suo valore di ritorno; nessuno la
// legge ancora -- servira' quando ci saranno i dialoghi.
static unsigned char respond_rate = 1;
// I quattro nomi predefiniti sono passati nell'overlay dell'intro (slice72):
// li' erano gia' rodata -- la selezione dei personaggi li mostra -- e averli
// in due posti voleva dire poterli cambiare in uno solo.

// Il PASSO fra un personaggio e l'altro, pubblicato dal gioco perche' le sonde
// Lua smettano di poterlo sbagliare. Lo scrive party_new_game.
unsigned char party_chr_size = 0;

// Se questi due divergono, il gruppo e il rendering parlano di lunghezze
// diverse. Array di dimensione negativa = errore di compilazione, non un bug
// da scoprire a schermo.
typedef char party_n_agreement_check[(N_PARTY == PARTY_N) ? 1 : -1];

// =====================================================================
//  La nascita del gruppo: DI QUA c'e' solo la regia (slice72)
// =====================================================================
// Il corpo -- lettura della tabella delle classi, nomi, HP, cariche, primo
// ricalcolo -- e' passato nell'overlay dell'intro (banco 21). Occupava **842
// byte della finestra fissa per sempre** e girava una volta sola, subito dopo
// la selezione dei personaggi: lo stesso rapporto fra costo e uso che in
// slice62 aveva fatto uscire di la' le scene di apertura, ed e' la prima
// delle tre leve di [[fixed-window-full]].
//
// QUI RESTANO TRE COSE, e nessuna delle tre poteva stare di la':
//   1. le classi FORZATE dalle build di prova. `-Defines` vale solo per la
//      compilazione della slice, non per quella degli overlay: se la scelta
//      delle classi finisse tutta di la', sei corse di validazione su sette
//      smetterebbero di poter fissare il gruppo;
//   2. `party_chr_size`, la sonda che pubblica il passo fra un personaggio e
//      l'altro. E' una variabile di questo file e l'overlay non la vede;
//   3. i SEMI delle build di prova -- magie, alterazioni, ferite, oggetti --
//      che vanno scritti DOPO la nascita, perche' la nascita li azzererebbe.
//
// La chiamata all'overlay e' la seconda: `INTRO_ARG_BUILD_PARTY` acceso nel
// bit 15 dell'argomento sceglie il secondo ingresso. Vedi overlay_main in
// src/ovl_intro.c.
#define INTRO_ARG_BUILD_PARTY  0x8000

// NOTA MISURATA (slice78), perche' la conclusione e' controintuitiva e mi ha
// fatto perdere un giro: nei semi delle build di prova NON conviene prendere
// il puntatore al personaggio. `PARTY.chr[2].spells[0]` ha indice COSTANTE,
// quindi sccz80 calcola l'indirizzo a tempo di compilazione e non emette
// nessuna moltiplicazione; sostituirlo con una funzione `pc(2)->spells[0]`
// mette una CHIAMATA dove c'era un immediato. Provato su tutti e 41 gli
// accessi: FORCE_MAGMENU e' passato da -109 a -156 byte.
//
// La nota su svc_equip_recalc (prendere il puntatore una volta) vale solo con
// indice VARIABILE, cioe' dentro un ciclo -- ed e' li' che si e' applicata,
// nel seme di FORCE_QUEST.
static void party_new_game(void) {
    int i;

#ifdef FORCE_SHOP
    // BUILD DI PROVA del negozio (suffisso _t). Le classi sono FISSE perche' i
    // permessi si provano solo con classi note: la selezione dei personaggi la
    // guidano pressioni cieche, e un gruppo diverso a ogni corsa renderebbe il
    // risultato "Rapier negata" indistinguibile da "Rapier negata a chi poteva".
    //   guerriero -> puo' tutto quello che il negozio di Coneria vende
    //   monaco    -> nunchaku si, stocco no, e per giunta la sua formula
    //                speciale del danno
    //   mago bianco / mago nero -> due divieti diversi sulla stessa lista
    party_class[0] = CLS_FT;
    party_class[1] = CLS_BB;
    party_class[2] = CLS_WM;
    party_class[3] = CLS_BM;
#endif
#ifdef FORCE_SPELLS
    // Stesse classi fisse di FORCE_SHOP e per la stessa ragione: un mago
    // bianco che capita a caso non e' una prova.
    party_class[0] = CLS_FT;
    party_class[1] = CLS_BB;
    party_class[2] = CLS_WM;
    party_class[3] = CLS_BM;
#endif
#ifdef FORCE_AIL
    //   mago nero   -> SLEP, l'unico incantesimo comprabile a Coneria che
    //                  infligge un'alterazione
    //   mago bianco -> LAMP, che ne toglie una (e la sua vittima e' seduta
    //                  accanto: il monaco parte cieco)
    party_class[0] = CLS_FT;
    party_class[1] = CLS_BB;
    party_class[2] = CLS_WM;
    party_class[3] = CLS_BM;
#endif
#ifdef FORCE_BUFF
    // Le tre magie scelte coprono i TRE modi di scegliere un bersaglio, che e'
    // la parte che si rompe piu' facilmente: FOG un compagno, RUSE chi lancia,
    // LOCK un nemico.
    party_class[0] = CLS_FT;
    party_class[1] = CLS_BB;
    party_class[2] = CLS_WM;
    party_class[3] = CLS_BM;
#endif
#ifdef FORCE_EQUIP
    party_class[1] = CLS_BB;
#endif
#ifdef FORCE_MAGMENU
    // BUILD DI PROVA della magia fuori battaglia (slice75). Due maghi bianchi
    // non servono: serve UN lanciatore con tutte e tredici le magie in mano, e
    // il resto del gruppo in condizioni diverse fra loro.
    //   mago bianco  -> lancia lui, ed e' la classe che quelle magie le impara
    //   guerriero    -> ferito, per la famiglia CURE
    //   ladro        -> avvelenato, per PURE
    //   mago nero    -> caduto, per LIFE
    party_class[0] = CLS_FT;
    party_class[1] = CLS_TH;
    party_class[2] = CLS_WM;
    party_class[3] = CLS_BM;
#endif
#ifdef FORCE_EQMENU
    // BUILD DI PROVA dell'equipaggiamento manuale (slice74). Le classi sono
    // fisse e scelte per i PERMESSI, che sono la meta' delicata: il guerriero
    // porta quasi tutto, il monaco quasi niente ma le nunchucks si', i due
    // maghi hanno divieti diversi sulla stessa armatura. Con classi a caso
    // "rifiutato" non si distingue da "rifiutato a chi poteva".
    party_class[0] = CLS_FT;
    party_class[1] = CLS_BB;
    party_class[2] = CLS_WM;
    party_class[3] = CLS_BM;
#endif
#ifdef FORCE_MENU
    // BUILD DI PROVA del MENU (slice73). Il gruppo classico FT/TH/WM/BM, e
    // fisso per la solita ragione: la schermata delle statistiche si controlla
    // NUMERO PER NUMERO contro lut_ClassStartingStats, e con classi a caso
    // "INT vale 20" non si distingue da "INT vale 20 per chi non doveva".
    // Il mago nero e' l'ultimo apposta: e' quello con INT 20, cioe' il caso in
    // cui la statistica appena resa viva si legge piu' chiaramente.
    party_class[0] = CLS_FT;
    party_class[1] = CLS_TH;
    party_class[2] = CLS_WM;
    party_class[3] = CLS_BM;
#endif

#ifdef FORCE_QUEST
    // Classi fisse come tutte le build di prova: quattro guerrieri, perche'
    // qui la battaglia di Garland e' un PASSAGGIO della storia, non il
    // soggetto -- il gruppo va potenziato (sotto, dopo la nascita) e quattro
    // FIGHT senza sottomenu sono la coreografia piu' corta.
    party_class[0] = CLS_FT;
    party_class[1] = CLS_FT;
    party_class[2] = CLS_FT;
    party_class[3] = CLS_FT;
#endif

    // Le quattro classi tornano impacchettate a tre bit l'una, nello stesso
    // formato in cui la selezione le aveva consegnate: cosi' esiste UN solo
    // formato fra slice e overlay, e non due che possono divergere.
    {
        unsigned int classes = 0;
        for (i = 0; i < N_PARTY; i++) {
            classes |= (unsigned int)(party_class[i] & 7) << (i * 3);
        }
        svc_run_overlay(INTRO_OVL_BANK, INTRO_ARG_BUILD_PARTY | classes);
    }

    // Il PASSO fra un personaggio e l'altro, pubblicato dal gioco perche' le
    // sonde smettano di poterlo sbagliare. Era cablato a 44 in due script Lua,
    // e con slice65 e' diventato 79: la trappola numero 1 del catalogo dice
    // che il magic va cambiato anche negli script, ed e' gia' stata
    // ricalpestata una volta. Un numero che il gioco RACCONTA non si
    // disallinea.
    party_chr_size = (unsigned char)sizeof(chr_t);

    // I SEMI DELLE BUILD DI PROVA NON SONO PIU' QUI (slice78): stanno in
    // src/ovl_intro.c, dentro build_party. Erano l'unico codice della
    // finestra fissa che nella ROM VERA non esiste, e in cambio le nove build
    // `-Defines` competevano per i byte piu' scarsi del progetto -- con
    // FORCE_MAGMENU che aveva smesso di starci.
    //
    // Ci potevano andare solo da quando build_all.ps1 passa i `-Defines`
    // ANCHE agli overlay: prima l'overlay non poteva sapere che si stava
    // compilando una build di prova, ed e' il motivo per cui erano nate qui.

}

// =====================================================================
//  Audio engine (Battle Theme sng50, NES-parity 4-voci minus PCM)
// =====================================================================
typedef struct { unsigned int period; unsigned char frames; } note_event_t;
// sng44 (OW theme) NON si include piu' qui (slice77): e' passato nel banco
// 10 con tutte le altre canzoni, quando il percorso start_song e' morto e la
// tabella song_tbl ha voluto una riga uniforme (un cast di indirizzo dentro
// un inizializzatore const e' un errore di parse per sccz80). Le costanti K
// qui sotto replicano songs/sng44.h come per tutte le canzoni in banco.
#define SNG44_SQ1_LEN_K   45
#define SNG44_SQ1_LOOP_K  0
#define SNG44_SQ2_LEN_K   90
#define SNG44_SQ2_LOOP_K  0
#define SNG44_TRI_LEN_K   204
#define SNG44_TRI_LOOP_K  0
// sng47 (Town theme) moved to bank 1 (intro_bank.c) for slice43b ROM budget.
// init_town_song uses init_bank1_song pattern, similar to Prelude.
#define SNG47_SQ1_LEN_K   37
#define SNG47_SQ1_LOOP_K  0
#define SNG47_SQ2_LEN_K   44
#define SNG47_SQ2_LOOP_K  0
#define SNG47_TRI_LEN_K   32
#define SNG47_TRI_LOOP_K  0
// sng50 (Battle) vive nel banco 10 (src/song_bank.c). Lunghezze e punti di
// loop ricopiati da src/songs/sng50.h: quell'header lo include SOLO il banco,
// qui servono i numeri. Se un giorno si riestrae la canzone, vanno riallineati.
#define SNG50_SQ1_LEN_K   160
#define SNG50_SQ1_LOOP_K  17
#define SNG50_SQ2_LEN_K   279
#define SNG50_SQ2_LOOP_K  20
#define SNG50_TRI_LEN_K   342
#define SNG50_TRI_LOOP_K  33
// sng53 (Victory fanfare), stesso banco. Il NES la fa ripartire in loop
// finche' il riquadro delle ricompense resta a schermo: qui uguale.
#define SNG53_SQ1_LEN_K   60
#define SNG53_SQ1_LOOP_K  28
#define SNG53_SQ2_LEN_K   60
#define SNG53_SQ2_LOOP_K  28
#define SNG53_TRI_LEN_K   118
#define SNG53_TRI_LOOP_K  22

typedef struct {
    const note_event_t *events;
    unsigned int total, loop, idx;
    unsigned char remaining;
} ch_state_t;
static ch_state_t sq1_st, sq2_st, tri_st;
static volatile unsigned char audio_enabled = 0;
// MegaCart bank where the CURRENTLY PLAYING song's event data lives. The audio
// NMI selects this bank before reading sng events, so playback is correct no
// matter which bank the main code has mapped. 0 = bank 0 (OW sng44); 1 = bank 1
// (intro/town sng41/42/47).
static volatile unsigned char audio_bank = 0;
// Bank the FOREGROUND code wants active for its current scene. The NMI restores
// this after each audio tick, so the main code always sees its own bank (the
// audio's bank-1 excursion happens entirely while the main code is paused in
// the NMI). 0 = OW/town/battle (data in bank 0); 1 = intro scenes (bank 1).
// This is why TOWN renders correctly even though sng47 lives in bank 1: town
// map/tsa/pattern data is bank 0, and main_bank=0 keeps it visible.
static volatile unsigned char main_bank = 0;

static void apply_sq1(unsigned int p) {
    if (p) { psg_tone(0, p); psg_volume(0, VOL_SQ1); } else psg_volume(0, 0);
}
static void apply_sq2(unsigned int p) {
    if (p) { psg_tone(1, p); psg_volume(1, VOL_SQ2); } else psg_volume(1, 0);
}
static void apply_tri(unsigned int p) {
    if (p) {
        AY_W(0, p & 0xFF); AY_W(1, (p >> 8) & 0x0F);
        AY_W(7, 0x3E); AY_W(8, VOL_TRI);
    } else AY_W(8, 0);
}
static void tick_sq1(void) {
    if (sq1_st.remaining) { sq1_st.remaining--; return; }
    sq1_st.idx++;
    if (sq1_st.idx >= sq1_st.total) sq1_st.idx = sq1_st.loop;
    apply_sq1(sq1_st.events[sq1_st.idx].period);
    sq1_st.remaining = sq1_st.events[sq1_st.idx].frames - 1;
}
static void tick_sq2(void) {
    if (sq2_st.remaining) { sq2_st.remaining--; return; }
    sq2_st.idx++;
    if (sq2_st.idx >= sq2_st.total) sq2_st.idx = sq2_st.loop;
    apply_sq2(sq2_st.events[sq2_st.idx].period);
    sq2_st.remaining = sq2_st.events[sq2_st.idx].frames - 1;
}
static void tick_tri(void) {
    if (tri_st.remaining) { tri_st.remaining--; return; }
    tri_st.idx++;
    if (tri_st.idx >= tri_st.total) tri_st.idx = tri_st.loop;
    apply_tri(tri_st.events[tri_st.idx].period);
    tri_st.remaining = tri_st.events[tri_st.idx].frames - 1;
}
// slice77: start_song (285 byte) NON C'E' PIU'. Era il percorso "canzone in
// rodata con struct" e lo usava solo sng44: adesso il tema della overworld
// sta nel banco 10 con tutte le altre canzoni e passa da init_song.

// Canzoni che vivono in un banco DATI: gli array stanno agli indirizzi puntati
// dalle variabili <prefisso>_sngXX_*. I puntatori si dereferenziano DOPO che il
// chiamante ha mappato quel banco, altrimenti si legge un altro banco.
// Il parametro `bank` diventa audio_bank: e' il banco che la NMI mappera' a
// ogni tick per leggere gli eventi, prima di rimettere main_bank.
// (slice52: era init_bank1_song, cablato sul banco 1. La battaglia suona dal
// banco 10, quindi il banco e' diventato un argomento.)
// init_bank_song NON C'E' PIU' (slice78): era una funzione da DIECI argomenti,
// 241 byte, e ogni chiamata ne impilava dieci. Il suo corpo vive dentro
// init_song, che gli argomenti li legge da una tabella. Vedi piu' sotto.
// slice77: i temi delle mappe nuove, dal banco 10. Le costanti replicano gli
// header (songs/sng48.h, sng4C.h, sng54.h) come per tutte le altre canzoni.
#define SNG48_SQ1_LEN_K   32
#define SNG48_SQ1_LOOP_K  0
#define SNG48_SQ2_LEN_K   61
#define SNG48_SQ2_LOOP_K  0
#define SNG48_TRI_LEN_K   16
#define SNG48_TRI_LOOP_K  0
#define SNG4C_SQ1_LEN_K   42
#define SNG4C_SQ1_LOOP_K  0
#define SNG4C_SQ2_LEN_K   136
#define SNG4C_SQ2_LOOP_K  0
#define SNG4C_TRI_LEN_K   93
#define SNG4C_TRI_LOOP_K  0
#define SNG54_SQ1_LEN_K   10
#define SNG54_SQ1_LOOP_K  0
#define SNG54_SQ2_LEN_K   10
#define SNG54_SQ2_LOOP_K  0
#define SNG54_TRI_LEN_K   10
#define SNG54_TRI_LOOP_K  0
#define SNG51_SQ1_LEN_K   35
#define SNG51_SQ1_LOOP_K  0
#define SNG51_SQ2_LEN_K   35
#define SNG51_SQ2_LOOP_K  0
#define SNG51_TRI_LEN_K   48
#define SNG51_TRI_LOOP_K  0
// La fanfara del NES dura 204 quadri; il nostro motore non ha i one-shot,
// quindi chi la suona aspetta FANFARE_FRAMES e rimette il tema della mappa.
// 200 e non 204: sei quadri PRIMA del loop, non sei quadri di ripartenza.
#define FANFARE_FRAMES  200
// =====================================================================
//  slice77: TUTTE le canzoni della slice in UNA tabella
// =====================================================================
// Una chiamata a init_bank_song sono DIECI argomenti impilati: ~70 byte di
// finestra fissa a call-site. A slice76 i call-site erano quattro; con
// castello, tempio e fanfara sarebbero diventati sette. Adesso il call-site
// e' UNO (dentro init_song) e ogni canzone e' una riga di rodata da 20 byte.
//
// IL CONTRATTO: init_song si chiama COL BANCO 0 MAPPATO (la tabella e'
// rodata della slice), mappa da sola il banco della canzone, e rimette lo
// zero. E' il contratto di tutti i suoi chiamanti -- enter_ow, enter_town,
// il main, la fanfara. Le due canzoni di BATTAGLIA (sng50, sng53) NON sono
// qui: le avviano le svc_ sotto l'overlay 20 mappato, dove questa tabella
// non si puo' leggere.
#define SONG_ROW_OW       0
#define SONG_ROW_PRELUDE  1
// Le tre righe delle mappe stanno in fila nell'ordine di MAPSONG_*: il tema
// della mappa corrente e' la riga SONG_ROW_TOWN + TD[MD_SONG].
#define SONG_ROW_TOWN     2
#define SONG_ROW_CASTLE   3
#define SONG_ROW_TOF      4
#define SONG_ROW_FANFARE  5
#define SONG_ROW_SHOP     6
// slice78: il Prologue. Era nel banco 1 dai tempi di slice62 e non era MAI
// stato suonato -- la scena del ponte e' il posto per cui il NES lo usa
// (track $42, bank_0D.asm:2212).
#define SONG_ROW_PROLOGUE 7
// Le due canzoni della BATTAGLIA stanno nella tabella come tutte le altre da
// slice78. Prima erano fuori perche' le avvia una svc_ mentre e' mappato
// l'overlay 20, dove la tabella (rodata del banco 0) non si legge: adesso
// init_song il banco 0 se lo mappa da sola e rimette main_bank.
#define SONG_ROW_BATTLE   8
#define SONG_ROW_VICTORY  9
static const unsigned int song_tbl[10 * 10] = {
    SONG_BANK, SONG_SNG44_SQ1_ADDR, SNG44_SQ1_LEN_K, SNG44_SQ1_LOOP_K,
       SONG_SNG44_SQ2_ADDR, SNG44_SQ2_LEN_K, SNG44_SQ2_LOOP_K,
       SONG_SNG44_TRI_ADDR, SNG44_TRI_LEN_K, SNG44_TRI_LOOP_K,
    1, INTRO_SNG41_SQ1_ADDR, SNG41_SQ1_LEN_K, SNG41_SQ1_LOOP_K,
       INTRO_SNG41_SQ2_ADDR, SNG41_SQ2_LEN_K, SNG41_SQ2_LOOP_K,
       INTRO_SNG41_TRI_ADDR, SNG41_TRI_LEN_K, SNG41_TRI_LOOP_K,
    1, INTRO_SNG47_SQ1_ADDR, SNG47_SQ1_LEN_K, SNG47_SQ1_LOOP_K,
       INTRO_SNG47_SQ2_ADDR, SNG47_SQ2_LEN_K, SNG47_SQ2_LOOP_K,
       INTRO_SNG47_TRI_ADDR, SNG47_TRI_LEN_K, SNG47_TRI_LOOP_K,
    SONG_BANK, SONG_SNG48_SQ1_ADDR, SNG48_SQ1_LEN_K, SNG48_SQ1_LOOP_K,
       SONG_SNG48_SQ2_ADDR, SNG48_SQ2_LEN_K, SNG48_SQ2_LOOP_K,
       SONG_SNG48_TRI_ADDR, SNG48_TRI_LEN_K, SNG48_TRI_LOOP_K,
    SONG_BANK, SONG_SNG4C_SQ1_ADDR, SNG4C_SQ1_LEN_K, SNG4C_SQ1_LOOP_K,
       SONG_SNG4C_SQ2_ADDR, SNG4C_SQ2_LEN_K, SNG4C_SQ2_LOOP_K,
       SONG_SNG4C_TRI_ADDR, SNG4C_TRI_LEN_K, SNG4C_TRI_LOOP_K,
    SONG_BANK, SONG_SNG54_SQ1_ADDR, SNG54_SQ1_LEN_K, SNG54_SQ1_LOOP_K,
       SONG_SNG54_SQ2_ADDR, SNG54_SQ2_LEN_K, SNG54_SQ2_LOOP_K,
       SONG_SNG54_TRI_ADDR, SNG54_TRI_LEN_K, SNG54_TRI_LOOP_K,
    SONG_BANK, SONG_SNG51_SQ1_ADDR, SNG51_SQ1_LEN_K, SNG51_SQ1_LOOP_K,
       SONG_SNG51_SQ2_ADDR, SNG51_SQ2_LEN_K, SNG51_SQ2_LOOP_K,
       SONG_SNG51_TRI_ADDR, SNG51_TRI_LEN_K, SNG51_TRI_LOOP_K,
    1, INTRO_SNG42_SQ1_ADDR, SNG42_SQ1_LEN_K, SNG42_SQ1_LOOP_K,
       INTRO_SNG42_SQ2_ADDR, SNG42_SQ2_LEN_K, SNG42_SQ2_LOOP_K,
       INTRO_SNG42_TRI_ADDR, SNG42_TRI_LEN_K, SNG42_TRI_LOOP_K,
    SONG_BANK, SONG_SNG50_SQ1_ADDR, SNG50_SQ1_LEN_K, SNG50_SQ1_LOOP_K,
       SONG_SNG50_SQ2_ADDR, SNG50_SQ2_LEN_K, SNG50_SQ2_LOOP_K,
       SONG_SNG50_TRI_ADDR, SNG50_TRI_LEN_K, SNG50_TRI_LOOP_K,
    SONG_BANK, SONG_SNG53_SQ1_ADDR, SNG53_SQ1_LEN_K, SNG53_SQ1_LOOP_K,
       SONG_SNG53_SQ2_ADDR, SNG53_SQ2_LEN_K, SNG53_SQ2_LOOP_K,
       SONG_SNG53_TRI_ADDR, SNG53_TRI_LEN_K, SNG53_TRI_LOOP_K,
};
// Avvia la canzone `idx` della tabella. MAPPA DA SOLA i banchi che le servono
// e rimette `main_bank`, non lo zero: e' cio' che la rende chiamabile da
// QUALUNQUE parte, comprese le svc_ che girano mentre e' mappato l'overlay
// della battaglia. E' la stessa regola di svc_run_overlay e svc_fetch_btl --
// il banco di ritorno e' quello letto, mai quello supposto
// ([[svc-return-bank-rule]]).
//
// Il corpo di init_bank_song sta QUI DENTRO e non in una funzione sua: dieci
// argomenti impilati costavano ~70 byte a chiamata e le chiamate erano tre.
static void init_song(unsigned char idx) {
    unsigned int v[10];
    unsigned char k;
    const unsigned int *p;
    const note_event_t *e;

    audio_enabled = 0;
    // La tabella e' rodata della slice: si legge SOLO col banco 0 mappato, e
    // qui il banco mappato puo' essere un overlay qualunque.
    mc_select_bank(0);
    p = &song_tbl[(unsigned int)idx * 10];
    for (k = 0; k < 10; k++) v[k] = p[k];

    // Da qui in poi si dereferenziano i puntatori della canzone, che vivono
    // nel SUO banco.
    mc_select_bank((unsigned char)v[0]);
    audio_bank = (unsigned char)v[0];
    e = *(const note_event_t **)v[1];
    sq1_st.events = e; sq1_st.total = v[2]; sq1_st.loop = v[3];
    sq1_st.idx = 0; apply_sq1(e[0].period); sq1_st.remaining = e[0].frames - 1;
    e = *(const note_event_t **)v[4];
    sq2_st.events = e; sq2_st.total = v[5]; sq2_st.loop = v[6];
    sq2_st.idx = 0; apply_sq2(e[0].period); sq2_st.remaining = e[0].frames - 1;
    e = *(const note_event_t **)v[7];
    tri_st.events = e; tri_st.total = v[8]; tri_st.loop = v[9];
    tri_st.idx = 0; apply_tri(e[0].period); tri_st.remaining = e[0].frames - 1;

    mc_select_bank(main_bank);
    audio_enabled = 1;
}
// Il tema della mappa corrente. Vedi il contratto di init_song.
static void init_map_song(void) {
    init_song((unsigned char)(SONG_ROW_TOWN + TD[MD_SONG]));
}
// Tema di battaglia (sng50) dal banco 10. Il chiamante DEVE aver mappato il
// banco 10: qui si dereferenziano i puntatori che ci vivono dentro.
static void silence_audio(void) {
    audio_enabled = 0;
    psg_volume(0, 0);
    psg_volume(1, 0);
    AY_W(7, 0x3F);
    AY_W(8, 0);
}
static void audio_nmi_tick(void) {
    if (!audio_enabled) return;
    // Select the song's bank to read its events, then RESTORE the foreground
    // scene's bank. The main code is paused for the whole NMI, so it never
    // observes the bank-1 excursion -- it always resumes on main_bank.
    mc_select_bank(audio_bank);
    tick_sq1(); tick_sq2(); tick_tri();
    mc_select_bank(main_bank);
}

// =====================================================================
//  VDP helpers
// =====================================================================
void svc_wait_vblank(void) {
    _tms9918_status_register = 0;
    while ((_tms9918_status_register & 0x80) == 0) { }
}
static void render_string(unsigned char col, unsigned char row, const char *s) {
    unsigned int nt_addr = 0x1800 + (unsigned int)row * 32 + col;
    int len = 0;
    while (s[len]) len++;
    if (len > 0) vdp_vwrite((void*)s, nt_addr, len);
}
// render_char NON C'E' PIU' (slice78): era definita e non la chiamava
// nessuno. Chi scrive un carattere solo passa da render_string con una
// stringa di uno, o scrive la name table da se'.
// =====================================================================
//  I TRE TERZI, una volta sola (slice76)
// =====================================================================
// In Mode 2 la tabella dei pattern e quella dei colori sono divise in tre
// blocchi da 2KB, uno per terzo di schermo, e una tile che deve vedersi
// ovunque va scritta in tutti e tre. Fino a slice75 quella tripletta era
// SCRITTA A MANO in quattordici punti diversi: 42 chiamate a `vdp_vwrite`, e
// ognuna nella finestra fissa costa una ventina di byte fra i tre argomenti
// impilati e la chiamata.
//
// Fattorizzarle e' la leva 2 di [[fixed-window-full]], quella che costa meno
// di uno spostamento: due funzioni di tre righe al posto di 42 punti di
// chiamata. Ed e' anche l'unica forma in cui "scriverne solo due su tre" --
// che a schermo si vede come un terzo di schermo con le tile sbagliate --
// smette di essere possibile.
//
// `addr` e' l'indirizzo nel PRIMO terzo: $0000 per i pattern, $2000 per i
// colori. Gli altri due li aggiunge la funzione.
static void vwrite3(const void *src, unsigned int addr, unsigned int len) {
    vdp_vwrite((void*)src, addr,          len);
    vdp_vwrite((void*)src, addr + 0x0800, len);
    vdp_vwrite((void*)src, addr + 0x1000, len);
}
static void vfill3(unsigned int addr, unsigned char val, unsigned int len) {
    vdp_vfill(addr,          val, len);
    vdp_vfill(addr + 0x0800, val, len);
    vdp_vfill(addr + 0x1000, val, len);
}
static void load_tile_3banks(unsigned char tile_id, const unsigned char *pat) {
    vwrite3(pat, (unsigned int)tile_id * 8, 8);
}
static void load_color_per_row_3banks(unsigned char tile_id, const unsigned char *colors_src) {
    vwrite3(colors_src, 0x2000 + (unsigned int)tile_id * 8, 8);
}
// Una posa di personaggio: 36 tile consecutive (6 classi x 6 tile) da due array
// paralleli del banco 2, sagome e colori per riga. La usano sia la posa in
// piedi sia quella di esultanza, che prima ne avevano una copia a testa: nella
// finestra fissa un doppio ciclo annidato in due punti costa piu' dei byte che
// vale. Il chiamante ha gia' mappato il banco 2.
#define POSE_TILES 36
static void load_class_pose(unsigned char base, const unsigned char *pat,
                            const unsigned char *col) {
    int k;
    for (k = 0; k < POSE_TILES; k++) {
        load_tile_3banks((unsigned char)(base + k), pat + k * 8);
        load_color_per_row_3banks((unsigned char)(base + k), col + k * 8);
    }
}
// CALLER MUST have bank 2 selected (data lives there). Reads the accent layout
// for class `cls` from a flat [288] array in gfx_bank (6 tiles x 8 byte per
// classe). `base` sceglie la posa: in piedi oppure esultanza.
// Lo sprite OAM e' 16x16 e copre solo le prime due righe di tile (UL UR ML MR);
// la riga DL/DR non ha strato di accento.
static void load_accent_oam(unsigned char handle, unsigned char cls,
                            const unsigned char *base) {
    unsigned char buf[32];
    int i;
    const unsigned char *cl   = base + (unsigned int)cls * 48;
    for (i = 0; i < 8; i++) buf[ 0 + i] = cl[0 * 8 + i];   // tile 0 UL
    for (i = 0; i < 8; i++) buf[ 8 + i] = cl[2 * 8 + i];   // tile 2 ML
    for (i = 0; i < 8; i++) buf[16 + i] = cl[1 * 8 + i];   // tile 1 UR
    for (i = 0; i < 8; i++) buf[24 + i] = cl[3 * 8 + i];   // tile 3 MR
    vdp_set_sprite_16(handle, buf);
}
// clear_row / render_u3 / render_tile_id sono migrate nell'overlay (slice52):
// le usava solo la schermata di battaglia.

// =====================================================================
//  OW (slice36-39)
// =====================================================================
// Read one macrotile from the full 256x256 OW. Caller specifies world macro
// coords (mx, my) already wrapped to [0, 256). Selects the appropriate
// quadrant bank, reads the byte, and (caller-controlled) may leave the bank
// selected to amortize the switch cost across a run.
//
// Always re-selects the quadrant bank before reading: the audio NMI may have
// switched to the song's bank (audio_bank) between any two reads, so caching a
// "current bank" is unsafe. The select is a cheap $FFC0+N read. (~768/redraw =
// ~2.6ms; the redraw already overruns a frame so movement speed is unaffected,
// and audio stays at full 60Hz with NO suspension.)
static unsigned char ow_read_macro(unsigned char mx, unsigned char my) {
    unsigned char Q    = (unsigned char)(((my >> 7) << 1) | (mx >> 7));
    unsigned char bank = (unsigned char)(OW_QUADRANT_NW + Q);
    unsigned char qx   = mx & 0x7F;
    unsigned char qy   = my & 0x7F;
    unsigned int  off  = ((unsigned int)qy << 7) + qx;
    if (off >= OW_TRIGGER_OFFSET) return OW_FALLBACK_MACRO;  // avoid $FFC0+ trigger
    mc_select_bank(bank);
    return OW_BANK_BASE[off];
}

// Render the visible 32x24 NT directly from the quadrant banks. The player
// is rendered at screen cell (VIEW_PLAYER_CELL_X, VIEW_PLAYER_CELL_Y) =
// (15, 11). The top-left visible CELL maps to world cell
// ((player_mx*2 - 15) mod 512, (player_my*2 - 11) mod 512); each cell maps
// back to a macro (cell >> 1) and a sub-cell (UL/UR/DL/DR per cell & 1).
//
// Bank switches: with row-major traversal, the bank only changes when
// world_mx crosses col 128 within a row -- max 2 changes per row, ~48 total.
// At end of frame, bank is restored to 0 so the next NMI reads sng44 OK.
// =====================================================================
//  slice78 -- IL PONTE
// =====================================================================
// Dove sta, e da dove viene il numero: `lut_InitUnsramFirstPage` del ROM
// (bank_00.dat offset $3000, byte $09 e $0A). Sul NES `bridge_x`/`bridge_y`
// stanno in unsram e NON vengono MAI scritti dal codice: nascono da quella
// tabella e restano li' per tutta la partita. Qui sono due costanti.
#define BRIDGE_OW_X  152
#define BRIDGE_OW_Y  152

// Il ponte c'e'? Il bit lo accende il Re (Talk_KingConeria, banco 26).
#define BRIDGE_VISIBLE()  ((WORLD.progress & WPROG_BRIDGE) != 0)

// La scena del ponte, una volta sola: 0 = mai calpestato, 1 = calpestato (la
// scena parte al prossimo giro del ciclo), 2 = gia' vista. Sono i tre stati
// di `bridgescene` sul NES (00 / 01 / $80), con gli stessi passaggi.
#define BRIDGESCENE_NONE  0
#define BRIDGESCENE_DUE   1
#define BRIDGESCENE_DONE  2
static unsigned char bridgescene = BRIDGESCENE_NONE;

// Le quattro tile del ponte scritte sopra la vista gia' disegnata, se la sua
// casella e' a schermo. DOPO il ridisegno e non dentro, per la stessa ragione
// degli abitanti di slice76: dentro il ciclo delle 768 celle sarebbe un
// confronto per cella: qui sono al massimo quattro scritture.
//
// `origin_cx/cy` sono la cella di mondo in alto a sinistra, in CELLE (mezzo
// macrotile), e la mappa e' toroidale: la sottrazione va riportata a segno o
// il ponte appena fuori dal bordo sinistro varrebbe colonna 500 invece di -2.
// SI DISEGNA SOLO SE STA TUTTO DENTRO LO SCHERMO, e la mezza misura non si
// perde: il giocatore e' fisso alla cella (15,11), quindi quando il ponte e'
// a meta' fuori sta a quindici celle di distanza -- e quando ci si cammina
// sopra e' esattamente al centro. Gestire i due casi di bordo costava ~180
// byte di finestra fissa (misurati) per pixel che nessuno guarda, e in piu'
// la scrittura da due byte a cavallo di una riga e' il difetto #1 di slice73
// che aspetta solo di essere rifatto.
static void draw_bridge(unsigned short origin_cx, unsigned short origin_cy) {
    unsigned int sc, sr;
    unsigned char b[2];

    if (!BRIDGE_VISIBLE()) return;

    sc = ((unsigned int)(BRIDGE_OW_X * 2) - origin_cx) & 0x1FF;
    sr = ((unsigned int)(BRIDGE_OW_Y * 2) - origin_cy) & 0x1FF;
    if (sc > 30) return;      /* senza segno: fuori a sinistra diventa enorme */
    if (sr > 22) return;

    b[0] = FF1_BRIDGE_TILE_BASE + 0;
    b[1] = FF1_BRIDGE_TILE_BASE + 1;
    vdp_vwrite(b, 0x1800 + sr * 32 + sc, 2);
    b[0] = FF1_BRIDGE_TILE_BASE + 2;
    b[1] = FF1_BRIDGE_TILE_BASE + 3;
    vdp_vwrite(b, 0x1800 + (sr + 1) * 32 + sc, 2);
}

static void redraw_ow_view_from_banks(unsigned char player_mx, unsigned char player_my) {
    unsigned short origin_cx = (unsigned short)((player_mx * 2 - VIEW_PLAYER_CELL_X) & 0x1FF);
    unsigned short origin_cy = (unsigned short)((player_my * 2 - VIEW_PLAYER_CELL_Y) & 0x1FF);
    unsigned char buf[32];
    int sx, sy;
    // No audio suspension: the audio NMI re-selects audio_bank before reading
    // sng events (see audio_nmi_tick), and ow_read_macro re-selects its quadrant
    // bank per read, so playback stays at full 60Hz even though the redraw maps
    // banks 3-6 and overruns a frame.
    for (sy = 0; sy < 24; sy++) {
        unsigned short wcy = (origin_cy + (unsigned short)sy) & 0x1FF;
        unsigned char  wmy = (unsigned char)(wcy >> 1);
        unsigned char  subcy = (unsigned char)(wcy & 1);
        for (sx = 0; sx < 32; sx++) {
            unsigned short wcx = (origin_cx + (unsigned short)sx) & 0x1FF;
            unsigned char  wmx = (unsigned char)(wcx >> 1);
            unsigned char  subcx = (unsigned char)(wcx & 1);
            unsigned char m = ow_read_macro(wmx, wmy);
            if (subcy == 0) buf[sx] = (subcx == 0) ? tsa_ul_cache[m] : tsa_ur_cache[m];
            else            buf[sx] = (subcx == 0) ? tsa_dl_cache[m] : tsa_dr_cache[m];
        }
        vdp_vwrite(buf, 0x1800 + sy * 32, 32);
    }
    mc_select_bank(0);  // leave bank 0 mapped for the OW main-loop rodata reads
    draw_bridge(origin_cx, origin_cy);
}

static unsigned char battlestep = 0;
static unsigned char battlestep_sign = 0;
static unsigned char battlecounter = 0;

// La tabella del RNG copiata in RAM SGM (slice54). ff1_rng_lut e' rodata di
// questa slice, quindi vive oltre $C000: leggibile solo col banco 0 mappato.
// Finche' il RNG serviva solo all'encounter in overworld andava bene; ora lo
// usa anche il passaggio di livello, che gira mentre e' mappato il banco 11 --
// e leggerebbe dati di livello al posto di numeri casuali. 256 byte di RAM
// tolgono il problema alla radice, per chiunque lo chiami e da qualunque banco.
// Stesso rimedio delle cache tsa_*_cache.
static unsigned char rng_lut_cache[256];
static void rng_cache_init(void) {          // CHIAMARE col banco 0 mappato
    int i;
    for (i = 0; i < 256; i++) rng_lut_cache[i] = ff1_rng_lut[i];
}
static unsigned char battle_step_rng(void) {
    if (battlestep_sign & 0x80) {
        battlestep--;
        if (battlestep == 0) battlestep_sign = (unsigned char)(battlestep_sign + 0xA0);
    } else {
        battlestep++;
        if (battlestep == 0) battlestep_sign = (unsigned char)(battlestep_sign + 0xA0);
    }
    return rng_lut_cache[battlestep];
}
static unsigned char get_battle_formation(unsigned char domain) {
    unsigned char rng_val, slot;
#ifdef FORCE_FORMATION
    // Build di PROVA soltanto (`-DFORCE_FORMATION=0x..`). Serve a incontrare
    // un nemico DOTATO DI IA senza dipendere da dove si e' e da cosa pesca la
    // tabella dei pesi: dal continente iniziale non se ne raggiunge nessuno, e
    // spostare lo spawn non basta perche' ff1_formation_weight favorisce le
    // prime quattro caselle del dominio, dove spesso l'IA non c'e'.
    // Il contatore lo si incrementa lo stesso: la sequenza del generatore
    // resta quella, cosi' la prova non si porta dietro un secondo scarto.
    battlecounter++;
    (void)domain;
    return (unsigned char)FORCE_FORMATION;
#else
    battlecounter++;
    rng_val = ff1_rng_lut[battlecounter];
    slot = ff1_formation_weight[rng_val & 0x3F];
    return ff1_domains[domain][slot];
#endif
}
static unsigned char compute_domain(unsigned char nes_x, unsigned char nes_y, unsigned char attr1) {
    unsigned char sub;
    if (!(attr1 & FF1_OW_ATTR1_FIGHT)) return 0xFF;
    sub = attr1 & FF1_OW_ATTR1_SUBMASK;
    if (sub == 0x02) return 0x42;
    if (sub == 0x01 || sub == 0x03) return (unsigned char)(0x40 | ((nes_y >> 7) & 1));
    return (unsigned char)((nes_y & 0xE0) >> 2) | (unsigned char)(nes_x >> 5);
}

// slice47: colori OW veri. Il vecchio codice riempiva l'intera color table
// con 0x3C (verde chiaro su verde scuro) -- da cui la overworld monocroma.
// Ora pattern e colore arrivano dal banco 8, generati da
// tools/extract_ow_colors.ps1: ogni tile TMS e' una coppia (tile CHR NES,
// sotto-palette), 236 combinazioni sulle 256 disponibili.
static void load_ow_chr_palette(void) {
    int i;
    const unsigned char *p;

    // Backdrop nero come su NES (era dark blue, visibile nell'overscan).
    vdp_color(VDP_INK_WHITE, VDP_INK_BLACK, VDP_INK_BLACK);

    // Il chiamante (enter_ow) ha gia' fatto silence_audio, ma azzeriamo
    // esplicitamente: se una NMI passasse mentre e' mappato il banco 8,
    // leggerebbe gli eventi di sng44 (banco 0) come pixel di terreno.
    audio_enabled = 0;
    mc_select_bank(OWGFX_BANK);

    p = *(const unsigned char **)OWGFX_PATTERN_ADDR;
    vwrite3(p, 0x0000, FF1_OWGFX_TILE_COUNT * 8);

    p = *(const unsigned char **)OWGFX_COLOR_ADDR;
    vwrite3(p, 0x2000, FF1_OWGFX_TILE_COUNT * 8);

    // slice78: le quattro tile del PONTE, negli slot 236-239 che il tileset
    // lascia liberi (ne usa 236 su 256). Si caricano SEMPRE, anche quando il
    // ponte non c'e' ancora: costano 64 byte di VRAM e nessuno le disegna
    // finche' WPROG_BRIDGE e' spento. Caricarle solo "quando serve" vorrebbe
    // dire un secondo percorso di caricamento che gira una volta nella
    // partita, cioe' il posto ideale per un difetto che non si vede mai.
    p = *(const unsigned char **)OWGFX_BRIDGE_PATTERN_ADDR;
    vwrite3(p, 0x0000 + FF1_BRIDGE_TILE_BASE * 8, 32);
    p = *(const unsigned char **)OWGFX_BRIDGE_COLOR_ADDR;
    vwrite3(p, 0x2000 + FF1_BRIDGE_TILE_BASE * 8, 32);

    // Le TSA vanno copiate in BSS: il redraw le legge mentre e' selezionato
    // un banco quadrante (3-6), quindi non possono restare nel banco 8.
    p = *(const unsigned char **)OWGFX_TSA_UL_ADDR;
    for (i = 0; i < 128; i++) tsa_ul_cache[i] = p[i];
    p = *(const unsigned char **)OWGFX_TSA_UR_ADDR;
    for (i = 0; i < 128; i++) tsa_ur_cache[i] = p[i];
    p = *(const unsigned char **)OWGFX_TSA_DL_ADDR;
    for (i = 0; i < 128; i++) tsa_dl_cache[i] = p[i];
    p = *(const unsigned char **)OWGFX_TSA_DR_ADDR;
    for (i = 0; i < 128; i++) tsa_dr_cache[i] = p[i];

    mc_select_bank(0);
    // audio_enabled resta 0: il chiamante fa init_song(SONG_ROW_OW) subito dopo,
    // che riaccende l'audio con lo stato della canzone gia' pronto.
}
// Colori del mapman della classe in testa al gruppo, copiati in RAM: il
// rendering li usa ogni frame e non puo' rimappare il banco 9 ogni volta.
static unsigned char mapman_top_col = VDP_INK_WHITE;
static unsigned char mapman_bot_col = VDP_INK_WHITE;
static unsigned char mapman_acc_col = VDP_INK_WHITE;

// Carica i 24 generatori sprite (8 alto + 8 basso + 8 incarnato) della classe
// `cls` dal banco 9, piu' i tre colori. Da chiamare a ogni ingresso OW/citta'.
static void load_mapman_sprites(unsigned char cls) {
    int i;
    const unsigned char *base;
    unsigned int cls_off = (unsigned int)cls * FF1_MAPMAN_CLASS_BYTES;
    // audio_enabled SI RIMETTE COM'ERA, non si lascia spento (slice77bis).
    // Lasciarlo a zero e' stata LA MUSICA CHE MUORE USCENDO DAL NEGOZIO:
    // town_restore_gfx riaccendeva l'audio e POI chiamava questa funzione,
    // che lo rispegneva per sempre. Da slice73, su ogni ritorno da negozio e
    // menu, e invisibile alle corse -sound none -- trovato A ORECCHIO su
    // CoolCV. Identico ad [[audio-fetch-btl-silence]]: stessa classe, stessa
    // cura di svc_fetch_btl.
    unsigned char prev_audio = audio_enabled;

    audio_enabled = 0;
    mc_select_bank(MAPMAN_BANK);

    base = *(const unsigned char **)MAPMAN_TOP_ADDR;
    for (i = 0; i < 8; i++) {
        vdp_set_sprite_16(MAPMAN_SPR_TOP_BASE + i,
                          (void*)(base + cls_off + (unsigned int)i * 32));
    }
    base = *(const unsigned char **)MAPMAN_BOT_ADDR;
    for (i = 0; i < 8; i++) {
        vdp_set_sprite_16(MAPMAN_SPR_BOT_BASE + i,
                          (void*)(base + cls_off + (unsigned int)i * 32));
    }
    base = *(const unsigned char **)MAPMAN_ACCENT_ADDR;
    for (i = 0; i < 8; i++) {
        vdp_set_sprite_16(MAPMAN_SPR_ACCENT_BASE + i,
                          (void*)(base + cls_off + (unsigned int)i * 32));
    }
    base = *(const unsigned char **)MAPMAN_OUTLINE_ADDR;
    for (i = 0; i < 8; i++) {
        vdp_set_sprite_16(MAPMAN_SPR_OUTLINE_BASE + i,
                          (void*)(base + cls_off + (unsigned int)i * 32));
    }

    base = *(const unsigned char **)MAPMAN_TOP_COLOR_ADDR;
    mapman_top_col = base[cls];
    base = *(const unsigned char **)MAPMAN_BOT_COLOR_ADDR;
    mapman_bot_col = base[cls];
    base = *(const unsigned char **)MAPMAN_ACCENT_COLOR_ADDR;
    mapman_acc_col = base[cls];

    mc_select_bank(0);
    audio_enabled = prev_audio;
}

// Quattro strati disgiunti (uno per valore di pixel NES): nessuno copre
// l'altro, quindi l'ordine SAT non e' critico -- ma sono ESATTAMENTE i 4
// sprite per scanline che il TMS9918 consente. Regge perche' in overworld e
// I contorni via dallo schermo. Serve prima di OGNI escursione in un overlay:
// gli sprite non appartengono alla name table, quindi il negozio, il menu e il
// riquadro di dialogo si disegnano SOTTO di loro e i contorni degli abitanti
// restano appesi sopra una schermata che non li riguarda. Nessuno degli
// overlay puo' rimediare da solo -- non sa quanti sono ne' dove stanno.
static void hide_npc_sprites(void) {
    unsigned char i;
    for (i = 0; i < NPC_MAX; i++) {
        vdp_put_sprite_16(NPC_SAT_BASE + i, 0, 200, 0, VDP_INK_TRANSPARENT);
    }
}

// in citta' il mapman e' l'unico sprite; aggiungerne altri sulle sue righe
// ne farebbe sparire uno.
static void draw_mapman(int sprite_handle) {
    vdp_put_sprite_16(0, PLAYER_SCREEN_X, PLAYER_SCREEN_Y,
                      MAPMAN_SPR_ACCENT_BASE + sprite_handle, mapman_acc_col);
    vdp_put_sprite_16(1, PLAYER_SCREEN_X, PLAYER_SCREEN_Y,
                      MAPMAN_SPR_TOP_BASE + sprite_handle, mapman_top_col);
    vdp_put_sprite_16(2, PLAYER_SCREEN_X, PLAYER_SCREEN_Y,
                      MAPMAN_SPR_BOT_BASE + sprite_handle, mapman_bot_col);
    vdp_put_sprite_16(3, PLAYER_SCREEN_X, PLAYER_SCREEN_Y,
                      MAPMAN_SPR_OUTLINE_BASE + sprite_handle, VDP_INK_BLACK);
}

static void load_ow_player_sprite(void) {
    load_mapman_sprites(party_class[0]);
}
static void enter_ow(unsigned char player_mx, unsigned char player_my) {
    // I contorni degli abitanti della citta' da cui si esce: in overworld non
    // c'e' nessuno a nasconderli, e resterebbero neri in mezzo alla mappa.
    hide_npc_sprites();
    silence_audio();
    main_bank = 0;             // OW data + sng44 all in bank 0
    mc_select_bank(0);
    // Blank NT first: stops the screen from showing scrambled tiles while
    // the pattern table is mid-swap. Tile 0 in OW pattern is uniform empty.
    vdp_vfill(0x1800, 0x00, 768);
    load_ow_chr_palette();
    load_ow_player_sprite();
    redraw_ow_view_from_banks(player_mx, player_my);
    // SAT[0..3] sono i quattro strati del mapman: si nasconde da 4 in poi.
    vdp_put_sprite_16(4, 0, 200, 0, VDP_INK_TRANSPARENT);
    init_song(SONG_ROW_OW);
}

// =====================================================================
//  TOWN (slice40)
// =====================================================================
static int town_cam_x, town_cam_y;
static int town_first_frame = 0;
static int town_progress = 0;
static int town_facing = DIR_DOWN;
static int town_walk_phase = 0;
static int town_total_shifts = 0;
// Posizione del giocatore in MACROtile. Fino a slice63 esisteva solo la
// camera in celle, e la posizione si sarebbe potuta ricavare da quella
// (cella + 15, cella + 11, diviso 2). Tenerla esplicita costa 4 byte e toglie
// di mezzo una conversione che va rifatta giusta a ogni lettura.
static unsigned char town_mx, town_my;
// Ultime proprieta' lette, e l'esito. Sono globali e non valori di ritorno
// perche' servono in due momenti diversi del passo: PRIMA per decidere se si
// passa, DOPO per far scattare quello che c'e' sulla casella.
static unsigned char town_prop0, town_prop1;
// Sonda: l'id del negozio calpestato, e quante volte se n'e' calpestato uno.
// Non c'e' modo di mostrarlo a schermo -- in citta' la VRAM porta le tile
// della citta', non il font del BIOS, e una stringa uscirebbe come muretti.
// Vale la regola del progetto: se non si vede, si mette in RAM e lo legge la
// sonda ([[emulator-automation]]).
static unsigned char town_shop_id = 0;
static unsigned char town_shop_hits = 0;
// Uscita in overworld: alzata quando si calpesta una casella TP_TELE_WARP.
static unsigned char town_warp_out = 0;
// La posizione in OVERWORLD, in macrotile NES. Definita qui e non sopra main()
// da slice77: il teletrasporto EXIT (il portone del castello) rientra in
// overworld a coordinate PROPRIE, quindi il ciclo delle citta' deve poterle
// scrivere. Il commento sul perche' sono globali (le sonde Lua) sta sopra
// main(), dov'era.
static unsigned char world_player_mx = SPAWN_WORLD_MX;
static unsigned char world_player_my = SPAWN_WORLD_MY;

// IL CHIAMANTE DEVE AVERE IL BANCO DELLA MAPPA (TD[MD_BANK]) MAPPATO: mappa e
// TSA ci vivono dentro. Da slice77 gli indirizzi vengono da TD, che e' RAM:
// leggerli qui e' legale anche con il banco della mappa gia' in primo piano.
// Si espande una volta sola all'ingresso in citta', dentro world_cells (RAM
// SGM, $2000-$5FFF), e da li' in poi il disegno non tocca piu' nessun banco.
// COME SI E' TROVATO IL DIFETTO DI QUESTA SLICE, perche' il metodo vale piu'
// del difetto: la citta' si disegnava benissimo ma "dal posto sbagliato". Tre
// cause diverse danno quel sintomo -- puntatore, banco, espansione -- e a
// schermo sono indistinguibili. Si sono messe in RAM, una alla volta:
//   1. il puntatore RISOLTO alla mappa           -> giusto ($D7E6)
//   2. i primi byte letti attraverso di esso     -> giusti ($0B $03)
//   3. la casella d'ingresso                     -> giusta ($10)
//   4. le celle che il gioco SCRIVE in world_cells -> SPAZZATURA
// Il salto fra 3 e 4 ha isolato il colpevole in una riga sola. Da notare che
// leggere world_cells dall'ESTERNO (sonda Lua su $2000) aveva dato un falso
// indizio: e' il gioco che deve raccontare cio' che scrive.
static void expand_town(void) {
    int my, mx;
    unsigned char m;
    int row_top, row_bot;
    // I simboli del banco sono l'indirizzo DEL PUNTATORE, non dei dati: una
    // dereferenza in piu' (stessa forma di load_ow_chr_palette).
    const unsigned char *map = *(const unsigned char **)TD[MD_MAP];
    const unsigned char *ul  = *(const unsigned char **)TD[MD_TSA_UL];
    const unsigned char *ur  = *(const unsigned char **)TD[MD_TSA_UR];
    const unsigned char *dl  = *(const unsigned char **)TD[MD_TSA_DL];
    const unsigned char *dr  = *(const unsigned char **)TD[MD_TSA_DR];

    for (my = 0; my < TOWN_MACRO_H; my++) {
        row_top = (my * 2)     * TOWN_CELL_W;
        row_bot = (my * 2 + 1) * TOWN_CELL_W;
        for (mx = 0; mx < TOWN_MACRO_W; mx++) {
            m = map[my * TOWN_MACRO_W + mx];
            world_cells[row_top + mx * 2 + 0] = ul[m];
            world_cells[row_top + mx * 2 + 1] = ur[m];
            world_cells[row_bot + mx * 2 + 0] = dl[m];
            world_cells[row_bot + mx * 2 + 1] = dr[m];
        }
    }
}
// Le proprieta' del macrotile (mx,my) di Coneria, dal banco 15.
//
// PERCHE' UN'ESCURSIONE NEL BANCO E NON UNA COPIA IN RAM. La tabella e' di
// 256 byte e ci starebbe; la MAPPA che serve per arrivarci e' di 4096, e
// quella non ci sta -- world_cells occupa gia' tutti i 16KB di $2000-$5FFF
// con la citta' espansa in celle, da cui il macrotile non si puo' piu'
// ricavare (la coppia tile/palette non e' invertibile). Copiare la sola
// tabella e leggere la mappa dal banco vorrebbe dire fare l'escursione lo
// stesso, e per meta' del dato. Tanto vale prendere tutti e due li' dentro:
// succede una volta per PASSO, non una per frame.
//
// `main_bank` si alza PRIMA di mappare e si abbassa PRIMA di rimappare, nei
// due versi. E' l'ordine di slice61 e non e' stile: una NMI caduta fra i due
// rimetterebbe il banco 0 sotto i piedi di questa lettura, che tornerebbe
// byte di un altro mondo -- e per giunta plausibili, perche' qualunque byte
// letto e' una proprieta' valida di qualche macrotile.
static void town_read_prop(unsigned char mx, unsigned char my) {
    const unsigned char *map;
    const unsigned char *prop;
    unsigned char m;

    main_bank = (unsigned char)TD[MD_BANK];
    mc_select_bank((unsigned char)TD[MD_BANK]);
    map  = *(const unsigned char **)TD[MD_MAP];
    prop = *(const unsigned char **)TD[MD_PROP];
    m = map[(int)my * TOWN_MACRO_W + (int)mx];
    town_prop0 = prop[m * 2];
    town_prop1 = prop[m * 2 + 1];
    main_bank = 0;
    mc_select_bank(0);
}
// =====================================================================
//  Gli abitanti (slice76): tile di FONDO, non sprite
// =====================================================================
// Ognuno degli abitanti occupa un macrotile, cioe' 2x2 celle, e le sue quattro
// tile TMS sono cotte a monte SOPRA il terreno su cui sta -- pattern e colore
// escono da tools/extract_sm_colors.ps1 insieme a quelli della citta'.
//
// PERCHE' NON SPRITE. Il mapman del giocatore ne occupa gia' QUATTRO
// sovrapposti ([[mapman-4layer]]) e il TMS9918 ne mostra quattro per scanline:
// un abitante di fianco al giocatore cadrebbe fuori -- e "di fianco" e'
// l'unica posizione da cui gli si puo' parlare. Sarebbe un difetto che si
// manifesta esattamente quando si usa la funzione.
//
// IL PREZZO, ed e' quello che si vede: un abitante cosi' NON CAMMINA. Le sue
// tile contengono il terreno, quindi spostarlo vorrebbe dire ricuocerle per
// ogni casella calpestabile. Sul NES gli abitanti vagano. Deviazione
// dichiarata in docs/Coleco_improvements.md.
//
// SI DISEGNA DOPO la vista, non dentro: patchare il buffer di riga dentro il
// ciclo delle 24 righe vorrebbe dire 24 x 15 confronti a ogni passo, mentre
// cosi' sono due scritture VDP per abitante. Il ciclo delle righe e' gia' il
// pezzo piu' caro del passo (~6.5 ms).
// Una meta' di abitante: due tile affiancate sulla riga `row`, a partire dalla
// colonna `col`, che puo' essere -1 (meta' sinistra gia' fuori) o 31 (meta'
// destra gia' fuori). I due casi di bordo si scrivono qui una volta sola --
// nel chiamante sarebbero quattro, uno per quadrante.
//
// LA SCRITTURA DA DUE BYTE NON VA MAI A CAVALLO DI UNA RIGA: la name table e'
// un nastro di 768 byte, non una griglia, e una tile scritta a colonna 32
// ricompare all'inizio della riga dopo (difetto #1 di slice73).
// TRAPPOLA sccz80 NUOVA, e costata una corsa. In una funzione che ha un ARRAY
// LOCALE, la SECONDA lettura di un parametro `char` prende l'offset del
// parametro SUCCESSIVO. Qui la prima stesura era
//     b[0] = t;
//     b[1] = (unsigned char)(t + 1);
// e l'assembly generato leggeva `t` da sp+4 la prima volta (giusto) e da
// **sp+6** la seconda -- che e' `row`. La seconda tile di ogni abitante valeva
// quindi `row + 1`.
//
// A schermo: meta' SINISTRA di ogni abitante giusta, meta' destra un pezzo di
// citta'. Che somiglia a un problema di larghezza della scrittura, o di
// bordo, o di tile mancanti -- e non al parametro sbagliato. L'ha inchiodato
// la lettura dell'assembly, poi ridotta a un caso minimo:
//     zcc +coleco -crt0=crt\sgm_megacart_crt0 -a -o build\npcasm.asm src\slice76.c
// Senza l'array locale il difetto NON si presenta (due letture di `t` dentro
// due `int` escono giuste tutte e due), e con una COPIA LOCALE nemmeno.
//
// LA FORMA SICURA: se una funzione ha un array locale, il parametro `char` si
// copia in un locale e si usa quello. Stessa famiglia di
// [[sccz80-ternary-and-trap]] -- il compilatore non sbaglia a compilare cio'
// che si legge, sbaglia su una forma particolare, e l'unico modo di saperlo e'
// guardare cosa produce.
static void put_npc_half(int col, int row, unsigned char t) {
    unsigned char b[2];
    unsigned char tt;
    unsigned int at;
    tt = t;
    b[0] = tt;
    b[1] = (unsigned char)(tt + 1);
    at = 0x1800 + (unsigned int)row * 32;
    if (col < 0)   { vdp_vwrite(&b[1], at, 1); return; }
    if (col == 31) { vdp_vwrite(b, at + 31, 1); return; }
    vdp_vwrite(b, at + col, 2);
}

static void draw_npcs(int cam_x, int cam_y) {
    unsigned char i;
    int sc, sr;
    unsigned char base;

    for (i = 0; i < WORLD.count; i++) {
        unsigned char oid = WORLD.id[i];
        // Il contorno si NASCONDE per primo e si rimette solo se l'abitante e'
        // davvero a schermo. Lasciarlo dov'era vorrebbe dire un contorno nero
        // fermo in mezzo al prato dopo che il suo padrone e' uscito dalla
        // vista -- e sarebbe l'unico sprite del gioco a farlo, quindi
        // sembrerebbe un difetto della citta', non del disegno.
        vdp_put_sprite_16(NPC_SAT_BASE + i, 0, 200, 0, VDP_INK_TRANSPARENT);
        if (oid == 0) continue;
        // Un oggetto invisibile non c'e'. Sul NES lo decide LoadSingleMapObject
        // all'ingresso nella mappa; qui si guarda al momento del disegno, cosi'
        // un oggetto nascosto mentre ci si sta sparisce senza dover rientrare.
        if (!OBJ_VISIBLE(oid)) continue;

        // Coordinate di schermo CON SEGNO. La mappa e' toroidale e la sottrazione
        // torna sempre positiva: senza il rientro qui sotto, un abitante appena
        // fuori dal bordo sinistro varrebbe colonna 127 invece di -1, e la sua
        // meta' visibile non si disegnerebbe -- comparirebbe di colpo tutto
        // intero un passo dopo.
        sc = (((int)WORLD.x[i] * 2) - cam_x) & TOWN_MASK_X;
        sr = (((int)WORLD.y[i] * 2) - cam_y) & TOWN_MASK_Y;
        if (sc > 32) sc -= TOWN_CELL_W;
        if (sr > 24) sr -= TOWN_CELL_H;
        if (sc <= -2 || sc >= 32) continue;
        if (sr <= -2 || sr >= 24) continue;

        base = (unsigned char)(NPC_TILE_BASE + i * 4);
        if (sr >= 0)      put_npc_half(sc, sr,     base);
        if (sr + 1 <= 23) put_npc_half(sc, sr + 1, (unsigned char)(base + 2));

        // Il contorno, sopra la sagoma. Solo quando l'abitante e' INTERO
        // dentro lo schermo: il TMS9918 sa clippare a destra e in basso ma non
        // a sinistra e in alto (li' servirebbe il bit di early clock, che
        // sposta TUTTI gli sprite di 32 pixel). Meglio nessun contorno che un
        // contorno che salta di mezzo schermo.
        if (sc >= 0) {
            if (sr >= 0) {
                vdp_put_sprite_16(NPC_SAT_BASE + i, sc * 8, sr * 8,
                                  NPC_SPR_BASE + i, VDP_INK_BLACK);
            }
        }
    }
}

// =====================================================================
//  slice77 -- i teletrasporti (banco 11, tabella 12 di svc_fetch_btl)
// =====================================================================
// UNA funzione per le tre famiglie: le fette X/Y/Map del ROM sono array
// paralleli a passo fisso (64 per NORM, 32 per ENTR, 16 per EXIT), quindi
// "la voce `id` della famiglia" e' base+id, base+passo+id, base+2*passi+id.
// Succede una volta per CAMBIO DI MAPPA, non per passo: il costo delle
// escursioni non conta, quello dei TRE corpi di funzione contava (la
// finestra fissa e' sforata di 297 byte alla prima build di questa slice).
//
// Le famiglie a TRE byte (NORM, ENTR) portano coordinate di mappa col bit 7
// di wrap del NES: si mascherano qui. Quella a DUE (EXIT) porta coordinate
// PIENE di overworld e non si tocca.
static void fetch_tele(unsigned int base, unsigned char stride,
                       unsigned char n, unsigned char id, unsigned char *dst) {
    unsigned char k;
    for (k = 0; k < n; k++) {
        svc_fetch_btl(12, base + id, 1, &dst[k]);
        base += stride;
    }
    if (n == 3) { dst[0] &= 0x3F; dst[1] &= 0x3F; }
}
#define fetch_norm_tele(id, dst) fetch_tele(FF1_TELE_NORM_X, 64, 3, (id), (dst))
#define fetch_exit_tele(id, dst) fetch_tele(FF1_TELE_EXIT_X, 16, 2, (id), (dst))
#define fetch_entr_tele(id, dst) fetch_tele(FF1_TELE_ENTR_X, 32, 3, (id), (dst))

// C'e' un abitante VISIBILE sul macrotile (mx,my)? Torna il suo indice di slot,
// oppure 0xFF. Una domanda sola per tre usi: il passo che si rifiuta, il
// bersaglio del dialogo, e (domani) chi sparisce dopo aver parlato.
static unsigned char npc_at(unsigned char mx, unsigned char my) {
    unsigned char i, oid;
    for (i = 0; i < WORLD.count; i++) {
        if (WORLD.x[i] != mx) continue;
        if (WORLD.y[i] != my) continue;
        oid = WORLD.id[i];
        if (oid == 0) continue;
        if (!OBJ_VISIBLE(oid)) continue;
        return i;
    }
    return 0xFF;
}

static void redraw_town_view(int cam_x, int cam_y) {
    int sy, sx, wx, wy;
    unsigned char buf[32];
    for (sy = 0; sy < 24; sy++) {
        wy = (cam_y + sy) & TOWN_MASK_Y;
        for (sx = 0; sx < 32; sx++) {
            wx = (cam_x + sx) & TOWN_MASK_X;
            buf[sx] = world_cells[wy * TOWN_CELL_W + wx];
        }
        vdp_vwrite(buf, 0x1800 + sy * 32, 32);
    }
    draw_npcs(cam_x, cam_y);
}
// Colori VERI (slice63). Prima erano una `vdp_vfill(0x2000, 0xF1, ...)`:
// bianco su nero per ogni tile, cioe' la citta' era una silhouette monocroma.
// Adesso ogni tile TMS e' una coppia (tile CHR, sotto-palette NES) e porta i
// suoi 8 byte di colore -- lo stesso schema che slice47 ha usato per la
// overworld ([[ow-color-pipeline]]).
//
// IL CHIAMANTE DEVE AVERE IL BANCO 15 MAPPATO.
static void load_town_chr_palette(void) {
    const unsigned char *p;

    // Backdrop nero come in overworld e in battaglia: il verde scuro di prima
    // era un ripiego per far sembrare erba una citta' senza colori.
    vdp_color(VDP_INK_WHITE, VDP_INK_BLACK, VDP_INK_BLACK);

    p = *(const unsigned char **)TD[MD_PATTERN];
    vwrite3(p, 0x0000, FF1_TOWNGFX_TILE_COUNT * 8);

    p = *(const unsigned char **)TD[MD_COLOR];
    vwrite3(p, 0x2000, FF1_TOWNGFX_TILE_COUNT * 8);

    // --- slice76: gli abitanti, la barra e il font -------------------------
    // La mappa dei 256 tile della citta' sta in world_state.h. Le tre fasce
    // qui sotto stanno TUTTE nei buchi lasciati dal tileset, che ne usa 93:
    //   96-155  quattro tile per slot NPC, cotte sopra il terreno (banco 15)
    //   159     la barra verticale del riquadro di dialogo
    //   160-254 il font del BIOS, caratteri $20-$7E
    // Il font viene dal BIOS ($15A3), che sta sotto i $2000 ed e' sempre
    // mappato: non e' un dato di questo banco e non serve nessuna escursione.
    p = *(const unsigned char **)TD[MD_NPC_PATTERN];
    vwrite3(p, 0x0000 + NPC_TILE_BASE * 8, NPC_MAX * 4 * 8);
    p = *(const unsigned char **)TD[MD_NPC_COLOR];
    vwrite3(p, 0x2000 + NPC_TILE_BASE * 8, NPC_MAX * 4 * 8);

    // I contorni, nel generatore degli sprite. Un abitante e' fatto di tre
    // colori -- terreno, corpo, contorno -- e una riga di tile in Mode 2 ne
    // porta due: il terzo entra da qui. Stessa divisione del lavoro dello
    // strato di accento del mapman ([[oam-accent-pattern]]).
    p = *(const unsigned char **)TD[MD_NPC_SPRITE];
    {
        int k;
        for (k = 0; k < NPC_MAX; k++) {
            vdp_set_sprite_16(NPC_SPR_BASE + k, (void*)(p + (unsigned int)k * 32));
        }
    }

    // La barra verticale del riquadro NON e' il carattere '|': nel font del
    // BIOS il glifo $7C si disegna come '>' ([[coleco-bios-pipe-glyph]]).
    // `town_vbar` e' rodata della slice, quindi si legge solo col banco 0
    // mappato -- e qui il banco mappato e' il 15. Per questo la barra e' un
    // FILL e non una copia: otto byte uguali non hanno bisogno di una
    // sorgente. Il valore 0x18 e' una riga di due pixel al centro della cella.
    vfill3(0x0000 + TOWN_VBAR_TILE * 8, 0x18, 8);
    vfill3(0x2000 + TOWN_VBAR_TILE * 8, 0xF1, 8);

    vwrite3(BIOS_FONT_ADDR, 0x0000 + TOWN_FONT_BASE * 8, BIOS_FONT_LEN);
    // Bianco su nero: il riquadro di dialogo e' una finestra nera aperta sopra
    // la citta', com'e' sul NES (li' e' blu scuro, che sul TMS non c'e' in una
    // tinta che non sembri acqua).
    vfill3(0x2000 + TOWN_FONT_BASE * 8, 0xF1, BIOS_FONT_LEN);
}

// La tabella degli abitanti, dal banco della mappa alla RAM condivisa.
// IL CHIAMANTE DEVE AVERE IL BANCO 15 MAPPATO -- come expand_town, che gira
// nella stessa escursione.
//
// PERCHE' UNA COPIA E NON UNA LETTURA AL VOLO. Le coordinate degli abitanti si
// leggono a ogni passo (per rifiutarlo) e a ogni disegno; farlo dal banco
// vorrebbe dire un'escursione per fotogramma, con la NMI dell'audio da
// serializzare ogni volta. 45 byte in RAM tolgono di mezzo la questione.
static void load_town_npcs(void) {
    const unsigned char *s = *(const unsigned char **)TD[MD_NPC_SLOTS];
    int i;
    WORLD.count = NPC_MAX;
    for (i = 0; i < NPC_MAX; i++) {
        WORLD.id[i] = s[i * 3];
        WORLD.x[i]  = s[i * 3 + 1];
        WORLD.y[i]  = s[i * 3 + 2];
    }
}
// Da slice77 l'ingresso e' un ARGOMENTO: la stessa funzione serve alla porta
// dall'overworld (coordinate di lut_EntrTele), alle scale del castello e al
// teletrasporto della principessa (coordinate di lut_NormTele). Il chiamante
// deve avere gia' scelto la mappa con town_select_map, col banco 0 mappato.
static void enter_town(unsigned char at_mx, unsigned char at_my) {
    int cx, cy;
    silence_audio();
    // Blank NT first to avoid garbage tiles during pattern swap.
    vdp_vfill(0x1800, 0x00, 768);

    // Il banco della mappa per tutta la preparazione: grafica E mappa ci
    // vivono dentro. audio_enabled a zero esplicito -- una NMI caduta qui
    // leggerebbe gli eventi della canzone dentro i pixel della citta' (stessa
    // precauzione di load_ow_chr_palette).
    audio_enabled = 0;
    mc_select_bank((unsigned char)TD[MD_BANK]);
    load_town_chr_palette();
    expand_town();
    load_town_npcs();
    mc_select_bank(0);

    load_ow_player_sprite();   // re-use OW fighter walker for in-town movement
    // Camera in cells: entry tile is in MACROtiles, so * 2.
    // Player stays screen-fixed at (15,11) so cam = entry*2 - (15,11).
    cx = ((int)at_mx * 2) - 15;
    cy = ((int)at_my * 2) - 11;
    town_cam_x = (cx + TOWN_CELL_W) & TOWN_MASK_X;
    town_cam_y = (cy + TOWN_CELL_H) & TOWN_MASK_Y;
    town_mx = at_mx;
    town_my = at_my;
    town_shop_id = 0;
    town_warp_out = 0;
    town_progress = 0;
    town_facing = DIR_UP;          // player came in from the south, faces north
    town_walk_phase = 0;
    town_total_shifts = 0;
    town_first_frame = 1;
    redraw_town_view(town_cam_x, town_cam_y);
    // Come in OW: SAT[0..3] sono il mapman, si nasconde da 4 in poi.
    vdp_put_sprite_16(4, 0, 200, 0, VDP_INK_TRANSPARENT);
    // La canzone della mappa (slice77): sng47 dal banco 1 per la citta',
    // sng48/sng4C dal banco 10 per castello e tempio. init_map_song mappa da
    // sola il banco giusto prima di dereferenziare.
    init_map_song();
    // Da qui in poi il gioco in citta' non legge PIU' nessun banco: la mappa
    // espansa sta in world_cells (RAM SGM) e il disegno legge solo quella. Il
    // banco 0 resta in primo piano per la rodata generale; la NMI passa al
    // banco della canzone per il tick e lo rimette.
    main_bank = 0;
    mc_select_bank(0);
}

// Il pezzo comune dei TRE modi di finire in una mappa (ingresso ENTR dalla
// overworld, scala NORM, teletrasporto della principessa): `t` sono i tre
// byte gia' prelevati dal banco 11 -- x, y, id di mappa FF1. Torna 0 se la
// mappa non ce l'abbiamo ancora, e allora non succede NIENTE: l'ingresso
// stampa TPxx, la scala si comporta da pavimento.
static unsigned char town_goto(unsigned char *t) {
    unsigned char slot = map_slot_for(t[2]);
    if (slot == 0xFF) return 0;
    town_select_map(slot);
    enter_town(t[0], t[1]);
    return 1;
}

// Town tick: torna 1 quando si esce in overworld (casella TP_TELE_WARP).
// 60Hz scroll, 2-cell macrotile step gating (slice12e validated design).
static int town_step_cooldown = 0;
static int town_stepping = 0;

// =====================================================================
//  Il menu (slice73): come ci si entra, da tutti e due i cicli di gioco
// =====================================================================
// FIRE2 A FRONTE, non a livello. Il menu si chiude con lo stesso tasto con cui
// si apre, e all'uscita quel tasto e' quasi sempre ANCORA PREMUTO: a livello
// il menu si riaprirebbe subito, e a schermo si vedrebbe un menu che non si
// chiude -- cioe' un difetto che somiglia a un blocco.
//
// Lo stato sta QUI e non nell'overlay apposta: l'overlay nasce e muore a ogni
// apertura, e la sua idea di "prima" verrebbe da byte non inizializzati.
static unsigned char menu_prev_f2 = 0;
static int menu_pressed(unsigned int j) {
    unsigned char now = 0, e = 0;
    if (j & MOVE_FIRE2) now = 1;
    // Due `if` annidati e non `now && !menu_prev_f2`: dentro sccz80 la forma
    // con `&&` e' sicura in un `if` ma non in un `?:`, e questa funzione e'
    // esattamente il posto in cui un giorno qualcuno ci metterebbe un `?:`.
    // Vedi la nota su draw_cursor in ovl_shop.c.
    if (now) { if (!menu_prev_f2) e = 1; }
    menu_prev_f2 = now;
    return e;
}

// FIRE1 = "parla", e vale la stessa regola del fronte: si torna dal riquadro
// con il tasto che lo ha chiuso ancora premuto, e a livello si riaprirebbe
// subito -- un dialogo che non finisce mai. E' il tasto A del NES
// (ProcessSMInput, bank_0F.asm:2298).
static unsigned char talk_prev_f1 = 0;
static int talk_pressed(unsigned int j) {
    unsigned char now = 0, e = 0;
    if (j & MOVE_FIRE1) now = 1;
    if (now) { if (!talk_prev_f1) e = 1; }
    talk_prev_f1 = now;
    return e;
}

// Il macrotile che il giocatore ha DAVANTI. Sul NES e' GetSMTargetCoords
// (bank_0F.asm), e la direzione e' quella dell'ultimo comando ricevuto anche
// se il passo era stato rifiutato: e' cio' che permette di parlare a chi sta
// dall'altra parte di un muro d'angolo girandosi soltanto.
static unsigned char talk_tx, talk_ty;
static void target_ahead(void) {
    int dx = 0, dy = 0;
    if (town_facing == DIR_UP)         dy = -1;
    else if (town_facing == DIR_DOWN)  dy =  1;
    else if (town_facing == DIR_LEFT)  dx = -1;
    else                               dx =  1;
    talk_tx = (unsigned char)(((int)town_mx + dx) & (TOWN_MACRO_W - 1));
    talk_ty = (unsigned char)(((int)town_my + dy) & (TOWN_MACRO_H - 1));
}

// Sonde: quante volte si e' parlato, e a chi. Un dialogo e' fatto di pixel e
// di niente altro -- non muove il gruppo, non tocca l'oro, non cambia una
// statistica. Senza questi due byte una corsa di validazione non saprebbe
// distinguere "ha parlato all'abitante giusto" da "non e' successo niente",
// e sono lo stesso identico caso di town_shop_id ([[emulator-automation]]).
static unsigned char town_talk_hits = 0;
static unsigned char town_talk_obj  = 0;
static unsigned char town_talk_dlg  = 0;
// slice77: il byte ALTO del ritorno dell'overlay 26 -- gli effetti chiesti
// dalla routine di dialogo (TALK_FX_* in world_state.h, scalati di 8). E' una
// sonda come town_talk_dlg: "il Re ha acceso il ponte" senza di lei sarebbe
// solo un bit in RAM che nessuna corsa sa distinguere da un bit mai scritto.
static unsigned char town_talk_fx   = 0;

// La battaglia che Talk_Garland apre (BTL_GARLAND in Constants.inc) e il
// teletrasporto di Talk_Princess1 (NORMTELE_SAVEDPRINCESS): due costanti del
// NES, usate solo dal motore -- l'overlay dice "battaglia" e "teleport" coi
// bit di TALK_FX_*, il QUALE lo sa questa parte.
#define BTL_GARLAND_FORMATION   0x7F
#define NORMTELE_SAVEDPRINCESS  0x3F

// Si parla. Prima si cerca un abitante sul macrotile davanti; se non c'e', si
// parla al TILE, che sul NES ha un dialogo suo nel byte 1 delle proprieta'
// (TalkToSMTile, bank_0F.asm:2822). L'ordine e' quello del NES e conta: un
// abitante fermo su una casella parlante nasconde il testo della casella.
static void town_talk(void) {
    unsigned char slot;
    unsigned int arg;

    target_ahead();
    slot = npc_at(talk_tx, talk_ty);
    if (slot != 0xFF) {
        town_talk_obj = WORLD.id[slot];
        arg = WORLD.id[slot];
    } else {
        unsigned char dlg = 0;
        town_read_prop(talk_tx, talk_ty);
        town_talk_obj = 0;
        // TP_NOTEXT_MASK = %11000010: teletrasporti e porte non parlano, e
        // un forziere non e' un dialogo. Con uno di quei bit acceso il NES
        // forza DLGID_NOTHING, che e' l'id 0 -- "Nothing here".
        if ((town_prop0 & 0xC2) == 0) {
            if ((town_prop0 & TP_SPEC_MASK) != TP_SPEC_TREASURE) {
                dlg = town_prop1;
            }
        }
        arg = TALK_ARG_TILE | dlg;
    }
    town_talk_hits++;

    // Il banco 26 scrive solo la name table: pattern, colori e sprite restano
    // quelli della citta'. Al ritorno basta ridisegnare la vista -- niente
    // `town_restore_gfx`, che ricaricherebbe 6KB di VRAM per rimettere a posto
    // dieci righe.
    // L'id del dialogo MOSTRATO torna dall'overlay: quale delle tre battute
    // esce lo decidono i flag di gioco, che si guardano di la'. Lo si pubblica
    // per le corse di validazione -- e' l'unico modo di distinguere "ha parlato
    // all'abitante giusto" da "gli ha fatto dire la frase giusta per il punto
    // della storia in cui siamo".
    hide_npc_sprites();
    {
        unsigned int r = svc_run_overlay(TALK_BANK, arg);
        town_talk_dlg = (unsigned char)r;
        town_talk_fx  = (unsigned char)(r >> 8);
    }
    redraw_town_view(town_cam_x, town_cam_y);
    draw_mapman(town_facing * 2 + town_walk_phase);
    // Gli effetti (fanfara, battaglia, teletrasporto) NON si eseguono qui:
    // li esegue town_tick al ritorno, che e' l'unico posto che viene DOPO
    // town_restore_gfx nel file e puo' quindi chiamarla. L'ordine e' quello
    // del NES: prima il riquadro si chiude, poi succede il resto.
}

// La grafica della citta', rimessa a posto dopo un'escursione in un overlay
// che si e' preso tutta la VRAM (il negozio o il menu). NON riespande la
// mappa: `world_cells` sta in RAM SGM e nessuno dei due la tocca, e
// `expand_town` costa ~140 frame -- con sette porte in una citta' sola, quella
// differenza e' tutta la giocabilita' del posto.
static void town_restore_gfx(void) {
    audio_enabled = 0;
    mc_select_bank((unsigned char)TD[MD_BANK]);
    load_town_chr_palette();
    mc_select_bank(0);
    audio_enabled = 1;
    redraw_town_view(town_cam_x, town_cam_y);
    load_ow_player_sprite();
    draw_mapman(town_facing * 2 + town_walk_phase);
}

// La fanfara dei dialoghi (slice77): sng54 al posto del tema, poi il tema da
// capo. BLOCCA per FANFARE_FRAMES quadri, ed e' una scelta: sul NES il
// riquadro non si puo' chiudere finche' la fanfara non finisce
// (bank_0F.asm:5216, il ciclo su music_track $81) -- qui il riquadro e' gia'
// chiuso, ma il giocatore resta fermo lo stesso e per lo stesso tempo. Un
// one-shot vero chiederebbe al motore audio una nozione di fine-canzone che
// non ha: 204 quadri di attesa contro un campo nuovo in tre strutture.
static void town_play_fanfare(void) {
    unsigned int i;
    silence_audio();
    init_song(SONG_ROW_FANFARE);
    for (i = 0; i < FANFARE_FRAMES; i++) svc_wait_vblank();
    silence_audio();
    init_map_song();
}

// Definita dopo il ciclo delle citta' (sta con la battaglia): il turno di
// Garland la chiama da town_tick, quindi il prototipo serve qui.
static unsigned int run_battle(unsigned char formation, unsigned char domain);

static int town_tick(void) {
    unsigned int j;
    int sprite_handle, frame;

    j = joystick(1);
    if (town_first_frame) {
        town_first_frame = 0;
        return 0;
    }

    // Il menu, PRIMA del passo: chi lo apre non si sta muovendo, e valutare il
    // passo nello stesso quadro vorrebbe dire consumarne uno dietro una
    // schermata che copre lo schermo.
    if (menu_pressed(j)) {
        // Il valore di ritorno conta da slice75: 1 = il gruppo e' stato
        // portato via da WARP o EXIT. Da una citta' quelle due magie fanno la
        // stessa cosa della casella di prato -- si torna in overworld alle
        // coordinate da cui si era entrati -- quindi si riusa la stessa
        // strada, `town_warp_out`, invece di scriverne una seconda.
        hide_npc_sprites();
        if (svc_run_overlay(MENU_BANK, 1)) {   /* 1 = si e' in una citta' */
            town_warp_out = 1;
            return 1;
        }
        town_restore_gfx();
        town_step_cooldown = STEP_COOLDOWN_FRAMES;
        return 0;
    }
    // FIRE2 non esce piu': l'uscita e' la casella di prato sotto la porta sud.
    // Vedi l'intestazione della slice.

    // Si parla PRIMA del passo, per la stessa ragione del menu: chi preme
    // FIRE1 non si sta muovendo, e valutare il passo nello stesso quadro
    // vorrebbe dire consumarne uno dietro un riquadro che copre lo schermo.
    if (talk_pressed(j)) {
        town_talk();
        // slice77: gli effetti che la routine di dialogo ha chiesto, nel
        // BYTE ALTO del ritorno (town_talk_fx, gia' scalato di 8). L'ordine
        // fanfara -> battaglia -> teletrasporto e' quello in cui il NES li
        // produce; nessuna routine ne chiede due insieme, ma l'ordine scritto
        // e' comunque uno solo.
        if (town_talk_fx & (TALK_FX_FANFARE >> 8)) {
            town_play_fanfare();
        }
        if (town_talk_fx & (TALK_FX_FIGHT >> 8)) {
            // Garland. Sul NES TalkBattle arma la battaglia e il loop della
            // mappa la fa partire a riquadro chiuso: qui e' la stessa cosa,
            // scritta in fila. Al ritorno la VRAM e' dell'arena: si rimette
            // la grafica della mappa e il suo tema (la battaglia ha suonato
            // sng50 e la vittoria sng53).
            run_battle(BTL_GARLAND_FORMATION, 0);
            town_restore_gfx();
            silence_audio();
            init_map_song();
        }
        if (town_talk_fx & (TALK_FX_TELE >> 8)) {
            // Il ritorno della principessa: NORM $3F, che porta alla stanza
            // del castello 2F. Stessa strada delle scale -- si cambia mappa
            // e si rientra dal ciclo, con la principessa salvata (id $12)
            // ormai visibile dove il descrittore la mette.
            unsigned char t[3];
            fetch_norm_tele(NORMTELE_SAVEDPRINCESS, t);
            town_goto(t);
        }
        town_step_cooldown = STEP_COOLDOWN_FRAMES;
        return 0;
    }

    if (town_step_cooldown > 0) {
        town_step_cooldown--;
    } else {
        int dx = 0, dy = 0;
        int held = 0;
        if (j & MOVE_UP)         { town_facing = DIR_UP;    dy = -1; held = 1; }
        else if (j & MOVE_DOWN)  { town_facing = DIR_DOWN;  dy =  1; held = 1; }
        else if (j & MOVE_LEFT)  { town_facing = DIR_LEFT;  dx = -1; held = 1; }
        else if (j & MOVE_RIGHT) { town_facing = DIR_RIGHT; dx =  1; held = 1; }
        if (held) {
            unsigned char dst_mx = (unsigned char)(((int)town_mx + dx) & (TOWN_MACRO_W - 1));
            unsigned char dst_my = (unsigned char)(((int)town_my + dy) & (TOWN_MACRO_H - 1));

            town_step_cooldown = STEP_COOLDOWN_FRAMES;

            // Le proprieta' della casella di ARRIVO, lette prima di muoversi:
            // e' l'unico ordine in cui si puo' rifiutare il passo, ed e'
            // quello del NES (`CanPlayerMoveSM` calcola le coordinate di
            // destinazione e legge li').
            town_read_prop(dst_mx, dst_my);

            // Un abitante e' un ostacolo. Sul NES lo e' a meta': lo si SPINGE
            // (mapobj_pl, bank_0F.asm:2587) e lui si sposta di una casella --
            // ma li' gli abitanti camminano. Qui stanno fermi, quindi spingere
            // vorrebbe dire attraversarli. Bloccano, e girarsi verso di loro
            // resta l'unico modo per parlargli: la stessa condizione, letta
            // due volte per due scopi.
            if (npc_at(dst_mx, dst_my) != 0xFF) {
                town_stepping = 0;
                draw_mapman(town_facing * 2 + town_walk_phase);
                return 0;
            }

            if ((town_prop0 & (TP_SPEC_MASK | TP_NOMOVE)) == TP_NOMOVE) {
                // Bloccato. Come `@CantMove` sul NES: non si muove e non
                // scatta niente. Il personaggio si GIRA lo stesso, perche' il
                // verso lo decide l'input prima del tentativo -- e' cio' che
                // rende leggibile un muro invece di far sembrare il comando
                // ignorato. Stessa scelta della collisione in overworld
                // (slice58).
                town_stepping = 0;
                draw_mapman(town_facing * 2 + town_walk_phase);
                return 0;
            }

            town_walk_phase = town_walk_phase ^ 1;
            town_stepping = 1;

            // Come in overworld (slice49): SAT prima dello scroll, o la
            // sprite sembra girare un frame dopo la mappa.
            draw_mapman(town_facing * 2 + town_walk_phase);

            town_mx = dst_mx;
            town_my = dst_my;
            town_cam_x = (town_cam_x + 2 * dx + TOWN_CELL_W) & TOWN_MASK_X;
            town_cam_y = (town_cam_y + 2 * dy + TOWN_CELL_H) & TOWN_MASK_Y;
            redraw_town_view(town_cam_x, town_cam_y);
            town_total_shifts++;

            // --- che cosa c'e' sulla casella su cui siamo appena saliti ---
            // Sul NES questo succede DOPO il passo, in StandardMapLoop
            // (bank_0F.asm:2150), e non prima: e' il motivo per cui una porta
            // si calpesta e poi il negozio si apre, invece di aprirsi da
            // fermi standoci accanto.
            if ((town_prop0 & TP_SPEC_MASK) == TP_SPEC_DOOR && town_prop1 != 0) {
                // Porta di negozio: si entra. La casella resta calpestabile,
                // quindi all'uscita si e' in piedi sulla soglia e un passo
                // qualunque porta via -- come sul NES.
                town_shop_id = town_prop1;
                town_shop_hits++;

                // La musica del NEGOZIO (slice77bis): il track $51 del NES,
                // che li' e' la STESSA musica per negozio e locanda -- e
                // siccome la locanda vive in questo stesso overlay, la
                // parita' e' gratis. Si avvia QUI e non nell'overlay: la
                // tabella delle canzoni e' rodata del banco 0, che il banco
                // 22 non vede. La NMI la suona dal banco 10 mentre il primo
                // piano e' l'overlay, come per la battaglia.
                silence_audio();
                init_song(SONG_ROW_SHOP);
                hide_npc_sprites();
                svc_run_overlay(SHOP_BANK, town_shop_id);

                // Al ritorno la VRAM e' quella del negozio: si rimette solo la
                // grafica. Da slice73 e' una funzione sola perche' anche il
                // menu esce di qui -- e due copie della stessa sequenza sono
                // due posti in cui dimenticare una riga.
                town_restore_gfx();
                // Il tema della mappa RIPARTE DA CAPO, come sul NES quando
                // si esce da un negozio (il map theme si riavvia, non
                // riprende da dove stava).
                silence_audio();
                init_map_song();
                town_step_cooldown = STEP_COOLDOWN_FRAMES;
            }
            if ((town_prop0 & TP_TELE_MASK) == TP_TELE_WARP) {
                // "Torna alla mappa precedente": per una citta' vuol dire
                // l'overworld, alle coordinate da cui si era entrati -- che
                // sono ancora in world_player_mx/my, mai toccate da qui.
                // Sul NES c'e' una pila dei teletrasporti e WARP la sfoglia
                // all'indietro; per le mappe che abbiamo -- Coneria, il
                // tempio, e un castello le cui scale sono NORM in tutte e
                // due le direzioni -- la pila e' profonda uno, e la mappa
                // precedente e' SEMPRE l'overworld. Il giorno dei sotterranei
                // a piu' piani, la pila va scritta davvero.
                town_warp_out = 1;
                return 1;
            }
            if ((town_prop0 & TP_TELE_MASK) == TP_TELE_NORM) {
                // slice77: cambia mappa RESTANDO nel ciclo delle citta' --
                // le scale del castello, in tutte e due le direzioni. La
                // destinazione viene da lut_NormTele (banco 11), lo slot
                // dalla tabella dei descrittori (banco 0, che qui e' quello
                // mappato: town_read_prop rimette sempre lo zero). Una mappa
                // che non abbiamo ancora (il ToF rivisitato) non fa niente,
                // come un pavimento: si vede dalla sonda cur_map_slot.
                unsigned char t[3];
                fetch_norm_tele(town_prop1, t);
                if (town_goto(t)) {
                    town_step_cooldown = STEP_COOLDOWN_FRAMES;
                    return 0;
                }
            }
            if ((town_prop0 & TP_TELE_MASK) == TP_TELE_EXIT) {
                // slice77: l'uscita con coordinate PROPRIE di overworld
                // (lut_ExitTele) -- il portone del castello. A differenza di
                // WARP qui la posizione nel mondo CAMBIA: e' l'unico
                // teletrasporto che scrive world_player_mx/my.
                unsigned char t[2];
                fetch_exit_tele(town_prop1, t);
                world_player_mx = t[0];
                world_player_my = t[1];
                town_warp_out = 1;
                return 1;
            }
        } else {
            town_stepping = 0;
        }
    }

    frame = town_stepping ? town_walk_phase : 0;
    sprite_handle = town_facing * 2 + frame;
    draw_mapman(sprite_handle);
    return 0;
}

// =====================================================================
//  SERVIZI ESPORTATI ALL'OVERLAY DI BATTAGLIA (prefisso svc_, non static)
// =====================================================================
// Firme dichiarate una sola volta in src/svc_api.h, che l'overlay include
// con SVC_OVERLAY definito per ottenere le stesse firme come puntatori.
//
// REGOLA D'ORO: nessuna di queste puo' leggere rodata della slice. Mentre
// l'overlay e' mappato, il banco 0 non e' raggiungibile e una stringa o una
// tabella di questo file tornerebbe byte del banco 20. Solo VDP, RAM, e i
// puntatori che arrivano come argomento (che puntano nell'overlay stesso,
// quindi validi).
//
// svc_wait_vblank sta piu' in alto, fra gli helper VDP: la usa anche la
// slice, non e' nata per l'overlay.

void svc_vwrite(const void *srcp, unsigned int addr, unsigned int len) {
    vdp_vwrite((void *)srcp, addr, len);
}
void svc_vfill(unsigned int addr, unsigned char val, unsigned int len) {
    vdp_vfill(addr, val, len);
}
void svc_put_sprite16(unsigned char id, int x, int y,
                      unsigned char handle, unsigned char color) {
    vdp_put_sprite_16((unsigned int)id, x, y,
                      (unsigned int)handle, (unsigned int)color);
}
// joy_read_p1 sta in src/joy.asm, sezione code_user = finestra fissa. La
// joystick(3) della libreria NON andrebbe bene: decodifica il tastierino con
// una tabella che il linker piazza a $E890, cioe' nella finestra commutabile,
// dove sotto il banco 20 ci sono i byte dell'overlay.
unsigned int svc_joystick(void) {
    return joy_read_p1();
}

// L'unica svc_ che cambia banco. Non e' un dettaglio: le CHR dei personaggi
// stanno nel banco 2, e l'overlay non puo' andarsele a prendere da solo --
// mapparlo lo cancellerebbe a meta' istruzione. Questo codice invece sta nella
// finestra fissa, che resta visibile qualunque banco sia selezionato, quindi
// puo' fare l'escursione e rimettere il banco 20 prima di tornare.
void svc_battle_load_gfx(void) {
    int i;
    const unsigned char *sprite_base;
    const unsigned char *color_base;
    const unsigned char *accent_col;

    // audio_enabled=0: una NMI mentre e' mappato il banco 2 leggerebbe pixel
    // di sprite come eventi di sng44.
    audio_enabled = 0;
    mc_select_bank(2);

    sprite_base = *(const unsigned char **)GFX_FF1_CLASS_SPRITE_ADDR;
    color_base  = *(const unsigned char **)GFX_FF1_CLASS_SPRITE_COLOR_ADDR;

    vdp_color(VDP_INK_WHITE, VDP_INK_DARK_BLUE, VDP_INK_BLACK);
    vdp_vfill(0x0000, 0, 6144);
    vdp_vfill(0x2000, 0xF1, 6144);
    vwrite3(BIOS_FONT_ADDR, 0x0000 + (FONT_TILE_BASE * 8), BIOS_FONT_LEN);
    load_class_pose(SPR_TILE_BASE, sprite_base, color_base);
    vdp_vfill(0x1800, 0x20, 768);

    // La posa di ESULTANZA NON si carica piu' qui -- vedi svc_battle_load_cheer.
    // Fino a slice54 stava nelle tile $A4-$C7 insieme alla posa in piedi, e
    // andava bene finche' nell'arena non c'era nessuno. Ora i nemici veri
    // chiedono 64 tile ($A4-$E3) e quelle stesse $A4-$C7 servono a loro.
    //
    // La collisione si risolve nel tempo invece che nello spazio: l'esultanza
    // serve SOLO dopo la vittoria, cioe' quando i mostri sono morti e le loro
    // tile non le guarda piu' nessuno. Si carica li' sopra, a fine battaglia.
    // Lo strato di accento in OAM invece resta caricato subito: sta nei
    // generatori sprite, che coi tile di sfondo non condividono niente.

    // Strato accento: 4 generatori OAM per la posa in piedi (handle 1-4) e 4
    // per l'esultanza (handle 5-8), + i 6 colori per classe copiati nel blocco
    // condiviso perche' l'overlay non puo' leggerli qui.
    {
        const unsigned char *stand_acc = *(const unsigned char **)GFX_FF1_CLASS_ACCENT_ADDR;
        const unsigned char *cheer_acc = *(const unsigned char **)GFX_FF1_CLASS_CHEER_ACCENT_ADDR;
        for (i = 0; i < N_PARTY; i++) {
            load_accent_oam((unsigned char)(ACC_HANDLE_STAND + i), party_class[i], stand_acc);
            load_accent_oam((unsigned char)(ACC_HANDLE_CHEER + i), party_class[i], cheer_acc);
        }
    }
    accent_col = *(const unsigned char **)GFX_FF1_CLASS_ACCENT_COLOR_ADDR;
    for (i = 0; i < BST_N_CLASSES; i++) BST.accent_color[i] = accent_col[i];

    // Si torna all'overlay: se qui restasse il banco 2, il `ret` finirebbe
    // dentro dati di sprite interpretati come istruzioni.
    mc_select_bank(BATTLE_BANK);
}

// ---------------------------------------------------------------------
//  svc_battle_load_enemy_gfx -- le sagome dei nemici, a colori
// ---------------------------------------------------------------------
// QUI si chiude il divario che si vedeva a schermo: fino a slice54 i mostri
// erano a tinta piatta, un colore pieno per sagoma, mentre i personaggi erano
// a piu' colori dalla slice30. Il colore per riga arriva dalla combinazione
// di due tabelle del banco 12:
//
//   ff1_mon_rowval[...]  = quale voce di palette (1-3) domina in quella riga
//   ff1_pal_tms[pal*4+v] = in che inchiostro TMS si traduce quella voce
//
// Tenerle separate e' cio' che fa sopravvivere lo swap di palette del NES:
// IMP e GrIMP condividono la sagoma E le dominanti, e differiscono solo per
// l'indice di palette. Se si fosse salvato il colore finale servirebbero due
// copie della grafica per ogni variante.
//
// I nemici GRANDI (slot grafico dispari) da slice56 ci sono: costano 36 tile
// invece di 16 e stanno nei banchi 13/14 invece che nel 12. La forma dei dati
// e' identica -- sagoma piu' dominante per riga -- quindi il ciclo di
// caricamento e' lo STESSO, ed e' per questo che sotto e' una funzione sola
// parametrica e non due copie: qui ogni byte di codice conta, la finestra
// fissa e' [[fixed-window-full]].

// Scrive N tile in VRAM, sagoma e colore per riga, nei tre banchi di pattern.
// Il chiamante ha gia' mappato il banco giusto e ha gia' in mano la palette:
// questa non cambia banco, cosi' vale per piccoli e grandi senza saperlo.
// base == 0xFF significa "tipo senza tile assegnate" e si scarta QUI, in un
// posto solo, invece che a ogni chiamata: e' il tipo di duplicazione che nella
// finestra fissa si paga in byte.
static void load_enemy_tiles(unsigned char base, const unsigned char *pp,
                             const unsigned char *rr, int ntiles,
                             const unsigned char *palrow) {
    int i, r;
    if (base == 0xFF) return;
    for (i = 0; i < ntiles; i++) {
        unsigned char cbuf[8];
        for (r = 0; r < 8; r++) {
            cbuf[r] = (unsigned char)((palrow[rr[i * 8 + r]] << 4) | VDP_INK_BLACK);
        }
        load_tile_3banks((unsigned char)(base + i), pp + i * 8);
        load_color_per_row_3banks((unsigned char)(base + i), cbuf);
    }
}

void svc_battle_load_enemy_gfx(void) {
    // Le palette si copiano subito e si portano dietro: ff1_pal_tms vive nel
    // banco 12, ma i grandi stanno nel 13/14, e mentre quelli sono mappati la
    // tabella dei colori non esiste. Sono 16 byte sullo stack contro un cambio
    // di banco per ogni tile.
    // Piatto e non [4][4]: sccz80 su un array a due dimensioni emette una
    // moltiplicazione a ogni accesso, mentre qui l'offset e' uno shift.
    unsigned char palcache[BST_MAX_TYPES * 4];
    const unsigned char *pat, *rval, *pal;
    int t, r;
    unsigned char n_large = 0;

    if (BST.n_types == 0) return;

    // Una NMI mentre e' mappato il banco 12 leggerebbe pixel di mostro come
    // eventi di canzone. Stessa precauzione di svc_battle_load_gfx.
    audio_enabled = 0;
    mc_select_bank(MONGFX_BANK);

    pat  = *(const unsigned char **)MONGFX_PATTERN_ADDR;
    rval = *(const unsigned char **)MONGFX_ROWVAL_ADDR;
    pal  = *(const unsigned char **)MONGFX_PAL_TMS_ADDR;

    for (t = 0; t < (int)BST.n_types; t++) {
        const unsigned char *pr = pal + (unsigned int)BST.type_pal[t] * 4;
        for (r = 0; r < 4; r++) palcache[t * 4 + r] = pr[r];
        if (BST.type_gfx[t] & 0x01) n_large++;
    }

    // Passata 1: i piccoli, col banco 12 gia' in mano.
    for (t = 0; t < (int)BST.n_types; t++) {
        unsigned int slot;
        if (BST.type_gfx[t] & 0x01) continue;
        // Lo slot grafico della formazione vale 0-3 e alterna piccolo/grande;
        // per i piccoli, gfx>>1 sceglie fra le due grafiche della pagina.
        slot = (unsigned int)BST.chr_page * FF1_MON_GFX_PER_PAGE +
               (unsigned int)(BST.type_gfx[t] >> 1);
        load_enemy_tiles(BST.type_tile_base[t],
                         pat  + slot * FF1_MON_SLOT_BYTES,
                         rval + slot * FF1_MON_SLOT_BYTES,
                         FF1_MON_TILES, palcache + t * 4);
    }

    // Passata 2: i grandi. Un cambio di banco solo per tutta la battaglia,
    // perche' la formazione dichiara UNA pagina CHR e la meta' e' decisa da
    // quella -- pagine 0-7 nel banco 13, 8-15 nel 14.
    if (n_large) {
        // I due banchi sono gemelli per costruzione -- stessa struttura, stesse
        // dimensioni -- quindi il linker mette i puntatori allo STESSO
        // indirizzo e qui basta scegliere il numero di banco, senza duplicare
        // il ramo. Il controllo sotto rende la cosa esigibile: se un domani i
        // due .c divergessero, il guasto sarebbe un errore di compilazione e
        // non un mostro fatto di byte a caso.
#if (MONLGLO_PATTERN_ADDR != MONLGHI_PATTERN_ADDR) || \
    (MONLGLO_ROWVAL_ADDR  != MONLGHI_ROWVAL_ADDR)
#error "monlg_lo_bank e monlg_hi_bank non hanno piu' lo stesso layout"
#endif
        mc_select_bank((BST.chr_page < FF1_MONLG_PAGES_HALF)
                           ? MONLG_LO_BANK : MONLG_HI_BANK);
        pat  = *(const unsigned char **)MONLGLO_PATTERN_ADDR;
        rval = *(const unsigned char **)MONLGLO_ROWVAL_ADDR;
        for (t = 0; t < (int)BST.n_types; t++) {
            unsigned int slot;
            if (!(BST.type_gfx[t] & 0x01)) continue;
            // La pagina dentro la meta' e' il resto della divisione per 8,
            // cioe' i tre bit bassi: nessuna sottrazione.
            slot = (unsigned int)(BST.chr_page & (FF1_MONLG_PAGES_HALF - 1)) * 2u +
                   (unsigned int)(BST.type_gfx[t] >> 1);
            load_enemy_tiles(BST.type_tile_base[t],
                             pat  + slot * FF1_MONLG_SLOT_BYTES,
                             rval + slot * FF1_MONLG_SLOT_BYTES,
                             FF1_MONLG_TILES, palcache + t * 4);
        }
    }

    mc_select_bank(BATTLE_BANK);
}

// ---------------------------------------------------------------------
//  svc_battle_load_cheer -- la posa di esultanza, caricata alla vittoria
// ---------------------------------------------------------------------
// Va chiamata SOLO dopo aver ripulito l'arena: scrive sulle tile $A4-$C7, che
// durante il combattimento appartengono ai primi due tipi di nemico. E' il
// prezzo di avere quattro tipi di nemico in 256 tile, ed e' il prezzo giusto:
// a vittoria ottenuta quei mostri non ci sono piu'.
void svc_battle_load_cheer(void) {
    audio_enabled = 0;
    mc_select_bank(2);
    load_class_pose(CHEER_TILE_BASE,
                    *(const unsigned char **)GFX_FF1_CLASS_CHEER_ADDR,
                    *(const unsigned char **)GFX_FF1_CLASS_CHEER_COLOR_ADDR);
    mc_select_bank(BATTLE_BANK);
}

// Fa partire sng50 dal banco 10. La chiama l'overlay DOPO aver disegnato la
// schermata, cosi' la musica entra insieme all'immagine invece che durante i
// 6000 e passa scritture VRAM del caricamento.
//
// Il giro dei banchi qui e' triplo e va letto con attenzione:
//   - si mappa il banco 10 per dereferenziare i puntatori alle note;
//   - audio_bank = 10 dice alla NMI dove leggere gli eventi a ogni tick;
//   - main_bank e' gia' 20 (lo ha messo run_battle), quindi la NMI rimette
//     l'overlay prima del `retn` e il codice interrotto ritrova se stesso;
//   - qui si rimette il banco 20 a mano, per il `ret` di questa funzione.
// E' lo stesso schema validato in slice51, con il banco della canzone che non
// e' piu' lo 0. Vedi [[code-overlay-architecture]] regola 6.
void svc_battle_start_music(void) {
    // init_song mappa da sola il banco 0 (per la tabella) e quello della
    // canzone, e rimette main_bank -- che qui e' il 20. Prima questa funzione
    // faceva le due commutazioni a mano col banco della battaglia CABLATO.
    init_song(SONG_ROW_BATTLE);
}

// =====================================================================
//  RICOMPENSE DI FINE BATTAGLIA (slice54)
// =====================================================================
// Replica EndOfBattleWrapUp + LvlUp_AwardExp + LvlUp_LevelUp (bank_0B.asm),
// con UNA deviazione voluta, segnata piu' sotto.
//
// Gira nel banco fisso perche' deve mappare il banco 11 (curva EXP e dati di
// livello): l'overlay non puo' farlo, si smonterebbe da solo.

// RNG DELLA BATTAGLIA, separato da quello dell'encounter. Non e' un dettaglio:
// `battle_step_rng` avanza la sequenza che decide gli incontri in overworld, e
// quella sequenza e' parte della parity col NES. Consumarla per tirare i
// bonus di livello la sfaserebbe per sempre.
// Sul NES sono davvero due generatori distinti (BattleRNG_L). Questo e' un
// SEGNAPOSTO: passo dispari sulla stessa tabella, cosi' percorre tutti i 256
// valori senza toccare l'indice dell'encounter. Va sostituito col BattleRNG
// vero quando arriva il turno fisico, che ne dipende molto piu' di qui.
static unsigned char btlrng_idx = 0;
static unsigned char battle_rng(void) {
    btlrng_idx = (unsigned char)(btlrng_idx + 0x11);
    return rng_lut_cache[btlrng_idx];
}

// L'ARITMETICA A 3 BYTE E IL PASSAGGIO DI LIVELLO NON SONO PIU' QUI (slice76).
// `level_up_one` e `svc_award_exp` erano **1539 byte di finestra fissa** che
// giravano una volta per battaglia vinta: dopo `party_init_from_classes` di
// slice72, il rapporto peggiore rimasto fra quanto una cosa costa e quanto la
// si usa. Sono passati nel banco 23 (`ovl_btlmagic.c`, modo BTLMAG_MODE_AWARDEXP),
// che l'overlay di battaglia gia' chiamava per la magia -- quindi zero strade
// nuove, un `else if` nel suo dispatch.
//
// Cio' che e' rimasto di la' e' l'unica cosa che DOVEVA restare: le tre
// tabelle dei livelli stanno nel banco 11 e un overlay non lo mappa. Le porta
// `svc_fetch_btl` con le tabelle 9, 10 e 11 -- tre `else if`, non una svc_
// nuova ([[svc-generalize-rule]]).

// Fanfara di vittoria (sng53). Sul NES la fa partire PlayFanfareAndCheer
// (bank_0C.asm:2435) con `LDA #$53`, insieme all'animazione di esultanza.
void svc_battle_victory_music(void) {
    silence_audio();
    init_song(SONG_ROW_VICTORY);
}

// =====================================================================
//  BATTAGLIA -- riempimento dello stato e salto nell'overlay
// =====================================================================
typedef unsigned int (*overlay_fn_t)(unsigned int);

// =====================================================================
//  svc_run_overlay -- la primitiva di ingresso in un banco di CODICE
// =====================================================================
// Mappa `bank`, salta al suo ingresso fisso ($C000, garantito un JP dal
// controllo in build_all.ps1), e rimette il banco che c'era prima.
//
// DUE ORDINI CHE NON SONO STILE:
//
//  1. `main_bank` si scrive PRIMA di mappare, in entrambe le direzioni. La
//     NMI dell'audio salta nel banco della canzone a ogni tick e in uscita
//     rimappa `main_bank`: se i due dati non sono d'accordo anche solo per
//     un'istruzione, una NMI caduta li' in mezzo lascia mappato il banco
//     sbagliato -- e il `ret` successivo atterra dentro dati. Il vecchio
//     codice di run_battle usciva nell'ordine opposto (`mc_select_bank(0)`
//     poi `main_bank = 0`) e aveva quella finestra aperta.
//
//  2. Il banco di ritorno e' quello LETTO all'ingresso, non lo zero. E' la
//     sola differenza che rende la primitiva annidabile: se a chiamare e'
//     un overlay -- attraverso il puntatore di main_symbols.h, quindi con il
//     codice nella finestra fissa, che c'e' sempre -- al ritorno si ritrova
//     mappato il PROPRIO banco e puo' proseguire.
//
// `arg` e il valore di ritorno passano com'erano: l'ingresso di un overlay ha
// firma unsigned int(unsigned int) e non e' cambiata.
unsigned int svc_run_overlay(unsigned char bank, unsigned int arg) {
    unsigned char prev = main_bank;
    unsigned int ret;

    main_bank = bank;
    mc_select_bank(bank);
    ret = ((overlay_fn_t)OVERLAY_ENTRY)(arg);
    main_bank = prev;
    mc_select_bank(prev);
    return ret;
}

// slice53: non copia piu' nulla del gruppo. Nomi, classi e HP li legge
// l'overlay direttamente da PARTY ($6100), che e' RAM e quindi visibile da
// qualunque banco. Prima venivano ricopiati a ogni ingresso in battaglia, e
// al ritorno i danni si sarebbero dovuti riscrivere all'indietro.
// =====================================================================
//  Prelievi per il motore di battaglia (banchi 11 e 12)
// =====================================================================
// Questi tre servizi sono deliberatamente STUPIDI: mappano un banco, copiano
// pochi byte, rimettono il banco dell'overlay. Tutta l'intelligenza -- la
// decodifica dei 16 byte, il tiro delle quantita', la somma del bottino -- sta
// nell'overlay.
//
// La divisione non e' estetica, e' imposta dallo spazio. In slice55 la
// decodifica era scritta qui, e il codice della slice e' passato da 14980 a
// 16916 byte: 684 oltre la fine della finestra fissa $8000-$BFFF. Il
// risultato non era un errore di compilazione ma uno schermo BLU, perche' quel
// pezzo di codice finiva sopra $C000 e la overworld lo cancellava mappando i
// quadranti della mappa. Nel banco fisso resta solo cio' che DEVE starci:
// chi cambia banco.

// I 16 byte grezzi della formazione. Il bit 7 dell'id sceglie la variante B
// della stessa riga, quindi l'indice di tabella e' id & $7F -- la variante la
// gestisce chi decodifica.
void svc_battle_fetch_formdata(void) {
    const unsigned char *forms;
    int i;

    audio_enabled = 0;
    mc_select_bank(MONGFX_BANK);
    forms = *(const unsigned char **)MONGFX_FORMS_ADDR;
    forms += (unsigned int)(BST.formation & 0x7F) * 16;
    for (i = 0; i < 16; i++) BST.formdata[i] = forms[i];
    mc_select_bank(BATTLE_BANK);
}

// 20 byte di statistiche di un nemico (ENROMSTAT_*), dal banco 11.
// Prelievo dal banco 11. Da slice60 e' UNA sola funzione per tutte e tre le
// tabelle, e ha SOSTITUITO svc_fetch_enemy_stat invece di affiancarla.
//
// La prima stesura la affiancava, ed e' costata 166 byte: la finestra fissa e'
// passata da 169 liberi a 3 (`memory/fixed_window_full.md`). Due cose l'hanno
// resa cara, ed e' utile saperle perche' varranno per la prossima svc_:
//   - la moltiplicazione `idx * len` con `len` VARIABILE chiama un aiuto di
//     libreria. Qui l'offset in byte lo calcola il chiamante, che le costanti
//     ce le ha in casa;
//   - due copie dello stesso "mappa, dereferenzia, copia, rimappa" costano
//     due volte senza dire niente di piu'.
//
//   tabella 0 = statistiche di un nemico  20 byte  (128 voci)
//   tabella 1 = dati di un incantesimo     8 byte  ( 92 voci, $00-$5B)
//   tabella 2 = voce di IA nemica         16 byte  ( 44 voci)
//   tabella 3 = permessi di magia         96 byte  (12 classi x 8 livelli)
//   tabella 4 = nomi degli oggetti         8 byte  (240 voci, spazio $00-$EF)
//
// NIENTE tabella di puntatori per scegliere la base: sarebbe rodata della
// slice, cioe' oltre $C000, invisibile mentre e' mappato il banco 11 -- e
// invisibile pure al chiamante, che e' l'overlay nel banco 20. La catena di
// `if` invece compila a costanti immediate, che stanno nel codice.
//
// --- slice67: due correzioni, e nessuna delle due e' cosmetica ---------
//
// 1. IL BANCO DI RITORNO E' `main_bank`, NON `BATTLE_BANK`. Cablato, questo
//    servizio poteva essere chiamato da un solo overlay: il negozio di magia
//    lo avrebbe lasciato con mappato il banco 20 e il primo `ret` sarebbe
//    atterrato dentro il codice della battaglia. E' la stessa ragione per cui
//    svc_run_overlay rimette il banco LETTO all'ingresso -- letto, non
//    supposto. Durante la battaglia `main_bank` VALE BATTLE_BANK, quindi per
//    quel chiamante non cambia niente.
//    Il conto, misurato: la copia scritta dentro `svc_shop_fetch` costava 105
//    byte di finestra fissa (247 liberi -> 142; con la copia per puntatori
//    invece che per indice, 146). Generalizzare questo servizio e togliere di
//    la' quel pezzo ne costa 27 in tutto -- ramo della tabella 3, ritorno a
//    `main_bank` e salvataggio dell'audio compresi -- e ne lascia liberi 220.
//
// 2. `audio_enabled` SI RIMETTE COM'ERA. Prima si spegneva e basta, e nessuno
//    lo riaccendeva: la musica di battaglia moriva al PRIMO nemico con IA
//    (fetch_ai passa di qui a ogni suo turno). Non e' mai stato visto perche'
//    le corse di validazione girano con `-sound none` e perche' gli IMP delle
//    prime prove IA non ce l'hanno. Si SALVA e si rimette invece di forzare 1:
//    all'apertura della battaglia questo servizio viene chiamato PRIMA di
//    `svc_battle_start_music`, e accendere li' vorrebbe dire una NMI che suona
//    una canzone non ancora inizializzata.
void svc_fetch_btl(unsigned char table, unsigned int off,
                   unsigned char len, unsigned char *dst) {
    const unsigned char *src;
    unsigned char i, prev_audio;

    prev_audio = audio_enabled;
    audio_enabled = 0;
    mc_select_bank(BTLDATA_BANK);
    if (table == 0)      src = *(const unsigned char **)BTL_ENEMY_STATS_ADDR;
    else if (table == 1) src = *(const unsigned char **)BTL_MAGIC_DATA_ADDR;
    else if (table == 2) src = *(const unsigned char **)BTL_ENEMY_AI_ADDR;
    else if (table == 3) src = *(const unsigned char **)BTL_MAGIC_PERM_ADDR;
    // Tabella 5 (slice73): la curva degli EXP, 49 voci da 3 byte. La legge la
    // riga NEXT delle statistiche. E' l'ottavo cliente di questo servizio e il
    // primo che non ha niente a che fare con la battaglia: `svc_fetch_btl` e'
    // ormai "il servizio del banco 11", non "quello dei nemici".
    else if (table == 5) src = *(const unsigned char **)BTL_EXP_TO_ADVANCE_ADDR;
    // Tabelle 9-11 (slice76): le tre tabelle dei LIVELLI. Sono arrivate qui
    // quando `svc_award_exp` e `level_up_one` sono passati nel banco 23 --
    // 1539 byte di finestra fissa che giravano una volta per battaglia vinta,
    // cioe' la leva 1 di [[fixed-window-full]] applicata al caso rimasto piu'
    // vistoso dopo party_init. Tre `else if` contro i ~166 byte che sarebbe
    // costata una svc_ nuova: quinta volta che la regola paga
    // ([[svc-generalize-rule]]).
    else if (table == 9)  src = *(const unsigned char **)BTL_LEVELUP_DATA_ADDR;
    else if (table == 10) src = *(const unsigned char **)BTL_HITRATE_BONUS_ADDR;
    else if (table == 11) src = *(const unsigned char **)BTL_MAGDEF_BONUS_ADDR;
    // Tabelle 6 e 7 (slice74): i permessi di equipaggiamento, 40 voci da una
    // PAROLA l'una (12 classi non stanno in un byte), bit acceso = NON puo'.
    // Sono le stesse `lut_WeaponPermissions` / `lut_ArmorPermissions` che il
    // negozio riceve dentro `SHOP.perm[]`, ma li' le voci sono cinque e le
    // sceglie il negozio: il menu deve poterle chiedere per un oggetto
    // qualunque, a schermata gia' aperta. Copiate nel banco 11 per la stessa
    // ragione dei nomi in slice68 -- questo servizio quel banco lo mappa gia'.
    else if (table == 6) src = *(const unsigned char **)BTL_WEAPON_PERMS_ADDR;
    else if (table == 7) src = *(const unsigned char **)BTL_ARMOR_PERMS_ADDR;
    // Tabella 8: l'icona di TIPO di ogni oggetto, un byte per id. Il menu la
    // cercava dentro gli otto byte del nome -- che e' dove sta nel ROM, non
    // dove sta qui: l'estrattore la sostituisce con uno spazio e la mette in
    // una tabella sua. Vedi il commento in btldata_bank.c.
    else if (table == 8) src = *(const unsigned char **)BTL_ITEM_ICON_ADDR;
    // Tabella 12 (slice77): i teletrasporti, le otto fette di lut_*Tele in un
    // array piatto di 320 byte (data/teleport_data.h). Li legge il motore
    // delle mappe -- nono cliente, e il secondo che con la battaglia non
    // c'entra niente. L'offset della fetta lo mette il chiamante
    // (FF1_TELE_NORM_X + id, eccetera).
    else if (table == 12) src = *(const unsigned char **)BTL_TELEPORT_ADDR;
    else                 src = *(const unsigned char **)BTL_ITEM_NAMES_ADDR;
    src += off;
    for (i = 0; i < len; i++) dst[i] = src[i];
    mc_select_bank(main_bank);
    audio_enabled = prev_audio;
}

// Le sotto-statistiche EFFETTIVE di un personaggio, dalle sue basi piu' cio'
// che indossa. Sta nella finestra fissa perche' e' l'unico posto che puo'
// mappare il banco 16 mentre un overlay e' attivo -- stessa ragione di
// svc_battle_load_gfx col banco 2.
//
// DA ZERO, NON INCREMENTALE, ed e' la scelta di progetto di questa funzione.
// Sul NES sono due routine gemelle: UnadjustEquipStats toglie i bonus,
// ReadjustEquipStats li rimette (bank_0F.asm:10854). Quel giro serve al MENU,
// che deve poter provare un'arma e disfare. A noi serve solo il risultato, e
// tenere il "togli" vuol dire poter sbagliare a toglierlo: un ricalcolo di
// troppo e i bonus si sommano due volte, in silenzio e per sempre. Qui le basi
// (dmg_b/hitrate_b/evade_b) non si toccano mai e l'effettivo si riscrive
// intero.
//
// IL BANCO DI RITORNO E' QUELLO LETTO ALL'INGRESSO, non lo zero: questa la
// chiamano la slice (banco 0), la battaglia (banco 20) e domani il negozio.
// E' la stessa regola che rende annidabile svc_run_overlay.
void svc_equip_recalc(unsigned char who) {
    // Il puntatore al personaggio si prende UNA volta. Scrivere
    // `PARTY.chr[who].campo` a ogni riga fa rifare la moltiplicazione per la
    // dimensione della voce a ogni campo, e sccz80 la moltiplicazione la
    // chiama come routine: in questa funzione erano centinaia di byte.
    chr_t *c = &PARTY.chr[who];
    const unsigned char *wp;
    const unsigned char *ar;
    unsigned char prev_bank;
    unsigned char k, v, idx, cls;
    // La somma dei soli bonus d'arma, tenuta a parte dal danno totale. Serve al
    // monaco: il suo danno NON comprende la base, e sommarci forza/2 sopra il
    // totale da' un valore piu' alto del dovuto. Misurato: 13 invece di 11.
    unsigned int wdmg = 0;
    unsigned int hit, dmg;
    int evade;
    unsigned int absorb;
    unsigned char resist = 0;

    hit   = c->hitrate_b;
    dmg   = c->dmg_b;
    evade = (int)c->evade_b;
    absorb = 0;

    audio_enabled = 0;
    prev_bank = main_bank;
    main_bank = ITEMDATA_BANK;
    mc_select_bank(ITEMDATA_BANK);
    wp = *(const unsigned char **)ITEMDATA_WEAPONS_ADDR;
    ar = *(const unsigned char **)ITEMDATA_ARMOR_ADDR;

    for (k = 0; k < PARTY_EQUIP_SLOTS; k++) {
        v = c->weapon[k];
        // Bit 7 spento = posseduta ma NON indossata: il NES la salta con un
        // BPL, e saltarla e' la differenza fra avere una spada nello zaino e
        // averla in mano.
        if (!(v & EQUIP_EQUIPPED)) continue;
        idx = (unsigned char)((v & 0x7F) - 1);   // la casella e' 1-based
        if (idx >= FF1_N_WEAPONS) continue;
        hit  += wp[(unsigned int)idx * WPN_STAT_SIZE + WPN_STAT_HIT];
        wdmg += wp[(unsigned int)idx * WPN_STAT_SIZE + WPN_STAT_DMG];
    }
    dmg += wdmg;
    for (k = 0; k < PARTY_EQUIP_SLOTS; k++) {
        v = c->armor[k];
        if (!(v & EQUIP_EQUIPPED)) continue;
        idx = (unsigned char)((v & 0x7F) - 1);
        if (idx >= FF1_N_ARMORS) continue;
        // L'evasione si SOTTRAE: un'armatura pesante rallenta. E' l'unico
        // termine con segno di tutta la funzione, ed e' il motivo per cui
        // evade e' un int e non un unsigned char.
        evade  -= (int)ar[(unsigned int)idx * ARM_STAT_SIZE + ARM_STAT_EVDPEN];
        absorb += ar[(unsigned int)idx * ARM_STAT_SIZE + ARM_STAT_ABSORB];
        resist |= ar[(unsigned int)idx * ARM_STAT_SIZE + ARM_STAT_ELEMDEF];
    }

    main_bank = prev_bank;
    mc_select_bank(prev_bank);
    audio_enabled = 1;

    // Monaco e Maestro: le regole speciali di ReadjustBBEquipStats
    // (bank_0F.asm:11020). Il danno del monaco NON parte dalla base -- sul NES
    // UnadjustBBEquipStats lo azzera prima, quindi la sua storia di livelli
    // non conta: a mani nude vale il livello, con un'arma vale forza/2 piu'
    // l'arma. Ed e' proprio per questo che un monaco armato picchia MENO di
    // uno a mani nude, che e' la cosa che tutti scoprono giocando.
    cls = c->cls;
    if (cls == CLS_BB || cls == CLS_MA) {
        // Le due condizioni guardano il VALORE, non "ha qualcosa addosso", ed
        // e' cosi' anche sul NES: ReadjustBBEquipStats prova `LDA ch_dmg / BEQ`
        // dopo che UnadjustBBEquipStats ha azzerato. Un'arma dal bonus nullo
        // conta quindi come nessuna arma -- pare una sottigliezza, ma e' la
        // differenza fra ricalcare la routine e riscriverne una che le somiglia.
        if (wdmg != 0) dmg = (unsigned int)(c->str >> 1) + wdmg;
        else           dmg = (unsigned int)c->level * 2;
        // Sul NES il livello e' 0-based fuori battaglia e la formula fa +1.
        // Il nostro e' 1-based sempre: il +1 sarebbe un livello di troppo.
        if (absorb == 0) absorb = c->level;
    }

    if (hit    > 255) hit    = 255;
    if (dmg    > 255) dmg    = 255;
    if (absorb > 255) absorb = 255;
    if (evade  < 0)   evade  = 0;
    if (evade  > 255) evade  = 255;

    c->hitrate = (unsigned char)hit;
    c->dmg     = (unsigned char)dmg;
    c->evade   = (unsigned char)evade;
    c->absorb  = (unsigned char)absorb;
    c->resist  = resist;
}

// Compone il listino di un negozio nel blocco condiviso, leggendolo dal banco
// 16. L'overlay del negozio non potrebbe farlo da solo: mentre gira, il banco
// mappato e' lui. Stessa divisione di svc_battle_fetch_formdata -- qui sta
// COME si leggono i dati, di la' COME si disegnano.
void svc_shop_fetch(unsigned char shop_id) {
    const unsigned char *sd, *st, *pr, *ic, *pp;
    const char *nm;
    unsigned char prev_bank, k, j, id, base;
    unsigned int off;

    audio_enabled = 0;
    prev_bank = main_bank;
    main_bank = ITEMDATA_BANK;
    mc_select_bank(ITEMDATA_BANK);
    sd = *(const unsigned char **)ITEMDATA_SHOPDATA_ADDR;
    st = *(const unsigned char **)ITEMDATA_SHOPTYPES_ADDR;
    pr = *(const unsigned char **)ITEMDATA_PRICES_ADDR;
    ic = *(const unsigned char **)ITEMDATA_ICON_OF_ADDR;
    nm = *(const char **)ITEMDATA_NAMES_ADDR;
    // slice66: i permessi viaggiano col listino. Sono l'unica cosa del negozio
    // che stava ancora nel banco 16 e serviva DENTRO l'overlay, e portarli qui
    // evita una svc_ nuova -- che al prezzo misurato in slice60 sarebbe stata
    // ~166 byte di finestra fissa, contro i 461 che restavano.
    //
    // QUALE tabella lo dice il TIPO di negozio, e si sceglie FUORI dal ciclo.
    // Sul NES e' la stessa forcella (`LDX shop_type / BNE @CheckArmor`,
    // EquipShop_GiveItemToChar). Deciderlo voce per voce dallo spazio degli id
    // e' altrettanto corretto e costa 46 byte di finestra fissa in piu':
    // misurato, non supposto.
    pp   = 0;
    base = 0;
    if (st[shop_id] == SHOPTYPE_WEAPON) {
        pp   = *(const unsigned char **)ITEMDATA_WEAPON_PERMS_ADDR;
        base = FF1_ITEM_WEAPON_BASE;
    } else if (st[shop_id] == SHOPTYPE_ARMOR) {
        pp   = *(const unsigned char **)ITEMDATA_ARMOR_PERMS_ADDR;
        base = FF1_ITEM_ARMOR_BASE;
    }

    SHOP.magic   = SHOP_STATE_MAGIC;
    SHOP.id      = shop_id;
    SHOP.type    = st[shop_id];
    SHOP.count   = 0;
    SHOP.service = 0;

    // I puntatori della tabella sono indirizzi ASSOLUTI del NES: lut_ShopData
    // sta a $8300 nel banco $0E, quindi l'offset e' `puntatore - $8300`.
    off = (unsigned int)sd[(unsigned int)shop_id * 2]
        | ((unsigned int)sd[(unsigned int)shop_id * 2 + 1] << 8);
    off -= 0x8300;

    if (SHOP.type == SHOPTYPE_CLINIC || SHOP.type == SHOPTYPE_INN) {
        // Non e' merce: e' il prezzo del servizio, word LE.
        SHOP.service = (unsigned int)sd[off] | ((unsigned int)sd[off + 1] << 8);
    } else {
        for (k = 0; k < SHOP_MAX_ITEMS; k++) {
            id = sd[off + k];
            // Si FERMA allo zero, non lo salta: le liste si sovrappongono e
            // oltre lo zero ci sono i byte del negozio dopo. Scorrendo tutti
            // e cinque, l'armeria di Coneria venderebbe CURE.
            if (id == 0) break;
            SHOP.item[k]  = id;
            SHOP.price[k] = (unsigned int)pr[(unsigned int)id * 2]
                          | ((unsigned int)pr[(unsigned int)id * 2 + 1] << 8);
            SHOP.icon[k]  = ic[id];
            // Il permesso e' una PAROLA (12 classi non stanno in un byte) e la
            // tabella si sceglie dallo SPAZIO DEGLI ID, non dal tipo di
            // negozio: e' l'id a dire che cos'e' un oggetto. Zero = nessun
            // divieto, ed e' cio' che vale per magie e consumabili, che
            // permessi di equipaggiamento non ne hanno.
            if (pp) {
                j = (unsigned char)((id - base) << 1);   /* voce da 2 byte */
                SHOP.perm[k] = (unsigned int)pp[j] | ((unsigned int)pp[j + 1] << 8);
            } else {
                SHOP.perm[k] = 0;
            }
            for (j = 0; j < SHOP_NAME_LEN; j++) {
                SHOP.name[(unsigned int)k * SHOP_NAME_LEN + j] =
                    nm[(unsigned int)id * SHOP_NAME_LEN + j];
            }
            SHOP.count++;
        }
    }

    // I PERMESSI DI MAGIA NON PASSANO DI QUI. Stanno nel banco 11, non nel 16,
    // e la prima stesura di slice67 li copiava proprio in questo punto con una
    // seconda escursione: costava 105 byte di finestra fissa, che a 247 liberi
    // era piu' del 40% di quello che restava. Li prende l'overlay da solo con
    // `svc_fetch_btl(3, ...)`, cioe' il servizio del banco 11 che esisteva gia'
    // -- una volta reso capace di tornare a `main_bank` invece che al banco
    // della battaglia. Un servizio generalizzato invece di un secondo servizio
    // che gli somiglia: e' la stessa lezione di slice60, li' costata 166 byte.
    main_bank = prev_bank;
    mc_select_bank(prev_bank);
    audio_enabled = 1;
}

// Le 12 tile delle icone di tipo, dal banco 16 alla VRAM. Separata dal
// listino perche' e' l'unica cosa che va nella VRAM e non in RAM, e perche'
// si fa una volta per apertura invece che una per voce.
void svc_shop_load_icons(unsigned char tile_base) {
    const unsigned char *p;
    unsigned char prev_bank;
    unsigned int addr;

    audio_enabled = 0;
    prev_bank = main_bank;
    main_bank = ITEMDATA_BANK;
    mc_select_bank(ITEMDATA_BANK);
    p = *(const unsigned char **)ITEMDATA_ICONS_ADDR;
    addr = (unsigned int)tile_base * 8;
    // In tutti e tre i terzi dello schermo, come per il font: in Mode 2 le
    // tre parti hanno tabelle di pattern separate.
    vwrite3(p, 0x0000 + addr, FF1_ICON_COUNT * 8);
    main_bank = prev_bank;
    mc_select_bank(prev_bank);
    audio_enabled = 1;
}

// NIENTE `svc_fetch_item_name`, ed e' una misura, non una dimenticanza.
// Il sottomenu della magia ha bisogno dei nomi degli incantesimi, che stanno
// nel banco 16 e da un overlay non si vedono. La strada ovvia era un servizio
// qui dentro: **165 byte MISURATI** per copiarne otto, con la finestra fissa a
// 220 liberi. Il prezzo non e' il ciclo, e' il contorno -- salvare e rimettere
// banco e audio, due commutazioni, il preludio di una funzione a due
// argomenti; scriverlo con `<< 3` invece che con `* 8` ne ha risparmiato UNO.
// I nomi sono passati nel banco 11 (btldata_bank.c) e li prende
// `svc_fetch_btl`, che quel banco lo mappava gia': una tabella in piu' costa
// un `else if`. La regola: **prima di aggiungere una svc_, guardare se una
// di quelle che ci sono gia' mappa il banco giusto.**

// Nome di un nemico, 8 caratteri + terminatore, gia' convertito dal charset
// custom $8A-$BD al font BIOS.
//
// IL BANCO DI RITORNO E' `main_bank`, NON `BATTLE_BANK` -- e questa riga e'
// costata una corsa in slice69.
//
// Cablato, il servizio funzionava per un chiamante solo. Quando la preparazione
// della battaglia si e' spostata nel banco 23, questa funzione ha rimappato il
// banco 20 e il `ret` e' atterrato all'indirizzo del chiamante DENTRO IL CODICE
// DI UN ALTRO OVERLAY. Il sintomo non e' stato un blocco: la macchina ha
// continuato a girare, la battaglia si e' aperta con i cinque mostri al posto
// giusto (decode_formation aveva gia' finito) e con TUTTI GLI HP A ZERO,
// perche' la riga dopo non e' mai stata eseguita. Cioe' esattamente un
// "difetto della formazione" da cercare per mezz'ora nel posto sbagliato.
//
// E' la stessa correzione gia' fatta a `svc_fetch_btl` in slice67, per la
// stessa ragione, sull'altro chiamante nuovo. La regola vale per TUTTE le
// svc_: **il banco di ritorno e' quello LETTO all'ingresso, mai quello
// supposto.** Le altre svc_battle_* qui sopra hanno ancora la costante e oggi
// sono corrette perche' le chiama un overlay solo; sono la prossima a cadere.
void svc_fetch_enemy_name(unsigned char id, unsigned char *dst) {
    const unsigned char *names;
    int i;

    audio_enabled = 0;
    mc_select_bank(MONGFX_BANK);
    names = *(const unsigned char **)MONGFX_NAMES_ADDR;
    names += (unsigned int)id * 9;
    for (i = 0; i < 9; i++) dst[i] = names[i];
    mc_select_bank(main_bank);
}

// Il generatore della battaglia, esposto all'overlay. Deve restare di qua
// perche' legge rng_lut_cache, che e' RAM della slice, e perche' e' lo stesso
// generatore che usa il passaggio di livello: due sequenze separate
// sfaserebbero la parity.
// Colore del bordo. E' l'unica cosa che un overlay non puo' fare da solo fra
// quelle che servono all'intro: scrivere un registro del VDP e' due OUT, ma
// vanno serializzati con la NMI dell'audio, che il VDP lo tocca a ogni frame.
// Il primo argomento di vdp_color e' irrilevante in modo 2 (i colori veri
// stanno nella tabella colori), quindi passa solo il bordo.
void svc_border(unsigned char color) {
    vdp_color(VDP_INK_WHITE, VDP_INK_BLACK, color);
}

unsigned char svc_battle_rng(void) {
    return battle_rng();
}

static void fill_battle_state(unsigned char formation, unsigned char domain) {
    BST.magic       = BATTLE_STATE_MAGIC;
    BST.formation   = formation;
    BST.domain      = domain;
    BST.turn_chr    = 0;
    BST.command_idx = 0;
    BST.round_num   = 1;
    BST.result      = 0;
    BST.exp_award   = 0;
    BST.gp_award    = 0;

    // La composizione del gruppo nemico NON si decide qui. La slice si limita
    // a dire QUALE formazione e' uscita; chi sono i nemici, quanti e con che
    // colori lo stabilisce l'overlay, che per farlo chiama i prelievi qui
    // sopra. Vedi la nota su svc_battle_fetch_formdata.
    BST.exp_total = 0;
    BST.gp_total  = 0;
}

// Blocca finche' la battaglia non finisce, poi ritorna il risultato.
static unsigned int run_battle(unsigned char formation, unsigned char domain) {
    unsigned int ret;

    fill_battle_state(formation, domain);

    // Silenzio il tema della overworld: sng50 riparte da capo dentro l'overlay,
    // via svc_battle_start_music, quando la schermata e' gia' disegnata.
    silence_audio();
    vdp_put_sprite_16(0, 0, 200, 0, VDP_INK_TRANSPARENT);

    // Tutta la parte di banchi sta in svc_run_overlay: qui resta solo cio' che
    // e' della BATTAGLIA (stato, silenzio, sprite).
    ret = svc_run_overlay(BATTLE_BANK, 0);

    // Il magic si azzera all'USCITA. Finche' restava scritto voleva dire "una
    // battaglia c'e' stata", non "sono in battaglia": chi guarda dall'esterno
    // (tools/mame_drive_battle.lua) non aveva modo di accorgersi del ritorno in
    // overworld, e quindi non poteva incatenare piu' incontri di seguito. Ora
    // il campo significa una cosa sola.
    BST.magic = 0;

    return ret;
}

// =====================================================================
//  MAIN
// =====================================================================
// Posizione nel mondo: 256x256 pieni, avvolgimento toroidale con & 0xFF.
//
// SONO GLOBALI, e non e' indifferente: da locali di main() non finiscono nella
// .map, quindi `tools/build_all.ps1` non riesce a metterle in
// build/probe_addrs.lua e le sonde Lua leggono `nil` -- che MAME converte in
// indirizzo 0 e restituisce un byte del BIOS. Il sintomo e' una posizione che
// non cambia mai (si legge due volte lo stesso byte), cioe' identico a un
// personaggio che non si muove: si accusa la collisione invece della sonda.
// Da slice77 la DEFINIZIONE sta piu' in alto, prima del ciclo delle citta':
// il teletrasporto EXIT e' il primo pezzo di quel ciclo che le scrive.

int main(void) {
    unsigned int j;
    int facing = DIR_DOWN;
    int walk_phase = 0;
    int sprite_handle, frame;
    unsigned char macro_id, attr1, domain, formation, rng_val, tele_id;
    int mode = MODE_OW;

    int step_cooldown = 0;
    int stepping = 0;

    vdp_set_mode(mode_2);
    vdp_set_sprite_mode(sprite_large);
    vdp_vfill(0x0000, 0, 6144);
    vdp_vfill(0x2000, 0, 6144);

    silence_audio();
    nmi_install_isr(audio_nmi_tick);

    // ---- Scene di apertura: banco 21 (slice62) ----------------------
    // Il Prelude parte QUI, non dentro l'overlay: init_song deve leggere la
    // tabella (rodata, banco 0) e poi dereferenziare puntatori che vivono
    // nel banco 1, e da dentro un overlay nessuno dei due esiste. Avviato
    // prima, continua da solo per tutta la scena -- la NMI mappa il banco 1
    // a ogni tick e rimette main_bank, che nel frattempo e' il 21.
    init_song(SONG_ROW_PRELUDE);
    main_bank = 1;
    mc_select_bank(1);

    // Le quattro classi (3 bit l'una) e il respond rate tornano impacchettati
    // nel valore di ritorno: vedi la nota su overlay_main in ovl_intro.c.
    {
        unsigned int packed = svc_run_overlay(INTRO_OVL_BANK, 0);
        int i;
        for (i = 0; i < N_PARTY; i++) {
            party_class[i] = (unsigned char)((packed >> (i * 3)) & 7);
        }
        respond_rate = (unsigned char)(((packed >> 12) & 0x0F) + 1);
    }

    // Il gruppo nasce QUI, ancora prima di tornare al banco 0: da slice72 le
    // statistiche iniziali le legge l'overlay dell'intro, che quella tabella
    // ce l'ha in casa. E' anche il motivo per cui l'avvertenza che stava qui
    // ("deve stare dopo mc_select_bank(0), o si leggerebbe il codice
    // dell'overlay come punti forza") non serve piu': non c'e' piu' niente da
    // leggere nella finestra commutabile.
    party_new_game();

    // ---- Transition to OW (bank 0 default for sng44; map reads via banks 3-6) ----
    silence_audio();
    main_bank = 0;
    mc_select_bank(0);
    rng_cache_init();
    load_ow_chr_palette();
    load_ow_player_sprite();
    redraw_ow_view_from_banks(world_player_mx, world_player_my);
    init_song(SONG_ROW_OW);

    while (1) {
        svc_wait_vblank();

        if (mode == MODE_TOWN) {
            // town_tick torna 1 solo per TP_TELE_WARP, ora che FIRE2 non esce
            // piu'. Si rientra in overworld alle coordinate da cui si era
            // partiti: world_player_mx/my non le tocca nessuno mentre si e' in
            // citta', ed e' esattamente il "torna alla mappa precedente" del
            // NES. Il teletrasporto della citta' non riscatta perche' entrare
            // in citta' e' dentro il ramo del PASSO: chi non si muove non lo
            // fa scattare.
            if (town_tick()) {
                mode = MODE_OW;
                silence_audio();
                mc_select_bank(0);
                enter_ow(world_player_mx, world_player_my);
                step_cooldown = 0;
                stepping = 0;
            }
            continue;
        }

        // ----- MODE_OW: discrete macrotile step on the full 256x256 OW -----
        j = joystick(1);

        // Il menu (slice73). In overworld il ritorno passa da `enter_ow`, che
        // ridisegna tutto e RIAVVIA il tema: e' la stessa strada del ritorno
        // dalla battaglia, gia' provata. In citta' invece il tema NON si
        // interrompe, perche' li' la grafica si rimette senza toccare l'audio.
        // La differenza si sente, ed e' un debito dichiarato: sparisce il
        // giorno in cui l'overworld avra' un ripristino leggero come quello
        // della citta'.
        if (menu_pressed(j)) {
            svc_run_overlay(MENU_BANK, 0);   /* 0 = si e' in overworld */
            enter_ow(world_player_mx, world_player_my);
            step_cooldown = STEP_COOLDOWN_FRAMES;
            stepping = 0;
            continue;
        }

        if (step_cooldown > 0) {
            step_cooldown--;
        } else {
            int dx = 0, dy = 0;
            int held = 0;
            if (j & MOVE_UP)         { facing = DIR_UP;    dy = -1; held = 1; }
            else if (j & MOVE_DOWN)  { facing = DIR_DOWN;  dy =  1; held = 1; }
            else if (j & MOVE_LEFT)  { facing = DIR_LEFT;  dx = -1; held = 1; }
            else if (j & MOVE_RIGHT) { facing = DIR_RIGHT; dx =  1; held = 1; }
            if (held) {
                // ---- collisione (slice58) --------------------------------
                // Il tile di DESTINAZIONE si legge PRIMA di muoversi, non dopo.
                // Non e' un riordino cosmetico: e' l'unico ordine in cui si
                // puo' rifiutare il passo, ed e' anche quello che fa il NES
                // (`OWCanMove`, bank_0F.asm:1086, calcola le coordinate di
                // arrivo e legge li' le proprieta').
                //
                // Il byte 0 delle proprieta' e' una maschera dei VEICOLI
                // BLOCCATI, non dei permessi: sul NES si fa `AND vehicle` e
                // zero vuol dire "si passa". A piedi il veicolo e' il bit 0,
                // cioe' FF1_OW_ATTR_NOWALK. Mare e montagne hanno quel bit
                // acceso, e i dati erano gia' in ff1_ow_attr da slice44 --
                // finora si leggeva solo il byte 1, quello dei teletrasporti.
                //
                // Questa lettura SOSTITUISCE quella che stava dopo il passo:
                // il costo in cambi di banco non cambia.
                unsigned char dst_mx = (unsigned char)((int)world_player_mx + dx);
                unsigned char dst_my = (unsigned char)((int)world_player_my + dy);
                unsigned char dst_macro;
                unsigned char on_bridge;

                step_cooldown = STEP_COOLDOWN_FRAMES;

                audio_enabled = 0;
                dst_macro = ow_read_macro(dst_mx, dst_my);
                mc_select_bank(0);   // rodata OW + NMI
                audio_enabled = 1;

                // slice78: IL PONTE, l'eccezione consultata DOPO il rifiuto.
                // L'ordine e' quello del NES (`IsOnBridge`, bank_0F.asm:565,
                // chiamata solo quando `OWCanMove` ha gia' detto no) e non e'
                // un dettaglio: il macrotile sotto resta OCEANO, quindi
                // guardare prima la casella del ponte vorrebbe dire un
                // secondo posto in cui l'acqua diventa calpestabile.
                on_bridge = 0;
                if (dst_mx == BRIDGE_OW_X) {
                    if (dst_my == BRIDGE_OW_Y) {
                        if (BRIDGE_VISIBLE()) on_bridge = 1;
                    }
                }

                if ((ff1_ow_attr[dst_macro][0] & FF1_OW_ATTR_NOWALK) && !on_bridge) {
                    // Bloccato. Come `@CantMove` sul NES (bank_0F.asm:612): non
                    // si muove, e soprattutto non scatta NIENTE -- ne' incontri
                    // ne' teletrasporti. Il personaggio pero' si GIRA, perche'
                    // il verso viene deciso dall'input prima del tentativo: e'
                    // cio' che rende leggibile un ostacolo invece di far
                    // sembrare il comando ignorato.
                    stepping = 0;
                    draw_mapman(facing * 2 + walk_phase);
                    goto ow_step_done;
                }

                walk_phase = walk_phase ^ 1;
                stepping = 1;

                // slice49: la SAT si scrive PRIMA dello scroll.
                // Il redraw di 768 celle costa ~6.5ms contro i ~4.4ms di
                // vblank, quindi sborda nel raster attivo: se il mapman
                // venisse aggiornato dopo, il pennello sarebbe gia' passato
                // sopra di lui e per un frame si vedrebbe la mappa gia'
                // scrollata con la sprite ancora girata come prima. E'
                // esattamente il "la sprite ruota DOPO lo scroll" notato
                // giocando. Scrivere i 4 sprite costa una manciata di byte
                // e sta comodamente nel vblank.
                draw_mapman(facing * 2 + walk_phase);

                // Toroidal step: wrap & 0xFF means walking off east edge
                // appears on west edge (and same for N/S). This is FF1's
                // canonical world topology.
                world_player_mx = dst_mx;
                world_player_my = dst_my;
                redraw_ow_view_from_banks(world_player_mx, world_player_my);

                // Il macro e' gia' in mano: lo ha letto il controllo di
                // collisione qui sopra, dalla stessa posizione. Rileggerlo
                // costerebbe un altro cambio di banco per avere lo stesso byte.
                macro_id = dst_macro;
                attr1 = ff1_ow_attr[macro_id][1];

                // slice78: sul PONTE non scatta NIENTE, ne' teletrasporti ne'
                // incontri. Sul NES lo si ottiene azzerando `tileprop+1`
                // prima del controllo (bank_0F.asm:563), ed e' necessario e
                // non cosmetico: sotto il ponte il tile e' OCEANO, quindi
                // l'incontro che scatterebbe sarebbe una battaglia NAVALE
                // presa a piedi. La scena, se e' la prima volta, si arma qui
                // e parte dopo il passo -- come `INC bridgescene`.
                if (on_bridge) {
                    if (bridgescene == BRIDGESCENE_NONE) bridgescene = BRIDGESCENE_DUE;
                    attr1 = 0;
                }

                if (attr1 & FF1_OW_ATTR1_TELEPORT) {
                    // slice77: qualunque ingresso consulta lut_EntrTele
                    // (banco 11) e cerca la mappa nella tabella dei
                    // descrittori. 1 = Coneria, 9 = castello 1F, 13 = il
                    // tempio. Le mappe che non abbiamo ancora stampano TPxx
                    // come prima -- e' la lista di cio' che manca, a schermo.
                    unsigned char t[3];
                    tele_id = attr1 & 0x3F;
                    fetch_entr_tele(tele_id, t);
                    if (town_goto(t)) {
                        mode = MODE_TOWN;
                        stepping = 0;
                        step_cooldown = 0;
                    } else {
                        char msg[5];
                        msg[0] = 'T'; msg[1] = 'P';
                        msg[2] = "0123456789ABCDEF"[(tele_id >> 4) & 0xF];
                        msg[3] = "0123456789ABCDEF"[tele_id & 0xF];
                        msg[4] = 0;
                        render_string(28, 23, msg);
                    }
                } else if (attr1 & FF1_OW_ATTR1_FIGHT) {
                    rng_val = battle_step_rng();
                    if (rng_val < ENCOUNTER_RATE_LAND) {
                        // World macro coords ARE the NES coords (slice43b's
                        // WINDOW_NES_X offset is gone -- we use the full world).
                        domain = compute_domain(world_player_mx, world_player_my, attr1);
                        if (domain != 0xFF) {
                            formation = get_battle_formation(domain);
                            // La battaglia BLOCCA: run_battle torna solo a
                            // battaglia finita. Non c'e' piu' un MODE_BATTLE
                            // nel ciclo principale -- il ciclo di battaglia
                            // adesso gira dentro l'overlay.
                            run_battle(formation, domain);
                            enter_ow(world_player_mx, world_player_my);
                            stepping = 0;
                            step_cooldown = 0;
                        }
                    }
                }
            } else {
                stepping = 0;
            }
        }

    ow_step_done:
        // slice78: la scena del ponte parte QUI, a passo finito, e non dentro
        // il ramo del passo. E' l'ordine del NES -- `DoOWTransitions`
        // (bank_0F.asm:291) gira dopo che il movimento e' completo -- e serve:
        // il giocatore deve VEDERSI sul ponte prima che lo schermo cambi,
        // altrimenti la scena sembra partire dalla casella precedente.
        if (bridgescene == BRIDGESCENE_DUE) {
            bridgescene = BRIDGESCENE_DONE;
            // Il Prologue (sng42) parte di qua, non dentro l'overlay: la
            // tabella delle canzoni e' rodata del banco 0 e il banco 1, dove
            // vivono gli eventi, da dentro un overlay non esiste. Avviato
            // prima, continua da solo per tutta la scena -- e' la stessa
            // strada del Prelude sulle scene di apertura (slice62).
            silence_audio();
            init_song(SONG_ROW_PROLOGUE);
            svc_run_overlay(BRIDGE_BANK, 0);
            // Al ritorno la VRAM e' quella della scena: la overworld si
            // rimette per intero, tema compreso.
            enter_ow(world_player_mx, world_player_my);
            stepping = 0;
            step_cooldown = 0;
        }
        if (mode == MODE_OW) {
            frame = stepping ? walk_phase : 0;
            sprite_handle = facing * 2 + frame;
            draw_mapman(sprite_handle);
        }
    }
    return 0;
}
