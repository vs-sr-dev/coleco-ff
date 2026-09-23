// =====================================================================
//  ovl_btlmagic.c -- la magia del giocatore, overlay di CODICE (banco 23)
// =====================================================================
// QUARTO overlay, e il PRIMO che gira dentro un altro: ci si entra da
// ovl_battle.c (banco 20) con `svc_run_overlay(BTLMAGIC_BANK, arg)`. Al
// ritorno il banco 20 e' di nuovo mappato e la battaglia riprende dalla riga
// dopo. E' l'annidamento per cui `svc_run_overlay` rimette il banco LETTO
// all'ingresso invece dello zero (slice61): senza quella scelta, tornare
// dalla magia avrebbe rimappato il banco 0 e il `ret` sarebbe atterrato dentro
// i dati della overworld.
//
// PERCHE' UN SECONDO OVERLAY E NON UN PEZZO DEL PRIMO
// Nel banco 20 restavano 886 byte. Il sottomenu, la scelta del bersaglio, le
// formule e i messaggi non ci stanno, e non e' una questione di scriverli
// stretti: il banco 20 e' pieno da slice56 e ogni cosa nuova della battaglia
// da qui in avanti -- alterazioni di stato, oggetti, effetti visivi -- ha lo
// stesso problema. Questo file e' il posto dove andranno.
//
// DUE MESTIERI, UN OVERLAY. Il byte alto di `arg` sceglie:
//   BTLMAG_MODE_SELECT  il sottomenu: quale magia, e -- quando serve -- su chi
//   BTLMAG_MODE_CAST    il lancio vero, che avviene DOPO, quando il round
//                       arriva al turno di quel personaggio
// Sono due momenti diversi (si sceglie prima, si lancia dopo: e' il round del
// NES) ma hanno bisogno delle stesse cose -- la tabella degli incantesimi, i
// nomi dal banco 11, la conversione da casella a id -- e separarli in due
// overlay vorrebbe dire due copie di quelle.
//
// COSA NON STA QUI, e perche':
//   * IL CURSORE SUI NEMICI. Quando la magia vuole UN nemico, questo file
//     torna `BTGT_PICK_FOE` e la scelta la fa l'overlay di battaglia, che il
//     cursore sull'arena ce l'ha gia' per FIGHT. La geometria della griglia
//     (quale slot sta in quale cella, con i buchi dei morti) resta in UN solo
//     posto: due copie che divergono darebbero un cursore sul mostro
//     sbagliato, che non somiglia a un difetto -- somiglia a una magia che ha
//     mancato.
//   * CANCELLARE I NEMICI MORTI e RINFRESCARE LA STRISCIA DI STATO. Qui si
//     scrivono gli HP in RAM; a rileggerli e ridisegnare ci pensa il banco 20
//     al ritorno, con le funzioni che ha gia'.
//
// LA TRAPPOLA CHE QUESTO FILE DEVE EVITARE: **niente `static` mutabili.**
// La BSS degli overlay sta a $6C00 per TUTTI (crt/overlay_crt0.asm), e questo
// overlay gira mentre quello di battaglia e' vivo: una variabile statica qui
// scriverebbe sopra le sue. E' un problema nuovo -- il negozio e l'intro non
// girano dentro nessuno -- e la soluzione e' la piu' semplice: tutto in
// variabili locali, che stanno sulla pila. La rodata invece e' del banco e non
// da' fastidio a nessuno.
// (E vale sempre la regola di slice62: la DATA di un overlay non viene MAI
// inizializzata, nemmeno per uno scalare. Qui non ce n'e' proprio.)
// =====================================================================

#define SVC_OVERLAY
#include "svc_api.h"
#include "party_state.h"
#include "battle_state.h"
#include "battle_ibstats.h"    // slice70: le statistiche della sola battaglia
#include "data/item_names.h"   // solo le macro dello spazio degli id
// slice76: le costanti dei livelli. Solo le costanti -- le tre tabelle stanno
// nel banco 11 e ci arrivano una riga alla volta con svc_fetch_btl.
#include "data/levelup_data.h"

// Costanti di games.h: l'overlay non linka nulla della libreria.
#define MOVE_RIGHT  1
#define MOVE_LEFT   2
#define MOVE_DOWN   4
#define MOVE_UP     8
#define MOVE_FIRE1 16
#define MOVE_FIRE2 32

#define NT_BASE   0x1800

// ---- la tabella degli incantesimi, banco 11 (come in ovl_battle.c) ----
#define MAG_STAT_SIZE 8
#define MAG_HITRATE   0
#define MAG_POWER     1
#define MAG_ELEMENT   2
#define MAG_TARGET    3
#define MAG_EFFECT    4

#define MAGTGT_ALL_FOES   0x01
#define MAGTGT_ONE_FOE    0x02
#define MAGTGT_CASTER     0x04
#define MAGTGT_ALL_ALLIES 0x08
#define MAGTGT_ONE_ALLY   0x10

// Gli effetti implementati. Da slice69 sono sette su diciotto, e coprono
// TUTTO quello che si compra a Coneria piu' meta' di quello che i mostri hanno
// in tabella:
//   $01 danno                 FIRE, LIT, ICE, e 12 attacchi speciali
//   $02 danno ai non-morti    HARM
//   $03 alterazione, col tiro SLEP, DARK, MUTE, HOLD, RUB, BANE... e TREDICI
//                             attacchi speciali dei mostri
//   $07 recupero HP           CURE, HEAL
//   $08 cura di un'alterazione LAMP, PURE, AMUT
//   $0F cura tutto            CUR4
//   $12 alterazione, senza tiro XXXX, BLND, STUN
// Restano fuori le modifiche alle STATISTICHE ($09 FOG, $0D TMPR, $0E LOCK,
// $10 RUSE...): non e' una formula che manca, e' una struttura -- servono
// statistiche valide per la sola battaglia, e qui i numeri si leggono da PARTY,
// che allo scontro sopravvive. Gli altri DICHIARANO di non fare niente invece
// di fingere -- vedi la nota su cast_spell.
#define MAGEFF_DAMAGE        0x01
#define MAGEFF_DAMAGE_UNDEAD 0x02
#define MAGEFF_AILMENT       0x03
#define MAGEFF_SLOW          0x04
#define MAGEFF_MORALE_DOWN   0x05
#define MAGEFF_RECOVER_HP    0x07
#define MAGEFF_CURE_AIL      0x08
#define MAGEFF_ABSORB_UP     0x09
#define MAGEFF_ELEM_RESIST   0x0A
#define MAGEFF_ATTACK_UP     0x0B
#define MAGEFF_FAST          0x0C
#define MAGEFF_ATTACK_UP2    0x0D
#define MAGEFF_EVADE_DOWN    0x0E
#define MAGEFF_CURE_ALL      0x0F
#define MAGEFF_EVADE_UP      0x10
#define MAGEFF_REMOVE_RESIST 0x11
#define MAGEFF_AILMENT2      0x12

// Gli effetti che toccano le STATISTICHE invece degli HP: quelli che hanno
// avuto bisogno del blocco IB (battle_ibstats.h) per esistere. Divisi non per
// cosa fanno ma per COME ATTERRANO, che e' l'unica differenza che il codice
// deve sapere:
//   * i potenziamenti (su chi lancia o sui compagni) non tirano mai;
//   * gli indebolimenti (sui nemici) tirano come le alterazioni.
#define IS_BUFF_EFFECT(e)                                                   \
    ((e) == MAGEFF_ABSORB_UP  || (e) == MAGEFF_ELEM_RESIST ||               \
     (e) == MAGEFF_ATTACK_UP  || (e) == MAGEFF_FAST        ||               \
     (e) == MAGEFF_ATTACK_UP2 || (e) == MAGEFF_EVADE_UP)
#define IS_DEBUFF_EFFECT(e)                                                 \
    ((e) == MAGEFF_SLOW || (e) == MAGEFF_MORALE_DOWN ||                     \
     (e) == MAGEFF_EVADE_DOWN || (e) == MAGEFF_REMOVE_RESIST)

// ---- le due correzioni di TABELLA, non di codice ----------------------
// Sono le uniche due voci di `lut_MagicData` che, prese come stanno, chiedono
// al motore di fare qualcosa che nessuna lettura del codice giustifica. Il
// resto della tabella si usa alla lettera; queste due si correggono QUI, in un
// punto solo, invece che nell'estrattore -- cosi' `src/data/magic_data.h`
// resta byte-exact rispetto al ROM e la deviazione e' leggibile accanto al
// motivo (`docs/Coleco_improvements.md`).
//
//   LOK2 ($17) dichiara l'effetto $10, che ALZA l'evasione, e bersaglia i
//   NEMICI. E' il contrario di quel che il nome dice e di quel che fa LOCK,
//   la sua versione debole: LOK2 costa una carica di terzo livello per
//   rendere un mostro piu' difficile da colpire. Va letta come $0E.
//   Il criterio generale, che vale anche se un giorno saltasse fuori un'altra
//   voce cosi': nessuno potenzia il proprio nemico.
//
//   HEL2 ($23) dichiara effectivity 48, che e' la STESSA di HEL3 ($33), la
//   sua versione di due livelli piu' alta. Una scala 12 / 48 / 48 non e' una
//   scala; 12 / 24 / 48 lo e'.
#define MAG_ID_LOK2  0x17
#define MAG_ID_HEL2  0x23
#define HEL2_POWER   24

#define BTLTAB_MAGIC   1
#define fetch_spell(id, dst) \
    svc_fetch_btl(BTLTAB_MAGIC, (unsigned int)(id) * MAG_STAT_SIZE, \
                  MAG_STAT_SIZE, (dst))

// I NOMI ARRIVANO DAL BANCO 11, non dal 16 dove li legge il negozio. E' una
// seconda copia in ROM (btldata_bank.c la spiega) e la ragione sta tutta in
// una misura: un `svc_fetch_item_name` nella finestra fissa costava 165 byte
// su 220 rimasti, mentre una tabella in piu' dentro `svc_fetch_btl` -- che il
// banco 11 lo mappa gia' -- costa un `else if`.
// Il nome di un incantesimo e' il nome dell'OGGETTO $B0+id: nello spazio degli
// id di FF1 le magie sono merce come le spade, ed e' il motivo per cui si
// comprano in un negozio.
#define BTLTAB_NAMES   4
#define FF1_NAME_LEN   8
#define fetch_item_name(id, dst) \
    svc_fetch_btl(BTLTAB_NAMES, (unsigned int)(id) << 3, FF1_NAME_LEN, (dst))
