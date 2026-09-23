// =====================================================================
//  ovl_intro.c -- le scene di apertura, overlay di CODICE (banco 21)
// =====================================================================
// SECONDO overlay del progetto, e la prova che `svc_run_overlay` di slice61
// e' davvero una primitiva e non il vecchio salto della battaglia con un
// nome nuovo: qui dentro entra codice che non c'entra niente con la
// battaglia, per una strada identica.
//
// COSA CI FA UNA SCENA DI APERTURA IN UN BANCO
// Legenda, menu di boot e selezione dei personaggi girano UNA VOLTA SOLA, al
// boot, e poi non servono mai piu' -- ma nella finestra fissa occupavano
// 2115 byte per sempre, sui 16KB totali, in un momento in cui ne restavano
// 66 liberi. E' il rapporto peggiore possibile fra quanto costa una cosa e
// quanto la si usa: e' per questo che sono le prime a uscire.
//
// -- le tre regole dell'overlay, e come sono rispettate qui --------------
//
// 1. NIENTE mc_select_bank: l'overlay E' il banco 21. Da qui non si vede
//    nessun altro banco. Ne discendono le due cose seguenti.
//
// 2. I TESTI VIVONO QUI. Prima stavano nel banco 1 accanto al Prelude
//    (intro_bank.c), perche' la scena girava col banco 1 mappato. Adesso il
//    banco mappato e' il 21, quindi i testi sono rodata di QUESTO file --
//    che e' anche piu' semplice: la scena e le sue parole nello stesso posto.
//
// 3. IL PRELUDE NON SI AVVIA DA QUI. `init_prelude_song` deve dereferenziare
//    puntatori che stanno nel banco 1, e da qui il banco 1 non esiste. Non
//    serve una svc_ nuova: la slice fa partire il Prelude PRIMA di entrare,
//    e la NMI dell'audio continua a suonarlo per tutto il tempo (mappa il
//    banco 1 a ogni tick e rimette il 21, che e' `main_bank`). Il risultato
//    a schermo e' quello di sempre: musica continua da legenda a selezione.
//
// -- la DATA di un overlay non esiste, e vale anche per gli scalari -------
// La DATA di un overlay non viene MAI inizializzata (non c'e' crt0_init):
// tutto cio' che il compilatore piazza li' dentro a runtime e' spazzatura.
// Ne discendono DUE divieti, e in slice62 sono costati un difetto ciascuno
// -- il secondo perche' la regola era scritta solo per il primo:
//
//  a) NIENTE TABELLE. sccz80 mette in DATA sia gli array di PUNTATORI (hanno
//     rilocazioni) sia i `static const` multidimensionali -- cioe' proprio le
//     due forme comode per una tabella di stringhe. Restano leciti i
//     `static const char[]` MONODIMENSIONALI, che finiscono in RODATA. Quindi
//     ogni gruppo di stringhe qui e' un solo array 1-D con i NUL dentro, e ci
//     si cammina con `str_at`.
//
//  b) NIENTE INIZIALIZZATORI, nemmeno su uno scalare. `static unsigned char
//     respond_rate = 1;` non vale 1 all'avvio: vale quello che c'era in RAM.
//     A schermo il menu si e' aperto su RESPOND RATE 0, e il difetto era
//     credibile come scelta di progetto -- il valore poi cambiava premendo,
//     quindi non sembrava rotto niente. I valori di partenza si assegnano a
//     runtime, in overlay_main.
//
// La forma (a) la intercetta la build: build_all.ps1 avvisa se la DATA di un
// overlay supera i 64 byte della libreria. La forma (b) NO -- un byte in piu'
// resta sotto la soglia. Quella va guardata a mano.
// =====================================================================

#define SVC_OVERLAY
#include "svc_api.h"
#include "party_state.h"
// slice72: la tabella delle statistiche iniziali viene QUI insieme al codice
// che la legge. E' un `static const unsigned char[]` monodimensionale, cioe'
// RODATA: la forma lecita in un overlay (vedi la nota (a) qui sopra).
#define FF1_CLASS_STATS_DEFINE_DATA
#include "data/class_stats.h"
// slice76: i flag di gioco nascono qui, insieme al gruppo. 208 byte di rodata
// in un banco che ne ha migliaia liberi.
#include "world_state.h"
#define FF1_INIT_FLAGS_DEFINE_DATA
#include "data/init_flags.h"

// Costanti di games.h: l'overlay non linka nulla della libreria.
#define MOVE_RIGHT 1
#define MOVE_LEFT  2
#define MOVE_DOWN  4
#define MOVE_UP    8
#define MOVE_FIRE1 16
#define MOVE_FIRE2 32

// tms99x8.h
#define INK_BLACK      0x01
#define INK_DARK_BLUE  0x04

// Il font del BIOS Coleco sta a $15A3, cioe' SOTTO $8000: non e' nella
// finestra commutabile e si legge da qui esattamente come dalla slice.
#define BIOS_FONT_ADDR  ((const void*)0x15A3)
#define BIOS_FONT_LEN   760
#define FONT_TILE_BASE  0x20

#define N_PARTY 4

// =====================================================================
//  I TESTI (rodata del banco 21)
// =====================================================================
// Un NUL separa le stringhe, un NUL in piu' chiude il gruppo.

// La leggenda e' testo del gioco: la genera tools/extract_intro_text.ps1 dal
// ROM (lut_IntroStoryText), con gli a capo del NES. Definisce txt_legend[] e
// LEGEND_LINES; sta qui, in mezzo agli altri testi, perche' e' qui che finiva
// nella rodata del banco 21.
#include "data/intro_text.h"

