// =====================================================================
//  ovl_menu.c -- il menu, overlay di CODICE (banco 24)
// =====================================================================
// QUINTO overlay del progetto. Ci si entra con FIRE2 dall'overworld e dalla
// citta', con `svc_run_overlay(MENU_BANK, in_citta')`.
//
// COSA FA (slice74)
//   ITEM     lo zaino si apre e si usa: tenda, capanna e casa rimettono in
//            piedi il gruppo, pozione, antidoto e ammorbidente curano UNO
//   MAGIC    le tredici magie di fuori battaglia -- nel banco 25 (slice75)
//   WEAPON   l'equipaggiamento manuale: indossa, scambia, butta via
//   ARMOR    la stessa schermata, con l'altra meta' delle caselle
//   STATUS   tutte le statistiche di un personaggio, INT compreso
//
// PERCHE' STATUS E' LA META' IMPORTANTE. Da slice59 INT decide l'accuratezza
// della magia e da slice54 i livelli fanno crescere i numeri con tiri casuali:
// due cose che non avevano nessun posto dove guardarsi. La battaglia mostra
// gli HP, la scelta dei personaggi mostra i valori di partenza -- che dopo il
// primo livello sono gia' scaduti. Una statistica che nessuno puo' leggere e
// una statistica che non esiste si somigliano troppo.
//
// -- le tre regole dell'overlay, e come sono rispettate qui --------------
//
// 1. NIENTE mc_select_bank: l'overlay E' il banco 24. I nomi degli oggetti
//    stanno nel banco 16 e la curva degli EXP nell'11, e nessuno dei due si
//    vede da qui: li portano `svc_fetch_btl` (tabella 4 e tabella 5), che quei
//    banchi li mappa e li rimette. Nessuna svc_ nuova -- e' la regola di
//    slice67, alla terza applicazione.
//
// 2. IL GRUPPO SI LEGGE E SI SCRIVE DIRETTAMENTE. `PARTY` sta in RAM SGM, che
//    non dipende dal banco: HP, MP, alterazioni e zaino si toccano da qui.
//
// 3. NIENTE INIZIALIZZATORI, nemmeno su uno scalare. La DATA di un overlay non
//    viene MAI inizializzata: `static unsigned char x = 1;` vale spazzatura.
//    I testi sono array 1-D con i NUL dentro (quella e' rodata, e la rodata
//    dell'overlay sta nel banco insieme al codice); i valori di partenza si
//    assegnano dentro le funzioni.
//
// PERCHE' UN BANCO SUO E NON IL 22 COL NEGOZIO. Il negozio ne ha 5861 liberi e
// oggi ci starebbe. Ma il menu deve ancora crescere di due sottoschermate --
// magia fuori battaglia ed equipaggiamento manuale -- e un banco costa 16KB su
// 512. Il vincolo non e' la ROM da slice45; e' il giorno in cui due scene
// nello stesso banco smettono di starci insieme.
//
// LE COORDINATE DELLO SCHERMO STANNO IN UN POSTO SOLO (i #define qui sotto).
// Il negozio le ha imparate a sue spese: una stringa scritta a colonna 26
// lunga 11 caratteri sborda nella riga dopo, perche' la name table non ha
// righe -- e' un nastro di 768 byte. Vedi txt_pack in ovl_shop.c.
// =====================================================================

#define SVC_OVERLAY
#include "svc_api.h"
#include "party_state.h"
#include "shop_state.h"       // SOLO CAN_EQUIP / CLASS_EQUIP_BIT (nessun dato)
#include "ff1_item_icons.h"   // FF1_ICON_FIRST / FF1_ICON_VALID / FF1_ICON_INDEX
#include "data/item_names.h"  // SOLO le macro dello spazio degli id (nessun dato)
// Anche questi due SENZA la guardia *_DEFINE_DATA: servono i soli conteggi
// (FF1_N_WEAPONS / FF1_N_ARMORS). Includerli con la guardia porterebbe 640
// byte di tabelle dentro l'overlay, e sarebbero la terza copia degli stessi
// numeri.
#include "data/weapon_data.h"
#include "data/armor_data.h"

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

#define BIOS_FONT_ADDR  ((const void*)0x15A3)
#define BIOS_FONT_LEN   760
#define FONT_TILE_BASE  0x20
#define ICON_TILE_BASE  0x10

// --- la pianta dello schermo, 32x24 ----------------------------------
#define ROW_TITLE    1
// Menu principale: le cinque voci a sinistra, il gruppo a destra.
#define ROW_CMD0     3      /* 3 5 7 9 11 */
#define COL_CMD      2
// PASSO 3 E NON 2, ed e' una correzione presa guardando lo schermo. Con due
// righe per personaggio e passo 2 gli otto righi sono ATTACCATI: nel font 8x8
// del BIOS non c'e' interlinea, e quattro coppie nome/HP di seguito si leggono
// come un blocco unico in cui non si vede dove finisce uno e comincia l'altro.
// Col passo 3 ogni coppia ha la sua riga vuota sotto -- 3/4, 6/7, 9/10, 12/13 --
// e le cinque voci dei comandi (righe 3 5 7 9 11, colonna 2) ci convivono
// perche' stanno dall'altra parte dello schermo.
#define ROW_PARTY0   3      /* 3-4  6-7  9-10  12-13 */
#define ROW_PARTY_STEP 3
#define COL_PARTY   14
#define COL_PARTY_CUR 13
#define ROW_GOLD    15
#define ROW_PROMPT  17
#define ROW_MSG     22
#define ROW_HINT    23

// Schermata delle statistiche.
#define ROW_ST_NAME   3
#define ROW_ST_CLASS  4
#define ROW_ST_HP     6
#define ROW_ST_EXP    7
#define ROW_ST_NEXT   8
#define ROW_ST_STAT0 10     /* STR AGL INT VIT LUCK, e a destra le derivate */
#define ROW_ST_MP    16
#define ROW_ST_WEAP  19
#define ROW_ST_ARM   21

// Schermata dello zaino: due colonne di dodici. Ventiquattro caselle contro i
// 23 oggetti diversi che FF1 permette di avere addosso tutti insieme (17
// chiave piu' 6 consumabili): ci stanno, ma di UNA sola -- se un giorno lo
// spazio degli id crescesse, questa e' la riga da rileggere.
#define ROW_IT0       3
#define IT_PER_COL   12
#define ROW_IT_PARTY 16     /* i quattro personaggi, per scegliere il bersaglio */

// Schermata WEAPON / ARMOR. TUTTO IL GRUPPO INSIEME, non un personaggio alla
// volta: e' cosi' anche sul NES (CopyEquipToItemBox copia le SEDICI caselle,
// quattro per testa, e `cursor` e' `personaggio*4 + casella`), ed e' l'unica
// forma in cui lo scambio fra due personaggi si puo' vedere mentre si fa.
//
// Un blocco per personaggio: riga di intestazione, poi due righe da due
// caselle. Sedici colonne per casella -- cursore, asterisco, sette lettere di
// nome -- e ne restano sette di margine, che e' quanto serve perche' un nome
// lungo non finisca nella riga dopo (la name table e' un nastro: vedi txt_pack
// in ovl_shop.c).
#define ROW_EQ_MODE   3
#define ROW_EQ0       5     /* 5 9 13 17: quattro blocchi da quattro righe */
#define ROW_EQ_STEP   4
#define COL_EQ_MODE0  2     /* EQUIP / TRADE / DROP, dieci colonne di passo */
#define EQ_MODE_STEP 10
#define EQ_MODE_EQUIP 0
#define EQ_MODE_TRADE 1
#define EQ_MODE_DROP  2
#define EQ_NONE     0xFF

// Il banco della magia fuori battaglia (slice75). Cablato QUI e non passato:
// un overlay che ne chiama un altro deve saperne il numero, e l'unica
// alternativa -- farselo dare dalla slice nell'argomento -- sarebbe un secondo
// posto in cui lo stesso numero puo' diventare sbagliato.
#define MAGIC_BANK 25

#define N_CMD  5
#define CMD_ITEM   0
#define CMD_MAGIC  1
#define CMD_WEAPON 2
#define CMD_ARMOR  3
#define CMD_STATUS 4

