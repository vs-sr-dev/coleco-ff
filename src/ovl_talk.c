// =====================================================================
//  ovl_talk.c -- si parla agli abitanti. Overlay di CODICE (banco 26)
// =====================================================================
// SETTIMO overlay del progetto. Ci si entra dalla citta' con
// `svc_run_overlay(26, arg)` e ci si sta finche' il riquadro non si chiude.
//
// PERCHE' UN BANCO E NON TRE FUNZIONI NELLA FINESTRA FISSA. Non e' il codice:
// e' il TESTO. I dialoghi delle quattro mappe di questa sessione sono 3113
// byte gia' decompressi, e la finestra fissa ne ha 657 liberi in tutto. Il
// testo deve stare in un banco per forza, e una volta li' conviene metterci
// accanto anche chi lo legge -- il contrario vorrebbe dire una `svc_` che fa
// l'escursione per ogni riga.
//
// COSA C'E' DENTRO
//   1. i 3113 byte di testo, gia' sciolti dal DTE del ROM (i byte $1A-$79 di
//      FF1 valgono due lettere l'uno: tools/extract_dialogue.ps1);
//   2. i 4 byte di dati di dialogo per ognuno dei 208 id di oggetto, e il
//      numero della routine che decide QUALE delle tre battute esce;
//   3. il riquadro: disegno, testo, attesa.
//
// LA REGOLA DEGLI OVERLAY ANNIDATI NON SERVE QUI -- ma si rispetta lo stesso.
// Questo overlay non gira dentro un altro (lo chiama la citta', che sta nella
// finestra fissa), quindi un `static` mutabile sarebbe legale. Non ce n'e'
// nemmeno uno: il giorno in cui un menu aprisse un dialogo, la regola varrebbe
// e nessuno se ne ricorderebbe. Vedi [[slice68-player-magic]].
//
// COSA NON RIPRISTINA. Il riquadro copre le righe 14-23 della name table e
// NON le rimette a posto: al ritorno ci pensa la citta' con `redraw_town_view`,
// che ridisegna comunque tutto e ridisegna anche gli NPC. Rifare qui la stessa
// cosa vorrebbe dire una seconda copia della composizione degli abitanti, cioe'
// due posti dove sbagliare la stessa somma.
// =====================================================================

#define SVC_OVERLAY
#include "svc_api.h"
#include "party_state.h"
#include "world_state.h"

#define FF1_DIALOGUE_DEFINE_DATA
#include "data/dialogue.h"
#define FF1_MAPOBJ_TALK_DEFINE_DATA
#include "data/mapobj_talk.h"

// Costanti di games.h: l'overlay non linka nulla della libreria.
#define MOVE_FIRE1 16
#define MOVE_FIRE2 32

// --- l'argomento -----------------------------------------------------
// Bit 15 acceso = si sta parlando a un MACROTILE e nel byte basso c'e' gia'
// l'id di dialogo (il byte 1 delle sue proprieta'). Spento = c'e' un abitante
// davanti e nel byte basso c'e' il suo id di oggetto.
// E' lo stesso trucco di slice72 sull'intro: un overlay con due ingressi costa
// un bit, un secondo overlay costa 16KB e una `svc_` in piu'.
#define TALK_ARG_TILE  0x8000

// --- la pianta del riquadro, 32x24 -----------------------------------
// Sta in BASSO e comincia alla riga 14: il giocatore e' fisso alla cella
// (15,11) e la sua sprite e' alta 16 pixel, cioe' righe 11 e 12. Un riquadro
// che cominciasse piu' su lo coprirebbe -- e chi parla vuole vedere a chi.
#define BOX_TOP     14
#define BOX_BOT     23
#define BOX_LEFT     2
#define BOX_RIGHT   29
#define TEXT_COL     4
#define TEXT_ROW     15
#define TEXT_COLS   FF1_DLG_MAX_COLS   /* 24, misurate sui testi veri */
#define TEXT_ROWS   FF1_DLG_MAX_ROWS   /* 8 */