static const char txt_menu[] =
    "CONTINUE\0"
    "NEW GAME\0"
    "RESPOND RATE  \0";

static const char txt_copyright[] = "(C) 1987 SQUARE";
static const char txt_port[]      = "COLECO PORT 2026 BY S.V.";

static const char txt_class_names[] =
    "FIGHTER\0" "THIEF\0" "BLACK BELT\0"
    "RED MAGE\0" "WHITE MAGE\0" "BLACK MAGE\0";

static const char txt_default_names[] =
    "ARTHUR\0" "ELDAN \0" "MERLIN\0" "MORDRD\0";

static const char txt_classel_header[] = "SELECT YOUR PARTY";
static const char txt_classel_inst[] =
    "DPAD: CYCLE CLASS\0"
    "FIRE2: PREV CLASS\0"
    "FIRE1: NEXT CHR  1-4: JUMP\0"
    "PICK 4 CLASSES TO BEGIN\0";

// n-esima stringa del gruppo che comincia a `p`.
static const char *str_at(const char *p, int n) {
    while (n > 0) {
        while (*p) p++;
        p++;
        n--;
    }
    return p;
}

// =====================================================================
//  Disegno
// =====================================================================
static void render_string(unsigned char col, unsigned char row, const char *s) {
    unsigned char buf[32];
    int n = 0;
    while (s[n] && n < 32) { buf[n] = (unsigned char)s[n]; n++; }
    if (n) svc_vwrite(buf, 0x1800 + (unsigned int)row * 32 + col, (unsigned int)n);
}

static void render_char(unsigned char col, unsigned char row, char c) {
    unsigned char b = (unsigned char)c;
    svc_vwrite(&b, 0x1800 + (unsigned int)row * 32 + col, 1);
}

static void load_intro_font(void) {
    svc_border(INK_DARK_BLUE);
    svc_vfill(0x0000, 0, 6144);
    svc_vwrite(BIOS_FONT_ADDR, 0x0000 + (FONT_TILE_BASE * 8), BIOS_FONT_LEN);
    svc_vwrite(BIOS_FONT_ADDR, 0x0800 + (FONT_TILE_BASE * 8), BIOS_FONT_LEN);
    svc_vwrite(BIOS_FONT_ADDR, 0x1000 + (FONT_TILE_BASE * 8), BIOS_FONT_LEN);
    svc_vfill(0x2000, 0xF4, 6144);   // bianco su blu scuro ovunque
    svc_vfill(0x1800, 0x20, 768);    // nametable vuota
}

// Lampo di conferma (idioma di slice21): il bordo sbatte per 8 frame.
static void ack_flash(void) {
    int k;
    svc_border(INK_BLACK);
    for (k = 0; k < 8; k++) svc_wait_vblank();
    svc_border(INK_DARK_BLUE);
}

// Fronte di rilascio+pressione di FIRE1. La NMI dell'audio continua.
static void wait_fire1_edge(void) {
    int prev = (svc_joystick() & MOVE_FIRE1) ? 1 : 0;
    while (1) {
        svc_wait_vblank();
        {
            int now = (svc_joystick() & MOVE_FIRE1) ? 1 : 0;
            if (now && !prev) return;
            prev = now;
        }
    }
}

// =====================================================================
//  LEGENDA (slice42)
// =====================================================================
// FF1 sul NES non ha una schermata del titolo: si apre con questo testo,
// mentre il Prelude suona -- vedi memory/ff1_opening_flow.md. sng42 e' la
// musica del ponte, non dell'apertura.
static void run_legend(void) {
    int i, hold;

    load_intro_font();
    svc_put_sprite16(0, 0, 200, 0, 0 /* trasparente */);

    for (i = 0; i < LEGEND_LINES; i++) {
        const char *line = str_at(txt_legend, i);
        if (line[0]) render_string(1, (unsigned char)(4 + i), line);
        // ~mezzo secondo a riga; FIRE1 salta l'attesa della riga in corso.
        for (hold = 0; hold < 30; hold++) {
            svc_wait_vblank();
            if (svc_joystick() & MOVE_FIRE1) hold = 30;
        }
    }
    wait_fire1_edge();
}

// =====================================================================
//  MENU DI BOOT (slice43)
// =====================================================================
// CONTINUE / NEW GAME / RESPOND RATE N, come sul NES.
// CONTINUE e' inerte: non c'e' ancora un salvataggio, e sul NES con un
// salvataggio vuoto si comporta cosi'.
// RESPOND RATE cicla 1..8; il valore torna alla slice nel risultato, e
// governera' la velocita' delle finestre di dialogo quando ci saranno.
#define BMENU_OPT_CONTINUE      0
#define BMENU_OPT_NEW_GAME      1
#define BMENU_OPT_RESPOND_RATE  2
#define BMENU_N_OPTIONS         3
#define BMENU_COL_CURSOR        9
#define BMENU_COL_LABEL        11
#define BMENU_ROW_CONTINUE      6
#define BMENU_ROW_NEW_GAME      9
#define BMENU_ROW_RESPOND_RATE 13

// SENZA inizializzatore, e non e' una svista: vedi la nota sulla DATA in
// testa al file. Il valore di partenza lo mette overlay_main.
static unsigned char respond_rate;