static const char txt_title[]  = "MENU";
static const char txt_cmds[]   = "ITEM\0MAGIC\0WEAPON\0ARMOR\0STATUS";
static const char txt_gold[]   = "GOLD";
static const char txt_gp[]     = "GP";
static const char txt_soon[]   = "NOT YET";
static const char txt_choose[] = "WHAT NOW?";
static const char txt_who[]    = "WHO?";
static const char txt_hint_main[] = "FIRE1 OK     FIRE2 CLOSE";
static const char txt_hint_who[]  = "FIRE1 OK     FIRE2 BACK";
static const char txt_hint_use[]  = "FIRE1 USE    FIRE2 BACK";
static const char txt_hint_back[] = "FIRE2: BACK";

static const char txt_status[]  = "STATUS";
static const char txt_lv[]      = "LV";
static const char txt_hp[]      = "HP";
static const char txt_exp[]     = "EXP";
static const char txt_next[]    = "NEXT";
static const char txt_mp[]      = "MP";
static const char txt_weapon[]  = "WEAPON";
static const char txt_armor[]   = "ARMOR";
static const char txt_maxlv[]   = "MAX";
// Le cinque base e le cinque derivate, incolonnate. Le derivate a destra
// perche' vengono DALLE prime piu' l'equipaggiamento: leggerle accanto e' il
// modo in cui la schermata spiega da sola che INT non e' un numero decorativo.
static const char txt_base[]    = "STR\0AGL\0INT\0VIT\0LUCK";
static const char txt_deriv[]   = "DAMAGE\0HIT %\0ABSORB\0EVADE %\0M.DEF";
// I dodici nomi di classe per esteso. Le sei promosse ci sono gia' perche'
// il cambio di classe e' deciso da slice59 e i suoi id (`ch_class += 6`) sono
// gia' quelli veri: una tabella che si ferma a sei mostrerebbe "FIGHTER" a un
// cavaliere il giorno che la promozione arriva.
static const char txt_classes[] =
    "FIGHTER\0THIEF\0BLACK BELT\0RED MAGE\0WHITE MAGE\0BLACK MAGE\0"
    "KNIGHT\0NINJA\0MASTER\0RED WIZARD\0WHITE WIZARD\0BLACK WIZARD";
// Le stesse in due lettere, per la striscia del gruppo. Sono l'abbreviazione
// che il progetto usa gia' negli script di validazione.
static const char txt_cls2[] = "FTTHBBRMWMBMKNNJMARWWWBW";

static const char txt_item[]    = "ITEM";
static const char txt_empty[]   = "THE PACK IS EMPTY";
static const char txt_nouse[]   = "IT HAS NO USE HERE";
static const char txt_nothere[] = "NOT INSIDE A TOWN";
static const char txt_rested[]  = "THE PARTY RESTS";
static const char txt_healed[]  = "FEELING BETTER!";
static const char txt_cured[]   = "THE POISON IS GONE";
static const char txt_soften[]  = "THE STONE CRUMBLES";
static const char txt_noneed[]  = "THAT ONE DOESN'T NEED IT";
// I tre modi del NES, nello stesso ordine (eq_modecurs 0/1/2).
static const char txt_eq_modes[]  = "EQUIP\0TRADE\0DROP";
static const char txt_hint_eq[]   = "1EQ 2TRADE 3DROP  F2 BACK";
static const char txt_eq_empty[]  = "NOTHING IN THAT SLOT";
static const char txt_eq_cannot[] = "THAT CLASS CANNOT USE IT";
static const char txt_eq_worn[]   = "NOW EQUIPPED";
static const char txt_eq_off[]    = "PUT AWAY";
static const char txt_eq_pick[]   = "NOW PICK THE OTHER SLOT";
static const char txt_eq_traded[] = "SWAPPED";
static const char txt_eq_ask[]    = "THROW IT AWAY? FIRE1 = YES";
static const char txt_eq_gone[]   = "GONE FOR GOOD";

static const char txt_dead[]    = "DEAD";
static const char txt_stone[]   = "STON";
static const char txt_pois[]    = "PSN";

// =====================================================================
//  Primitive di schermo
// =====================================================================
// Copiate da ovl_shop.c e non condivise: un file .h di helper linkato in due
// overlay diversi finirebbe DUE VOLTE in ROM comunque (i banchi non si vedono
// fra loro), e in cambio farebbe credere che esista un modulo comune.
static unsigned char prev_bits, prev_key;

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

static void clear_span(unsigned char col, unsigned char row, unsigned char n) {
    svc_vfill(0x1800 + (unsigned int)row * 32 + col, 0x20, n);
}

// Un numero a 16 bit, senza zeri iniziali, allineato a DESTRA di `col`.
static void render_num_right(unsigned char col, unsigned char row, unsigned int v) {
    unsigned char buf[6];
    int n = 0, k;
    if (v == 0) { buf[0] = '0'; n = 1; }
    while (v > 0 && n < 6) { buf[n] = (unsigned char)('0' + (v % 10)); v /= 10; n++; }
    for (k = 0; k < n; k++) {
        svc_vwrite(&buf[k], 0x1800 + (unsigned int)row * 32 + col - k, 1);
    }
}

// Un numero a 24 BIT, che serve davvero: gli EXP di FF1 arrivano a 989641 e
// l'oro a 999999, e nessuno dei due sta in una parola. Il negozio se la cava
// stampando i 16 bit bassi -- a Coneria non capita altro -- ma la riga EXP
// diventerebbe sbagliata a meta' gioco, cioe' proprio quando qualcuno la
// guarda per decidere qualcosa.
//
// Divisione lunga in base 256, dal byte alto: il resto parziale non supera 9,
// quindi `r * 256 + byte` sta comodo in una parola (2559 al massimo) e non
// serve nessuna aritmetica a piu' cifre oltre a questa.
static void render_num24_right(unsigned char col, unsigned char row,
                               const unsigned char *v) {
    unsigned char a2 = v[2], a1 = v[1], a0 = v[0];
    unsigned char buf[8];
    unsigned char n = 0;
    unsigned int t, r;
    do {
        r = 0;
        t = (unsigned int)a2;          r = t % 10; a2 = (unsigned char)(t / 10);
        t = (unsigned int)(r * 256 + a1); r = t % 10; a1 = (unsigned char)(t / 10);
        t = (unsigned int)(r * 256 + a0); r = t % 10; a0 = (unsigned char)(t / 10);
        buf[n] = (unsigned char)('0' + r);
        n++;
    } while ((a0 | a1 | a2) != 0 && n < 8);
    {
        unsigned char k;
        for (k = 0; k < n; k++) {
            svc_vwrite(&buf[k], 0x1800 + (unsigned int)row * 32 + col - k, 1);
        }
    }
}

// NON scrivere `ch = (on && i == sel) ? '>' : ' ';` -- sccz80 lo compila
// SBAGLIATO: decide col carry dell'ultimo confronto invece che col valore.
// La spiegazione per esteso sta su draw_cursor in ovl_shop.c, dove e' costata
// mezz'ora di ricerca nel disegno invece che nella logica.
static void draw_cursor(unsigned char col, unsigned char row0, unsigned char step,
                        unsigned char n, unsigned char sel, unsigned char on) {
    unsigned char i, ch;
    for (i = 0; i < n; i++) {
        ch = ' ';
        if (on) {
            if (i == sel) ch = '>';
        }
        render_tile(col, (unsigned char)(row0 + i * step), ch);
    }
}

static unsigned int read_edge(void) {
    unsigned int j;
    unsigned char bits, key, ebits, ekey;
    svc_wait_vblank();
    j    = svc_joystick();
    bits = (unsigned char)(j & 0x00FF);
    key  = (unsigned char)(j >> 8);
    ebits = (unsigned char)(bits & ~prev_bits);
    ekey = 0;
    if (key != 0) {
        if (key != prev_key) ekey = key;
    }
    prev_bits = bits;
    prev_key  = key;
    return (unsigned int)ebits | ((unsigned int)ekey << 8);
}

static void draw_msg(const char *s) {
    clear_row(ROW_MSG);
    if (s) render_string(1, ROW_MSG, s);
}

static void draw_prompt(const char *s) {
    clear_row(ROW_PROMPT);
    if (s) render_string(1, ROW_PROMPT, s);
}

static void draw_hint(const char *s) {
    clear_row(ROW_HINT);
    render_string(1, ROW_HINT, s);
}

