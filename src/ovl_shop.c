// =====================================================================
//  ovl_shop.c -- il negozio, overlay di CODICE (banco 22)
// =====================================================================
// TERZO overlay del progetto. Ci si entra dalla citta' calpestando una porta,
// con `svc_run_overlay(SHOP_BANK, shop_id)`: la citta' e' gia' dentro un
// contesto suo, e la chiamata e' annidabile proprio per questo.
//
// COSA FA (slice67)
//   armi/armature  compra, paga, riempie la casella e -- se i permessi lo
//                  consentono e il posto e' libero -- INDOSSA
//   magia          insegna: permesso di classe, "la sa gia'", livello pieno.
//                  NUOVO in slice67, ed e' il prerequisito della magia del
//                  giocatore in battaglia -- il motore c'e' da slice60, ma a
//                  nuova partita `ch_spells` e' vuoto e non c'e' niente da
//                  lanciare
//   locanda        paga e rimette in piedi HP e MP di tutti
//   clinica        paga e riporta in vita UN caduto (1 HP, come il NES)
//   oggetti        mostra il listino e dice ancora NOT YET: un inventario del
//                  gruppo non esiste, quindi comprare non cambierebbe niente
//
// -- le tre regole dell'overlay, e come sono rispettate qui --------------
//
// 1. NIENTE mc_select_bank: l'overlay E' il banco 22. Le tabelle dei negozi
//    stanno nel 16 e da qui NON si vedono. Le porta una `svc_` della finestra
//    fissa (`svc_shop_fetch`) nel blocco condiviso di shop_state.h, e le tile
//    delle icone in VRAM (`svc_shop_load_icons`). Qui dentro resta solo il
//    disegno e le decisioni. Dalla slice66 il listino porta con se' anche i
//    PERMESSI: erano l'ultima cosa del banco 16 che serviva qui dentro.
//
// 2. IL GRUPPO SI LEGGE E SI SCRIVE DIRETTAMENTE. `PARTY` sta in RAM SGM, che
//    non dipende dal banco: oro, caselle, HP e MP si toccano da qui senza
//    nessun servizio. L'unica chiamata dopo aver scritto una casella e'
//    `svc_equip_recalc`, che deve stare di la' perche' mappa il banco 16.
//
// 3. NIENTE INIZIALIZZATORI, nemmeno su uno scalare, e niente tabelle. La DATA
//    di un overlay non viene MAI inizializzata: `static unsigned char x = 1;`
//    vale spazzatura. I testi sono array 1-D con i NUL dentro; i valori di
//    partenza si assegnano dentro le funzioni. E' la trappola che in slice62
//    ha prodotto un menu aperto su "RESPOND RATE 0" senza sembrare rotto.
//
// PERCHE' L'ACQUISTO EQUIPAGGIA (deviazione dal NES, docs/Coleco_improvements.md)
// Sul NES comprare mette l'oggetto nello zaino con il bit 7 spento, e per
// indossarlo si passa dal MENU. Il menu qui non esiste ancora: senza il passo
// automatico, comprare non cambierebbe un solo numero visibile e non ci
// sarebbe modo di sapere se ha funzionato. Le condizioni sono le stesse che il
// menu del NES applicherebbe (`IsEquipLegal`): permesso di classe, e un solo
// pezzo per posto -- un'arma, e una corazza/scudo/elmo/guanto ciascuno. Se il
// posto e' gia' occupato l'oggetto resta nello zaino, esattamente come sul NES.
//
// PERCHE' IL NEGOZIO SI RIDISEGNA DA SOLO E LA CITTA' NO
// All'ingresso questo file si prende tutta la VRAM (font del BIOS + icone) e
// all'uscita la citta' deve rimettere la sua. Ma NON deve riespandere la
// mappa: `expand_town` costa ~140 frame e scrive `world_cells`, che sta in RAM
// SGM e che il negozio non tocca. Serve solo ricaricare pattern e colori e
// ridisegnare la vista -- una manciata di frame.
// =====================================================================

#define SVC_OVERLAY
#include "svc_api.h"
#include "party_state.h"
#include "shop_state.h"
#include "ff1_item_icons.h"   // FF1_ICON_FIRST / FF1_ICON_VALID / FF1_ICON_INDEX
#include "data/item_names.h"  // SOLO le macro dello spazio degli id (nessun dato)

// Costanti di games.h: l'overlay non linka nulla della libreria.
#define MOVE_RIGHT  1
#define MOVE_LEFT   2
#define MOVE_DOWN   4
#define MOVE_UP     8
#define MOVE_FIRE1 16
#define MOVE_FIRE2 32

// tms99x8.h
#define INK_BLACK      0x01
#define INK_DARK_BLUE  0x04

// Il font del BIOS Coleco sta a $15A3, cioe' SOTTO $8000: non e' nella
// finestra commutabile e si legge da qui come dalla slice.
#define BIOS_FONT_ADDR  ((const void*)0x15A3)
#define BIOS_FONT_LEN   760
#define FONT_TILE_BASE  0x20
// Le 12 icone di tipo vanno SOTTO il font, nelle tile $10-$1B: quella zona in
// Mode 2 non la usa nessuno, e mettendole sopra il font ($7F+) avrebbero
// litigato con le tile dei personaggi quando il negozio dovra' mostrarli.
#define ICON_TILE_BASE  0x10

// --- la pianta dello schermo, 32x24 ----------------------------------
#define ROW_TITLE   1
#define ROW_ITEM0   3     /* le voci vanno di due in due: 3 5 7 9 11 */
#define ROW_GOLD   13
#define ROW_PROMPT 15
#define ROW_CHR0   17     /* i quattro personaggi: 17 18 19 20 */
#define ROW_MSG    22
#define ROW_HINT   23

// Esiti dell'acquisto. Non e' un lusso: "comprato e indossato" e "comprato e
// riposto" sono due cose diverse per chi gioca, e distinguerle a schermo evita
// la domanda "ho comprato la spada e il danno non e' cambiato, e' rotto?".
#define BUY_WORN     0
#define BUY_STOWED   1
#define BUY_NOROOM   2
#define BUY_NOGOLD   3