static void bmenu_render_cursor(int sel) {
    render_char(BMENU_COL_CURSOR, BMENU_ROW_CONTINUE,     (sel == BMENU_OPT_CONTINUE)     ? '>' : ' ');
    render_char(BMENU_COL_CURSOR, BMENU_ROW_NEW_GAME,     (sel == BMENU_OPT_NEW_GAME)     ? '>' : ' ');
    render_char(BMENU_COL_CURSOR, BMENU_ROW_RESPOND_RATE, (sel == BMENU_OPT_RESPOND_RATE) ? '>' : ' ');
}

static void bmenu_render_rate(void) {
    render_char(BMENU_COL_LABEL + 14, BMENU_ROW_RESPOND_RATE, (char)('0' + respond_rate));
}

static void run_boot_menu(void) {
    int sel = BMENU_OPT_NEW_GAME;
    unsigned int j, prev_j;

    // Cancella la legenda. Il font e' gia' caricato, il Prelude non si ferma.
    svc_vfill(0x1800, 0x20, 768);

    render_string(BMENU_COL_LABEL, BMENU_ROW_CONTINUE,     str_at(txt_menu, 0));
    render_string(BMENU_COL_LABEL, BMENU_ROW_NEW_GAME,     str_at(txt_menu, 1));
    render_string(BMENU_COL_LABEL, BMENU_ROW_RESPOND_RATE, str_at(txt_menu, 2));
    bmenu_render_rate();
    render_string(8, 20, txt_copyright);
    render_string(4, 22, txt_port);
    bmenu_render_cursor(sel);

    prev_j = svc_joystick();
    while (1) {
        svc_wait_vblank();
        j = svc_joystick();

        if ((j & MOVE_UP) && !(prev_j & MOVE_UP)) {
            sel = (sel + BMENU_N_OPTIONS - 1) % BMENU_N_OPTIONS;
            bmenu_render_cursor(sel);
        }
        if ((j & MOVE_DOWN) && !(prev_j & MOVE_DOWN)) {
            sel = (sel + 1) % BMENU_N_OPTIONS;
            bmenu_render_cursor(sel);
        }
        if ((j & MOVE_FIRE1) && !(prev_j & MOVE_FIRE1)) {
            if (sel == BMENU_OPT_RESPOND_RATE) {
                respond_rate = (unsigned char)((respond_rate % 8) + 1);
                bmenu_render_rate();
            } else if (sel == BMENU_OPT_NEW_GAME) {
                ack_flash();
                return;
            }
            // CONTINUE: inerte finche' non c'e' un salvataggio.
        }
        prev_j = j;
    }
}

// =====================================================================
//  SELEZIONE DEI PERSONAGGI (slice43b)
// =====================================================================
// Griglia 2x2, cursore '>' a sinistra del personaggio attivo. D-pad cicla la
// classe in avanti, FIRE2 all'indietro, i tasti 1-4 del tastierino saltano
// direttamente, FIRE1 conferma e passa al successivo.
//
// Origine delle celle inline, niente tabella (vedi la nota sulla DATA):
//   CHR 0 col 2  riga 4    CHR 1 col 18 riga 4
//   CHR 2 col 2  riga 14   CHR 3 col 18 riga 14
// Dentro la cella: riga 0 = nome della classe, riga 2 = nome del personaggio.
#define CLASSEL_N_CLASSES 6

static unsigned char party_class_sel[4];
static int classel_active_pg;

static unsigned char classel_cell_row(int idx) { return (idx < 2) ? 4 : 14; }
static unsigned char classel_cell_col(int idx) { return (idx & 1) ? 18 : 2; }

static void classel_render_label_and_name(int idx) {
    unsigned char r0 = classel_cell_row(idx);
    unsigned char c0 = classel_cell_col(idx);
    unsigned char buf[12];
    int i;
    for (i = 0; i < 12; i++) buf[i] = ' ';
    svc_vwrite(buf, 0x1800 + (unsigned int)r0 * 32 + c0, 12);
    render_string((unsigned char)(c0 + 2), r0, str_at(txt_class_names, party_class_sel[idx]));
    render_string((unsigned char)(c0 + 2), (unsigned char)(r0 + 2), str_at(txt_default_names, idx));
}

static void classel_set_cursor(int idx, char ch) {
    render_char(classel_cell_col(idx), classel_cell_row(idx), ch);
}

static void classel_render_screen(void) {
    int i;
    svc_vfill(0x1800, 0x20, 768);
    render_string(7, 0, txt_classel_header);
    for (i = 0; i < N_PARTY; i++) {
        classel_render_label_and_name(i);
        classel_set_cursor(i, (i == classel_active_pg) ? '>' : ' ');
    }
    for (i = 0; i < 4; i++) {
        render_string(2, (unsigned char)(20 + i), str_at(txt_classel_inst, i));
    }
}