#define fetch_spell_name(mid, dst) \
    fetch_item_name((unsigned char)(FF1_ITEM_SPELL_BASE + (mid)), (dst))

// ---- statistiche di un nemico, banco 11, tabella 0 --------------------
#define BTLTAB_ENEMY       0
#define ENROMSTAT_SIZE     20
#define ENROMSTAT_HPMAX    0x04     /* 2 byte LE: serve al tiro del risveglio */
/* I cinque campi che slice70 COPIA in RAM perche' qualcosa puo' cambiarli. */
#define ENROMSTAT_MORALE   0x06
#define ENROMSTAT_EVADE    0x08
#define ENROMSTAT_ABSORB   0x09
#define ENROMSTAT_DAMAGE   0x0C
#define ENROMSTAT_CATEGORY 0x10
#define ENROMSTAT_MAGDEF   0x11
#define ENROMSTAT_ELEMWEAK 0x12
#define ENROMSTAT_ELEMRES  0x13
#define CATEGORY_UNDEAD    0x08
#define fetch_enemy_stat(id, dst) \
    svc_fetch_btl(BTLTAB_ENEMY, (unsigned int)(id) * ENROMSTAT_SIZE, \
                  ENROMSTAT_SIZE, (dst))

// ---- la pianta del sottomenu -----------------------------------------
// Righe 16-21 sono i due riquadri della battaglia (bersagli a sinistra,
// comandi a destra): il sottomenu se le prende tutte e al ritorno il banco 20
// le ridisegna con render_target_box + render_command_box, che ha gia'.
// La riga 23 e' il messaggio, la 22 il suggerimento. Le colonne si fermano a
// 23: da 24 in poi c'e' la striscia di stato, che deve restare leggibile --
// e' li' che si guardano gli HP mentre si sceglie una cura.
#define MAG_ROW_TOP    16
#define MAG_ROW_0      17     /* quattro livelli visibili: 17 18 19 20 */
#define MAG_ROW_BOT    21
#define MAG_ROW_HINT   22
#define MAG_ROW_MSG    23
#define MAG_ROWS        4     /* livelli per pagina */
#define MAG_COL_CELL    6     /* larghezza di una casella di magia */
#define MAG_COL_FIRST   6     /* dove comincia la prima casella */
#define STAT_COL       25     /* la striscia di stato, come in ovl_battle.c */

static const char txt_hint_pick[] = "FIRE1 CAST   FIRE2 BACK";
static const char txt_hint_who[]  = "FIRE1 OK     FIRE2 BACK";
static const char txt_empty[]     = "NOTHING THERE";
static const char txt_nomp[]      = "NO CHARGES LEFT";
static const char txt_nothing[]   = "NOTHING HAPPENS";
static const char txt_casts[]     = " CASTS ";
static const char txt_ineff[]     = "INEFFECTIVE";
static const char txt_dies[]      = " DIES";
// I quattro esiti del turno di chi non puo' agire. Sono i messaggi del NES
// (BTLMSG_SLEEPING, BTLMSG_WOKEUP, BTLMSG_PARALYZED_B, BTLMSG_CURED).
static const char txt_sleeping[]  = " SLEEPING";
static const char txt_wokeup[]    = " WOKE UP";
static const char txt_paralyzed[] = " PARALYZED";
static const char txt_cured[]     = " CURED";
static const char txt_confused[]  = " CONFUSED";

// =====================================================================
//  Scrittura a schermo -- le stesse quattro di ovl_battle.c
// =====================================================================
// Sono ricopiate e non condivise, e la scelta e' consapevole: sono quattro
// funzioni di tre righe che scrivono in VRAM a coordinate date, senza nessuna
// conoscenza della battaglia. Cio' che NON si ricopia e' tutto quello che sa
// dove stanno i mostri -- quello resta di la' (vedi l'intestazione).
static unsigned int nt_at(unsigned char col, unsigned char row) {
    return NT_BASE + (unsigned int)row * 32 + col;
}
static void ov_string(unsigned char col, unsigned char row, const char *s) {
    unsigned char buf[32];
    int n = 0;
    while (s[n] && n < 32) { buf[n] = (unsigned char)s[n]; n++; }
    if (n) svc_vwrite(buf, nt_at(col, row), (unsigned int)n);
}
static void ov_char(unsigned char col, unsigned char row, char c) {
    unsigned char t = (unsigned char)c;
    svc_vwrite(&t, nt_at(col, row), 1);
}
static void ov_fill_row(unsigned char row, unsigned char col_start,
                        unsigned char n, unsigned char c) {
    svc_vfill(nt_at(col_start, row), c, (unsigned int)n);
}
// Tre cifre senza zeri iniziali a sinistra, come ov_u3 di ovl_battle.c.
static void ov_u3(unsigned char col, unsigned char row, unsigned int v) {
    unsigned char b[3];
    if (v > 999) v = 999;
    b[0] = (unsigned char)('0' + v / 100);
    b[1] = (unsigned char)('0' + (v / 10) % 10);
    b[2] = (unsigned char)('0' + v % 10);
    if (b[0] == '0') { b[0] = ' '; if (b[1] == '0') b[1] = ' '; }
    svc_vwrite(b, nt_at(col, row), 3);
}
static void render_message(const char *m) {
    ov_fill_row(MAG_ROW_MSG, 0, 24, ' ');
    ov_string(0, MAG_ROW_MSG, m);
}
static void wait_frames(int n) {
    while (n-- > 0) svc_wait_vblank();
}
static int msg_lit(char *dst, int k, const char *s) {
    while (*s && k < 25) dst[k++] = *s++;
    return k;
}
static int msg_name(char *dst, int k, const char *src) {
    // I nomi arrivano imbottiti di spazi (7 caratteri fissi nel ROM): si
    // copiano fino allo spazio, o "CURE   " mangerebbe mezza riga.
    while (*src && *src != ' ' && k < 25) dst[k++] = *src++;
    return k;
}

// RandAX del NES, identica a quella dell'overlay di battaglia: non e' un
// modulo ma una moltiplicazione di cui si tiene il byte alto.
static unsigned char rand_ax(unsigned char lo, unsigned char hi) {
    unsigned int range;
    if (hi < lo) hi = lo;
    range = (unsigned int)hi + 1u - (unsigned int)lo;
    return (unsigned char)((unsigned int)lo +
        (((unsigned int)svc_battle_rng() * range) >> 8));
}

// =====================================================================
//  Dalla casella all'incantesimo
// =====================================================================
// `ch_spells` fuori battaglia tiene 1-8: QUALE degli otto incantesimi del
// livello, non il posto in cui sta. L'id vero della tabella e' 0-63 e si
// ottiene com'e' scritto in ConvertOBStatsToIB (bank_0B.asm:379):
//   id = livello*8 + (valore - 1)
// Sul NES la conversione si fa una volta sola all'ingresso in battaglia, e da
// li' in poi `ch_spells` contiene gia' l'id: qui la si fa al momento dell'uso,
// cosi' il blocco del gruppo ha UN solo formato e non due a seconda di dove
// ci si trova. Il prezzo e' questa riga; il guadagno e' non dover convertire
// avanti e indietro a ogni battaglia -- e non poter dimenticare di farlo.
static unsigned char spell_id_of(chr_t *c, unsigned char lvl, unsigned char col) {
    unsigned char v = c->spells[(unsigned int)lvl * PARTY_SPELLS_PER_LEVEL + col];
    if (v == 0) return 0xFF;                    /* casella vuota */
    return (unsigned char)(lvl * 8 + (v - 1));
}

// =====================================================================
//  Il sottomenu
// =====================================================================
// Quattro livelli per pagina, tre caselle per livello, e la pagina segue il
// livello scelto invece di essere un comando a parte: sul NES la si cambia con
// un tasto apposito perche' li' non c'e' altro modo, qui basta scorrere.
// I tasti 1-8 del tastierino saltano direttamente al livello, che e' l'uso per
// cui [[design-input]] voleva il tastierino -- con otto livelli e tre caselle
// contare i passi del cursore e' proprio il lavoro da evitare.
static void draw_cell(chr_t *c, unsigned char lvl, unsigned char col,
                      unsigned char row, unsigned char sel) {
    unsigned char id = spell_id_of(c, lvl, col);
    unsigned char x  = (unsigned char)(MAG_COL_FIRST + col * MAG_COL_CELL);
    unsigned char nm[FF1_NAME_LEN];

    ov_char(x, row, sel ? '>' : ' ');
    if (id == 0xFF) {
        ov_string((unsigned char)(x + 1), row, "----");
        return;
    }
    fetch_spell_name(id, nm);
    nm[4] = 0;                                  /* i nomi delle magie sono 4 */
    ov_string((unsigned char)(x + 1), row, (const char *)nm);
}

static void draw_level_row(chr_t *c, unsigned char lvl, unsigned char row,
                           unsigned char sel_col, unsigned char is_sel) {
    unsigned char k;
    ov_fill_row(row, 0, 24, ' ');
    ov_char(0, row, 'L');
    ov_char(1, row, (unsigned char)('1' + lvl));
    // Le cariche del livello, che sono gli "MP" di FF1: non un serbatoio unico
    // ma otto contatori. E' il posto giusto per mostrarli -- la striscia di
    // battaglia non li porta apposta ([[feedback-hud-parity]]).
    ov_char(2, row, (unsigned char)('0' + (c->curmp[lvl] % 10)));
    ov_char(3, row, '/');
    ov_char(4, row, (unsigned char)('0' + (c->maxmp[lvl] % 10)));
    for (k = 0; k < PARTY_SPELLS_PER_LEVEL; k++) {
        unsigned char s = 0;
        if (is_sel) { if (k == sel_col) s = 1; }
        draw_cell(c, lvl, k, row, s);
    }
}

static void draw_page(chr_t *c, unsigned char lvl, unsigned char col) {
    unsigned char page = (unsigned char)(lvl >> 2);   /* 0 = L1-4, 1 = L5-8 */
    unsigned char i;
    for (i = 0; i < MAG_ROWS; i++) {
        unsigned char l = (unsigned char)(page * MAG_ROWS + i);
        unsigned char is = 0;
        if (l == lvl) is = 1;
        draw_level_row(c, l, (unsigned char)(MAG_ROW_0 + i), col, is);
    }
}