static void load_menu_screen(void) {
    unsigned char i;
    svc_border(INK_DARK_BLUE);
    svc_vfill(0x0000, 0, 6144);
    svc_vwrite(BIOS_FONT_ADDR, 0x0000 + (FONT_TILE_BASE * 8), BIOS_FONT_LEN);
    svc_vwrite(BIOS_FONT_ADDR, 0x0800 + (FONT_TILE_BASE * 8), BIOS_FONT_LEN);
    svc_vwrite(BIOS_FONT_ADDR, 0x1000 + (FONT_TILE_BASE * 8), BIOS_FONT_LEN);
    // Le icone di TIPO servono anche qui: senza, le statistiche mostrerebbero
    // "Wooden" e "Wooden" fra le armi e cinque "Opal" fra le armature. E' lo
    // stesso motivo per cui esistono nel negozio, e la stessa svc_.
    svc_shop_load_icons(ICON_TILE_BASE);
    svc_vfill(0x2000, 0xF4, 6144);   // bianco su blu scuro ovunque
    svc_vfill(0x1800, 0x20, 768);
    // TUTTI E QUATTRO gli sprite del mapman: in citta' e in overworld il
    // personaggio e' fatto di quattro strati sovrapposti, e spegnerne uno solo
    // lascia tre quarti di eroe in mezzo al menu.
    for (i = 0; i < 4; i++) svc_put_sprite16(i, 0, 200, 0, 0);
}

// =====================================================================
//  Nomi degli oggetti: dal banco 16, otto byte per volta
// =====================================================================
// Il 7o byte del nome nel ROM e' un'ICONA di tipo, non una lettera. Senza, due
// voci della stessa lista si leggono identiche -- e' il motivo per cui le icone
// esistono (slice65), e nell'equipaggiamento e' peggio che nel negozio: li'
// "Iron" e "Iron" sono un'armatura e un elmo, e stanno nella stessa griglia.
//
// L'ICONA NON STA DENTRO IL NOME, e questa riga e' una correzione di slice74.
// Fin qui questa funzione la cercava fra gli otto byte con FF1_ICON_VALID --
// che e' giusto per il ROM e sbagliato per noi: `tools/extract_item_names.ps1`
// la sostituisce con uno spazio e la mette in una tabella a parte
// (`ff1_item_icon`, un byte per id). Il ciclo quindi non trovava mai niente e
// il menu non ha mai mostrato una sola icona. Non si vedeva perche' gli unici
// nomi che elencava -- i sei consumabili dello zaino -- sono tutti diversi fra
// loro: il difetto era invisibile finche' non e' arrivata la lista in cui due
// voci si chiamano uguale.
static unsigned char nm_buf[FF1_ITEM_NAME_LEN];

static unsigned char fetch_name(unsigned char id) {
    unsigned char icon;
    svc_fetch_btl(4, ((unsigned int)id) << 3, FF1_ITEM_NAME_LEN, nm_buf);
    // Il nome nel ROM non e' terminato dentro gli otto byte quando riempie
    // tutti e sette i caratteri: il terminatore lo mettiamo noi in coda.
    nm_buf[FF1_ITEM_NAME_LEN - 1] = 0;
    svc_fetch_btl(8, (unsigned int)id, 1, &icon);
    return icon;
}

// Nome a `col`, e l'icona subito prima. Torna niente: chi chiama sa gia' dove
// ha scritto.
static void draw_item_name(unsigned char col, unsigned char row, unsigned char id) {
    unsigned char icon = fetch_name(id);
    render_string(col, row, (const char *)nm_buf);
    if (FF1_ICON_VALID(icon)) {
        render_tile((unsigned char)(col - 1), row,
                    (unsigned char)(ICON_TILE_BASE + FF1_ICON_INDEX(icon)));
    }
}

// =====================================================================
//  L'oro del gruppo
// =====================================================================
static void draw_gold(void) {
    clear_row(ROW_GOLD);
    render_string(1, ROW_GOLD, txt_gold);
    render_num24_right(12, ROW_GOLD, PARTY.gp);
    render_string(14, ROW_GOLD, txt_gp);
}

// =====================================================================
//  La striscia del gruppo
// =====================================================================
// Il TAG delle alterazioni non e' un abbellimento: e' l'unica cosa che
// distingue "la pozione non ha funzionato" da "su un morto non funziona", e
// senza di essa il rifiuto sembrerebbe un difetto.
static void draw_ail_tag(unsigned char col, unsigned char row, unsigned char ail) {
    clear_span(col, row, 4);
    if (ail & AIL_DEAD)       render_string(col, row, txt_dead);
    else if (ail & AIL_STONE) render_string(col, row, txt_stone);
    else if (ail & AIL_POISON) render_string(col, row, txt_pois);
}

// La sigla di due lettere si stampa CARATTERE PER CARATTERE, non con
// render_string: `txt_cls2` e' una stringa unica senza NUL in mezzo, e
// puntarci dentro stamperebbe da li' fino alla fine -- ventiquattro lettere
// dove ce ne stanno due. Ventiquattro NUL in piu' per farla funzionare con
// render_string costerebbero il doppio della tabella.
static void draw_cls2(unsigned char col, unsigned char row, unsigned char cls) {
    unsigned int o = (unsigned int)cls * 2;
    render_tile(col,       row, (unsigned char)txt_cls2[o]);
    render_tile((unsigned char)(col + 1), row, (unsigned char)txt_cls2[o + 1]);
}

// `two_rows` = 1 nel menu principale (nome/classe/livello sopra, HP sotto),
// 0 nella schermata dello zaino, dove la striscia serve a scegliere un
// bersaglio e una riga per personaggio basta.
//
// LE COLONNE SONO CONTATE DA `col` E ARRIVANO AL LIMITE. Nel menu principale
// `col` vale 14 e l'ultimo campo finisce alla 31: una riga in piu' di quelle
// che ci sono e la scritta ricomincerebbe dalla colonna 0 della riga dopo, che
// e' come si presenta il traboccamento della name table (vedi ovl_shop.c).
static void draw_party_strip(unsigned char col, unsigned char row0,
                             unsigned char step, unsigned char two_rows) {
    unsigned char i, row;
    for (i = 0; i < PARTY.n; i++) {
        chr_t *c = &PARTY.chr[i];   /* il puntatore una volta sola */
        row = (unsigned char)(row0 + i * step);
        // SI PULISCE SOLO DA `col` IN POI, non la riga intera. Nel menu
        // principale le prime quattro voci -- ITEM, MAGIC, WEAPON, ARMOR --
        // stanno alle righe 3, 5, 7 e 9, cioe' le stesse su cui si affaccia la
        // striscia del gruppo: un `clear_row` qui le cancellava tutte e
        // quattro, e a schermo restava il solo "5 STATUS". Sembrava un menu con
        // una voce sola, non una pulizia troppo larga.
        clear_span(col, row, (unsigned char)(32 - col));
        render_tile(col, row, (unsigned char)('1' + i));
        render_string((unsigned char)(col + 2), row, c->name);
        draw_cls2((unsigned char)(col + 9), row, c->cls);
        if (two_rows) {
            render_string((unsigned char)(col + 12), row, txt_lv);
            render_num_right((unsigned char)(col + 16), row, c->level);
            row++;
            clear_span(col, row, (unsigned char)(32 - col));
            render_string((unsigned char)(col + 2), row, txt_hp);
            render_num_right((unsigned char)(col + 7), row, c->curhp);
            render_tile((unsigned char)(col + 8), row, '/');
            render_num_right((unsigned char)(col + 12), row, c->maxhp);
            draw_ail_tag((unsigned char)(col + 14), row, c->ailments);
        } else {
            render_string((unsigned char)(col + 12), row, txt_hp);
            render_num_right((unsigned char)(col + 19), row, c->curhp);
            render_tile((unsigned char)(col + 20), row, '/');
            render_num_right((unsigned char)(col + 25), row, c->maxhp);
            draw_ail_tag((unsigned char)(col + 27), row, c->ailments);
        }
    }
}