static void run_class_select(void) {
    unsigned int j, prev_j;
    unsigned char joy, key, prev_keypad, joy_edges, key_edges;
    int confirms = 0;

    classel_active_pg = 0;
    classel_render_screen();

    prev_j = svc_joystick();
    prev_keypad = (unsigned char)((prev_j >> 8) & 0xFF);

    while (1) {
        svc_wait_vblank();
        j = svc_joystick();
        joy = (unsigned char)(j & 0xFF);
        key = (unsigned char)((j >> 8) & 0xFF);
        joy_edges = joy & ~(unsigned char)(prev_j & 0xFF);
        key_edges = (key && key != prev_keypad) ? key : 0;

        if (joy_edges & (MOVE_UP | MOVE_DOWN | MOVE_LEFT | MOVE_RIGHT)) {
            party_class_sel[classel_active_pg] =
                (unsigned char)((party_class_sel[classel_active_pg] + 1) % CLASSEL_N_CLASSES);
            classel_render_label_and_name(classel_active_pg);
            classel_set_cursor(classel_active_pg, '>');
        }
        if (joy_edges & MOVE_FIRE2) {
            party_class_sel[classel_active_pg] =
                (unsigned char)((party_class_sel[classel_active_pg] + CLASSEL_N_CLASSES - 1) % CLASSEL_N_CLASSES);
            classel_render_label_and_name(classel_active_pg);
            classel_set_cursor(classel_active_pg, '>');
        }
        if (joy_edges & MOVE_FIRE1) {
            int prev = classel_active_pg;
            confirms++;
            if (confirms >= N_PARTY) {
                ack_flash();
                return;
            }
            classel_active_pg = (classel_active_pg + 1) % N_PARTY;
            classel_set_cursor(prev, ' ');
            classel_set_cursor(classel_active_pg, '>');
        }
        if (key_edges >= '1' && key_edges <= '4') {
            int target = key_edges - '1';
            if (target != classel_active_pg) {
                int prev = classel_active_pg;
                classel_active_pg = target;
                classel_set_cursor(prev, ' ');
                classel_set_cursor(classel_active_pg, '>');
            }
        }
        prev_j = j;
        prev_keypad = key;
    }
}

// =====================================================================
//  LA NASCITA DEL GRUPPO (slice72)
// =====================================================================
// Replica NewGame_LoadStartingStats (bank_0F.asm:1811) sul gruppo in RAM SGM.
//
// PERCHE' STA QUI E NON PIU' NELLA SLICE. Girava UNA VOLTA SOLA, subito dopo
// la selezione dei personaggi, e occupava **842 byte della finestra fissa per
// sempre**: lo stesso rapporto fra costo e uso che in slice62 aveva fatto
// uscire di la' le scene di apertura. E' la prima delle tre leve di
// [[fixed-window-full]], applicata al caso rimasto piu' vistoso.
//
// E il posto giusto e' proprio questo overlay, non uno nuovo: la selezione
// delle classi ce l'ha gia' in mano, i quattro nomi predefiniti sono gia'
// rodata qui accanto (txt_default_names, li usa la selezione per mostrarli), e
// cosi' i tre pezzi di "come nasce una partita" stanno insieme.
//
// LE DUE COSE CHE NON POTEVANO VENIRE, e come si e' fatto:
//   - `svc_equip_recalc` mappa il banco 16, che da qui non si vede. E' gia'
//     una svc_ e il suo banco di ritorno e' quello LETTO all'ingresso: dentro
//     l'overlay legge 21 e rimette 21. Niente da cambiare.
//   - `party_chr_size`, che il gioco pubblica per le sonde Lua, e' una
//     variabile della slice: da qui non si scrive. La assegna la slice, ed e'
//     una riga -- `sizeof(chr_t)` lo sa anche lei.
static void build_party(unsigned int classes12) {
    int i, k;

    PARTY.magic = PARTY_STATE_MAGIC;
    PARTY.n     = N_PARTY;
    // 400 GP, dal ROM: l'oro sta a unsram+$1C e la pagina iniziale di unsram
    // si copia da lut_InitUnsramFirstPage ($B000, banco $00), dove i tre byte
    // a +$1C sono 90 01 00. Con zero i sette negozi di Coneria sarebbero
    // inutilizzabili.
    PARTY.gp[0] = 0x90; PARTY.gp[1] = 0x01; PARTY.gp[2] = 0x00;

    // ZAINO VUOTO. In FF1 si parte senza niente. Non e' pignoleria: questa e'
    // RAM SGM, che all'accensione vale spazzatura, e una quantita' a caso non
    // sembrerebbe un difetto -- sembrerebbe un gioco che regala pozioni.
    for (k = 0; k < INV_COUNT; k++) PARTY.item[k] = 0;

    // I FLAG DI GIOCO (slice76), dalla stessa tabella del ROM. Stessa ragione
    // dello zaino, con una conseguenza in piu': i flag decidono CHI SI VEDE
    // sulle mappe, e con byte a caso una citta' si riempirebbe di abitanti che
    // non dovrebbero esserci -- o si svuoterebbe. La principessa salvata ($12)
    // comincia nascosta apposta, ed e' il bit che mezza Coneria guarda per
    // decidere quale delle due battute dire.
    WORLD.magic    = WORLD_STATE_MAGIC;
    WORLD.progress = 0;
    WORLD.count    = 0;
    for (k = 0; k < GAME_FLAG_COUNT; k++) WORLD.flags[k] = ff1_init_flags[k];

    for (i = 0; i < N_PARTY; i++) {
        unsigned char cls = (unsigned char)((classes12 >> (i * 3)) & 7);
        chr_t *c = &PARTY.chr[i];   /* il puntatore una volta sola */
        // Sul NES: ASL x4 -> *16. Stessa cosa, la voce e' CLS_STAT_RECSIZE.
        const unsigned char *s = lut_ClassStartingStats +
                                 (unsigned int)cls * CLS_STAT_RECSIZE;
        const char *nm = str_at(txt_default_names, i);

        c->cls      = cls;
        c->ailments = 0;
        for (k = 0; k < PARTY_NAME_LEN - 1; k++) c->name[k] = nm[k];
        c->name[PARTY_NAME_LEN - 1] = 0;
        for (k = 0; k < 3; k++) c->exp[k] = 0;
        c->level = 1;

        c->curhp    = s[CLS_STAT_HP];
        c->maxhp    = s[CLS_STAT_HP];
        c->str      = s[CLS_STAT_STR];
        c->agil     = s[CLS_STAT_AGL];
        c->int_stat = s[CLS_STAT_INT];
        c->vit      = s[CLS_STAT_VIT];
        c->luck     = s[CLS_STAT_LUCK];
        // Le BASE: quello che la tabella da' e che i livelli faranno crescere.
        // Gli EFFETTIVI li scrive svc_equip_recalc in fondo, e a nuova partita
        // coincidono -- il gruppo parte disarmato, come in FF1.
        c->dmg_b     = s[CLS_STAT_DMG];
        c->hitrate_b = s[CLS_STAT_HIT];
        c->evade_b   = s[CLS_STAT_EVADE];
        c->magdef    = s[CLS_STAT_MDEF];
        // absorb e resist non hanno una base: sul NES arrivano solo
        // dall'equipaggiamento, e a inizio partita nessuno indossa niente.

        // Caselle vuote. NON e' pignoleria: e' RAM SGM, e un bit 7 acceso per
        // caso verrebbe letto come "arma equipaggiata" con un indice a caso.
        for (k = 0; k < PARTY_EQUIP_SLOTS; k++) {
            c->weapon[k] = 0;
            c->armor[k]  = 0;
        }
        for (k = 0; k < PARTY_SPELL_LEVELS * PARTY_SPELLS_PER_LEVEL; k++) {
            c->spells[k] = 0;
        }
        for (k = 0; k < PARTY_SPELL_LEVELS; k++) {
            c->curmp[k] = 0;
            c->maxmp[k] = 0;
        }
        // "Award starting MP if the class ID is >= RM, but < KN": due cariche
        // di magia di PRIMO livello ai tre incantatori. Sul NES e' scritto in
        // codice, non nella tabella -- da qui il ramo esplicito.
        if (cls >= CLS_RM && cls < CLS_KN) {
            c->curmp[0] = 2;
            c->maxmp[0] = 2;
        }
    }

    // Gli EFFETTIVI si scrivono qui, non a mano: cosi' esiste UNA sola riga in
    // tutto il gioco che sa comporre le sotto-statistiche. Con le caselle
    // vuote copia le basi -- salvo il monaco, che a mani nude prende gia' qui
    // il suo danno da livello.
    for (i = 0; i < N_PARTY; i++) svc_equip_recalc((unsigned char)i);
}