// Il cursore sui personaggi, per le magie che curano UNO. Sta nella colonna 24
// della striscia di stato, dove l'overlay di battaglia mette gia' la freccia
// di chi deve scegliere: al ritorno la ridisegna lui con render_status_strip.
static void draw_ally_cursor(unsigned char who, unsigned char on) {
    unsigned char i;
    for (i = 0; i < PARTY.n; i++) {
        unsigned char c = ' ';
        if (on) { if (i == who) c = '>'; }
        ov_char(24, (unsigned char)(i * 4), (char)c);
    }
}

// Scelta di un compagno. Ritorna il suo indice, o 0xFF se si torna indietro.
// I morti si possono puntare apposta: LIFE esiste, e anche una CURE su un
// caduto e' una mossa che il NES lascia fare (non fa niente, e lo dice).
static unsigned char pick_ally(unsigned char start,
                               unsigned int *pj, unsigned char *pk) {
    unsigned char who = start;
    ov_fill_row(MAG_ROW_HINT, 0, 24, ' ');
    ov_string(0, MAG_ROW_HINT, txt_hint_who);
    draw_ally_cursor(who, 1);

    for (;;) {
        unsigned int j;
        unsigned char joy, key, je, ke;
        svc_wait_vblank();
        j   = svc_joystick();
        joy = (unsigned char)(j & 0xFF);
        key = (unsigned char)(j >> 8);
        je  = (unsigned char)(joy & ~(unsigned char)(*pj & 0xFF));
        ke  = 0;
        if (key != 0) { if (key != *pk) ke = key; }
        *pj = j; *pk = key;

        if (je & MOVE_FIRE2) { draw_ally_cursor(who, 0); return 0xFF; }
        if (je & (MOVE_UP | MOVE_LEFT)) {
            who = (unsigned char)(who ? who - 1 : PARTY.n - 1);
            draw_ally_cursor(who, 1);
        } else if (je & (MOVE_DOWN | MOVE_RIGHT)) {
            who = (unsigned char)((who + 1 >= PARTY.n) ? 0 : who + 1);
            draw_ally_cursor(who, 1);
        } else if (ke >= '1' && ke < (unsigned char)('1' + PARTY.n)) {
            who = (unsigned char)(ke - '1');
            draw_ally_cursor(who, 1);
        } else if (je & MOVE_FIRE1) {
            draw_ally_cursor(who, 0);
            return who;
        }
    }
}

static unsigned int run_select(unsigned char chr) {
    chr_t *c = &PARTY.chr[chr];
    unsigned char lvl = 0, col = 0;
    unsigned int  pj;
    unsigned char pk;

    ov_fill_row(MAG_ROW_TOP, 0, 24, ' ');
    ov_fill_row(MAG_ROW_BOT, 0, 24, ' ');
    ov_fill_row(MAG_ROW_HINT, 0, 24, ' ');
    ov_string(0, MAG_ROW_HINT, txt_hint_pick);
    render_message("");
    draw_page(c, lvl, col);

    // Il primo frame serve solo a fotografare i pulsanti: si arriva qui col
    // FIRE1 che ha scelto MAGIC ancora premuto, e senza questo verrebbe letto
    // come un fronte e lancerebbe la prima magia della lista. E' la stessa
    // precauzione che apre overlay_main della battaglia.
    svc_wait_vblank();
    pj = svc_joystick();
    pk = (unsigned char)(pj >> 8);

    for (;;) {
        unsigned int  j;
        unsigned char joy, key, je, ke, nl, nc;

        svc_wait_vblank();
        j   = svc_joystick();
        joy = (unsigned char)(j & 0xFF);
        key = (unsigned char)(j >> 8);
        je  = (unsigned char)(joy & ~(unsigned char)(pj & 0xFF));
        ke  = 0;
        if (key != 0) { if (key != pk) ke = key; }
        pj = j; pk = key;

        if (je & MOVE_FIRE2) return BTLMAG_CANCELLED;

        nl = lvl; nc = col;
        if (je & MOVE_UP)    nl = (unsigned char)(lvl ? lvl - 1 : PARTY_SPELL_LEVELS - 1);
        if (je & MOVE_DOWN)  nl = (unsigned char)((lvl + 1 >= PARTY_SPELL_LEVELS) ? 0 : lvl + 1);
        if (je & MOVE_LEFT)  nc = (unsigned char)(col ? col - 1 : PARTY_SPELLS_PER_LEVEL - 1);
        if (je & MOVE_RIGHT) nc = (unsigned char)((col + 1 >= PARTY_SPELLS_PER_LEVEL) ? 0 : col + 1);
        if (ke >= '1' && ke <= '8') nl = (unsigned char)(ke - '1');

        if (nl != lvl || nc != col) {
            lvl = nl; col = nc;
            // Si ridisegna la pagina intera e non le due caselle cambiate:
            // cambiando livello puo' essere cambiata la PAGINA, e allora sono
            // quattro righe diverse. Sono 4 scritture in VRAM dentro il tempo
            // di quadro, non un ciclo di gioco.
            draw_page(c, lvl, col);
            continue;
        }

        if (je & MOVE_FIRE1) {
            unsigned char id = spell_id_of(c, lvl, col);
            unsigned char sp[MAG_STAT_SIZE];
            unsigned char tgt;

            // I due rifiuti del NES (@NothingBox in BattleSubMenu_Magic,
            // bank_0C.asm:729) sono lo stesso riquadro per due ragioni
            // diverse. Qui si distinguono: "non c'e' niente" e "non hai piu'
            // cariche" portano a due mosse diverse di chi gioca.
            if (id == 0xFF)          { render_message(txt_empty); continue; }
            if (c->curmp[lvl] == 0)  { render_message(txt_nomp);  continue; }

            fetch_spell(id, sp);
            // La maschera dei bersagli, nell'ordine in cui la prova il NES.
            // L'ordine conta: RUSE ha 04 (chi lancia) e alcune ne hanno piu'
            // di uno acceso, quindi "il primo bit che si trova" fa parte
            // della definizione.
            if (sp[MAG_TARGET] & MAGTGT_ALL_FOES) {
                tgt = BTGT_ALL_FOES;
            } else if (sp[MAG_TARGET] & MAGTGT_ONE_FOE) {
                tgt = BTGT_PICK_FOE;        /* il cursore lo muove il banco 20 */
            } else if (sp[MAG_TARGET] & MAGTGT_CASTER) {
                tgt = (unsigned char)(BTGT_IS_CHR | chr);
            } else if (sp[MAG_TARGET] & MAGTGT_ALL_ALLIES) {
                tgt = BTGT_ALL_ALLIES;
            } else {
                unsigned char who = pick_ally(chr, &pj, &pk);
                if (who == 0xFF) {          /* tornato indietro: si rifa' */
                    ov_fill_row(MAG_ROW_HINT, 0, 24, ' ');
                    ov_string(0, MAG_ROW_HINT, txt_hint_pick);
                    continue;
                }
                tgt = (unsigned char)(BTGT_IS_CHR | who);
            }
            return (unsigned int)id | ((unsigned int)tgt << 8);
        }
    }
}

// =====================================================================
//  Il lancio
// =====================================================================

// Il tiro della magia: per le magie di UTILITA' decide se atterrano, per
// quelle di DANNO decide se fanno CRITICO, perche' quelle colpiscono sempre
// (bank_0C.asm:8284). Un tiro solo, due letture -- gemella di quella
// dell'overlay di battaglia, che la usa per i nemici.
static int magic_roll(int chance) {
    int roll = (int)rand_ax(0, 200);
    if (roll == 200) return 0;          /* 200 esatto = fallito sicuro */
    return chance >= roll;
}

// Le due voci di tabella che si correggono, in un punto solo (slice70).
// Il perche' di ciascuna sta accanto alle costanti, in cima al file. Qui c'e'
// solo la ragione della FORMA: si corregge la copia appena prelevata, non
// `src/data/magic_data.h`, cosi' il file generato resta byte-exact rispetto al
// ROM e la deviazione vive accanto al motore che la applica -- dove la legge
// chi si chiede perche' LOK2 si comporta diversamente da quel che dice la
// tabella.
// Vale per gli incantesimi del GRUPPO e per quelli dei MOSTRI: la chiamano
// tutte e due le strade, perche' una correzione applicata da un lato solo
// sarebbe peggio di nessuna.
static void patch_spell(unsigned char id, unsigned char *sp) {
    if (id == MAG_ID_LOK2) sp[MAG_EFFECT] = MAGEFF_EVADE_DOWN;
    if (id == MAG_ID_HEL2) sp[MAG_POWER]  = HEL2_POWER;
}

// INT: da statistica morta ad ACCURATEZZA MAGICA (slice69).
//
// Sul NES questa statistica non entra in NESSUNA formula: e' il bug piu' citato
// del gioco, e il mago nero tira i suoi incantesimi con la stessa precisione
// del guerriero che ne ruba uno. La decisione (sessione 16,
// [[int-stat-decided]]) e' un aggancio SOLO: `+ INT/4` nella chance di colpo.
// Un aggancio solo perche' quel numero e' gia' due cose -- sulle magie di
// utilita' decide se atterrano, su quelle di danno E' la chance di critico --
// e quindi INT alza anche il danno senza che nessuna formula del danno lo
// nomini. NON e' difesa magica: quella e' magdef, esiste gia', e i mostri
// un'INT non ce l'hanno proprio.
//
// Vale per gli incantesimi del GRUPPO. Quelli dei mostri non ne hanno: le loro
// statistiche sono venti byte in ROM e l'intelligenza non e' fra quelli.
static int int_bonus(chr_t *c) { return (int)(c->int_stat >> 2); }