// Le tile della citta' NON sono il font: la mappa dei 256 tile sta in
// world_state.h, e li' il font comincia a 160 invece che a $20. Da cui questa
// macro, che e' l'unica differenza fra scrivere qui e scrivere in una
// qualunque altra schermata del gioco.
#define TILE(c)     ((unsigned char)(TOWN_FONT_BASE + (unsigned char)(c) - TOWN_FONT_FIRST))

// =====================================================================
//  Primitive di schermo
// =====================================================================
// Non condivise con gli altri overlay: un .h di helper linkato in due banchi
// finirebbe due volte in ROM comunque (i banchi non si vedono fra loro) e in
// cambio farebbe credere che esista un modulo comune. Qui per giunta sono
// DIVERSE -- scrivono tile di font a base 160, non caratteri ASCII, perche' in
// citta' il font non e' a $20.
static void put_tile(unsigned char col, unsigned char row, unsigned char t) {
    svc_vwrite(&t, 0x1800 + (unsigned int)row * 32 + col, 1);
}

static void fill_tiles(unsigned char col, unsigned char row,
                       unsigned char n, unsigned char t) {
    svc_vfill(0x1800 + (unsigned int)row * 32 + col, t, (unsigned int)n);
}

// =====================================================================
//  Il riquadro
// =====================================================================
static void draw_box(void) {
    unsigned char r;
    unsigned char w = (unsigned char)(BOX_RIGHT - BOX_LEFT - 1);

    for (r = (unsigned char)(BOX_TOP + 1); r < BOX_BOT; r++) {
        put_tile(BOX_LEFT,  r, TOWN_VBAR_TILE);
        put_tile(BOX_RIGHT, r, TOWN_VBAR_TILE);
        fill_tiles((unsigned char)(BOX_LEFT + 1), r, w, TILE(' '));
    }
    put_tile(BOX_LEFT,  BOX_TOP, TILE('+'));
    put_tile(BOX_RIGHT, BOX_TOP, TILE('+'));
    fill_tiles((unsigned char)(BOX_LEFT + 1), BOX_TOP, w, TILE('-'));
    put_tile(BOX_LEFT,  BOX_BOT, TILE('+'));
    put_tile(BOX_RIGHT, BOX_BOT, TILE('+'));
    fill_tiles((unsigned char)(BOX_LEFT + 1), BOX_BOT, w, TILE('-'));
}

// Il testo. NIENTE a capo automatico: le stringhe di FF1 portano gia' i propri
// (il codice $05 del ROM), e tools/extract_dialogue.ps1 si ferma con un errore
// se una riga supera le 24 colonne o un testo le 8 righe. Un a capo calcolato
// qui sarebbe un secondo impaginatore che puo' non essere d'accordo col primo.
static void draw_text(unsigned int dlg) {
    unsigned char buf[TEXT_COLS];
    const unsigned char *p = &ff1_dlg_text[ff1_dlg_offset[dlg]];
    unsigned char row = TEXT_ROW;
    unsigned char n = 0;
    unsigned char c;

    while (1) {
        c = *p++;
        if (c == 0 || c == FF1_DLG_NEWLINE) {
            if (n) svc_vwrite(buf, 0x1800 + (unsigned int)row * 32 + TEXT_COL, (unsigned int)n);
            if (c == 0) return;
            n = 0;
            row++;
            if (row >= TEXT_ROW + TEXT_ROWS) return;
            continue;
        }
        if (n < TEXT_COLS) buf[n++] = TILE(c);
    }
}

// Attesa. Si chiude col FIRE1 e col FIRE2, tutti e due A FRONTE: si arriva qui
// con il FIRE1 che ha aperto il dialogo ancora premuto, e a livello il
// riquadro si chiuderebbe nello stesso quadro in cui si e' aperto -- cioe' un
// abitante che non dice niente, che e' come un abitante rotto.
static void wait_close(void) {
    unsigned char prev = 1;   /* 1 = "qualcosa era gia' premuto": vedi sopra */
    unsigned char now;
    unsigned int j;
    while (1) {
        svc_wait_vblank();
        j = svc_joystick();
        now = (unsigned char)((j & (MOVE_FIRE1 | MOVE_FIRE2)) != 0);
        if (now) { if (!prev) return; }
        prev = now;
    }
}