// Scelta di un personaggio. Torna l'indice, oppure 0xFF se si e' rinunciato.
// Il tastierino sceglie in un tasto solo -- e' il vantaggio del Coleco sul
// NES, dove per arrivare al quarto servono tre pressioni (design_input.md).
static unsigned char pick_char(unsigned char col_cur, unsigned char row0,
                               unsigned char step, const char *prompt) {
    unsigned int e;
    unsigned char bits, key, who;

    who = 0;
    draw_prompt(prompt);
    draw_hint(txt_hint_who);
    draw_cursor(col_cur, row0, step, PARTY.n, who, 1);

    while (1) {
        e    = read_edge();
        bits = (unsigned char)(e & 0x00FF);
        key  = (unsigned char)(e >> 8);
        if (bits & MOVE_FIRE2) {
            draw_cursor(col_cur, row0, step, PARTY.n, who, 0);
            return 0xFF;
        }
        if (bits & (MOVE_UP | MOVE_DOWN)) {
            who = (unsigned char)((bits & MOVE_UP)
                    ? (who ? who - 1 : PARTY.n - 1)
                    : ((who + 1 >= PARTY.n) ? 0 : who + 1));
            draw_cursor(col_cur, row0, step, PARTY.n, who, 1);
        } else if (key >= '1' && key < (unsigned char)('1' + PARTY.n)) {
            who = (unsigned char)(key - '1');
            draw_cursor(col_cur, row0, step, PARTY.n, who, 1);
        } else if (bits & MOVE_FIRE1) {
            draw_cursor(col_cur, row0, step, PARTY.n, who, 0);
            return who;
        }
    }
}

// =====================================================================
//  STATUS
// =====================================================================
// Gli EXP che mancano al livello dopo. `lut_ExpToAdvance` (banco 11, tabella 5
// di svc_fetch_btl) tiene gli EXP TOTALI da raggiungere, indicizzati per
// livello 0-based -- la voce 0 e' "da L1 a L2". Il nostro `level` e' 1-based
// SEMPRE (fuori battaglia il NES lo tiene 0-based, ed e' gia' costato un bug
// in slice59): l'indice giusto e' `level - 1`.
static void draw_next_exp(chr_t *c) {
    unsigned char need[3];
    unsigned char i, borrow;
    unsigned int t;

    render_string(1, ROW_ST_NEXT, txt_next);
    clear_span(6, ROW_ST_NEXT, 8);
    if (c->level >= 50) {          /* LVLUP_MAX_LEVEL: non c'e' un dopo */
        render_string(9, ROW_ST_NEXT, txt_maxlv);
        return;
    }
    svc_fetch_btl(5, (unsigned int)(c->level - 1) * 3, 3, need);
    // Sottrazione a 24 bit: quello che manca, non quello che serve in totale.
    // Il totale sarebbe un numero che non dice niente da solo -- il giocatore
    // dovrebbe farsi la differenza a mente ogni volta.
    borrow = 0;
    for (i = 0; i < 3; i++) {
        t = (unsigned int)need[i] - (unsigned int)c->exp[i] - (unsigned int)borrow;
        need[i] = (unsigned char)t;
        borrow  = (unsigned char)((t & 0xFF00) ? 1 : 0);
    }
    // Se il gruppo ha gia' passato la soglia (succede: il livello sale a fine
    // battaglia, non a ogni EXP guadagnato) il prestito resta acceso e il
    // numero sarebbe enorme. Zero e' la risposta onesta.
    if (borrow) { need[0] = 0; need[1] = 0; need[2] = 0; }
    render_num24_right(13, ROW_ST_NEXT, need);
}

// Le quattro caselle di un tipo, con l'asterisco su quelle INDOSSATE. Il bit 7
// del byte e' proprio quello (`EQUIP_EQUIPPED`), ed e' anche la differenza fra
// un'arma comprata e un'arma che fa danno: mostrarla e' meta' del motivo per
// cui questa schermata esiste.
static void draw_equip_row(unsigned char row, const unsigned char *slot,
                           unsigned char is_weapon) {
    unsigned char k, v, id;
    clear_row(row);
    for (k = 0; k < PARTY_EQUIP_SLOTS; k++) {
        unsigned char col = (unsigned char)(1 + k * 8);
        v = slot[k];
        if (v == 0) continue;
        if (v & EQUIP_EQUIPPED) render_tile((unsigned char)(col - 1), row, '*');
        if (is_weapon) id = FF1_WEAPON_SLOT_TO_ITEM((unsigned char)(v & 0x7F));
        else           id = FF1_ARMOR_SLOT_TO_ITEM((unsigned char)(v & 0x7F));
        // Il nome pieno e' 7 caratteri e la colonna ne ha 7: l'icona finirebbe
        // sopra l'asterisco. Qui il nome si stampa senza icona -- nella lista
        // dell'equipaggiamento (slice futura) ci sara' spazio per entrambi.
        fetch_name(id);
        render_string(col, row, (const char *)nm_buf);
    }
}

static void run_status(unsigned char who) {
    unsigned int e;
    chr_t *c = &PARTY.chr[who];
    unsigned char i;

    svc_vfill(0x1800, 0x20, 768);
    render_string(1, ROW_TITLE, txt_status);

    render_string(1, ROW_ST_NAME, c->name);
    render_string(12, ROW_ST_NAME, txt_lv);
    render_num_right(17, ROW_ST_NAME, c->level);
    draw_ail_tag(20, ROW_ST_NAME, c->ailments);
    render_string(1, ROW_ST_CLASS, str_at(txt_classes, (int)c->cls));

    render_string(1, ROW_ST_HP, txt_hp);
    render_num_right(9, ROW_ST_HP, c->curhp);
    render_tile(10, ROW_ST_HP, '/');
    render_num_right(15, ROW_ST_HP, c->maxhp);
    render_string(1, ROW_ST_EXP, txt_exp);
    render_num24_right(13, ROW_ST_EXP, c->exp);
    draw_next_exp(c);

    // Le cinque base a sinistra e le cinque derivate a destra, riga per riga.
    // Un ciclo solo e non due: incolonnarle e' quello che le mette in
    // relazione, e due cicli separati inviterebbero a spostarne uno.
    for (i = 0; i < 5; i++) {
        unsigned char row = (unsigned char)(ROW_ST_STAT0 + i);
        unsigned char bv, dv;
        if (i == 0)      { bv = c->str;      dv = c->dmg;     }
        else if (i == 1) { bv = c->agil;     dv = c->hitrate; }
        else if (i == 2) { bv = c->int_stat; dv = c->absorb;  }
        else if (i == 3) { bv = c->vit;      dv = c->evade;   }
        else             { bv = c->luck;     dv = c->magdef;  }
        render_string(1, row, str_at(txt_base, (int)i));
        render_num_right(9, row, bv);
        render_string(13, row, str_at(txt_deriv, (int)i));
        render_num_right(29, row, dv);
    }

    // Le cariche di magia, quattro livelli per riga. In FF1 gli "MP" non sono
    // un serbatoio unico: sono otto contatori separati, uno per livello, ed e'
    // proprio la ragione per cui il menu deve mostrarli tutti e otto invece di
    // una coppia sola (memory/feedback_hud_parity.md).
    render_string(1, ROW_ST_MP, txt_mp);
    for (i = 0; i < PARTY_SPELL_LEVELS; i++) {
        unsigned char row = (unsigned char)(ROW_ST_MP + (i >> 2));
        unsigned char col = (unsigned char)(4 + (i & 3) * 7);
        render_tile(col, row, (unsigned char)('1' + i));
        render_num_right((unsigned char)(col + 3), row, c->curmp[i]);
        render_tile((unsigned char)(col + 4), row, '/');
        render_num_right((unsigned char)(col + 5), row, c->maxmp[i]);
    }

    render_string(1, ROW_ST_WEAP, txt_weapon);
    draw_equip_row((unsigned char)(ROW_ST_WEAP + 1), c->weapon, 1);
    render_string(1, ROW_ST_ARM, txt_armor);
    draw_equip_row((unsigned char)(ROW_ST_ARM + 1), c->armor, 0);

    draw_hint(txt_hint_back);
    while (1) {
        e = read_edge();
        if (e & (MOVE_FIRE1 | MOVE_FIRE2)) return;
    }
}