// Esiti dell'apprendimento (slice67). Sono i TRE rifiuti di
// MagicShop_AssertLearn (bank_0E.asm:5705) piu' l'oro, e vanno tenuti distinti
// per la stessa ragione di sopra: "non puo' impararla", "la sa gia'" e "il
// livello e' pieno" portano a tre mosse diverse del giocatore, e un unico "no"
// glielo lascerebbe indovinare.
#define LEARN_OK      0
#define LEARN_NOPERM  1
#define LEARN_KNOWN   2
#define LEARN_FULL    3
#define LEARN_NOGOLD  4

// Otto incantesimi per livello nel ROM (4 bianchi + 4 neri); un personaggio ne
// impara al massimo TRE. I due numeri sono diversi apposta e confonderli e' il
// modo naturale di sbagliare: il valore scritto in `ch_spells` dice QUALE
// degli otto (1-8), la casella dice IN QUALE DEI TRE POSTI sta.
#define MAGIC_PER_LEVEL  8

static const char txt_types[] =
    "WEAPON SHOP\0"
    "ARMOR SHOP\0"
    "WHITE MAGIC SHOP\0"
    "BLACK MAGIC SHOP\0"
    "CLINIC\0"
    "INN\0"
    "ITEM SHOP\0"
    "CARAVAN\0";

static const char txt_gold[]    = "GOLD";
static const char txt_gp[]      = "GP";
static const char txt_soon[]    = "BUYING: NOT YET";
static const char txt_toomany[] = "YOU'RE CARRYING TOO MANY";
// SETTE CARATTERI, e non "IN THE PACK". `render_string` scrive `n` byte di
// seguito nella name table e la name table non ha righe: una stringa che
// sborda dalla colonna 31 riprende dalla colonna 0 della riga DOPO. Con
// "IN THE PACK" a colonna 26 le quattro lettere di troppo cadevano sopra
// "1 HE" della prima voce, che a schermo diventava ">PACKAL   60 GP" -- cioe'
// un titolo che sembra scritto nel posto sbagliato invece di una stringa
// troppo lunga. 25 + 7 = 32: entra esatta.
static const char txt_pack[]    = "IN PACK";
#define COL_PACK  25
static const char txt_stay[]    = "A NIGHT'S REST COSTS";
static const char txt_cure[]    = "TREATMENT COSTS";
static const char txt_what[]    = "WHAT WILL IT BE?";
static const char txt_who[]     = "GIVE IT TO WHO?";
static const char txt_stayq[]   = "STAY THE NIGHT?";
static const char txt_whodead[] = "WHO NEEDS TO COME BACK?";
static const char txt_nodead[]  = "YOU DON'T NEED MY HELP";
static const char txt_alive[]   = "THAT ONE IS ALIVE AND WELL";
static const char txt_thanks[]  = "THANK YOU!";
static const char txt_stowed[]  = "IN THE PACK: NO ROOM TO WEAR";
static const char txt_noroom[]  = "NO ROOM FOR IT";
static const char txt_poor[]    = "YOU CAN'T AFFORD IT";
static const char txt_morning[] = "GOOD MORNING!";
static const char txt_revive[]  = "RETURN TO LIFE!";
static const char txt_dead[]    = "DEAD";
static const char txt_no[]      = "NO";
static const char txt_learn[]   = "WHO WILL LEARN IT?";
static const char txt_nolearn[] = "THAT ONE CAN'T LEARN IT";
static const char txt_known[]   = "THAT ONE KNOWS IT ALREADY";
static const char txt_full[]    = "THAT SPELL LEVEL IS FULL";
static const char txt_learned[] = "THE SPELL IS LEARNED!";
static const char txt_kn[]      = "KNOWN";
static const char txt_fl[]      = "FULL";
static const char txt_hint_buy[]  = "FIRE1 BUY    FIRE2 LEAVE";
static const char txt_hint_who[]  = "FIRE1 OK     FIRE2 BACK";
static const char txt_hint_yes[]  = "FIRE1 YES    FIRE2 NO";
static const char txt_hint_out[]  = "FIRE2: LEAVE";

// n-esima stringa del gruppo che comincia a `p`.
static const char *str_at(const char *p, int n) {
    while (n > 0) {
        while (*p) p++;
        p++;
        n--;
    }
    return p;
}

static void render_string(unsigned char col, unsigned char row, const char *s) {
    unsigned char buf[32];
    int n = 0;
    while (s[n] && n < 32) { buf[n] = (unsigned char)s[n]; n++; }
    if (n) svc_vwrite(buf, 0x1800 + (unsigned int)row * 32 + col, (unsigned int)n);
}

static void render_tile(unsigned char col, unsigned char row, unsigned char t) {
    svc_vwrite(&t, 0x1800 + (unsigned int)row * 32 + col, 1);
}

static void clear_row(unsigned char row) {
    svc_vfill(0x1800 + (unsigned int)row * 32, 0x20, 32);
}

// Un numero senza zeri iniziali, allineato a DESTRA di `col`. A destra perche'
// in una colonna di prezzi le unita' devono incolonnarsi: 5 e 100 allineati a
// sinistra si leggono peggio di quanto sembri.
static void render_num_right(unsigned char col, unsigned char row, unsigned int v) {
    unsigned char buf[6];
    int n = 0;
    if (v == 0) { buf[0] = '0'; n = 1; }
    while (v > 0 && n < 6) { buf[n] = (unsigned char)('0' + (v % 10)); v /= 10; n++; }
    {
        int k;
        for (k = 0; k < n; k++) {
            svc_vwrite(&buf[k], 0x1800 + (unsigned int)row * 32 + col - k, 1);
        }
    }
}

// =====================================================================
//  L'oro del gruppo: 3 byte, come `gold` sul NES
// =====================================================================
// FF1 arriva a 999999 GP e il tetto e' proprio quello del formato. Qui se ne
// stampano i 16 bit bassi piu' niente: sopra i 65535 servirebbe una divisione
// a 24 bit, e a Coneria non capita. Il CONFRONTO e la SOTTRAZIONE invece sono
// a 24 bit veri, perche' quelli devono restare giusti anche a fine gioco.
static unsigned int party_gold_low(void) {
    return (unsigned int)PARTY.gp[0] | ((unsigned int)PARTY.gp[1] << 8);
}