// =====================================================================
//  Chi decide quale delle tre battute esce
// =====================================================================
// I numeri sono quelli di tools/extract_dialogue.ps1 (ff1_obj_kind) e i due
// elenchi devono restare allineati -- il generatore li riscrive in testa al
// file che produce apposta, cosi' una divergenza si vede leggendolo.
//
// I quattro byte non hanno un significato fisso: dipende dalla routine. Per le
// generiche il byte 0 e' il PARAMETRO della condizione e i byte 1-3 sono i tre
// dialoghi possibili (bank_0E.asm:1025).
#define K_NONE      0
#define K_NORM      1
#define K_IFVIS     2
#define K_IFITEM    3
#define K_IFEVENT   4
#define K_4ORB      5
#define K_GOBRIDGE  6
#define K_INVIS     7
// slice77: le routine che CAMBIANO qualcosa. Scrivono da sole cio' che e' RAM
// (flag di visibilita', il LUTE, il ponte); cio' che ha bisogno del motore --
// fanfara, battaglia, teletrasporto -- torna nei bit alti (TALK_FX_* in
// world_state.h) e lo esegue town_tick a riquadro chiuso.
#define K_KING      8
#define K_PRINCESS1 9
#define K_PRINCESS2 10
#define K_GARLAND   11

// OBJID_PRINCESS_2: la principessa SALVATA, l'oggetto che comincia invisibile
// e diventa visibile quando la si libera dal Temple of Fiends. Mezza Coneria
// guarda quel bit per sapere se rispondere "salvatela!" o "grazie".
#define OBJID_PRINCESS_2  0x12
// Garland e la principessa RAPITA, tutti e due nel tempio: sono gli oggetti
// che le rispettive routine nascondono (HideThisMapObject sul NES).
#define OBJID_GARLAND     0x02
#define OBJID_PRINCESS_1  0x03

static unsigned char all_orbs_lit(void) {
    return (unsigned char)(PARTY.item[ITEM_ORB_FIRST + 0] &&
                           PARTY.item[ITEM_ORB_FIRST + 1] &&
                           PARTY.item[ITEM_ORB_FIRST + 2] &&
                           PARTY.item[ITEM_ORB_FIRST + 3]);
}