// =====================================================================
//  WEAPON / ARMOR -- l'equipaggiamento manuale
// =====================================================================
// PERCHE' CONTA PIU' DI UNA SCHERMATA IN PIU'. Da slice66 comprare EQUIPAGGIA
// da solo (deviazione 1.5 di Coleco_improvements): era l'unico modo di far
// cambiare un numero visibile a un acquisto, ma senza questa schermata era
// anche senza rimedio -- un'arma finita addosso alla persona sbagliata ci
// restava. Qui la si toglie, e la si passa a un altro.
//
// I TRE MODI SONO QUELLI DEL NES, ma raggiungibili in un tasto invece che
// uscendo e rientrando da un sottomenu (`eq_modecurs` + A + B, EnterEquipMenu
// bank_0E.asm:8845). Il cursore vive sempre sulla griglia e il tastierino
// sceglie che cosa fa FIRE1: e' la stessa mossa gia' fatta per le voci del
// negozio (1.7) e per il menu stesso (1.9). Un livello di navigazione in meno
// e nessuna funzione in piu'.
//
// NIENTE LAMPEGGIO, e non e' pigrizia: il NES fa lampeggiare il secondo
// cursore del TRADE e quello della conferma del DROP. Qui i due cursori sono
// due caratteri diversi -- '>' dove si e', '<' su cio' che si e' preso -- e la
// conferma e' scritta a parole. Una posizione a schermo che vale come prova
// dev'essere ASSERIBILE (regola di slice66), e un carattere che c'e' un
// quadro su due non lo e'.

// I permessi delle 40 voci del tipo aperto: una PAROLA l'una, bit acceso =
// quella classe NON puo'. Si prendono UNA volta all'apertura, non una per
// casella: sono 80 byte e l'alternativa e' un'escursione di banco per ogni
// domanda, cioe' fino a sedici per ridisegno.
static unsigned char eq_perm[FF1_N_WEAPONS * 2];
static unsigned char eq_is_weapon;

static unsigned char *eq_slots(unsigned char who) {
    chr_t *c = &PARTY.chr[who];
    if (eq_is_weapon) return c->weapon;
    return c->armor;
}

static unsigned int eq_perm_of(unsigned char v) {
    unsigned int i = (unsigned int)((v & 0x7F) - 1) * 2;
    return (unsigned int)eq_perm[i] | ((unsigned int)eq_perm[i + 1] << 8);
}

// Il tipo di armatura, cioe' il posto che occupa addosso. Stessa funzione di
// ovl_shop.c e per la stessa ragione: `lut_ArmorTypes` (bank_0E.asm:9212) e'
// fatta di quattro tratti contigui -- 16 corazze, 9 scudi, 7 elmi, 8 guanti --
// e i quattro confini bastano. Non e' condivisa perche' un .h di helper linkato
// in due overlay finirebbe due volte in ROM comunque: i banchi non si vedono
// fra loro.
static unsigned char armor_kind(unsigned char idx) {
    if (idx < 16) return 0;
    if (idx < 25) return 1;
    if (idx < 32) return 2;
    return 3;
}

// La cella di una casella. L'indice e' `personaggio*4 + casella`, cioe' quello
// del NES (`cursor`), e la disposizione lo rispecchia: due colonne per riga,
// quindi l'indice lineare SI MUOVE come si muove l'occhio -- +-1 di lato, +-2
// sopra e sotto, e i blocchi in ordine. E' il motivo per cui il movimento del
// cursore piu' avanti non ha nessuna aritmetica dentro.
static void eq_cell(unsigned char sel, unsigned char *col, unsigned char *row) {
    unsigned char k = (unsigned char)(sel & 3);
    *col = (unsigned char)((k & 1) * 16);
    *row = (unsigned char)(ROW_EQ0 + (sel >> 2) * ROW_EQ_STEP + 1 + (k >> 1));
}

// La cella: cursore, asterisco, ICONA di tipo, nome. Dieci colonne su sedici.
// L'icona qui e' obbligatoria e non un ornamento: fra le armature "Iron" sono
// tre voci diverse -- corazza, scudo ed elmo -- e nella griglia stanno una
// sotto l'altra.
static void draw_eq_slot(unsigned char sel) {
    unsigned char *slots = eq_slots((unsigned char)(sel >> 2));
    unsigned char col, row, v, id, icon;
    eq_cell(sel, &col, &row);
    clear_span((unsigned char)(col + 1), row, 10);
    v = slots[sel & 3];
    if (v == 0) return;
    // L'asterisco su cio' che si indossa e' la sola differenza fra un'arma nello
    // zaino e un'arma in mano, e senza di esso la schermata non direbbe niente
    // di cio' che il comando EQUIP ha appena fatto.
    if (v & EQUIP_EQUIPPED) render_tile((unsigned char)(col + 1), row, '*');
    if (eq_is_weapon) id = FF1_WEAPON_SLOT_TO_ITEM((unsigned char)(v & 0x7F));
    else              id = FF1_ARMOR_SLOT_TO_ITEM((unsigned char)(v & 0x7F));
    icon = fetch_name(id);
    if (FF1_ICON_VALID(icon)) {
        render_tile((unsigned char)(col + 2), row,
                    (unsigned char)(ICON_TILE_BASE + FF1_ICON_INDEX(icon)));
    }
    render_string((unsigned char)(col + 3), row, (const char *)nm_buf);
}

static void draw_eq_all(void) {
    unsigned char i, k;
    for (i = 0; i < PARTY.n; i++) {
        chr_t *c = &PARTY.chr[i];
        unsigned char row = (unsigned char)(ROW_EQ0 + i * ROW_EQ_STEP);
        clear_row(row);
        render_tile(0, row, (unsigned char)('1' + i));
        render_string(2, row, c->name);
        draw_cls2(10, row, c->cls);
        for (k = 0; k < PARTY_EQUIP_SLOTS; k++) {
            draw_eq_slot((unsigned char)(i * PARTY_EQUIP_SLOTS + k));
        }
    }
}

// `src` = la casella presa in TRADE, EQ_NONE se non ce n'e' una.
static void draw_eq_cursor(unsigned char sel, unsigned char src) {
    unsigned char s, n, col, row, ch;
    n = (unsigned char)(PARTY.n * PARTY_EQUIP_SLOTS);
    for (s = 0; s < n; s++) {
        eq_cell(s, &col, &row);
        ch = ' ';
        // DUE `if` E NON UN `?:` a due termini: dentro un `?:` sccz80 decide col
        // carry dell'ultimo confronto (la spiegazione lunga sta su draw_cursor
        // qui sopra). Qui in piu' l'ordine conta -- dove il cursore sta sopra
        // la casella presa, vince il cursore.
        if (s == src) ch = '<';
        if (s == sel) ch = '>';
        render_tile(col, row, ch);
    }
}

static void draw_eq_mode(unsigned char mode) {
    unsigned char m, col;
    clear_row(ROW_EQ_MODE);
    for (m = 0; m < 3; m++) {
        col = (unsigned char)(COL_EQ_MODE0 + m * EQ_MODE_STEP);
        if (m == mode) render_tile((unsigned char)(col - 1), ROW_EQ_MODE, '>');
        render_string(col, ROW_EQ_MODE, str_at(txt_eq_modes, (int)m));
    }
}

// Indossa o toglie. Torna il messaggio da mostrare -- che e' anche l'esito: i
// due rifiuti hanno cause diverse, e dirle e' cio' che distingue "non ha
// funzionato" da "non poteva funzionare".
static const char *eq_do_equip(unsigned char sel) {
    unsigned char who = (unsigned char)(sel >> 2);
    unsigned char k   = (unsigned char)(sel & 3);
    chr_t *c = &PARTY.chr[who];
    unsigned char *slots = eq_slots(who);
    unsigned char v = slots[k];
    unsigned char i, w, kind;

    if (v == 0) return txt_eq_empty;
    // Togliersi qualcosa e' SEMPRE lecito, e il NES nemmeno lo controlla
    // (`BMI @ToggleEquip` salta IsEquipLegal): un permesso che cambia -- e col
    // cambio di classe cambia -- non deve poter incastrare un pezzo addosso.
    if (v & EQUIP_EQUIPPED) {
        slots[k] = (unsigned char)(v & 0x7F);
        svc_equip_recalc(who);
        return txt_eq_off;
    }
    if (!CAN_EQUIP(eq_perm_of(v), c->cls)) return txt_eq_cannot;

    // Un'arma sola addosso; le armature una per POSTO. E' la seconda meta' di
    // IsEquipLegal (bank_0E.asm:9098 e 9145), che infatti disequipaggia mentre
    // controlla -- qui e' separato perche' la risposta al permesso serve anche
    // quando non si equipaggia niente.
    kind = 0;
    if (!eq_is_weapon) kind = armor_kind((unsigned char)((v & 0x7F) - 1));
    for (i = 0; i < PARTY_EQUIP_SLOTS; i++) {
        w = slots[i];
        if (!(w & EQUIP_EQUIPPED)) continue;
        if (!eq_is_weapon) {
            if (armor_kind((unsigned char)((w & 0x7F) - 1)) != kind) continue;
        }
        slots[i] = (unsigned char)(w & 0x7F);
    }
    slots[k] = (unsigned char)(v | EQUIP_EQUIPPED);
    svc_equip_recalc(who);
    return txt_eq_worn;
}