static unsigned char gold_ge(unsigned int price) {
    // Sopra i 65535 GP qualunque prezzo e' alla portata: e' la stessa
    // scorciatoia di Shop_CanAfford (bank_0E.asm:4255), che sul byte alto fa
    // un BNE e basta.
    if (PARTY.gp[2] != 0) return 1;
    return (unsigned char)(party_gold_low() >= price);
}

static void gold_pay(unsigned int price) {
    unsigned int lo = party_gold_low();
    if (lo < price) PARTY.gp[2]--;      // prestito dal byte alto
    lo = (unsigned int)(lo - price);
    PARTY.gp[0] = (unsigned char)lo;
    PARTY.gp[1] = (unsigned char)(lo >> 8);
}

// =====================================================================
//  Schermo
// =====================================================================

static void load_shop_screen(void) {
    svc_border(INK_DARK_BLUE);
    svc_vfill(0x0000, 0, 6144);
    svc_vwrite(BIOS_FONT_ADDR, 0x0000 + (FONT_TILE_BASE * 8), BIOS_FONT_LEN);
    svc_vwrite(BIOS_FONT_ADDR, 0x0800 + (FONT_TILE_BASE * 8), BIOS_FONT_LEN);
    svc_vwrite(BIOS_FONT_ADDR, 0x1000 + (FONT_TILE_BASE * 8), BIOS_FONT_LEN);
    // Le icone DOPO il font: entrambe scrivono nella stessa tabella di
    // pattern, e caricare il font per ultimo cancellerebbe le tile $10-$1B se
    // un giorno il blocco del font si allargasse all'indietro.
    svc_shop_load_icons(ICON_TILE_BASE);
    svc_vfill(0x2000, 0xF4, 6144);   // bianco su blu scuro ovunque
    svc_vfill(0x1800, 0x20, 768);    // nametable vuota
    // TUTTI E QUATTRO gli sprite del mapman, non solo il primo. In citta' il
    // personaggio e' fatto di quattro strati sovrapposti (SAT 0-3, vedi
    // [[mapman-4layer]]): spegnendo solo lo 0 restavano tre quarti di eroe in
    // mezzo al listino -- e a occhio sembrava UNO sprite dimenticato, non tre.
    {
        unsigned char i;
        for (i = 0; i < 4; i++) svc_put_sprite16(i, 0, 200, 0, 0);
    }
}

static void draw_gold(void) {
    clear_row(ROW_GOLD);
    render_string(1, ROW_GOLD, txt_gold);
    render_num_right(12, ROW_GOLD, party_gold_low());
    render_string(14, ROW_GOLD, txt_gp);
}

static void draw_prompt(const char *s) {
    clear_row(ROW_PROMPT);
    if (s) render_string(1, ROW_PROMPT, s);
}

static void draw_msg(const char *s) {
    clear_row(ROW_MSG);
    if (s) render_string(1, ROW_MSG, s);
}

static void draw_hint(const char *s) {
    clear_row(ROW_HINT);
    render_string(1, ROW_HINT, s);
}

static void draw_listing(void) {
    unsigned char k, row, ic;

    for (k = 0; k < SHOP.count; k++) {
        row = (unsigned char)(ROW_ITEM0 + k * 2);
        // Il numero della voce: col tastierino si salta dritti alla merce, che
        // e' il vantaggio del Coleco sul NES (memory/design_input.md).
        render_tile(1, row, (unsigned char)('1' + k));
        render_string(3, row, &SHOP.name[(unsigned int)k * SHOP_NAME_LEN]);
        // L'ICONA DI TIPO, che e' il motivo per cui questa schermata puo'
        // esistere: senza, l'armeria di Coneria mostra "Wooden" due volte
        // e le armature sarebbero cinque "Opal" indistinguibili.
        ic = SHOP.icon[k];
        if (FF1_ICON_VALID(ic)) {
            render_tile(11, row, (unsigned char)(ICON_TILE_BASE + FF1_ICON_INDEX(ic)));
        }
        render_num_right(20, row, SHOP.price[k]);
        render_string(22, row, txt_gp);
    }
}

// Il cursore, su una delle due colonne di scelta. Si ridisegna solo quando
// qualcosa cambia: e' una scrittura in VRAM, e farla a ogni frame per
// riscrivere gli stessi byte e' lavoro dentro il tempo di quadro.
// NON scrivere `ch = (on && i == sel) ? '>' : ' ';` -- MISURATO, sccz80 lo
// compila SBAGLIATO. Mette 0 o 1 in HL e poi decide con `jp nc`, cioe' guarda
// il CARRY lasciato dall'ultimo confronto invece del valore appena calcolato:
//
//      cp   (hl)        ; i contro sel
//      jp   nz,i_59
//      ld   hl,1        ; "vero"
//   i_60:
//      jp   nc,i_61     ; <-- il carry viene dal cp, non da HL
//
// Con un `==` fra byte l'ultimo confronto e' un `cp`, e li' il carry vuol dire
// MINORE, non UGUALE: il risultato e' che il cursore compare su tutte le righe
// PRIMA di quella scelta e mai su quella giusta. A schermo sembra un problema
// di cancellazione ("i cursori vecchi restano"), e si perde tempo a cercarlo
// nel disegno.
// La stessa forma con `(key && key != prev_key) ? key : 0` -- che sta in mezza
// dozzina di file di questo progetto -- funziona per CASO: li' l'ultimo
// termine e' un `!=` a 16 bit, che sccz80 risolve con una routine di libreria
// che il carry lo imposta col risultato giusto.
// Regola pratica: dentro un `?:` niente `&&`/`||`. Con due `if` si compila
// giusto e si legge uguale.
static void draw_cursor(unsigned char row0, unsigned char step,
                        unsigned char n, unsigned char sel, unsigned char on) {
    unsigned char i, ch;
    for (i = 0; i < n; i++) {
        ch = ' ';
        if (on) {
            if (i == sel) ch = '>';
        }
        render_tile(0, (unsigned char)(row0 + i * step), ch);
    }
}