// =====================================================================
//  INGRESSO
// =====================================================================
// Il risultato viaggia nel valore di ritorno, non in RAM condivisa: sono
// quattro id di classe (0-5) piu' il respond rate, e ci stanno tutti in 16
// bit. Una struct in RAM SGM per venti bit sarebbe stato un indirizzo in piu'
// da tenere allineato fra slice, overlay e sonde Lua.
//
//   bit 0-2   classe CHR 1        bit 3-5   classe CHR 2
//   bit 6-8   classe CHR 3        bit 9-11  classe CHR 4
//   bit 12-15 respond rate meno uno (1-8 -> 0-7)
//
// DUE INGRESSI IN UN OVERLAY SOLO (slice72). `arg` sceglie:
//   arg == 0            -> le scene di apertura, e torna il pacchetto
//   arg & $8000 acceso  -> costruisce il gruppo con le 12 classi nei bit
//                          bassi, e torna 0
// Il bit 15 e' libero in ENTRATA perche' il pacchetto e' un valore di USCITA:
// le due direzioni non si sovrappongono. Un secondo banco per una funzione
// che gira una volta e usa gli stessi dati sarebbe stato uno spreco, e una
// `svc_` in piu' avrebbe rimesso nella finestra fissa proprio i byte che
// questa slice ne toglie.
//
// PERCHE' DUE CHIAMATE E NON UNA SOLA CHE FA TUTTO. In mezzo la slice deve
// poter cambiare le classi: le build di prova (-DFORCE_SHOP e compagnia) le
// forzano, e `-Defines` vale solo per la compilazione della slice, non per
// quella degli overlay. Con una chiamata sola quelle build non esisterebbero
// piu' -- cioe' sei corse di validazione su sette.