// Scambia due caselle, anche fra personaggi diversi -- che e' tutto il punto:
// e' l'unico modo di passare un'arma a chi la puo' usare.
//
// TUTTE E DUE ESCONO SPENTE (`AND #$7F` due volte, EquipMenu_TRADE bank_0E:8929).
// Non e' un dettaglio di implementazione: un'arma che cambia mano non puo'
// restare "indossata", perche' il permesso del nuovo proprietario non e' stato
// chiesto a nessuno. Chi la riceve preme EQUIP, e li' il permesso si chiede.
static void eq_do_trade(unsigned char a, unsigned char b) {
    unsigned char *sa = eq_slots((unsigned char)(a >> 2));
    unsigned char *sb = eq_slots((unsigned char)(b >> 2));
    unsigned char t = sa[a & 3];
    sa[a & 3] = (unsigned char)(sb[b & 3] & 0x7F);
    sb[b & 3] = (unsigned char)(t & 0x7F);
    svc_equip_recalc((unsigned char)(a >> 2));
    svc_equip_recalc((unsigned char)(b >> 2));
}

// I buchi si chiudono all'USCITA, non a ogni mossa. Sul NES e' la stessa cosa
// (`SortEquipmentList` all'ingresso e all'uscita di EnterEquipMenu): farlo
// mentre il cursore e' sullo schermo vorrebbe dire caselle che si spostano
// sotto il cursore, cioe' un DROP che sembra averne cancellata un'altra.
// Serve davvero: il negozio mette la merce nella PRIMA casella libera, e senza
// compattare un acquisto finirebbe in mezzo a due vuoti.
static void eq_sort(void) {
    unsigned char i, k, n, w;
    for (i = 0; i < PARTY.n; i++) {
        unsigned char *slots = eq_slots(i);
        n = 0;
        for (k = 0; k < PARTY_EQUIP_SLOTS; k++) {
            w = slots[k];
            if (w == 0) continue;
            slots[k] = 0;
            slots[n] = w;
            n++;
        }
    }
}

static void run_equip(unsigned char is_weapon) {
    unsigned int e;
    unsigned char bits, key, sel, src, mode, nc;
    const char *msg;

    eq_is_weapon = is_weapon;
    // Tabella 6 = armi, 7 = armature (slice74). Le due hanno 40 voci da una
    // parola l'una, quindi la stessa lunghezza e lo stesso vettore.
    svc_fetch_btl((unsigned char)(is_weapon ? 6 : 7), 0,
                  (unsigned char)(FF1_N_WEAPONS * 2), eq_perm);

    sel  = 0;
    src  = EQ_NONE;
    mode = EQ_MODE_EQUIP;
    nc   = (unsigned char)(PARTY.n * PARTY_EQUIP_SLOTS);

    svc_vfill(0x1800, 0x20, 768);
    if (is_weapon) render_string(1, ROW_TITLE, txt_weapon);
    else           render_string(1, ROW_TITLE, txt_armor);
    draw_eq_mode(mode);
    draw_eq_all();
    draw_hint(txt_hint_eq);
    draw_eq_cursor(sel, src);

    while (1) {
        e    = read_edge();
        bits = (unsigned char)(e & 0x00FF);
        key  = (unsigned char)(e >> 8);

        if (bits & MOVE_FIRE2) {
            // Il primo FIRE2 lascia andare cio' che si era preso: uscire dal
            // TRADE a meta' e uscire dalla schermata sono due intenzioni
            // diverse, e sul NES infatti sono due `RTS` a due livelli.
            if (src != EQ_NONE) {
                src = EQ_NONE;
                draw_eq_cursor(sel, src);
                draw_msg(0);
                continue;
            }
            eq_sort();
            return;
        }

        if (bits & (MOVE_UP | MOVE_DOWN)) {
            sel = (unsigned char)((bits & MOVE_UP)
                    ? ((sel < 2) ? (sel + nc - 2) : (sel - 2))
                    : ((sel + 2 >= nc) ? (sel + 2 - nc) : (sel + 2)));
            draw_eq_cursor(sel, src);
        } else if (bits & (MOVE_LEFT | MOVE_RIGHT)) {
            sel = (unsigned char)(sel ^ 1);
            draw_eq_cursor(sel, src);
        } else if (key >= '1' && key <= '3') {
            // Cambiare modo LASCIA ANDARE la casella presa: una meta' di
            // scambio che sopravvive a un cambio di modo e' uno stato che il
            // giocatore non vede piu' da nessuna parte.
            mode = (unsigned char)(key - '1');
            src  = EQ_NONE;
            draw_eq_mode(mode);
            draw_eq_cursor(sel, src);
            draw_msg(0);
        } else if (bits & MOVE_FIRE1) {
            msg = 0;
            if (mode == EQ_MODE_EQUIP) {
                msg = eq_do_equip(sel);
                // Si ridisegna TUTTO il blocco e non la sola casella toccata:
                // indossare qualcosa ne spegne altre, e una che resta con
                // l'asterisco addosso e' una schermata che mente.
                draw_eq_all();
                draw_eq_cursor(sel, src);
            } else if (mode == EQ_MODE_TRADE) {
                if (src == EQ_NONE) {
                    // Anche una casella VUOTA si puo' prendere: scambiare con
                    // il vuoto e' come si sposta un oggetto, ed e' cosi' anche
                    // sul NES (nessun controllo prima di @DoTrade).
                    src = sel;
                    msg = txt_eq_pick;
                    draw_eq_cursor(sel, src);
                } else {
                    eq_do_trade(src, sel);
                    src = EQ_NONE;
                    msg = txt_eq_traded;
                    draw_eq_all();
                    draw_eq_cursor(sel, src);
                }
            } else {
                unsigned char *slots = eq_slots((unsigned char)(sel >> 2));
                if (slots[sel & 3] == 0) {
                    msg = txt_eq_empty;
                } else {
                    // La conferma e' un ciclo suo: buttare via un pezzo di
                    // equipaggiamento in FF1 e' definitivo -- non c'e' nessun
                    // posto dove vada a finire -- e il NES per questo la chiede.
                    draw_msg(txt_eq_ask);
                    while (1) {
                        e = read_edge();
                        bits = (unsigned char)(e & 0x00FF);
                        if (bits & MOVE_FIRE1) {
                            slots[sel & 3] = 0;
                            svc_equip_recalc((unsigned char)(sel >> 2));
                            msg = txt_eq_gone;
                            draw_eq_all();
                            draw_eq_cursor(sel, src);
                            break;
                        }
                        if (bits & MOVE_FIRE2) break;
                    }
                }
            }
            draw_msg(msg);
        }
    }
}

// =====================================================================
//  ITEM
// =====================================================================
// La lista si RICOSTRUISCE a ogni uso, e non si aggiorna: usare l'ultima
// pozione fa sparire una voce, e tenere insieme una lista e la sua sorgente
// e' esattamente il modo in cui il cursore finisce a puntare una casella che
// non c'e' piu'.
static unsigned char item_ids[INV_COUNT];
static unsigned char item_n;