// =====================================================================
//  Magia: i tre conti che servono sia a disegnare sia a comprare
// =====================================================================
// Sono scritti una volta e usati due, ed e' voluto: il negozio mostra PRIMA
// dell'acquisto lo stesso giudizio che poi applica: se le due strade fossero
// due copie del conto, un giorno direbbero cose diverse e a schermo sembrerebbe
// che il negozio mente.
//
// Da id-oggetto ($B0-$EF) a id di magia (0-63). Il livello sono i tre bit
// alti, la casella dentro il livello i tre bassi: e' la stessa divisione che
// fa MagicShop_AssertLearn con `LSR LSR LSR` e `AND #$07`.
#define SPELL_MID(id)    ((unsigned char)((id) - FF1_ITEM_SPELL_BASE))
#define SPELL_LEVEL(mid) ((unsigned char)((mid) >> 3))
// Il valore scritto in `ch_spells`: la casella 0-7, PIU' UNO, perche' zero
// vuol dire "posto vuoto". Fuori battaglia il NES tiene proprio questo
// (variables.inc:407); in battaglia ci somma livello*8 per farne l'id vero.
#define SPELL_VALUE(mid) ((unsigned char)(((mid) & 7) + 1))
// Il bit nella tabella dei permessi: `lut_BIT`, cioe' $80 spostato a destra
// della casella. Bit ACCESO = NON puo'.
#define SPELL_BIT(mid)   ((unsigned char)(0x80 >> ((mid) & 7)))

// Scritta con un `if` e non con un `?:` per la ragione spiegata sopra
// draw_cursor: sccz80 dentro un `?:` decide col carry dell'ultimo confronto, e
// qui l'ultima operazione e' un AND. Un permesso letto al contrario non
// sembrerebbe un difetto -- sembrerebbe un negozio che non vende a nessuno.
static unsigned char spell_can_learn(chr_t *c, unsigned char mid) {
    unsigned char lvl = SPELL_LEVEL(mid);
    if (SHOP.magperm[(unsigned int)(c->cls << 3) + lvl] & SPELL_BIT(mid)) return 0;
    return 1;
}

// Quante ne sa a quel livello, e se sa gia' proprio quella. Un giro solo:
// sono le due domande che si fanno sempre insieme.
static unsigned char spell_count_at(chr_t *c, unsigned char lvl,
                                    unsigned char want, unsigned char *knows) {
    unsigned char *p = &c->spells[(unsigned int)lvl * PARTY_SPELLS_PER_LEVEL];
    unsigned char i, n = 0;
    *knows = 0;
    for (i = 0; i < PARTY_SPELLS_PER_LEVEL; i++) {
        if (p[i] == 0) continue;
        n++;
        if (p[i] == want) *knows = 1;
    }
    return n;
}

// I quattro personaggi. `mode` 0 = negozio d'equipaggiamento (danno,
// assorbimento e il divieto di classe per la voce puntata), 1 = locanda o
// clinica (HP e chi e' caduto), 2 = negozio di magia (livello, quante ne sa
// gia' su tre, e il motivo per cui non potrebbe impararla).
static void draw_party(unsigned char mode, unsigned char sel_item) {
    unsigned char i, row;
    for (i = 0; i < PARTY.n; i++) {
        chr_t *c = &PARTY.chr[i];   /* il puntatore una volta sola */
        row = (unsigned char)(ROW_CHR0 + i);
        clear_row(row);
        render_tile(1, row, (unsigned char)('1' + i));
        render_string(3, row, c->name);
        if (mode == 2) {
            // Il TRE e' il numero di posti, non il numero di magie del
            // livello: quelle sono otto, e sceglierne tre e' il gioco.
            unsigned char mid = SPELL_MID(SHOP.item[sel_item]);
            unsigned char lvl = SPELL_LEVEL(mid);
            unsigned char knows, n;
            n = spell_count_at(c, lvl, SPELL_VALUE(mid), &knows);
            render_tile(11, row, 'L');
            render_tile(12, row, (unsigned char)('1' + lvl));
            render_tile(14, row, (unsigned char)('0' + n));
            render_tile(15, row, '/');
            render_tile(16, row, (unsigned char)('0' + PARTY_SPELLS_PER_LEVEL));
            // I tre rifiuti, nello stesso ordine in cui li prova l'acquisto:
            // il permesso viene prima di tutto, e "la sa gia'" prima di "non
            // c'e' posto" -- altrimenti a livello pieno il negozio direbbe
            // FULL anche a chi quella magia ce l'ha gia'.
            if (!spell_can_learn(c, mid))                    render_string(18, row, txt_no);
            else if (knows)                                  render_string(18, row, txt_kn);
            else if (n >= PARTY_SPELLS_PER_LEVEL)            render_string(18, row, txt_fl);
        } else if (mode == 0) {
            render_tile(11, row, 'D');
            render_num_right(15, row, c->dmg);
            render_tile(17, row, 'A');
            render_num_right(21, row, c->absorb);
            // Il divieto di classe, mostrato PRIMA dell'acquisto: sul NES si
            // scopre solo dal menu, e la spada comprata al mago resta li' a
            // non servire a niente. Il bit ACCESO vieta.
            if (SHOP.count && !CAN_EQUIP(SHOP.perm[sel_item], c->cls)) {
                render_string(24, row, txt_no);
            }
        } else {
            render_tile(11, row, 'H');
            render_tile(12, row, 'P');
            render_num_right(17, row, c->curhp);
            render_tile(18, row, '/');
            render_num_right(21, row, c->maxhp);
            if ((c->ailments & 0x03) == 1) render_string(23, row, txt_dead);
        }
    }
}

// =====================================================================
//  Ingresso: i fronti di pressione
// =====================================================================
// Entrando si tiene ancora premuta la direzione che ha calpestato la porta, e
// senza il fronte il negozio si chiuderebbe da solo prima di essere visto.
// `prev_bits` parte a $FF apposta: tutto cio' che e' gia' premuto conta come
// tenuto, e vale solo dal rilascio in poi.
static unsigned char prev_bits;
static unsigned char prev_key;