// =====================================================================
//  Gli effetti che toccano le STATISTICHE (slice70)
// =====================================================================
// UNA funzione per le due parti del campo, ed e' il motivo per cui il blocco IB
// ha la stessa voce per un personaggio e per un mostro: alzare l'evasione e'
// la stessa operazione su chiunque. L'unica cosa che cambia fra i due lati e'
// SE l'incantesimo atterra, e quello lo decide il chiamante -- che e' l'unico
// a sapere da che parte guarda e dove prende la difesa magica.
//
// Ritorna 1 se ha morso. Un potenziamento che non puo' salire piu' NON ha
// morso, ed e' il NES a dirlo: `BtlMag_Effect_Fast` (bank_0C.asm:8616) dichiara
// il lancio riuscito e poi lo DISDICE se il moltiplicatore era gia' al massimo.
// La differenza si vede a schermo -- "FAST di nuovo" contro "FAST sprecata" --
// ed e' esattamente la coppia che questo progetto separa sempre.
static int stat_effect(ibstat_t *t, unsigned char eff, unsigned char e) {
    unsigned int v;

    if (eff == MAGEFF_ABSORB_UP) {
        v = (unsigned int)t->absorb + e;
        t->absorb = (unsigned char)((v > 255) ? 255 : v);
        return 1;
    }
    if (eff == MAGEFF_EVADE_UP) {
        // Il NES qui somma con `ADC` e senza `CLC` (bank_0C.asm:8699): il
        // riporto del confronto precedente puo' regalare un punto di evasione.
        // Uno su duecento, invisibile, e non c'e' ragione di riprodurlo.
        v = (unsigned int)t->evade + e;
        t->evade = (unsigned char)((v > 255) ? 255 : v);
        return 1;
    }
    if (eff == MAGEFF_ELEM_RESIST) {
        t->resist |= e;
        return 1;
    }
    if (eff == MAGEFF_ATTACK_UP || eff == MAGEFF_ATTACK_UP2) {
        // Le due voci fanno la stessa cosa e il NES le scrive due volte
        // ($0B e $0D), col commento "you could just JMP there". La $0D in piu'
        // vorrebbe sommare il tiro dell'incantesimo al tiro di chi la riceve,
        // e lo scrive in `$6884`, che non e' il tiro di nessuno. Qui va dove
        // deve: non cambia un numero -- TMPR e SABR hanno tiro zero, ed e' il
        // motivo per cui il difetto non si e' mai visto -- e toglie una
        // domanda a chi legge.
        v = (unsigned int)t->dmg + e;
        t->dmg = (unsigned char)((v > 255) ? 255 : v);
        return 1;
    }
    if (eff == MAGEFF_FAST) {
        if (t->hits_mult >= IB_HITS_MULT_MAX) {
            t->hits_mult = IB_HITS_MULT_MAX;
            return 0;                       /* gia' al massimo: sprecata */
        }
        t->hits_mult++;
        return 1;
    }
    if (eff == MAGEFF_SLOW) {
        // Il difetto del NES e' l'ordine: decrementa, e se e' andato sotto zero
        // rimette il valore -- ma si e' gia' dichiarato riuscito
        // (bank_0C.asm:8457, "this is where the 'bug' is"). Cosi' SLOW su chi
        // e' gia' lento dice di aver funzionato. Qui l'esito segue il fatto.
        if (t->hits_mult == 0) return 0;
        t->hits_mult--;
        return 1;
    }
    if (eff == MAGEFF_EVADE_DOWN) {
        t->evade = (unsigned char)((t->evade > e) ? (t->evade - e) : 0);
        return 1;
    }
    if (eff == MAGEFF_MORALE_DOWN) {
        t->morale = (unsigned char)((t->morale > e) ? (t->morale - e) : 0);
        return 1;
    }
    if (eff == MAGEFF_REMOVE_RESIST) {
        t->resist = 0;
        return 1;
    }
    return 0;
}

// Danno di un incantesimo contro UN nemico (BtlMag_Effect_Damage,
// bank_0C.asm:8283). La gemella verso i personaggi sta piu' sotto, e la
// differenza NON e' solo il verso: un nemico puo' avere una DEBOLEZZA
// elementale, un personaggio no (btlch_elemweak e' forzato a zero,
// bank_0C.asm:5668). Il ramo del +40 e del danno x1.5 esiste solo di qua, ed
// e' quello che rende FIRE una scelta e non un'abitudine.
//
// L'ORDINE DELLE ESTRAZIONI E' PARTE DELLA FORMULA: prima il danno, poi il
// colpo (BtlMag_PrepHitAndDamage, righe 8162-8171).
// LA RESISTENZA DEL MOSTRO SI LEGGE DAL BLOCCO IB, NON DALLA ROM (slice70,
// fix #6). E' la riga che fa esistere XFER, AFIR e compagnia contro i mostri:
// sul NES quel valore resta nella ROM, quindi modificarlo non serve a niente e
// il disassembly lo annota come il vero motivo del bug di XFER
// (bank_0C.asm:8740). La DEBOLEZZA invece resta di ROM: nessun incantesimo la
// tocca, e copiarla in RAM sarebbe uno stato in piu' senza nessuno che lo
// scrive.
static unsigned int magic_damage_on_enemy(const unsigned char *sp,
                                          const unsigned char *st,
                                          int slot, int ib) {
    int base   = (int)sp[MAG_POWER];
    int chance = 148;
    unsigned int dmg;

    if (sp[MAG_ELEMENT] & IBE(slot).resist) {
        chance = 0;
        base >>= 1;
    }
    if (sp[MAG_ELEMENT] & st[ENROMSTAT_ELEMWEAK]) {
        chance += 40;
        base += base >> 1;              /* danno x1.5, come sul NES */
    }
    chance += (int)sp[MAG_HITRATE] + ib - (int)st[ENROMSTAT_MAGDEF];

    dmg = (unsigned int)base +
          (unsigned int)rand_ax(0, (unsigned char)((base > 255) ? 255 : base));
    if (magic_roll(chance)) dmg <<= 1;
    return dmg;
}

// Il tiro di un incantesimo di UTILITA' contro un mostro: alterazioni e
// indebolimenti lo usano identico (`BtlMag_DoStatPrep`, bank_0C.asm:8182).
// Estratto perche' da slice70 i chiamanti sono due e il conto ha quattro
// termini: due copie che divergono darebbero "SLEP prende piu' spesso di
// LOCK", che non somiglia a un difetto.
static int enemy_util_chance(const unsigned char *sp, const unsigned char *st,
                             int slot, int ib) {
    int chance = 148;
    if (sp[MAG_ELEMENT] & IBE(slot).resist)       chance = 0;
    if (sp[MAG_ELEMENT] & st[ENROMSTAT_ELEMWEAK]) chance += 40;
    return chance + (int)sp[MAG_HITRATE] + ib - (int)st[ENROMSTAT_MAGDEF];
}

// L'ALTERAZIONE addosso a un nemico (slice69). Ritorna 1 se ha morso.
//
// I DUE MODI DI ATTERRARE, che sul NES sono due routine e qui due rami:
//   $03 InflictAilment   tira. 148 di base, azzerato dalla resistenza
//                        elementale e alzato di 40 dalla debolezza, piu' il
//                        tiro dell'incantesimo meno la difesa magica.
//                        Resistere NON e' immunita': con chance 0 un tiro di 0
//                        passa lo stesso.
//   $12 InflictAilment2  non tira affatto (bank_0C.asm:8814). O il difensore
//                        resiste all'elemento -- e allora e' immune davvero --
//                        oppure basta che stia sotto i 300 HP. E' il motivo per
//                        cui XXXX e' terrificante presto e inutile poi.
//
// "INEFFECTIVE" quando il bersaglio ce l'ha GIA', e l'alterazione si somma lo
// stesso: e' cio' che fa BtlMag_ApplyAilments (bank_0C.asm:8430), che stampa il
// messaggio e poi fa l'OR comunque. Sommare un bit gia' acceso non cambia
// niente, quindi il messaggio dice il vero e non serve un secondo ramo.
static int inflict_on_enemy(const unsigned char *sp, const unsigned char *st,
                            int slot, int ib) {
    unsigned char m = sp[MAG_POWER];

    if (sp[MAG_EFFECT] == MAGEFF_AILMENT2) {
        if (sp[MAG_ELEMENT] & IBE(slot).resist) return 0;
        if (BST.enemy_hp[slot] >= 300) return 0;
    } else {
        if (!magic_roll(enemy_util_chance(sp, st, slot, ib))) return 0;
    }

    if (BST.enemy_ail[slot] & m) { render_message(txt_ineff); wait_frames(30); }
    BST.enemy_ail[slot] |= m;
    BST.ail_set++;
    BST.ail_last = m;
    // Morte o PIETRA tolgono il mostro dal campo, e il modo di dirlo e'
    // azzerargli gli HP: da li' in poi `enemy_alive` lo esclude, l'overlay di
    // battaglia gli cancella la sagoma al ritorno e la vittoria si accorge da
    // sola. Vale per i mostri e NON per i personaggi, dove la pietra lascia gli
    // HP dove sono perche' un giorno una SOFT glieli restituira'.
    if (m & AIL_OUT) BST.enemy_hp[slot] = 0;
    return 1;
}

// Un incantesimo del GRUPPO su UNO slot nemico. Ritorna 1 se ha morso, 0 se il
// bersaglio non c'era o era immune (HARM su un vivo).
static int apply_foe(const unsigned char *sp, int slot, int ib) {
    unsigned char st[ENROMSTAT_SIZE];
    unsigned char eff = sp[MAG_EFFECT];
    unsigned int dmg;

    if (BST.enemy_type[slot] == BST_NO_ENEMY) return 0;
    if (BST.enemy_hp[slot] == 0) return 0;
    fetch_enemy_stat(BST.type_enemy[BST.enemy_type[slot]], st);

    if (eff == MAGEFF_AILMENT)  return inflict_on_enemy(sp, st, slot, ib);
    if (eff == MAGEFF_AILMENT2) return inflict_on_enemy(sp, st, slot, ib);

    // Gli INDEBOLIMENTI (slice70): stesso tiro delle alterazioni, poi la
    // funzione comune ai due lati del campo.
    if (IS_DEBUFF_EFFECT(eff)) {
        if (!magic_roll(enemy_util_chance(sp, st, slot, ib))) return 0;
        if (!stat_effect(&IBE(slot), eff, sp[MAG_POWER])) return 0;
        BST.buff_set++;
        BST.buff_last = eff;
        wait_frames(20);
        return 1;
    }

    if (eff == MAGEFF_DAMAGE_UNDEAD) {
        // BtlMag_Effect_DamageUndead (bank_0C.asm:8369) NON guarda l'elemento,
        // nemmeno se la magia ne dichiara uno: le HARM sono non-elementali di
        // fatto. Preservato -- e' una stranezza senza effetti osservabili in
        // FF1, dove nessuna HARM ha elemento, non un difetto da correggere.
        if (!(st[ENROMSTAT_CATEGORY] & CATEGORY_UNDEAD)) return 0;
    }

    dmg = magic_damage_on_enemy(sp, st, slot, ib);
    if (dmg >= BST.enemy_hp[slot]) BST.enemy_hp[slot] = 0;
    else                           BST.enemy_hp[slot] -= dmg;
    ov_u3(21, MAG_ROW_MSG, (dmg > 999) ? 999 : dmg);
    wait_frames(20);
    return 1;
}