static void build_item_list(void) {
    unsigned char id;
    item_n = 0;
    // Dalla casella 1: la zero non e' un oggetto (sul NES `items+0` non ha
    // nome) e resta sempre a zero. Partire da zero mostrerebbe una voce senza
    // nome il giorno in cui un byte ci finisse per sbaglio -- ed e' proprio il
    // giorno in cui si vorrebbe vederla, quindi la difesa e' l'azzeramento a
    // nuova partita, non il nascondere qui.
    for (id = 1; id < INV_COUNT; id++) {
        // LE QUATTRO SFERE NON SONO ROBA DA ZAINO. Occupano le caselle
        // $12-$15 come tutto il resto, ma nel ROM il loro NOME E' VUOTO --
        // sette spazi (item_names.h, "$12 (vuoto)"). Elencarle darebbe quattro
        // righe bianche con un "1" a destra, che a schermo non si legge come
        // "hai una sfera": si legge come una lista rotta.
        // Non e' una mancanza dei dati: sul NES le sfere si mostrano nel menu
        // principale come quattro gemme accese o spente, e nella lista degli
        // oggetti non compaiono. Qui si saltano, e il loro posto giusto -- le
        // quattro gemme -- e' debito dichiarato finche' non c'e' un modo di
        // ottenerle.
        if (id >= ITEM_ORB_FIRST && id < ITEM_ORB_FIRST + 4) continue;
        if (PARTY.item[id]) { item_ids[item_n] = id; item_n++; }
    }
}

static void item_cell(unsigned char k, unsigned char *col, unsigned char *row) {
    if (k < IT_PER_COL) { *col = 0;  *row = (unsigned char)(ROW_IT0 + k); }
    else                { *col = 16; *row = (unsigned char)(ROW_IT0 + k - IT_PER_COL); }
}

static void draw_item_list(void) {
    unsigned char k, col, row;
    for (row = ROW_IT0; row < ROW_IT0 + IT_PER_COL; row++) clear_row(row);
    for (k = 0; k < item_n; k++) {
        if (k >= IT_PER_COL * 2) break;      /* niente terza colonna: vedi ROW_IT0 */
        item_cell(k, &col, &row);
        draw_item_name((unsigned char)(col + 2), row, item_ids[k]);
        render_num_right((unsigned char)(col + 12), row, PARTY.item[item_ids[k]]);
    }
}

static void draw_item_cursor(unsigned char sel, unsigned char on) {
    unsigned char k, col, row, ch;
    for (k = 0; k < item_n; k++) {
        if (k >= IT_PER_COL * 2) break;
        item_cell(k, &col, &row);
        ch = ' ';
        if (on) {
            if (k == sel) ch = '>';
        }
        render_tile(col, row, ch);
    }
}

// HP a un personaggio, senza sfondare il massimo. Il NES ha due versioni della
// stessa cosa (`MenuRecoverHP` salta i caduti, `_Abs` no) perche' i chiamanti
// il controllo se lo fanno da soli: qui la scelta la passa `skip_out`, cosi'
// esiste UNA funzione e la differenza si legge nella chiamata.
static void recover_hp(chr_t *c, unsigned int amount, unsigned char skip_out) {
    if (skip_out) {
        if (c->ailments & AIL_OUT) return;
    }
    c->curhp = (unsigned int)(c->curhp + amount);
    if (c->curhp > c->maxhp) c->curhp = c->maxhp;
}

// Esiti dell'uso. Distinti perche' portano a mosse diverse del giocatore, ed
// e' la stessa ragione per cui il negozio distingue "comprato e indossato" da
// "comprato e riposto".
#define USE_NONE   0   /* non e' successo niente: l'oggetto resta */
#define USE_DONE   1   /* consumato */

static unsigned char use_camp(unsigned char id, unsigned char in_town) {
    unsigned char i;
    unsigned int amount;
    // TENDA, CAPANNA E CASA SOLO FUORI DALLE CITTA'. Sul NES il controllo e'
    // `LDA mapflags / LSR / BCS` -- il bit della mappa standard -- e vale per
    // tutte e tre. La ragione di gioco e' che in citta' c'e' la locanda.
    if (in_town) return USE_NONE;
    if (id == ITEM_TENT)       amount = 30;
    else if (id == ITEM_CABIN) amount = 60;
    else                       amount = 120;
    for (i = 0; i < PARTY.n; i++) recover_hp(&PARTY.chr[i], amount, 1);
    // LA CASA RIMETTE ANCHE LE CARICHE DI MAGIA. Sul NES lo fa DOPO il
    // salvataggio, e chi non salva non le riprende -- un effetto collaterale
    // dell'ordine delle chiamate che la comunita' considera un bug
    // (bank_0E.asm:7095, "some would say this is BUGGED"). Qui non c'e' un
    // salvataggio da cui dipendere, quindi la casa fa sempre tutto: e' la
    // lettura giusta dell'intento, non una scorciatoia.
    if (id == ITEM_HOUSE) {
        for (i = 0; i < PARTY.n; i++) {
            chr_t *c = &PARTY.chr[i];
            unsigned char k;
            if (c->ailments & AIL_OUT) continue;
            for (k = 0; k < PARTY_SPELL_LEVELS; k++) c->curmp[k] = c->maxmp[k];
        }
    }
    return USE_DONE;
}

// Le tre che si usano su UNO. Tornano l'esito e, in `*msg`, che cosa dire: il
// rifiuto ha un motivo diverso per ciascuna, e dirlo e' cio' che distingue
// "non ha funzionato" da "non serviva".
//
// IL MESSAGGIO ESCE COME PARAMETRO E NON LO SCRIVE QUESTA FUNZIONE, perche' i
// due esiti finiscono in due momenti diversi: il rifiuto si scrive subito, la
// riuscita DOPO il ridisegno della lista -- che altrimenti la cancella.
static unsigned char use_on_one(unsigned char id, unsigned char who,
                                const char **msg) {
    chr_t *c = &PARTY.chr[who];
    if (id == ITEM_HEAL) {
        // Su un caduto o un pietrificato la pozione non fa niente, come sul
        // NES (UseItem_Heal controlla le due alterazioni prima di curare).
        // Su chi sta bene invece SI PUO' sprecare, e cura zero: e' cosi' anche
        // sul NES, che li' non guarda gli HP. `recover_hp` taglia al massimo.
        if (c->ailments & AIL_OUT) { *msg = txt_noneed; return USE_NONE; }
        recover_hp(c, 30, 0);
        *msg = txt_healed;
        return USE_DONE;
    }
    if (id == ITEM_PURE) {
        if (!(c->ailments & AIL_POISON)) { *msg = txt_noneed; return USE_NONE; }
        c->ailments = (unsigned char)(c->ailments & ~AIL_POISON);
        *msg = txt_cured;
        return USE_DONE;
    }
    /* ITEM_SOFT */
    if (!(c->ailments & AIL_STONE)) { *msg = txt_noneed; return USE_NONE; }
    c->ailments = (unsigned char)(c->ailments & ~AIL_STONE);
    // Sciogliendo la pietra si torna vivi con gli HP che si avevano; se erano
    // zero il personaggio resterebbe in piedi a zero HP, che in FF1 non e' uno
    // stato possibile. Un HP, come fa la clinica con i caduti.
    if (c->curhp == 0) c->curhp = 1;
    *msg = txt_soften;
    return USE_DONE;
}