static unsigned int read_edge(void) {
    unsigned int j;
    unsigned char bits, key, ebits, ekey;
    svc_wait_vblank();
    j    = svc_joystick();
    bits = (unsigned char)(j & 0x00FF);
    key  = (unsigned char)(j >> 8);
    ebits = (unsigned char)(bits & ~prev_bits);
    // Scritto con due `if` e non con un `?:` per la ragione spiegata sopra
    // draw_cursor: la forma `(key && key != prev_key) ? key : 0` che sta negli
    // altri overlay funziona, ma per caso -- e appoggiarsi a un caso fortunato
    // due volte nello stesso file e' come dichiarare che si e' capito.
    ekey = 0;
    if (key != 0) {
        if (key != prev_key) ekey = key;
    }
    prev_bits = bits;
    prev_key  = key;
    return (unsigned int)ebits | ((unsigned int)ekey << 8);
}

// =====================================================================
//  L'acquisto
// =====================================================================
// Il tipo di armatura, cioe' il posto che occupa addosso. Sul NES e'
// `lut_ArmorTypes` (bank_0E.asm:9212), 40 byte; ma quella tabella e' fatta di
// quattro tratti contigui -- 16 corazze, 9 scudi, 7 elmi, 8 guanti -- e i
// quattro confini bastano. Una tabella nell'overlay sarebbe rodata in piu' per
// dire la stessa cosa.
static unsigned char armor_kind(unsigned char idx) {
    if (idx < 16) return 0;
    if (idx < 25) return 1;
    if (idx < 32) return 2;
    return 3;
}

static unsigned char do_buy(unsigned char who, unsigned char k) {
    chr_t *c = &PARTY.chr[who];
    unsigned char id = SHOP.item[k];
    unsigned char *slots;
    unsigned char idx, i, v, free_slot, is_armor, wear;

    is_armor = (unsigned char)(FF1_ITEM_IS_ARMOR(id) ? 1 : 0);
    if (is_armor) {
        slots = c->armor;
        idx   = (unsigned char)(id - FF1_ITEM_ARMOR_BASE);
    } else {
        slots = c->weapon;
        idx   = (unsigned char)(id - FF1_ITEM_WEAPON_BASE);
    }

    // Prima il posto nello zaino, poi l'oro: e' l'ordine del NES
    // (EquipShop_GiveItemToChar viene DOPO Shop_CanAfford, ma paga solo se
    // l'oggetto e' entrato -- qui l'oro si tocca solo a cose fatte).
    free_slot = 0xFF;
    for (i = 0; i < PARTY_EQUIP_SLOTS; i++) {
        if (slots[i] == 0) { free_slot = i; break; }
    }
    if (free_slot == 0xFF) return BUY_NOROOM;
    if (!gold_ge(SHOP.price[k])) return BUY_NOGOLD;
    gold_pay(SHOP.price[k]);

    // Si indossa se la classe puo' E se il posto e' libero. Le stesse due
    // condizioni di IsEquipLegal, meno il "togli l'altro": togliere qualcosa
    // che il giocatore ha scelto di indossare non e' compito di un acquisto.
    wear = (unsigned char)(CAN_EQUIP(SHOP.perm[k], c->cls) ? 1 : 0);
    if (wear) {
        for (i = 0; i < PARTY_EQUIP_SLOTS; i++) {
            v = slots[i];
            if (!(v & EQUIP_EQUIPPED)) continue;
            // Un'arma sola addosso; le armature una per tipo. Il valore di
            // casella e' 1-based, quindi -1 per tornare all'indice.
            if (is_armor &&
                armor_kind((unsigned char)((v & 0x7F) - 1)) != armor_kind(idx)) continue;
            wear = 0;
            break;
        }
    }

    slots[free_slot] = (unsigned char)((idx + 1) | (wear ? EQUIP_EQUIPPED : 0));
    // L'unico servizio che serve dopo aver scritto una casella: le
    // sotto-statistiche si ricompongono DA ZERO dalle basi (slice65), quindi
    // chiamarla due volte di fila non somma niente due volte.
    svc_equip_recalc(who);
    return (unsigned char)(wear ? BUY_WORN : BUY_STOWED);
}

// =====================================================================
//  I tre negozi che funzionano
// =====================================================================