// =====================================================================
//  I SEMI DELLE BUILD DI PROVA (slice78)
// =====================================================================
// Stavano nella finestra fissa, dentro party_new_game, ed erano l'unico
// codice di quella finestra che nella ROM VERA non esiste: nove build
// `-Defines` che si contendevano i byte piu' scarsi del progetto. A slice78
// FORCE_MAGMENU aveva smesso di starci (-109 byte) e il ponte non entrava.
//
// Qui costano ZERO alla finestra fissa e nulla alla ROM vera, che questi
// #ifdef non li vede mai. Ci possono stare solo da quando build_all.ps1 passa
// i `-Defines` anche agli overlay -- prima l'overlay non aveva modo di sapere
// che si stava compilando una build di prova, ed e' il motivo per cui i semi
// erano nati dall'altra parte.
//
// IL GRUPPO E' GIA' NATO quando questa gira (build_party sta appena sopra):
// i semi DEVONO venire dopo, o la nascita li azzererebbe. E' lo stesso ordine
// che avevano nella slice.
//
// LE CLASSI invece restano nella slice: sono quattro assegnazioni costanti,
// costano una manciata di byte, e arrivano qui gia' impacchettate
// nell'argomento -- spostarle vorrebbe dire un secondo formato.
static void seed_test_party(void)
{
    // `i` serve ai semi che scorrono il gruppo (FORCE_QUEST, FORCE_EQUIP).
    // Nella ROM vera questa funzione e' vuota e il compilatore la butta via.
    int i;
    (void)i;
#ifdef FORCE_BRIDGE
    // BUILD DI PROVA del PONTE (slice78). Il ponte lo accende il Re, in fondo
    // a una quest di sei tappe: rifarla per provare il ponte vorrebbe dire
    // che un difetto del ponte e un difetto della quest fanno fallire la
    // stessa corsa. La quest ha gia' la sua (mame_drive_quest.lua): qui il
    // bit si SEMINA e si parte dalla riva.
    //
    // NB: va dopo build_party, che azzera WORLD.progress.
    WORLD.progress |= WPROG_BRIDGE;
#endif

#ifdef FORCE_SPELLS
    // Le magie in tasca senza passare dal negozio. NON e' una scorciatoia che
    // salta una prova: il negozio ha la sua corsa (mame_drive_magicshop.lua,
    // 50 controlli), e farlo rifare a questa vorrebbe dire che un difetto del
    // LANCIO e un difetto dell'ACQUISTO fanno fallire lo stesso controllo.
    //
    // Il valore e' quello di `ch_spells`, cioe' QUALE DEGLI OTTO del livello,
    // e non l'id di magia: CURE e' 1, HARM 2, FIRE 5, LIT 8.
    PARTY.chr[2].spells[0] = 1;   /* CURE */
    PARTY.chr[2].spells[1] = 2;   /* HARM */
    PARTY.chr[3].spells[0] = 5;   /* FIRE */
    PARTY.chr[3].spells[1] = 8;   /* LIT  */
    // Nove cariche invece di due: la prova lancia piu' volte, e restare senza
    // a meta' corsa darebbe un "non ha lanciato" che somiglia a un difetto.
    PARTY.chr[2].curmp[0] = 9;  PARTY.chr[2].maxmp[0] = 9;
    PARTY.chr[3].curmp[0] = 9;  PARTY.chr[3].maxmp[0] = 9;
    // Il guerriero ferito, o la cura non avrebbe niente da riempire.
    PARTY.chr[0].curhp = 12;
#endif
#ifdef FORCE_AIL
    // Le due alterazioni SEMINATE, che non aspettano un nemico per esserci:
    //   il VELENO addosso al guerriero -- due HP a fine di ogni round, ed e'
    //     l'unico effetto delle alterazioni che si legge come un NUMERO;
    //   la CECITA' addosso al monaco -- che e' anche il bersaglio di LAMP, e
    //     quindi la stessa semina prova l'alterazione e la sua cura.
    PARTY.chr[0].ailments = AIL_POISON;
    PARTY.chr[1].ailments = AIL_DARK;
    // SLEP e' il SESTO degli otto del primo livello (CURE HARM FOG RUSE FIRE
    // SLEP LOCK LIT), LAMP il PRIMO del secondo.
    PARTY.chr[3].spells[0] = 6;   /* SLEP, livello 1 */
    PARTY.chr[2].spells[PARTY_SPELLS_PER_LEVEL] = 1;   /* LAMP, livello 2 */
    PARTY.chr[3].curmp[0] = 9;  PARTY.chr[3].maxmp[0] = 9;
    PARTY.chr[2].curmp[1] = 9;  PARTY.chr[2].maxmp[1] = 9;
#endif
#ifdef FORCE_BUFF
    // Il primo livello e' CURE HARM FOG RUSE FIRE SLEP LOCK LIT: FOG e' 3,
    // RUSE e' 4, LOCK e' 7. Scritti in chiaro apposta.
    PARTY.chr[2].spells[0] = 3;   /* FOG  */
    PARTY.chr[2].spells[1] = 4;   /* RUSE */
    PARTY.chr[3].spells[0] = 7;   /* LOCK */
    PARTY.chr[2].curmp[0] = 9;  PARTY.chr[2].maxmp[0] = 9;
    PARTY.chr[3].curmp[0] = 9;  PARTY.chr[3].maxmp[0] = 9;
#endif
#ifdef FORCE_ITEM
    // BUILD DI PROVA del negozio di OGGETTI (slice71, suffisso _t).
    //
    // Il negozio di Coneria vende HEAL (60), PURE (75) e TENT (75), e con i
    // 400 GP di partenza due dei tre rifiuti si esercitano da soli: comprando
    // pozioni finche' l'oro finisce si arriva a "non te la puoi permettere".
    // Il TERZO -- il tetto di 99 per tipo -- non si raggiungerebbe mai: a 75 GP
    // l'una servirebbero 7425 GP. Si SEMINA a 98, cosi' un solo acquisto lo
    // porta a 99 e il successivo dev'essere rifiutato.
    //
    // 98 e non 99 apposta: il controllo interessante non e' "rifiuta a 99", e'
    // che l'ULTIMO acquisto consentito passi. Partendo da 99 si proverebbe
    // solo il rifiuto, e un negozio rotto che rifiuta sempre supererebbe la
    // prova.
    PARTY.item[ITEM_PURE] = 98;
#endif
#ifdef FORCE_MENU
    // BUILD DI PROVA del MENU (slice73, suffisso _t). Semina tutto cio' che il
    // menu deve saper mostrare e curare, e che una partita nuova non ha:
    //   - lo zaino pieno di roba di tutti e tre i tipi (consumabili, oggetti
    //     chiave, sfere), perche' la lista a due colonne e il "non serve a
    //     niente" hanno bisogno di voci vere;
    //   - un ferito, un avvelenato e un pietrificato: sono i tre bersagli
    //     delle tre pozioni, e senza di loro l'uso finirebbe sempre nel ramo
    //     "non ne ha bisogno";
    //   - EXP a meta' strada, cosi' la riga NEXT mostra un numero calcolato e
    //     non la soglia intera.
    PARTY.item[ITEM_HEAL]  = 5;
    PARTY.item[ITEM_PURE]  = 3;
    PARTY.item[ITEM_SOFT]  = 2;
    PARTY.item[ITEM_TENT]  = 4;
    PARTY.item[ITEM_CABIN] = 1;
    PARTY.item[ITEM_HOUSE] = 1;
    PARTY.item[ITEM_LUTE]  = 1;
    PARTY.item[ITEM_CROWN] = 1;
    // La SFERA c'e' apposta e NON deve comparire in lista: il suo nome nel ROM
    // e' sette spazi, e la riga uscirebbe bianca. E' il caso che la prova deve
    // vedere respinto -- seminarla e' l'unico modo di provare che il salto
    // esiste davvero invece di essere una riga di codice mai eseguita.
    PARTY.item[ITEM_ORB_FIRST] = 1;
    PARTY.chr[0].curhp    = 5;                 /* il ferito: la pozione ha lavoro */
    PARTY.chr[1].ailments = AIL_POISON;        /* l'avvelenato: PURE */
    PARTY.chr[2].ailments = AIL_STONE;         /* il pietrificato: SOFT */
    PARTY.chr[2].curhp    = 0;                 /* e a zero HP: SOFT deve dargliene 1 */
    PARTY.chr[0].exp[0]   = 20;                /* meta' dei 40 che servono per L2 */
#endif
#ifdef FORCE_QUEST
    // Il gruppo POTENZIATO, dopo la nascita (che lo azzererebbe). Garland ha
    // 106 HP e assorbe 10: con danno 60 i quattro lo chiudono al primo round,
    // e la corsa non deve sopravvivere a quindici round di tiri casuali. Si
    // scrivono sia le BASI sia gli effettivi: nessun equip_recalc girera'
    // prima della battaglia, ma se un domani girasse, le basi lo reggono.
    // Il puntatore si prende UNA volta: scrivere `PARTY.chr[i].campo` a ogni
    // riga fa rifare la moltiplicazione per la dimensione della voce, e
    // sccz80 la moltiplicazione la chiama come routine. Misurato in questa
    // slice: 120 byte di finestra fissa per sei campi, che nella build di
    // prova erano proprio quelli che mancavano. Stessa nota di
    // svc_equip_recalc, e vale ovunque si tocchi piu' di un campo.
    for (i = 0; i < N_PARTY; i++) {
        chr_t *c = &PARTY.chr[i];
        c->curhp = c->maxhp = 300;
        c->dmg_b = c->dmg = 60;
        c->hitrate_b = c->hitrate = 99;
    }
#endif
#ifdef FORCE_SHOP
    // Gruppo malconcio, e serve: locanda e clinica non hanno niente da fare su
    // un gruppo intero. Un ferito, un caduto e nessuna carica di magia
    // esercitano in una corsa sola le tre regole -- la locanda rimette in
    // sesto HP e MP, il caduto lo SALTA (MenuFillPartyHP), e la clinica lo
    // rialza con UN HP.
    PARTY.chr[0].curhp    = 1;
    PARTY.chr[2].ailments = 1;   /* caduto */
    PARTY.chr[2].curhp    = 0;
    PARTY.chr[3].curmp[0] = 0;
#endif
#ifdef FORCE_MAGMENU
    // Le tredici magie in mano al mago bianco, piu' una da battaglia. Il valore
    // di `spells` e' QUALE DEGLI OTTO del livello (1-8), non l'id di tabella:
    // l'id vero e' `livello*8 + (valore-1)`. Gli otto di ogni livello, in
    // ordine, sono quelli di item_names.h da $B0 in poi.
    {
        chr_t *w = &PARTY.chr[2];        /* il mago bianco */
        unsigned char k;
        w->spells[0]  = 1;   /* L1 CURE */
        w->spells[1]  = 2;   /* L1 HARM -- da BATTAGLIA: serve il rifiuto */
        w->spells[6]  = 1;   /* L3 CUR2 */
        w->spells[7]  = 4;   /* L3 HEAL */
        w->spells[9]  = 1;   /* L4 PURE */
        w->spells[12] = 1;   /* L5 CUR3 */
        w->spells[13] = 2;   /* L5 LIFE */
        w->spells[14] = 4;   /* L5 HEL2 */
        w->spells[15] = 1;   /* L6 SOFT */
        w->spells[16] = 2;   /* L6 EXIT */
        w->spells[18] = 1;   /* L7 CUR4 */
        w->spells[19] = 4;   /* L7 HEL3 */
        w->spells[21] = 1;   /* L8 LIF2 */
        for (k = 0; k < PARTY_SPELL_LEVELS; k++) { w->curmp[k] = 9; w->maxmp[k] = 9; }
        // L8 A SECCO APPOSTA. Serve a provare l'ORDINE dei controlli: le
        // cariche si guardano PRIMA dell'effetto, quindi LIF2 su un vivo deve
        // dire "non hai cariche" e non "non ne ha bisogno". Con nove cariche
        // ovunque quel ramo non si eserciterebbe mai -- a 9 per livello non si
        // finiscono in una corsa.
        w->curmp[7] = 0;
    }
    // I tre bersagli, in tre condizioni diverse: nessuno di loro puo' essere
    // curato dalle stesse magie degli altri, quindi ogni prova ha un solo esito
    // giusto.
    PARTY.chr[0].curhp    = 5;                          /* ferito: CURE */
    PARTY.chr[1].ailments = (AIL_POISON | AIL_STONE);   /* PURE, poi SOFT */
    PARTY.chr[3].ailments = AIL_DEAD;                   /* LIFE */
    PARTY.chr[3].curhp    = 0;
#endif
#ifdef FORCE_EQMENU
    // Lo zaino di ferraglia che il menu deve saper maneggiare. Il valore di
    // casella e' l'indice 1-BASED nella tabella (arma o armatura), col bit 7
    // acceso se e' addosso -- vedi party_state.h.
    //
    // Ogni riga esercita UN caso, e insieme coprono tutte le regole:
    //   arma indossata          Rapier addosso al guerriero
    //   permesso NEGATO         nunchucks al guerriero (perm $0DE7: FT vietato)
    //   scambio d'arma          IronHammer: puo' portarlo, e scalza il Rapier
    //                           -- un'arma sola addosso, sempre
    //   armature dello STESSO tipo   IronArmor scalza Cloth (entrambe corpo)
    //   armature di tipo DIVERSO     WoodenShield convive con Cloth
    //   la stessa arma dai due lati  nunchucks al monaco: LUI puo'
    //   e Rapier al monaco: non puo' (perm $02CB: BB vietato)
    // Il coltello al mago nero serve al TRADE: e' l'unica cosa che ha, quindi
    // dopo lo scambio la sua casella dev'essere vuota o piena di cio' che ha
    // ricevuto, senza ambiguita'.
    PARTY.chr[0].weapon[0] = (unsigned char)(EQUIP_EQUIPPED | 4);   /* Rapier   */
    PARTY.chr[0].weapon[1] = 1;                                     /* WoodNunch*/
    PARTY.chr[0].weapon[2] = 5;                                     /* IronHammr*/
    PARTY.chr[0].armor[0]  = (unsigned char)(EQUIP_EQUIPPED | 1);   /* Cloth    */
    PARTY.chr[0].armor[1]  = 4;                                     /* IronArmor*/
    PARTY.chr[0].armor[2]  = 19;                                    /* WoodShield*/
    PARTY.chr[1].weapon[0] = 1;                                     /* WoodNunch*/
    PARTY.chr[1].weapon[1] = 4;                                     /* Rapier   */
    PARTY.chr[2].armor[0]  = (unsigned char)(EQUIP_EQUIPPED | 1);   /* Cloth    */
    PARTY.chr[3].weapon[0] = 2;                                     /* SmallKnife*/
    for (i = 0; i < N_PARTY; i++) svc_equip_recalc((unsigned char)i);
#endif
#ifdef FORCE_EQUIP
    // In FF1 il gruppo parte disarmato e si compra a Coneria: qui
    // l'equipaggiamento si scrive a mano, e il danno in battaglia diventa la
    // prova della formula.
    //
    // Rapier (id oggetto $1F -> indice 3 -> casella 4): +5 mira, +9 danno.
    // Cloth  (id oggetto $44 -> indice 0 -> casella 1): -2 evasione, +1 assorb.
    //
    // AL MONACO L'ARMATURA NON SI DA', apposta: cosi' una sola corsa esercita
    // ENTRAMBI i rami della sua regola speciale -- armato, il danno vale
    // forza/2 + 9; disarmato di armatura, l'assorbimento vale il livello.
    for (i = 0; i < N_PARTY; i++) {
        PARTY.chr[i].weapon[0] = (unsigned char)(EQUIP_EQUIPPED | 4);
        if (i != 1) PARTY.chr[i].armor[0] = (unsigned char)(EQUIP_EQUIPPED | 1);
    }
    // TRE VOLTE PIU' QUELLA DELLA NASCITA, ed e' la prova piu' importante di
    // quella slice: un ricalcolo di troppo non deve sommare niente. Se i bonus
    // finissero sopra il valore che gia' li contiene, ogni chiamata li
    // aggiungerebbe di nuovo.
    for (i = 0; i < N_PARTY; i++) svc_equip_recalc((unsigned char)i);
    for (i = 0; i < N_PARTY; i++) svc_equip_recalc((unsigned char)i);
    for (i = 0; i < N_PARTY; i++) svc_equip_recalc((unsigned char)i);
#endif
    (void)i;}

#define INTRO_ARG_BUILD_PARTY  0x8000

unsigned int overlay_main(unsigned int arg) {
    unsigned int packed;
    int i;

    if (arg & INTRO_ARG_BUILD_PARTY) {
        build_party((unsigned int)(arg & 0x0FFF));
        seed_test_party();
        return 0;
    }

    // Valori di partenza: qui e non negli inizializzatori, vedi la nota (b)
    // in testa al file.
    respond_rate = 1;
    classel_active_pg = 0;

    // Gruppo predefinito FT/TH/WM/BM, come sul NES all'ingresso della scena.
    party_class_sel[0] = CLS_FT;
    party_class_sel[1] = CLS_TH;
    party_class_sel[2] = CLS_WM;
    party_class_sel[3] = CLS_BM;

    run_legend();
    run_boot_menu();
    run_class_select();

    packed = (unsigned int)(respond_rate - 1) << 12;
    for (i = 0; i < N_PARTY; i++) {
        packed |= (unsigned int)(party_class_sel[i] & 7) << (i * 3);
    }
    return packed;
}