// Un incantesimo del gruppo su UN COMPAGNO: cure e recuperi.
//   $07 recupero HP  rand[eff, eff*2], tetto a 255, e su un CADUTO non fa
//                    niente -- per rialzare c'e' LIFE. La prova e' il BIT
//                    AIL_DEAD e non gli HP a zero: e' il motivo per cui
//                    l'overlay di battaglia accende quel bit quando qualcuno
//                    cade, invece di lasciare che a dirlo siano gli HP.
//   $08 cura di UNA  l'effectivity e' la MASCHERA da spegnere. LAMP toglie
//                    $08 (cecita'), PURE $04 (veleno), AMUT $40 (silenzio).
//   $0F cura tutto   HP al massimo e maschera azzerata. Rialza anche i caduti,
//                    ed e' voluto sul NES: CUR4 azzera il byte intero, bit
//                    della morte compreso (BtlMag_Effect_CureAll, 8687).
static void apply_ally(const unsigned char *sp, int who) {
    chr_t *c = &PARTY.chr[who];
    unsigned char eff = sp[MAG_EFFECT];
    unsigned char m;

    // I POTENZIAMENTI (slice70). Non tirano mai -- il NES non li fa nemmeno
    // passare da `DoStatPrep` -- e vanno nel blocco IB, che muore con la
    // battaglia. Scritti su PARTY un FOG varrebbe per il resto della partita.
    if (IS_BUFF_EFFECT(eff)) {
        if (!stat_effect(&IBC(who), eff, sp[MAG_POWER])) {
            render_message(txt_ineff);   /* FAST sopra il massimo, SLOW a zero */
            wait_frames(30);
            return;
        }
        BST.buff_set++;
        BST.buff_last = eff;
        wait_frames(20);
        return;
    }

    if (eff == MAGEFF_RECOVER_HP) {
        unsigned int amt;
        if (c->ailments & AIL_DEAD) return;
        amt = (unsigned int)sp[MAG_POWER] +
              (unsigned int)rand_ax(0, sp[MAG_POWER]);
        if (amt > 255) amt = 255;
        c->curhp += amt;
        if (c->curhp > c->maxhp) c->curhp = c->maxhp;
        ov_u3(21, MAG_ROW_MSG, amt);
        wait_frames(20);
        return;
    }

    if (eff == MAGEFF_CURE_ALL) {
        c->curhp    = c->maxhp;
        c->ailments = 0;
        wait_frames(20);
        return;
    }

    /* MAGEFF_CURE_AIL. Il NES qui esce in silenzio se non c'e' niente da
       togliere (BtlMag_Effect_CureAilment, 8553); noi lo diciamo, perche' una
       LAMP sprecata su chi ci vede benissimo e una LAMP che non funziona si
       somigliano troppo. */
    m = sp[MAG_POWER];
    if (!(c->ailments & m)) { render_message(txt_ineff); wait_frames(30); return; }
    c->ailments &= (unsigned char)~m;
    wait_frames(20);
}

static void cast_spell(unsigned char chr) {
    chr_t *c = &PARTY.chr[chr];
    unsigned char id  = BST.chr_spell[chr];
    unsigned char tgt = BST.chr_tgt[chr];
    unsigned char lvl = (unsigned char)(id >> 3);
    unsigned char sp[MAG_STAT_SIZE];
    char msg[26];
    unsigned char nm[FF1_NAME_LEN];
    int k, hit;

    // La carica si spende QUI e non alla scelta, ed e' l'ordine del NES
    // (`DEC ch_mp, X` subito prima di Player_DoMagic, bank_0C.asm:3705): chi
    // muore prima del proprio turno non ha speso niente. Alla scelta era gia'
    // stato controllato che ce ne fosse una, ma fra la scelta e il turno passa
    // mezzo round: il controllo si rifa'.
    if (c->curmp[lvl] == 0) return;
    c->curmp[lvl]--;

    fetch_spell(id, sp);
    patch_spell(id, sp);
    BST.pc_cast_count++;
    BST.pc_last_spell = id;

    fetch_spell_name(id, nm);
    nm[4] = 0;
    k = msg_name(msg, 0, c->name);
    k = msg_lit(msg, k, txt_casts);
    k = msg_name(msg, k, (const char *)nm);
    msg[k] = 0;
    render_message(msg);
    wait_frames(30);

    // Lo smistamento e' per LATO DEL CAMPO, non per effetto: un effetto sceglie
    // gia' il suo lato (non esiste una cura sui nemici ne' un danno sui
    // compagni), mentre il modo di scorrere i bersagli e' lo stesso per tutti
    // quelli che stanno dalla stessa parte. Scritto per effetto sarebbero
    // sette copie dello stesso ciclo.
    if (sp[MAG_EFFECT] == MAGEFF_DAMAGE || sp[MAG_EFFECT] == MAGEFF_DAMAGE_UNDEAD ||
        sp[MAG_EFFECT] == MAGEFF_AILMENT || sp[MAG_EFFECT] == MAGEFF_AILMENT2 ||
        IS_DEBUFF_EFFECT(sp[MAG_EFFECT])) {
        int ib = int_bonus(c);
        hit = 0;
        if (tgt == BTGT_ALL_FOES) {
            int s;
            for (s = 0; s < BST_MAX_ENEMIES; s++) hit |= apply_foe(sp, s, ib);
        } else if (!(tgt & BTGT_IS_CHR)) {
            hit = apply_foe(sp, (int)tgt, ib);
        }
        // "INEFFECTIVE" e' il messaggio del NES (Battle_ShowIneffective) per
        // un incantesimo che non ha morso. Serve soprattutto a HARM contro un
        // vivo, che altrimenti sarebbe indistinguibile da un turno perso per
        // un difetto -- ed e' la meta' del motivo per cui HARM esiste. Da
        // slice69 serve anche a SLEP che non ha preso, che e' la cosa che
        // capita piu' spesso di tutte.
        if (!hit) { render_message(txt_ineff); wait_frames(30); }
        return;
    }

    if (sp[MAG_EFFECT] == MAGEFF_RECOVER_HP || sp[MAG_EFFECT] == MAGEFF_CURE_AIL ||
        sp[MAG_EFFECT] == MAGEFF_CURE_ALL   || IS_BUFF_EFFECT(sp[MAG_EFFECT])) {
        if (tgt == BTGT_ALL_ALLIES) {
            int i;
            for (i = 0; i < (int)PARTY.n; i++) apply_ally(sp, i);
        } else if (tgt & BTGT_IS_CHR) {
            apply_ally(sp, (int)(tgt & 3));
        }
        return;
    }

    // DICHIARATO, non simulato. Da slice70 la lista si e' ridotta a UNA voce:
    // le magie che hanno effetto $00 e tiro $FF, cioe' quelle che funzionano
    // solo FUORI dalla battaglia -- LIFE, LIF2, SOFT, WARP, EXIT. Non e' un
    // pezzo di motore che manca: e' che fuori dalla battaglia non c'e' ancora
    // un posto da cui lanciare, e quel posto e' il menu.
    render_message(txt_nothing);
    wait_frames(45);
}

// =====================================================================
//  Preparazione della battaglia (slice69) -- arrivata dal banco 20
// =====================================================================
// Non c'entra niente con la magia, e sta qui per una ragione onesta: erano
// 1402 byte -- il secondo pezzo piu' grosso dell'overlay di battaglia -- e
// servono UNA VOLTA SOLA, prima che il round cominci. Occupavano posto in un
// banco che deve tenerci tutto il combattimento, mentre qui di byte liberi ce
// ne sono novemila.
//
// Che potessero muoversi si vede da cosa NON toccano: ne' VRAM, ne' sprite, ne'
// tastiera. Leggono i sedici byte grezzi della formazione da BST e riempiono
// altri campi di BST. Il commento storico qui sotto spiega perche' a suo tempo
// se ne andarono dalla SLICE; vale ancora, ed e' lo stesso motivo per cui adesso
// se ne vanno anche dal banco 20.
//
// Ricalca PrepareEnemyFormation_SmallLarge (bank_0B.asm:$A17E). Il formato dei
// 16 byte e' documentato in tools/decode_formations.ps1, che lo stampa in
// chiaro -- NB il commento di extract_encounter_data.ps1 aveva i nibble delle
// quantita' INVERTITI (dice max in alto, min in basso: e' il contrario, il
// codice del NES mette min in alto).
//
// Il numero di NEMICI non e' il numero di TIPI: cinque IMP sono cinque nemici
// e un tipo solo. La distinzione conta perche' ogni tipo costa 16 tile in VRAM,
// mentre un nemico in piu' dello stesso tipo costa zero.