static void run_equip_shop(void) {
    unsigned char sel, who, picking;
    unsigned int e;
    unsigned char bits, key;

    sel = 0; who = 0; picking = 0;

    draw_listing();
    draw_gold();
    draw_party(0, sel);
    draw_prompt(txt_what);
    draw_hint(txt_hint_buy);
    draw_cursor(ROW_ITEM0, 2, SHOP.count, sel, 1);

    while (1) {
        e    = read_edge();
        bits = (unsigned char)(e & 0x00FF);
        key  = (unsigned char)(e >> 8);

        if (!picking) {
            if (bits & MOVE_FIRE2) return;
            if (bits & (MOVE_UP | MOVE_DOWN)) {
                sel = (unsigned char)((bits & MOVE_UP)
                        ? (sel ? sel - 1 : SHOP.count - 1)
                        : ((sel + 1 >= SHOP.count) ? 0 : sel + 1));
            } else if (key >= '1' && key < (unsigned char)('1' + SHOP.count)) {
                sel = (unsigned char)(key - '1');
            } else if (bits & MOVE_FIRE1) {
                // L'oro si prova PRIMA di chiedere a chi darla, come sul NES:
                // chiedere e poi rifiutare farebbe sembrare colpa della scelta.
                if (!gold_ge(SHOP.price[sel])) {
                    draw_msg(txt_poor);
                } else {
                    picking = 1;
                    draw_prompt(txt_who);
                    draw_hint(txt_hint_who);
                    draw_msg(0);
                    draw_cursor(ROW_ITEM0, 2, SHOP.count, sel, 0);
                    draw_cursor(ROW_CHR0, 1, PARTY.n, who, 1);
                    continue;
                }
            } else {
                continue;
            }
            draw_cursor(ROW_ITEM0, 2, SHOP.count, sel, 1);
            draw_party(0, sel);   // il divieto e' della VOCE puntata: si rifa'
            continue;
        }

        // --- scelta del personaggio ---
        if (bits & MOVE_FIRE2) {
            picking = 0;
            draw_prompt(txt_what);
            draw_hint(txt_hint_buy);
            draw_cursor(ROW_CHR0, 1, PARTY.n, who, 0);
            draw_cursor(ROW_ITEM0, 2, SHOP.count, sel, 1);
            continue;
        }
        if (bits & (MOVE_UP | MOVE_DOWN)) {
            who = (unsigned char)((bits & MOVE_UP)
                    ? (who ? who - 1 : PARTY.n - 1)
                    : ((who + 1 >= PARTY.n) ? 0 : who + 1));
            draw_cursor(ROW_CHR0, 1, PARTY.n, who, 1);
        } else if (key >= '1' && key < (unsigned char)('1' + PARTY.n)) {
            who = (unsigned char)(key - '1');
            draw_cursor(ROW_CHR0, 1, PARTY.n, who, 1);
        } else if (bits & MOVE_FIRE1) {
            unsigned char r = do_buy(who, sel);
            if      (r == BUY_WORN)   draw_msg(txt_thanks);
            else if (r == BUY_STOWED) draw_msg(txt_stowed);
            else if (r == BUY_NOROOM) draw_msg(txt_noroom);
            else                      draw_msg(txt_poor);
            draw_gold();
            draw_party(0, sel);
            picking = 0;
            draw_prompt(txt_what);
            draw_hint(txt_hint_buy);
            draw_cursor(ROW_CHR0, 1, PARTY.n, who, 0);
            draw_cursor(ROW_ITEM0, 2, SHOP.count, sel, 1);
        }
    }
}

// Le tre condizioni di MagicShop_AssertLearn (bank_0E.asm:5705), nello stesso
// ordine, piu' l'oro. L'ORDINE NON E' ARBITRARIO: sul NES i tre rifiuti
// scartano la chiamata prima ancora di mostrare il prezzo, e l'oro si prova
// per ultimo. Rovesciarlo vorrebbe dire far pagare una magia che il
// personaggio non poteva imparare.
static unsigned char do_learn(unsigned char who, unsigned char k) {
    chr_t *c = &PARTY.chr[who];
    unsigned char mid = SPELL_MID(SHOP.item[k]);
    unsigned char lvl = SPELL_LEVEL(mid);
    unsigned char val = SPELL_VALUE(mid);
    unsigned char *p  = &c->spells[(unsigned int)lvl * PARTY_SPELLS_PER_LEVEL];
    unsigned char i, knows, n, free_slot;

    if (!spell_can_learn(c, mid)) return LEARN_NOPERM;
    n = spell_count_at(c, lvl, val, &knows);
    if (knows) return LEARN_KNOWN;
    if (n >= PARTY_SPELLS_PER_LEVEL) return LEARN_FULL;
    if (!gold_ge(SHOP.price[k])) return LEARN_NOGOLD;

    free_slot = 0xFF;
    for (i = 0; i < PARTY_SPELLS_PER_LEVEL; i++) {
        if (p[i] == 0) { free_slot = i; break; }
    }
    // Non puo' capitare -- il conto qui sopra dice che un posto c'e'. Se
    // capitasse, meglio non pagare che scrivere fuori casella.
    if (free_slot == 0xFF) return LEARN_FULL;

    gold_pay(SHOP.price[k]);
    p[free_slot] = val;
    // Nessun `svc_equip_recalc` qui: le magie non entrano nelle
    // sotto-statistiche. E' l'unica differenza vera fra questo acquisto e
    // quello dell'equipaggiamento.
    return LEARN_OK;
}

// I due negozi di magia. La forma e' quella di run_equip_shop e non e' copia
// per pigrizia: la scelta a due tempi -- prima la merce, poi il personaggio --
// e' quella del NES e vale per tutti e tre i negozi che vendono qualcosa a
// qualcuno. Quello che cambia e' cio' che si legge sulle righe del gruppo e
// quali sono i rifiuti possibili.
static void run_magic_shop(void) {
    unsigned char sel, who, picking;
    unsigned int e;
    unsigned char bits, key;

    sel = 0; who = 0; picking = 0;

    // I permessi arrivano QUI e non col listino: stanno nel banco 11 insieme
    // ai dati degli incantesimi da cui sono estratti, non nel 16 dei negozi.
    // `svc_fetch_btl` e' il servizio che quel banco lo sa mappare -- lo usa la
    // battaglia per le statistiche dei nemici -- e da slice67 torna a
    // `main_bank`, cioe' anche a questo overlay.
    svc_fetch_btl(3, 0, SHOP_MAGIC_PERM_BYTES, SHOP.magperm);

    draw_listing();
    draw_gold();
    draw_party(2, sel);
    draw_prompt(txt_what);
    draw_hint(txt_hint_buy);
    draw_cursor(ROW_ITEM0, 2, SHOP.count, sel, 1);

    while (1) {
        e    = read_edge();
        bits = (unsigned char)(e & 0x00FF);
        key  = (unsigned char)(e >> 8);

        if (!picking) {
            if (bits & MOVE_FIRE2) return;
            if (bits & (MOVE_UP | MOVE_DOWN)) {
                sel = (unsigned char)((bits & MOVE_UP)
                        ? (sel ? sel - 1 : SHOP.count - 1)
                        : ((sel + 1 >= SHOP.count) ? 0 : sel + 1));
            } else if (key >= '1' && key < (unsigned char)('1' + SHOP.count)) {
                sel = (unsigned char)(key - '1');
            } else if (bits & MOVE_FIRE1) {
                if (!gold_ge(SHOP.price[sel])) {
                    draw_msg(txt_poor);
                } else {
                    picking = 1;
                    draw_prompt(txt_learn);
                    draw_hint(txt_hint_who);
                    draw_msg(0);
                    draw_cursor(ROW_ITEM0, 2, SHOP.count, sel, 0);
                    draw_cursor(ROW_CHR0, 1, PARTY.n, who, 1);
                    continue;
                }
            } else {
                continue;
            }
            draw_cursor(ROW_ITEM0, 2, SHOP.count, sel, 1);
            // Le tre etichette sono della MAGIA puntata, non del personaggio:
            // cambiando voce cambia il livello, e con esso il "2/3".
            draw_party(2, sel);
            continue;
        }

        // --- scelta del personaggio ---
        if (bits & MOVE_FIRE2) {
            picking = 0;
            draw_prompt(txt_what);
            draw_hint(txt_hint_buy);
            draw_cursor(ROW_CHR0, 1, PARTY.n, who, 0);
            draw_cursor(ROW_ITEM0, 2, SHOP.count, sel, 1);
            continue;
        }
        if (bits & (MOVE_UP | MOVE_DOWN)) {
            who = (unsigned char)((bits & MOVE_UP)
                    ? (who ? who - 1 : PARTY.n - 1)
                    : ((who + 1 >= PARTY.n) ? 0 : who + 1));
            draw_cursor(ROW_CHR0, 1, PARTY.n, who, 1);
        } else if (key >= '1' && key < (unsigned char)('1' + PARTY.n)) {
            who = (unsigned char)(key - '1');
            draw_cursor(ROW_CHR0, 1, PARTY.n, who, 1);
        } else if (bits & MOVE_FIRE1) {
            unsigned char r = do_learn(who, sel);
            if      (r == LEARN_OK)     draw_msg(txt_learned);
            else if (r == LEARN_NOPERM) draw_msg(txt_nolearn);
            else if (r == LEARN_KNOWN)  draw_msg(txt_known);
            else if (r == LEARN_FULL)   draw_msg(txt_full);
            else                        draw_msg(txt_poor);
            draw_gold();
            draw_party(2, sel);
            picking = 0;
            draw_prompt(txt_what);
            draw_hint(txt_hint_buy);
            draw_cursor(ROW_CHR0, 1, PARTY.n, who, 0);
            draw_cursor(ROW_ITEM0, 2, SHOP.count, sel, 1);
        }
    }
}