// Torna l'id del dialogo da mostrare NEL BYTE BASSO, e gli eventuali effetti
// TALK_FX_* nei bit alti. Da slice77 ci sono anche le routine che CAMBIANO
// qualcosa -- il Re, Garland e le due principesse; le restanti (Talk_Replace,
// Talk_BlackOrb, Talk_fight...) rispondono ancora con la prima battuta,
// finche' non c'e' una mappa che le usa.
static unsigned int resolve_object(unsigned char oid) {
    const unsigned char *d = &ff1_obj_talk[(unsigned int)oid * 4];
    unsigned char kind = ff1_obj_kind[oid];

    if (kind == K_IFVIS) {
        if (OBJ_VISIBLE(d[0])) return d[2];
        return d[1];
    }
    if (kind == K_IFEVENT) {
        if (OBJ_EVENT(d[0])) return d[2];
        return d[1];
    }
    if (kind == K_IFITEM) {
        if (PARTY.item[d[0]]) return d[1];
        return d[2];
    }
    if (kind == K_4ORB) {
        if (all_orbs_lit()) return d[1];
        return d[2];
    }
    if (kind == K_GOBRIDGE) {
        // "Vai dal Re": [1] solo nella finestra fra la principessa salvata e il
        // ponte costruito. Due `if` annidati e non un `&&`: dentro un `?:`
        // sccz80 lo compila sbagliato, e questa e' esattamente la forma in cui
        // qualcuno un giorno ci metterebbe un `?:`
        // ([[sccz80-ternary-and-trap]]).
        if (OBJ_VISIBLE(OBJID_PRINCESS_2)) {
            if ((WORLD.progress & WPROG_BRIDGE) == 0) return d[1];
        }
        return d[2];
    }
    if (kind == K_INVIS) {
        if (!OBJ_VISIBLE(OBJID_PRINCESS_2)) {
            if (PARTY.item[ITEM_LUTE] == 0) return d[1];
        }
        return d[2];
    }
    if (kind == K_KING) {
        // Talk_KingConeria (bank_0E.asm:1039). [1] finche' la principessa e'
        // rapita; la PRIMA volta che la rivede, ordina il ponte e suona la
        // fanfara ([2]); poi [3] per sempre. Il ponte e' un bit di
        // WORLD.progress, cioe' RAM: si accende qui, come sul NES fa
        // `INC bridge_vis` dentro la routine stessa.
        if (!OBJ_VISIBLE(OBJID_PRINCESS_2)) return d[1];
        if (WORLD.progress & WPROG_BRIDGE) return d[3];
        WORLD.progress |= WPROG_BRIDGE;
        return TALK_FX_FANFARE | d[2];
    }
    if (kind == K_PRINCESS2) {
        // Talk_Princess2 (bank_0E.asm:1409): la prima volta da' il LUTE con
        // la fanfara, poi [2]. `PARTY.item` e' RAM condivisa: l'oggetto
        // chiave entra nello zaino da qui, come `INC item_lute`.
        if (PARTY.item[ITEM_LUTE]) return d[2];
        PARTY.item[ITEM_LUTE] = 1;
        return TALK_FX_FANFARE | d[1];
    }
    if (kind == K_GARLAND) {
        // Talk_Garland (bank_0E.asm:1059): si nasconde (HideThisMapObject) e
        // apre la battaglia $7F. QUALE battaglia lo sa il motore: qui si
        // chiede solo "battaglia", col bit TALK_FX_FIGHT.
        WORLD.flags[OBJID_GARLAND] &= (unsigned char)~GMFLG_OBJVISIBLE;
        return TALK_FX_FIGHT | d[1];
    }
    if (kind == K_PRINCESS1) {
        // Talk_Princess1 (bank_0E.asm:1072): la rapita si nasconde, la
        // salvata compare al castello, e il gruppo viene teletrasportato
        // nella sua stanza (NORM $3F, eseguito dal motore a riquadro chiuso).
        WORLD.flags[OBJID_PRINCESS_1] &= (unsigned char)~GMFLG_OBJVISIBLE;
        WORLD.flags[OBJID_PRINCESS_2] |= GMFLG_OBJVISIBLE;
        return TALK_FX_TELE | d[1];
    }
    if (kind == K_NONE) return 0;
    // K_NORM e tutto quello che non e' ancora implementato: la prima battuta.
    // E' la scelta del NES per Talk_norm, che e' anche il caso piu' comune.
    return d[1];
}

// =====================================================================
unsigned int overlay_main(unsigned int arg) {
    unsigned int dlg;
    unsigned int fx = 0;

    if (arg & TALK_ARG_TILE) {
        dlg = arg & 0x00FF;
    } else {
        // slice77: il byte basso e' il dialogo, i bit alti gli effetti
        // TALK_FX_* che il motore esegue a riquadro chiuso.
        dlg = resolve_object((unsigned char)(arg & 0x00FF));
        fx  = dlg & 0xFF00;
        dlg &= 0x00FF;
    }
    if (dlg >= FF1_DLG_COUNT) dlg = 0;

    draw_box();
    draw_text(dlg);
    wait_close();
    // Si torna l'id del dialogo MOSTRATO, non zero. E' l'unica cosa che la
    // citta' non puo' sapere da sola: quale delle tre battute e' uscita lo
    // decide qui dentro, guardando i flag di gioco. Senza questo valore una
    // corsa di validazione potrebbe dire "ha parlato all'abitante giusto" ma
    // non "gli ha fatto dire la frase giusta per il momento della storia in
    // cui siamo" -- che e' proprio cio' che cambia quando la principessa viene
    // salvata e mezza Coneria cambia risposta.
    return fx | dlg;
}