static void decode_formation(void) {
    unsigned char is_b = (unsigned char)(BST.formation & 0x80);
    unsigned char small_slots, large_slots;
    unsigned char small_pos, large_pos;
    unsigned int  next_tile;
    int g, k;

    BST.btl_type = (unsigned char)(BST.formdata[0] >> 4);
    BST.chr_page = (unsigned char)(BST.formdata[0] & 0x0F);
    BST.no_run   = (unsigned char)(BST.formdata[0x0D] & 0x01);
    BST.n_types   = 0;
    BST.n_enemies = 0;
    for (k = 0; k < BST_MAX_ENEMIES; k++) {
        BST.enemy_type[k] = BST_NO_ENEMY;
        BST.enemy_hp[k]   = 0;
    }

    for (k = 0; k < BST_MAX_TYPES; k++) BST.type_tile_base[k] = 0xFF;

    // Posti in campo, da lut_EnemyCountByBattleType. Il tipo "mix" ha una riga
    // sua nella LUT del NES ma non la usa: la routine del mix li imposta a
    // mano, 2 grandi + 6 piccoli.
    //
    // Fiend e Chaos non passano di qui sul NES (PrepareEnemyFormation_FiendChaos
    // e' una routine tutta sua, che disegna una TSA invece di comporre gruppi).
    // Fino a slice55 finivano nel ramo "9small" con zero posti grandi, e siccome
    // il loro bit di slot dice "grande" il risultato era una battaglia con
    // ZERO nemici. Qui prendono un posto solo, quello vero: uno e uno soltanto,
    // e il censimento lo conferma -- tutte e 9 le righe fiend/chaos hanno un
    // gruppo solo (tools/census_fiend_tsa.ps1).
    if (BST.btl_type == BTL_TYPE_4LARGE)      { small_slots = 0; large_slots = 4; }
    else if (BST.btl_type == BTL_TYPE_MIX)    { small_slots = 6; large_slots = 2; }
    else if (BST.btl_type >= BTL_TYPE_FIEND)  { small_slots = 1; large_slots = 1; }
    else                                      { small_slots = 9; large_slots = 0; }

    // Nel "mix" la posizione NON segue l'ordine dei gruppi: i grandi vanno
    // SEMPRE negli slot 0-1 e i piccoli dal 2 in poi (PrepareEnemyFormation_Mix
    // tiene btltmp_smallslotpos, inizializzato a 2). Serve davvero: nella
    // maggior parte delle formazioni miste il gruppo grande e' il terzo, non il
    // primo, quindi un cursore unico lo metterebbe in un posto da piccolo.
    // Negli altri tipi i due cursori non si incontrano mai -- 9small non ha
    // grandi, 4large non ha piccoli -- e partono entrambi da 0.
    large_pos = 0;
    small_pos = (unsigned char)((BST.btl_type == BTL_TYPE_MIX) ? 2 : 0);

    for (g = 0; g < BST_MAX_TYPES; g++) {
        unsigned char gfx_pair, is_large, pal_id, qty, qmin, qmax, n;
        int type_idx;

        // Variante B: le quantita' vengono dai byte E,F e valgono solo per i
        // primi due gruppi -- gli altri due non esistono in questa variante.
        if (is_b) {
            if (g >= 2) continue;
            qty = BST.formdata[0x0E + g];
        } else {
            qty = BST.formdata[6 + g];
        }
        qmin = (unsigned char)(qty >> 4);
        qmax = (unsigned char)(qty & 0x0F);
        if (qmax == 0 && qmin == 0) continue;

        n = rand_ax(qmin, qmax);
        if (n == 0) continue;

        gfx_pair = (unsigned char)((BST.formdata[1] >> (2 * g)) & 0x03);
        is_large = (unsigned char)(gfx_pair & 0x01);
        // Il gruppo g legge il bit (7-g) del nibble alto del byte D: 0 sceglie
        // la palette del byte A, 1 quella del byte B. E' lo swap che distingue
        // IMP da GrIMP -- stessa grafica, due palette.
        pal_id = ((BST.formdata[0x0D] >> (7 - g)) & 0x01)
                     ? BST.formdata[0x0B] : BST.formdata[0x0A];

        type_idx = (int)BST.n_types;
        BST.type_gfx[type_idx]   = gfx_pair;
        BST.type_pal[type_idx]   = (unsigned char)(pal_id & 0x3F);
        BST.type_enemy[type_idx] = BST.formdata[2 + g];
        BST.n_types++;

        while (n--) {
            unsigned char pos;
            if (is_large) {
                if (large_slots == 0) break;
                large_slots--;
                pos = large_pos++;
            } else {
                if (small_slots == 0) break;
                small_slots--;
                pos = small_pos++;
            }
            if (pos >= BST_MAX_ENEMIES) break;
            BST.enemy_type[pos] = (unsigned char)type_idx;
            BST.n_enemies++;
        }
    }

    // ---- allocazione delle tile VRAM ------------------------------------
    // Fino a slice55 era implicita: quattro fette fisse da 16, base = A4 + t*16.
    // Con i grandi non regge piu' -- 36 contro 16 -- e serve una somma
    // progressiva. La fa QUI e non nella svc_ che carica: questo e' l'unico
    // punto che sa quali tipi sono davvero in campo, e tenere il calcolo in un
    // posto solo e' cio' che impedisce ai due lati di divergere.
    //
    // Il totale ci sta sempre: tools/census_tile_budget.ps1 misura tutte e 256
    // le varianti e il massimo e' 72 su 92 disponibili. Il controllo resta
    // comunque, perche' sforare in silenzio vorrebbe dire scrivere sopra il
    // font -- e il sintomo sarebbe una schermata di testo illeggibile, che non
    // assomiglia per niente alla causa.
    next_tile = MON_TILE_BASE;
    for (g = 0; g < (int)BST.n_types; g++) {
        unsigned int need;
        // Fiend e Chaos hanno una grafica TSA tutta loro e non sono ancora
        // estratti: nessuna tile, e l'arena lo dice a schermo.
        if (BST.btl_type >= BTL_TYPE_FIEND) break;
        need = (BST.type_gfx[g] & 0x01) ? MON_TILES_LARGE : MON_TILES;
        if (next_tile + need > MON_TILE_END) continue;   /* 0xFF, gia' scritto */
        BST.type_tile_base[g] = (unsigned char)next_tile;
        next_tile += need;
    }
}

// Nomi (banco 12) e statistiche (banco 11) dei nemici generati. Da qui esce
// anche il BOTTINO: exp_total e gp_total erano due valori di prova fissi
// (100 e 50) fino a slice54, e adesso sono la somma vera degli avversari in
// campo. Il motore delle ricompense a valle -- divisione fra i superstiti,
// passaggio di livello -- non cambia di una riga: era gia' scritto e validato.
static void load_enemy_info(void) {
    unsigned char stat[20];
    unsigned int exp_tot = 0, gp_tot = 0;
    int t, k, c;

    for (t = 0; t < BST_MAX_TYPES; t++) {
        if (t < (int)BST.n_types) {
            svc_fetch_enemy_name(BST.type_enemy[t], (unsigned char *)BST.type_name[t]);
        } else {
            for (c = 0; c < 8; c++) BST.type_name[t][c] = ' ';
        }
        BST.type_name[t][8] = 0;
    }

    /* Slot, non nemici: vedi la nota in render_monster_area. */
    for (k = 0; k < BST_MAX_ENEMIES; k++) {
        unsigned char t2 = BST.enemy_type[k];
        ibstat_t *ib = &IBE(k);
        /* Azzerato anche per gli slot vuoti: la RAM SGM non la pulisce nessuno
           fra una battaglia e l'altra, e un LOCK della battaglia scorsa non
           deve sopravvivere su uno slot che adesso ospita un altro mostro. */
        ib->dmg = 0; ib->hitrate = 0; ib->absorb = 0; ib->evade = 0;
        ib->resist = 0; ib->morale = 0;
        ib->hits_mult = IB_HITS_MULT_DEFAULT;
        if (t2 == BST_NO_ENEMY || t2 >= BST_MAX_TYPES) continue;
        fetch_enemy_stat(BST.type_enemy[t2], stat);
        BST.enemy_hp[k] = (unsigned int)stat[4] | ((unsigned int)stat[5] << 8);
        exp_tot += (unsigned int)stat[0] | ((unsigned int)stat[1] << 8);
        gp_tot  += (unsigned int)stat[2] | ((unsigned int)stat[3] << 8);
        /* La COPIA delle statistiche che qualcosa puo' cambiare (slice70). Le
           altre -- tiro, critico, colpi, difesa magica, debolezza elementale --
           restano di ROM e si leggono di la': copiarle vorrebbe dire tenere
           allineato uno stato che non cambia mai. */
        ib->dmg    = stat[ENROMSTAT_DAMAGE];
        ib->absorb = stat[ENROMSTAT_ABSORB];
        ib->evade  = stat[ENROMSTAT_EVADE];
        ib->resist = stat[ENROMSTAT_ELEMRES];
        ib->morale = stat[ENROMSTAT_MORALE];
    }

    /* E il gruppo. Parte dai valori che l'equipaggiamento ha composto
       (`svc_equip_recalc`), che e' il motivo per cui questa copia si rifa' a
       ogni battaglia invece di una volta sola: fra un incontro e l'altro ci si
       passa dal negozio. */
    for (k = 0; k < IB_CHRS; k++) {
        chr_t *c = &PARTY.chr[k];
        ibstat_t *ib = &IBC(k);
        ib->dmg       = c->dmg;
        ib->hitrate   = c->hitrate;
        ib->absorb    = c->absorb;
        ib->evade     = c->evade;
        ib->resist    = c->resist;
        ib->morale    = 0;
        ib->hits_mult = IB_HITS_MULT_DEFAULT;
    }
    IB.magic = IB_STATE_MAGIC;

    BST.exp_total = exp_tot;
    BST.gp_total  = gp_tot;
}


// =====================================================================
//  Il turno di chi non puo' agire (slice69)
// =====================================================================
// Vale per le DUE parti del campo, ed e' il motivo per cui sta qui invece che
// nell'overlay di battaglia: il tiro e' lo stesso, e due copie che divergono
// darebbero "i mostri si svegliano prima dei personaggi" -- che e' anche quello
// che fa una copia giusta, quindi non si vedrebbe.
//
// I TRE TIRI, e le due volte che ci discostiamo dal NES:
//   SONNO      ci si sveglia se maxHP > rand[0,$50]. Quindi un personaggio
//              robusto si sveglia quasi sempre, uno fragile resta giu': e'
//              esattamente il contrario dell'intuizione, ed e' voluto -- gli HP
//              massimi fanno da "vigore".
//              **FIX #14.** Sul NES questo tiro vale solo per il gruppo. Per i
//              mostri il ramo e' rotto in modo spettacolare (bank_0C.asm:6710:
//              carica un campo mai inizializzato, sottrae dal buffer sbagliato
//              e controlla un segno che MathBuf_Sub non puo' produrre), col
//              risultato che un mostro addormentato si sveglia SEMPRE al primo
//              turno. Qui i due lati usano lo stesso tiro, ed e' l'unica cosa
//              che rende SLEP un incantesimo invece di un turno perso.
//   PARALISI   un tiro su quattro per il gruppo (rand & 3), 25 su 256 per i
//              mostri (~10%). L'asimmetria e' del NES ed e' PRESERVATA: sono
//              due routine diverse con due costanti diverse, non un refuso, e
//              nessuna delle due liste di correzioni la nomina.
//   CONFUSIONE 25% di riprendersi. Se non si riprende, sul NES il mostro lancia
//              FIRE su un suo compagno -- il fix #12 dice di usargli il vero
//              attacco al posto di FIRE, ma nessuna delle due cose esiste
//              ancora: manca il lato mostro-contro-mostro. Qui il turno si
//              perde e lo si DICE. Nessun incantesimo raggiungibile a Coneria
//              confonde (CONF e' di livello 4).
static void ail_turn(unsigned char who) {
    unsigned char *pa;
    const char *name;
    const char *res;
    unsigned int hpmax;
    unsigned char is_chr = (unsigned char)(who & BTGT_IS_CHR);
    char msg[26];
    int k;

    BST.ail_turns++;
    if (is_chr) {
        chr_t *c = &PARTY.chr[who & 3];
        pa    = &c->ailments;
        name  = c->name;
        hpmax = c->maxhp;
    } else {
        unsigned char st[ENROMSTAT_SIZE];
        fetch_enemy_stat(BST.type_enemy[BST.enemy_type[who]], st);
        pa    = &BST.enemy_ail[who];
        name  = BST.type_name[BST.enemy_type[who]];
        hpmax = (unsigned int)st[ENROMSTAT_HPMAX] |
                ((unsigned int)st[ENROMSTAT_HPMAX + 1] << 8);
    }

    if (*pa & AIL_SLEEP) {
        res = txt_sleeping;
        if ((unsigned int)rand_ax(0, 0x50) < hpmax) {
            *pa &= (unsigned char)~AIL_SLEEP;
            res = txt_wokeup;
        }
    } else if (*pa & AIL_STUN) {
        unsigned char r = svc_battle_rng();
        unsigned char freed;
        // Niente `&&` dentro un `?:` e nemmeno un `?:` che decida su due
        // confronti diversi: sccz80 lo compila sul carry dell'ultimo, ed e' la
        // trappola che e' costata una sessione intera ([[sccz80-ternary-and-trap]]).
        if (is_chr) freed = (unsigned char)((r & 3) == 0);
        else        freed = (unsigned char)(r < 25);
        res = txt_paralyzed;
        if (freed) {
            *pa &= (unsigned char)~AIL_STUN;
            res = txt_cured;
        }
    } else {
        res = txt_confused;
        if (svc_battle_rng() < 0x40) {
            *pa &= (unsigned char)~AIL_CONF;
            res = txt_cured;
        }
    }

    k = msg_name(msg, 0, name);
    k = msg_lit(msg, k, res);
    msg[k] = 0;
    render_message(msg);
    wait_frames(45);
}