static void run_inn(void) {
    unsigned int e;
    unsigned char bits, i;

    render_string(1, 5, txt_stay);
    render_num_right(9, 7, SHOP.service);
    render_string(11, 7, txt_gp);
    draw_gold();
    draw_party(1, 0);
    draw_prompt(txt_stayq);
    draw_hint(txt_hint_yes);

    while (1) {
        e    = read_edge();
        bits = (unsigned char)(e & 0x00FF);
        if (bits & MOVE_FIRE2) return;
        if (!(bits & MOVE_FIRE1)) continue;

        if (!gold_ge(SHOP.service)) { draw_msg(txt_poor); continue; }
        gold_pay(SHOP.service);
        // MenuFillPartyHP + MenuRecoverPartyMP (bank_0E.asm:5875/5908): chi e'
        // morto o pietrificato NON si rimette in sesto dormendo. Il NES qui
        // salverebbe anche la partita: noi non abbiamo ancora dove.
        for (i = 0; i < PARTY.n; i++) {
            chr_t *c = &PARTY.chr[i];
            unsigned char ail = (unsigned char)(c->ailments & 0x03);
            unsigned char k;
            if (ail == 1 || ail == 2) continue;
            c->curhp = c->maxhp;
            for (k = 0; k < PARTY_SPELL_LEVELS; k++) c->curmp[k] = c->maxmp[k];
        }
        draw_gold();
        draw_party(1, 0);
        draw_msg(txt_morning);
    }
}

static void run_clinic(void) {
    unsigned int e;
    unsigned char bits, key, who, i, any;

    who = 0;
    render_string(1, 5, txt_cure);
    render_num_right(9, 7, SHOP.service);
    render_string(11, 7, txt_gp);
    draw_gold();
    draw_party(1, 0);

    any = 0;
    for (i = 0; i < PARTY.n; i++) {
        if ((PARTY.chr[i].ailments & 0x03) == 1) { any = 1; break; }
    }
    draw_prompt(any ? txt_whodead : txt_nodead);
    draw_hint(any ? txt_hint_who : txt_hint_out);
    if (any) draw_cursor(ROW_CHR0, 1, PARTY.n, who, 1);

    while (1) {
        e    = read_edge();
        bits = (unsigned char)(e & 0x00FF);
        key  = (unsigned char)(e >> 8);
        if (bits & MOVE_FIRE2) return;
        if (!any) continue;

        if (bits & (MOVE_UP | MOVE_DOWN)) {
            who = (unsigned char)((bits & MOVE_UP)
                    ? (who ? who - 1 : PARTY.n - 1)
                    : ((who + 1 >= PARTY.n) ? 0 : who + 1));
            draw_cursor(ROW_CHR0, 1, PARTY.n, who, 1);
        } else if (key >= '1' && key < (unsigned char)('1' + PARTY.n)) {
            who = (unsigned char)(key - '1');
            draw_cursor(ROW_CHR0, 1, PARTY.n, who, 1);
        } else if (bits & MOVE_FIRE1) {
            chr_t *c = &PARTY.chr[who];
            if ((c->ailments & 0x03) != 1) { draw_msg(txt_alive); continue; }
            if (!gold_ge(SHOP.service))    { draw_msg(txt_poor);  continue; }
            gold_pay(SHOP.service);
            // Un HP, non gli HP pieni: e' quello che fa il NES
            // (EnterShop_Clinic, bank_0E.asm:4409). Per rimettersi in sesto si
            // paga anche la locanda.
            c->ailments = 0;
            c->curhp    = 1;
            draw_gold();
            draw_party(1, 0);
            draw_msg(txt_revive);
            any = 0;
            for (i = 0; i < PARTY.n; i++) {
                if ((PARTY.chr[i].ailments & 0x03) == 1) { any = 1; break; }
            }
            if (!any) {
                draw_prompt(txt_nodead);
                draw_hint(txt_hint_out);
                draw_cursor(ROW_CHR0, 1, PARTY.n, who, 0);
            }
        }
    }
}