static void run_item(unsigned char in_town) {
    unsigned int e;
    unsigned char bits, key, sel, id, res;
    // IL MESSAGGIO SOPRAVVIVE AL RIDISEGNO, e non e' un dettaglio: usare una
    // pozione fa ricostruire la lista (la voce puo' essere sparita), e la
    // ricostruzione ripulisce lo schermo -- compresa la riga in cui si e'
    // appena scritto "FEELING BETTER!". Scritto e cancellato nello stesso
    // quadro vuol dire mai scritto: a schermo l'uso riuscito sembrerebbe non
    // aver fatto niente, che e' esattamente quello che si vede quando e'
    // rotto davvero.
    const char *msg;

    sel = 0;
    msg = 0;
    while (1) {
        svc_vfill(0x1800, 0x20, 768);
        render_string(1, ROW_TITLE, txt_item);
        build_item_list();
        if (item_n == 0) {
            draw_prompt(txt_empty);
            draw_hint(txt_hint_back);
            while (1) {
                e = read_edge();
                if (e & (MOVE_FIRE1 | MOVE_FIRE2)) return;
            }
        }
        if (sel >= item_n) sel = (unsigned char)(item_n - 1);
        draw_item_list();
        draw_party_strip(1, ROW_IT_PARTY, 1, 0);
        draw_prompt(txt_choose);
        draw_hint(txt_hint_use);
        draw_item_cursor(sel, 1);
        draw_msg(msg);          /* 0 = riga pulita */
        msg = 0;

        // Ciclo interno: si esce solo per USARE qualcosa (e allora il ciclo
        // esterno ridisegna tutto) o per chiudere.
        while (1) {
            e    = read_edge();
            bits = (unsigned char)(e & 0x00FF);
            key  = (unsigned char)(e >> 8);
            if (bits & MOVE_FIRE2) return;

            if (bits & (MOVE_UP | MOVE_DOWN)) {
                sel = (unsigned char)((bits & MOVE_UP)
                        ? (sel ? sel - 1 : item_n - 1)
                        : ((sel + 1 >= item_n) ? 0 : sel + 1));
                draw_item_cursor(sel, 1);
            } else if (bits & (MOVE_LEFT | MOVE_RIGHT)) {
                // Fra le due colonne. Non e' un lusso: con ventiquattro voci
                // in colonna sola il su/giu' costerebbe fino a dodici
                // pressioni per attraversare.
                if (sel >= IT_PER_COL) sel = (unsigned char)(sel - IT_PER_COL);
                else if (sel + IT_PER_COL < item_n) sel = (unsigned char)(sel + IT_PER_COL);
                draw_item_cursor(sel, 1);
            } else if (bits & MOVE_FIRE1) {
                id  = item_ids[sel];
                res = USE_NONE;
                msg = 0;
                if (id == ITEM_TENT || id == ITEM_CABIN || id == ITEM_HOUSE) {
                    res = use_camp(id, in_town);
                    if (res == USE_DONE) msg = txt_rested;
                    else                 msg = txt_nothere;
                } else if (id == ITEM_HEAL || id == ITEM_PURE || id == ITEM_SOFT) {
                    unsigned char who = pick_char(0, ROW_IT_PARTY, 1, txt_who);
                    draw_prompt(txt_choose);
                    draw_hint(txt_hint_use);
                    if (who != 0xFF) res = use_on_one(id, who, &msg);
                } else {
                    // Oggetti chiave: esistono, si vedono, e non servono a
                    // niente finche' non ci sono i luoghi in cui si usano.
                    // Dichiarato, non silenzioso.
                    msg = txt_nouse;
                }
                if (res == USE_DONE) {
                    PARTY.item[id]--;
                    break;      /* ridisegna, e `msg` sopravvive al ridisegno */
                }
                // Niente da consumare: il messaggio si scrive subito -- qui
                // non c'e' nessun ridisegno che lo cancelli -- e basta
                // rinfrescare la striscia, che il sotto-cursore ha sporcato.
                draw_msg(msg);
                msg = 0;
                draw_party_strip(1, ROW_IT_PARTY, 1, 0);
                draw_item_cursor(sel, 1);
            }
        }
    }
}

// =====================================================================
//  Il menu principale
// =====================================================================
static void draw_main(unsigned char sel) {
    unsigned char i;
    svc_vfill(0x1800, 0x20, 768);
    render_string(1, ROW_TITLE, txt_title);
    for (i = 0; i < N_CMD; i++) {
        unsigned char row = (unsigned char)(ROW_CMD0 + i * 2);
        render_tile(COL_CMD, row, (unsigned char)('1' + i));
        render_string((unsigned char)(COL_CMD + 2), row, str_at(txt_cmds, (int)i));
    }
    draw_party_strip(COL_PARTY, ROW_PARTY0, ROW_PARTY_STEP, 1);
    draw_gold();
    draw_prompt(txt_choose);
    draw_hint(txt_hint_main);
    draw_cursor((unsigned char)(COL_CMD - 1), ROW_CMD0, 2, N_CMD, sel, 1);
}

// arg: 1 = si e' dentro una citta', 0 = overworld. Serve a una cosa sola --
// tenda, capanna e casa non si usano in citta' -- ma passarlo e' meglio che
// farlo dedurre da qui: l'overlay non ha nessun modo di saperlo, e una
// variabile globale in piu' nella slice sarebbe un secondo posto in cui la
// stessa verita' puo' diventare falsa.
//
// Torna 1 se il gruppo e' stato portato via da WARP o EXIT, 0 altrimenti --
// e' l'unica cosa che il menu non puo' fare da solo, perche' uscire da una
// citta' vuol dire ridisegnare l'overworld. Tutto il resto di quello che il
// menu cambia sta in RAM SGM e non ha bisogno di essere raccontato.
unsigned int overlay_main(unsigned int arg) {
    unsigned int e;
    unsigned char bits, key, sel, in_town;

    in_town = (unsigned char)(arg & 1);
    prev_bits = 0xFF;   // NIENTE inizializzatori nella DATA di un overlay
    prev_key  = 0;
    sel = 0;

    load_menu_screen();
    draw_main(sel);

    while (1) {
        e    = read_edge();
        bits = (unsigned char)(e & 0x00FF);
        key  = (unsigned char)(e >> 8);
        if (bits & MOVE_FIRE2) return 0;

        if (bits & (MOVE_UP | MOVE_DOWN)) {
            sel = (unsigned char)((bits & MOVE_UP)
                    ? (sel ? sel - 1 : N_CMD - 1)
                    : ((sel + 1 >= N_CMD) ? 0 : sel + 1));
            draw_cursor((unsigned char)(COL_CMD - 1), ROW_CMD0, 2, N_CMD, sel, 1);
        } else if (key >= '1' && key < (unsigned char)('1' + N_CMD)) {
            sel = (unsigned char)(key - '1');
            draw_cursor((unsigned char)(COL_CMD - 1), ROW_CMD0, 2, N_CMD, sel, 1);
        } else if (bits & MOVE_FIRE1) {
            if (sel == CMD_ITEM) {
                run_item(in_town);
                draw_main(sel);
            } else if (sel == CMD_MAGIC) {
                // Il bersaglio si sceglie DENTRO l'altro overlay; qui si
                // sceglie chi LANCIA, come sul NES (`MainMenuSubTarget` vale
                // per MAGIC come per STATUS).
                unsigned char who = pick_char(COL_PARTY_CUR, ROW_PARTY0, ROW_PARTY_STEP, txt_who);
                if (who != 0xFF) {
                    // SESTO overlay, e SECONDO annidato: questo file gira nel
                    // banco 24 e ne chiama un altro nel 25. Vale la regola di
                    // slice68 -- di la' niente `static` mutabili, o scrivono
                    // sopra le variabili di qui, che sono ancora vive.
                    if (svc_run_overlay(MAGIC_BANK,
                            (unsigned int)who | (in_town ? 4u : 0u))) {
                        // WARP o EXIT: il gruppo e' stato portato via. Il menu
                        // si chiude da solo e passa la notizia alla slice, che
                        // e' l'unica a saper uscire da una citta'.
                        return 1;
                    }
                    draw_main(sel);
                } else {
                    draw_prompt(txt_choose);
                    draw_hint(txt_hint_main);
                    draw_cursor((unsigned char)(COL_CMD - 1), ROW_CMD0, 2, N_CMD, sel, 1);
                }
            } else if (sel == CMD_WEAPON || sel == CMD_ARMOR) {
                // NIENTE scelta del personaggio prima, ed e' il NES: la
                // schermata mostra tutte e sedici le caselle del gruppo, perche'
                // lo scambio fra due personaggi va visto mentre si fa.
                run_equip((unsigned char)((sel == CMD_WEAPON) ? 1 : 0));
                draw_main(sel);
            } else if (sel == CMD_STATUS) {
                // La scelta del bersaglio prima della schermata, come sul NES
                // (`MainMenuSubTarget`): rinunciare qui deve riportare al menu
                // senza aver disegnato niente.
                unsigned char who = pick_char(COL_PARTY_CUR, ROW_PARTY0, ROW_PARTY_STEP, txt_who);
                if (who != 0xFF) {
                    run_status(who);
                    draw_main(sel);
                } else {
                    draw_prompt(txt_choose);
                    draw_hint(txt_hint_main);
                    draw_cursor((unsigned char)(COL_CMD - 1), ROW_CMD0, 2, N_CMD, sel, 1);
                }
            } else {
                draw_msg(txt_soon);
            }
        }
    }
}