// =====================================================================
//  Il lancio dalla parte dei MOSTRI (slice60, traslocato qui in slice69)
// =====================================================================
// Stava nell'overlay di battaglia e adesso sta accanto al suo gemello. La
// ragione lunga e' nell'intestazione di ovl_battle.c; quella corta e' che erano
// due copie dello stesso motore e con le alterazioni sarebbero diventate
// quattro.
//
// Cosa NON si fa qui, e non per pigrizia: il lampeggio della sagoma colpita e
// la sagoma da spegnere quando qualcuno cade. Chi sa dove stanno le sagome e'
// l'altro overlay, e resta l'unico a saperlo. Quindi si restituisce la MASCHERA
// di chi e' stato toccato e a farla vedere pensa lui.

// Bersaglio di un mostro, con la distribuzione FRONTALE del NES
// (`GetRandomPlayerTarget`, bank_0C.asm:6997): 4/8 al primo, 2/8 al secondo,
// 1/8 al terzo, 1/8 al quarto. E' la ragione per cui in FF1 il guerriero si
// mette in cima alla lista, cioe' una regola che il giocatore conosce.
// Il ciclo e' limitato e il NES no: un gruppo tutto a terra lo farebbe girare
// per sempre, e su Coleco un ciclo infinito e' una console da spegnere.
static int random_player_target(void) {
    int tries, i;
    for (tries = 0; tries < 64; tries++) {
        unsigned char r = svc_battle_rng();
        int t = 0;
        if (r < 0x20) t++;
        if (r < 0x40) t++;
        if (r < 0x80) t++;
        if (t < (int)PARTY.n) { if (!(PARTY.chr[t].ailments & AIL_OUT)) return t; }
    }
    for (i = 0; i < (int)PARTY.n; i++) {
        if (!(PARTY.chr[i].ailments & AIL_OUT)) return i;
    }
    return -1;
}

// Danno di un incantesimo contro UN personaggio. Rispetto alla gemella verso i
// mostri manca il ramo della DEBOLEZZA elementale, e non per semplificare: un
// personaggio non ne ha, `btlch_elemweak` e' forzato a zero
// (bank_0C.asm:5668). La resistenza invece c'e' e viene dall'armatura.
static unsigned int magic_damage_on_chr(const unsigned char *sp, int who) {
    chr_t *c = &PARTY.chr[who];
    int base   = (int)sp[MAG_POWER];
    int chance = 148;
    unsigned int dmg;

    // La resistenza si legge dal blocco IB e non da PARTY (slice70): li' ci
    // sono anche quelle che AFIR e WALL hanno acceso in questa battaglia, e
    // che alla fine spariranno. Il valore di partenza e' comunque quello
    // dell'armatura -- lo copia la preparazione.
    if (sp[MAG_ELEMENT] & IBC(who).resist) {
        chance = 0;
        base >>= 1;
    }
    chance += (int)sp[MAG_HITRATE] - (int)c->magdef;

    dmg = (unsigned int)base +
          (unsigned int)rand_ax(0, (unsigned char)((base > 255) ? 255 : base));
    if (magic_roll(chance)) dmg <<= 1;
    return dmg;
}

// L'alterazione addosso a un personaggio: la gemella di inflict_on_enemy, senza
// il ramo della debolezza per lo stesso motivo di qui sopra.
static int inflict_on_chr(const unsigned char *sp, int who) {
    chr_t *c = &PARTY.chr[who];
    unsigned char m = sp[MAG_POWER];

    if (sp[MAG_EFFECT] == MAGEFF_AILMENT2) {
        if (sp[MAG_ELEMENT] & IBC(who).resist) return 0;
        if (c->curhp >= 300) return 0;
    } else {
        int chance = 148;
        if (sp[MAG_ELEMENT] & IBC(who).resist) chance = 0;
        chance += (int)sp[MAG_HITRATE] - (int)c->magdef;
        if (!magic_roll(chance)) return 0;
    }

    if (c->ailments & m) { render_message(txt_ineff); wait_frames(30); }
    c->ailments |= m;
    BST.ail_set++;
    BST.ail_last = m;
    // La morte azzera gli HP, la PIETRA no: chi e' di pietra e' fuori dalla
    // battaglia ma i suoi HP sono ancora suoi, e li ritrovera' quando qualcuno
    // gli tirera' addosso una SOFT. Chi decide se e' fuori e' la maschera
    // AIL_OUT, ed e' per questo che l'overlay di battaglia ha smesso di contare
    // i vivi guardando gli HP.
    if (m & AIL_DEAD) c->curhp = 0;
    return 1;
}

static void report_down(const char *who) {
    char msg[26];
    int k = msg_name(msg, 0, who);
    k = msg_lit(msg, k, txt_dies);
    msg[k] = 0;
    render_message(msg);
    wait_frames(45);
}

static unsigned int run_enemy_cast(unsigned char slot) {
    unsigned char sp[MAG_STAT_SIZE];
    unsigned char eff;
    unsigned int mask = 0;
    char msg[26];
    int k, i, first, last;

    // L'id dell'incantesimo arriva da `last_spell`, che il banco 20 ha appena
    // scritto: nell'argomento di svc_run_overlay c'e' posto per un byte solo e
    // quel byte serve allo slot.
    fetch_spell(BST.last_spell, sp);
    patch_spell(BST.last_spell, sp);
    eff = sp[MAG_EFFECT];

    k = msg_name(msg, 0, BST.type_name[BST.enemy_type[slot]]);
    k = msg_lit(msg, k, " CASTS");
    msg[k] = 0;
    render_message(msg);
    wait_frames(30);

    // IL POTENZIAMENTO SU SE STESSO (slice70). E' l'unico caso di
    // mostro-su-mostro che si puo' scrivere oggi, e non e' un ripiego: la
    // maschera dei bersagli dice "chi lancia", quindi il bersaglio e' noto
    // senza bisogno di scegliere, e il blocco IB del mostro c'e' gia'. Restano
    // fuori le cure fra mostri, che vorrebbero un bersaglio scelto fra i
    // compagni -- e per quelle serve il cursore che oggi punta solo il gruppo.
    if (IS_BUFF_EFFECT(eff)) {
        if (sp[MAG_TARGET] & MAGTGT_CASTER) {
            if (stat_effect(&IBE(slot), eff, sp[MAG_POWER])) {
                BST.buff_set++;
                BST.buff_last = eff;
                wait_frames(30);
                return 0;
            }
        }
        render_message(txt_nothing);
        wait_frames(45);
        return 0;
    }

    if (eff != MAGEFF_DAMAGE && eff != MAGEFF_AILMENT &&
        eff != MAGEFF_AILMENT2 && !IS_DEBUFF_EFFECT(eff)) {
        render_message(txt_nothing);
        wait_frames(45);
        return 0;
    }

    // La maschera dei bersagli e' scritta dal punto di vista di CHI LANCIA:
    // per un mostro "tutti i nemici" e' tutto il gruppo.
    if (sp[MAG_TARGET] & MAGTGT_ALL_FOES) {
        first = 0;
        last  = (int)PARTY.n - 1;
    } else if (sp[MAG_TARGET] & MAGTGT_ONE_FOE) {
        first = random_player_target();
        if (first < 0) return 0;
        last = first;
    } else {
        /* Bersaglio dalla parte di chi lancia, ma non un potenziamento: sono le
           cure fra mostri, che vogliono un compagno scelto. */
        render_message(txt_nothing);
        wait_frames(45);
        return 0;
    }

    for (i = first; i <= last; i++) {
        chr_t *c = &PARTY.chr[i];
        if (c->ailments & AIL_OUT) continue;

        if (eff == MAGEFF_DAMAGE) {
            unsigned int dmg = magic_damage_on_chr(sp, i);
            if (dmg >= c->curhp) { c->curhp = 0; c->ailments |= AIL_DEAD; }
            else                 { c->curhp -= dmg; }
            ov_u3(21, MAG_ROW_MSG, (dmg > 999) ? 999 : dmg);
        } else if (IS_DEBUFF_EFFECT(eff)) {
            // Un indebolimento su un personaggio: stesso tiro delle
            // alterazioni, che di qua non ha ne' debolezza ne' bonus da INT.
            int chance = 148;
            if (sp[MAG_ELEMENT] & IBC(i).resist) chance = 0;
            chance += (int)sp[MAG_HITRATE] - (int)c->magdef;
            if (!magic_roll(chance)) continue;
            if (!stat_effect(&IBC(i), eff, sp[MAG_POWER])) continue;
            BST.buff_set++;
            BST.buff_last = eff;
        } else if (!inflict_on_chr(sp, i)) {
            continue;                   /* non ha morso: niente lampeggio */
        }

        mask |= (unsigned int)1 << i;
        if (c->ailments & AIL_OUT) report_down(c->name);
    }
    wait_frames(30);
    return mask;
}