// =====================================================================
//  Il negozio di OGGETTI (slice71) -- e la carovana, che e' lo stesso
// =====================================================================
// Fino a slice70 diceva "BUYING: NOT YET", e non era pigrizia: senza un
// inventario, comprare avrebbe scritto in caselle che nessuno legge. Adesso
// `PARTY.item[]` esiste e l'acquisto e' tre righe -- il grosso del lavoro
// l'aveva gia' fatto `svc_shop_fetch`, che per i consumabili portava nome,
// prezzo e icona come per qualunque altra merce (i permessi valgono zero, che
// per una pozione e' la risposta giusta e non un caso mancante).
//
// PERCHE' LA CAROVANA VIENE QUI. Sul NES `EnterShop_Caravan` fa `BNE` sulla
// prima istruzione di `EnterShop_Item` e cade dentro: sono la stessa routine
// con una grafica diversa. La sua lista e' `[0F 00 E8 00 EC]`, e siccome le
// liste si fermano al primo zero vende una cosa sola -- la BOTTLE. I due
// incantesimi che si vedono nei byte successivi appartengono gia' al negozio
// dopo, e su NES non sono raggiungibili nemmeno li'.
//
// LA DIFESA SULL'ID non e' teorica. `PARTY.item[]` copre $00-$1B; il resto
// dello spazio degli id sono armi, armature, importi in oro e incantesimi. Sul
// NES `INC items,X` con X=$E8 scriverebbe dentro `ch_stats` -- cioe' negli HP
// di qualcuno -- e a non farlo succedere e' soltanto lo zero che chiude la
// lista della carovana. Qui la lista si legge allo stesso modo, ma un dato
// storto un giorno non deve poter corrompere il gruppo: l'id fuori intervallo
// si rifiuta e basta.
static void draw_item_qty(void) {
    unsigned char k, row, id, q;
    for (k = 0; k < SHOP.count; k++) {
        row = (unsigned char)(ROW_ITEM0 + k * 2);
        id  = SHOP.item[k];
        // Il campo si RIPULISCE prima: da 9 a 10 la cifra delle unita' resta
        // sotto quella nuova se si scrive solo allineati a destra.
        svc_vfill(0x1800 + (unsigned int)row * 32 + 26, 0x20, 4);
        if (id >= INV_COUNT) continue;
        q = PARTY.item[id];
        render_tile(26, row, 'x');
        // Anche lo zero, apposta: la colonna serve a far VEDERE l'acquisto, e
        // una casella vuota che diventa "1" si legge meglio di un "1" che
        // compare dal niente.
        render_num_right(29, row, q);
    }
}

static void run_item_shop(void) {
    unsigned int e;
    unsigned char bits, key, sel, id;

    sel = 0;
    draw_listing();
    draw_item_qty();
    draw_gold();
    render_string(COL_PACK, (unsigned char)(ROW_ITEM0 - 1), txt_pack);
    draw_prompt(txt_what);
    draw_hint(txt_hint_buy);
    draw_cursor(ROW_ITEM0, 2, SHOP.count, sel, 1);

    while (1) {
        e    = read_edge();
        bits = (unsigned char)(e & 0x00FF);
        key  = (unsigned char)(e >> 8);
        if (bits & MOVE_FIRE2) return;

        if (bits & (MOVE_UP | MOVE_DOWN)) {
            sel = (unsigned char)((bits & MOVE_UP)
                    ? (sel ? sel - 1 : SHOP.count - 1)
                    : ((sel + 1 >= SHOP.count) ? 0 : sel + 1));
            draw_cursor(ROW_ITEM0, 2, SHOP.count, sel, 1);
        } else if (key >= '1' && key < (unsigned char)('1' + SHOP.count)) {
            sel = (unsigned char)(key - '1');
            draw_cursor(ROW_ITEM0, 2, SHOP.count, sel, 1);
        } else if (bits & MOVE_FIRE1) {
            id = SHOP.item[sel];
            if (id >= INV_COUNT) { draw_msg(txt_soon); continue; }
            // L'ORO PRIMA DEL TETTO, come sul NES (ItemShop, bank_0E.asm:4199:
            // `Shop_CanAfford` e solo dopo `CMP #99`). I due rifiuti si
            // sovrappongono in un caso solo -- 99 in tasca e la borsa vuota --
            // e li' il negozio dice "non te la puoi permettere". Fedele.
            if (!gold_ge(SHOP.price[sel]))     { draw_msg(txt_poor);    continue; }
            if (PARTY.item[id] >= INV_MAX_QTY) { draw_msg(txt_toomany); continue; }
            gold_pay(SHOP.price[sel]);
            PARTY.item[id]++;
            draw_gold();
            draw_item_qty();
            draw_msg(txt_thanks);
        }
    }
}

// arg = shop_id. Torna 0: quello che il negozio cambia sta tutto in RAM SGM
// (oro, caselle, HP), e il chiamante lo rilegge da li'.
unsigned int overlay_main(unsigned int arg) {
    svc_shop_fetch((unsigned char)arg);
    load_shop_screen();

    prev_bits = 0xFF;   // NIENTE inizializzatori nella DATA di un overlay
    prev_key  = 0;

    render_string(1, ROW_TITLE, str_at(txt_types, (int)SHOP.type));

    if (SHOP.type == SHOPTYPE_INN)          run_inn();
    else if (SHOP.type == SHOPTYPE_CLINIC)  run_clinic();
    else if (SHOP.type == SHOPTYPE_WEAPON ||
             SHOP.type == SHOPTYPE_ARMOR)   run_equip_shop();
    else if (SHOP.type == SHOPTYPE_WMAGIC ||
             SHOP.type == SHOPTYPE_BMAGIC)  run_magic_shop();
    // Oggetti e carovana: la stessa routine, come sul NES. Resta l'`else` e
    // non un `== SHOPTYPE_ITEM`, cosi' un tipo che un giorno non conoscessimo
    // finisce in una schermata che si sa chiudere invece che in un ciclo muto.
    else                                    run_item_shop();
    return 0;
}