// =====================================================================
//  LE RICOMPENSE (slice76): EXP, oro, livelli
// =====================================================================
// Arrivati qui da `svc_award_exp`, che stava nella finestra fissa: insieme a
// `level_up_one` erano **1539 byte** per girare una volta per battaglia vinta.
// E' la leva 1 di [[fixed-window-full]], la stessa diagnosi di slice62 e
// slice72 -- si sposta cio' che costa sempre e serve di rado.
//
// LA COSA CHE DOVEVA RESTARE DI LA', e non e' il codice: le tre tabelle dei
// livelli stanno nel banco 11, che un overlay non mappa. Le porta
// `svc_fetch_btl` con le tabelle 9, 10 e 11 -- tre `else if` invece dei ~166
// byte di una svc_ nuova ([[svc-generalize-rule]], quinta volta).
//
// SI PRENDE UNA RIGA ALLA VOLTA, non la tabella intera: la voce di livello e'
// di 2 byte, la soglia di EXP di 3, i due bonus di 1. Copiare le tabelle
// complete (1176 byte di lut_LevelUpData) vorrebbe dire un buffer in RAM piu'
// grande di tutto il blocco del gruppo, per leggerne quattro.
#define BTLTAB_EXPADV   5
#define BTLTAB_LVLDATA  9
#define BTLTAB_HITB    10
#define BTLTAB_MAGDEFB 11

// Aritmetica a 3 byte little-endian: EXP e oro di FF1 arrivano a 999999, che
// in 16 bit non ci sta. Copie di quelle che stavano nella slice -- i banchi
// non si vedono fra loro, quindi condividerle non e' possibile nemmeno
// volendo.
static void add24_u16(unsigned char *v, unsigned int amount) {
    unsigned int t;
    t = (unsigned int)v[0] + (amount & 0x00FF);
    v[0] = (unsigned char)t;
    t = (unsigned int)v[1] + ((amount >> 8) & 0x00FF) + (t >> 8);
    v[1] = (unsigned char)t;
    t = (unsigned int)v[2] + (t >> 8);
    v[2] = (unsigned char)t;
}
static int ge24(const unsigned char *a, const unsigned char *b) {
    if (a[2] != b[2]) return a[2] > b[2];
    if (a[1] != b[1]) return a[1] > b[1];
    return a[0] >= b[0];
}

// Un passaggio di livello, ricalcando LvlUp_LevelUp (bank_0B.asm:852).
static void level_up_one(unsigned char i) {
    chr_t *c = &PARTY.chr[i];   /* il puntatore una volta sola */
    unsigned char cls   = c->cls;
    unsigned char oldlv = c->level;     // 1-based
    unsigned char ld[LVLUP_REC];
    unsigned char bonus;
    unsigned char sb, mpbits, hpgain, k;
    unsigned char up_str = 0, up_agl = 0;
    unsigned int t;

    if (oldlv >= LVLUP_MAX_LEVEL) return;
    c->level = (unsigned char)(oldlv + 1);

    // La voce e' indicizzata dal livello VECCHIO 0-based.
    svc_fetch_btl(BTLTAB_LVLDATA,
                  ((unsigned int)cls * LVLUP_N_LEVELS + (oldlv - 1)) * LVLUP_REC,
                  LVLUP_REC, ld);
    sb     = ld[0];
    mpbits = ld[1];

    // LE BASE, non gli effettivi (slice65). Se il livello facesse crescere il
    // valore che contiene gia' i bonus dell'equipaggiamento, il ricalcolo
    // successivo ripartirebbe da una base gonfiata e il bonus dell'arma
    // resterebbe dentro per sempre, a ogni livello un po' di piu'.
    svc_fetch_btl(BTLTAB_HITB, cls, 1, &bonus);
    t = (unsigned int)c->hitrate_b + bonus;
    c->hitrate_b = (unsigned char)((t > 200) ? 200 : t);
    svc_fetch_btl(BTLTAB_MAGDEFB, cls, 1, &bonus);
    t = (unsigned int)c->magdef + bonus;
    c->magdef  = (unsigned char)((t > 200) ? 200 : t);

    // Cariche di magia: mai a guerriero e ladro. Sul NES il controllo e' sulla
    // classe e non sui dati, perche' cavaliere e ninja condividono le tabelle
    // di guerriero e ladro ma la magia ce l'hanno.
    if (cls != CLS_FT && cls != CLS_TH) {
        for (k = 0; k < PARTY_SPELL_LEVELS; k++) {
            if (mpbits & (unsigned char)(1 << k)) {
                if (c->maxmp[k] < 9) c->maxmp[k]++;
            }
        }
    }

    // HP: vitalita'/4 + 1, piu' rand[20,25] se il livello e' "forte".
    hpgain = (unsigned char)((c->vit >> 2) + 1);
    if (sb & LVLUP_STRONG) hpgain = (unsigned char)(hpgain + 20 + (svc_battle_rng() % 6));
    c->maxhp += hpgain;
    c->curhp += hpgain;

    // Le 5 statistiche base, nell'ordine in cui le scorre il NES: forza,
    // agilita', intelligenza, vitalita', fortuna. Bit acceso = aumento certo,
    // altrimenti 25%.
    for (k = 0; k < 5; k++) {
        unsigned char mask = (unsigned char)(LVLUP_STR >> k);   // 10 08 04 02 01
        unsigned char inc  = (sb & mask) ? 1 : (unsigned char)(((svc_battle_rng() & 3) == 0) ? 1 : 0);
        unsigned char *p;
        if (!inc) continue;
        switch (k) {
            case 0:  p = &c->str;      break;
            case 1:  p = &c->agil;     break;
            case 2:  p = &c->int_stat; break;
            case 3:  p = &c->vit;      break;
            default: p = &c->luck;     break;
        }
        // Il NES scarta l'aumento se il risultato e' esattamente 100: di fatto
        // il tetto e' 99. Preservato.
        if ((unsigned int)(*p) + 1 == 100) continue;
        (*p)++;
        if (k == 0) up_str = 1;
        if (k == 1) up_agl = 1;
    }

    // Sotto-statistiche: danno +1 ogni 2 punti di forza (cioe' quando la forza
    // arriva a un numero pari), schivata +1 se e' salita l'agilita'.
    if (up_str && ((c->str & 1) == 0)) {
        if (c->dmg_b < 200) c->dmg_b++;
    }
    if (up_agl) {
        if (c->evade_b < 200) c->evade_b++;
    }
    // NON implementato: LvlUp_AdjustBBSubStats, la regola speciale di danno e
    // assorbimento del monaco a mani nude. Va scritta guardando quella
    // routine, non indovinata: per ora un monaco sale di livello come gli
    // altri e i suoi sotto-valori a mani nude restano indietro.
}

// Assegna il bottino di BST.exp_total / BST.gp_total e fa salire di livello.
// Ingresso e uscita passano dal blocco di battaglia, com'era quando stava
// nella finestra fissa: l'overlay di battaglia non si accorge del trasloco se
// non per la riga con cui ci arriva.
static void award_exp(void) {
    unsigned char i;
    int survivors = 0;
    unsigned int exp_each;
    unsigned char thr[3];

    // Vale la regola del NES: chi e' morto o pietrificato non prende niente.
    // Avvelenato si'.
    for (i = 0; i < PARTY_N; i++) {
        unsigned char ail = (unsigned char)(PARTY.chr[i].ailments & 0x03);
        BST.new_level[i] = 0;
        if (ail == 0 || ail == 3) survivors++;
    }
    if (survivors == 0) { BST.exp_award = 0; BST.gp_award = 0; return; }

    // Gli EXP si dividono fra i superstiti, l'oro no. Minimo 1 EXP a testa.
    exp_each = BST.exp_total / (unsigned int)survivors;
    if (exp_each == 0) exp_each = 1;

    add24_u16(PARTY.gp, BST.gp_total);

    for (i = 0; i < PARTY_N; i++) {
        // Il puntatore una volta sola, come in equip_recalc: il passo della
        // voce e' 79 e sccz80 lo moltiplica chiamando una routine, quindi ogni
        // `PARTY.chr[i].campo` in piu' e' una chiamata in piu'.
        chr_t *c = &PARTY.chr[i];
        unsigned char ail = (unsigned char)(c->ailments & 0x03);
        if (ail != 0 && ail != 3) continue;
        add24_u16(c->exp, exp_each);
        // DEVIAZIONE VOLUTA dal NES: qui si sale di TUTTI i livelli che gli
        // EXP consentono, non di uno solo. E' uno dei fix decisi nel digest
        // AstralEsper (memory/ff1_engine_intent_priorities.md): sul NES, se un
        // colpo di fortuna ti dava EXP per due livelli, il secondo andava
        // perso fino alla battaglia dopo.
        while (c->level < LVLUP_MAX_LEVEL) {
            svc_fetch_btl(BTLTAB_EXPADV, ((unsigned int)c->level - 1) * 3, 3, thr);
            if (!ge24(c->exp, thr)) break;
            level_up_one(i);
            BST.new_level[i] = c->level;
        }
    }

    // equip_recalc DOPO tutti i livelli, non dentro il ciclo: mappa il banco 16
    // per conto suo e rimette quello che trova all'ingresso, che qui e' il 23.
    for (i = 0; i < PARTY_N; i++) {
        if (BST.new_level[i]) svc_equip_recalc(i);
    }

    BST.exp_award = exp_each;
    BST.gp_award  = BST.gp_total;
}

// ---------------------------------------------------------------------
//  Ingresso: il primo byte del banco 23 e' `jp _overlay_main` ($C000).
// ---------------------------------------------------------------------
unsigned int overlay_main(unsigned int arg) {
    unsigned char who  = (unsigned char)(arg & 0x00FF);
    unsigned int  mode = arg & 0xFF00;

    if (mode == BTLMAG_MODE_CAST)      { cast_spell(who); return 0; }
    if (mode == BTLMAG_MODE_AILTURN)   { ail_turn(who);   return 0; }
    if (mode == BTLMAG_MODE_ENEMYCAST) return run_enemy_cast(who);
    if (mode == BTLMAG_MODE_AWARDEXP)  { award_exp();      return 0; }
    if (mode == BTLMAG_MODE_SETUP) {
        decode_formation();
        load_enemy_info();
        return 0;
    }
    return run_select(who);
}
