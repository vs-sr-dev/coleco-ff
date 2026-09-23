// =====================================================================
//  ovl_bridge.c -- la scena del ponte. Overlay di CODICE (banco 27)
// =====================================================================
// OTTAVO overlay del progetto, e il primo che disegna una FIGURA invece di
// una schermata di testo: la title card di FINAL FANTASY, quella che sul NES
// compare la prima volta che si attraversa il ponte, con le quattro pagine di
// storia e il Prologue.
//
// PERCHE' UN BANCO: non e' il codice, e' l'IMMAGINE -- 6144 byte di pattern
// piu' 6144 di colore. Il codice qui dentro sono poche centinaia di byte.
//
// COME CI STA UNA FIGURA A SCHERMO INTERO SU UN TMS9918
//   In Mode 2 la tabella dei pattern e' divisa in TRE blocchi da 2KB, uno per
//   terzo di schermo, e ogni blocco tiene 256 tile -- cioe' esattamente quante
//   celle ha un terzo di schermo (8 righe x 32 colonne). Quindi ogni cella
//   puo' avere la sua tile privata e la name table diventa NT[i] = i & 0xFF.
//   E' il "modo bitmap" del TMS, e questa e' la prima schermata del progetto
//   che lo usa: tutte le altre riusano poche tile molte volte.
//
//   Conseguenza che decide come si scrive il testo: NON esiste un "font
//   caricato in VRAM" da richiamare con la name table, perche' la name table
//   e' gia' impegnata a fare da griglia. Una lettera si disegna SCRIVENDO IL
//   SUO PATTERN nella tile privata della cella che la ospita. Costa 8 byte di
//   VRAM per carattere invece di 1, e in cambio il testo puo' stare ovunque
//   sopra la figura senza toccarla.
//
// IL FONT VIENE DAL BIOS ($15A3), che sta sotto i $2000 ed e' sempre mappato:
// non e' un dato di questo banco e non serve nessuna escursione.
//
// LA REGOLA DEGLI OVERLAY ANNIDATI: qui non serve (ci si entra dal ciclo
// dell'overworld, che sta nella finestra fissa) ma si rispetta lo stesso --
// nemmeno un `static` mutabile. Vedi [[slice68-player-magic]].
// =====================================================================

#define SVC_OVERLAY
#include "svc_api.h"

#define FF1_BRIDGE_DEFINE_DATA
#include "data/bridge_scene.h"
#define FF1_STORY_DEFINE_DATA
#include "data/story_text.h"

// Costanti di games.h: l'overlay non linka nulla della libreria.
#define MOVE_FIRE1 16
#define MOVE_FIRE2 32

// Il font del BIOS: 96 caratteri da $20 a $7F, 8 byte l'uno.
#define BIOS_FONT_ADDR   ((const unsigned char *)0x15A3)
#define FONT_FIRST       0x20

// --- la pianta della pagina di testo ---------------------------------
// Sta in ALTO, sul cielo: la meta' bassa della figura ha il logo, la rupe e i
// quattro eroi, cioe' tutto quello che si deve vedere. Sul NES il riquadro sta
// a (4,4) ed e' 18x12; qui il testo e' al massimo 16x6 (misurato da
// tools/extract_story.ps1) e sta in una finestra piu' stretta.
#define TEXT_COL   7
#define TEXT_ROW   2
#define TEXT_COLS  FF1_STORY_MAX_COLS
#define TEXT_ROWS  FF1_STORY_MAX_ROWS

// Bianco su nero per il testo: sul cielo ciano un testo bianco senza fondo
// non si legge, e il nero e' il colore che la figura usa gia' (la rupe).
#define TEXT_INK   0xF1

// Quanto resta a schermo una pagina. Sul NES sono 512 quadri massimi, e si
// passa oltre col tasto (Story_Wait, bank_0D.asm:2395). Qui uguale: 512 e' un
// tempo di lettura giusto per due righe e lunghissimo per sei, ed e' proprio
// per questo che il tasto c'e'.
#define PAGE_FRAMES  512

// =====================================================================
//  Primitive
// =====================================================================
// La cella (col,row) ha la SUA tile: pattern a $0000 + i*8, colore a $2000 +
// i*8, dove i = row*32+col. Il terzo di schermo non entra nel conto proprio
// perche' i tre blocchi da 2KB sono contigui e i = 0..767 li attraversa.
static unsigned int cell_addr(unsigned char col, unsigned char row) {
    return ((unsigned int)row * 32 + col) * 8;
}

// Un carattere, scritto nel pattern della sua cella. Il colore si scrive
// SEMPRE, anche per lo spazio: e' quello che apre la "finestra" nera sopra la
// figura, e senza, una riga corta lascerebbe pezzi di cielo in mezzo al testo.
static void put_char(unsigned char col, unsigned char row, unsigned char c) {
    unsigned int a = cell_addr(col, row);
    unsigned char ink[8];
    unsigned char k;
    for (k = 0; k < 8; k++) ink[k] = TEXT_INK;
    svc_vwrite(BIOS_FONT_ADDR + ((unsigned int)(c - FONT_FIRST) * 8), a, 8);
    svc_vwrite(ink, 0x2000 + a, 8);
}

// Rimette la figura in una cella: pattern e colore tornano quelli originali.
// E' cosi' che una pagina si cancella -- non riscrivendo tutto lo schermo, ma
// solo le celle che il testo aveva occupato.
static void restore_cell(unsigned char col, unsigned char row) {
    unsigned int a = cell_addr(col, row);
    svc_vwrite(&ff1_bridge_pattern[a], a, 8);
    svc_vwrite(&ff1_bridge_color[a], 0x2000 + a, 8);
}

static void clear_page(void) {
    unsigned char r, c;
    for (r = 0; r < TEXT_ROWS; r++) {
        for (c = 0; c < TEXT_COLS; c++) restore_cell(TEXT_COL + c, TEXT_ROW + r);
    }
}

// =====================================================================
//  Il testo
// =====================================================================
// NIENTE a capo automatico: le pagine portano gia' i propri (il codice $01
// del ROM) e tools/extract_story.ps1 si ferma con un errore se una riga supera
// la larghezza. Un impaginatore qui sarebbe un secondo giudice che puo' non
// essere d'accordo col primo.
//
// IL TESTO E' CENTRATO, e non e' un vezzo: le quattro pagine sono larghe da 6
// a 16 caratteri e allineate a sinistra sembrerebbero cadere dal bordo. Sul
// NES la centratura e' cotta negli spazi della stringa; qui le stringhe sono
// gia' senza spazi di riempimento (l'estrattore le taglia), quindi si centra.
static void draw_page(unsigned int page) {
    const unsigned char *p = &ff1_story_text[ff1_story_offset[page]];
    unsigned char buf[TEXT_COLS];
    unsigned char row = 0;
    unsigned char n = 0;
    unsigned char c, k, pad;

    while (1) {
        c = *p++;
        if (c == 0 || c == FF1_STORY_NEWLINE) {
            if (n) {
                pad = (unsigned char)((TEXT_COLS - n) / 2);
                for (k = 0; k < n; k++) {
                    put_char((unsigned char)(TEXT_COL + pad + k), (unsigned char)(TEXT_ROW + row), buf[k]);
                }
            }
            if (c == 0) return;
            n = 0;
            row++;
            if (row >= TEXT_ROWS) return;
            continue;
        }
        if (n < TEXT_COLS) buf[n++] = c;
    }
}

// Attesa: il tasto passa oltre, altrimenti si aspetta PAGE_FRAMES. A FRONTE,
// perche' si arriva qui col tasto che ha chiuso la pagina precedente ancora
// premuto -- a livello, le quattro pagine passerebbero tutte in un quadro.
static void wait_page(void) {
    unsigned int t = 0;
    unsigned char prev = 1;   /* 1 = "qualcosa era gia' premuto" */
    unsigned char now;
    unsigned int j;
    while (t < PAGE_FRAMES) {
        svc_wait_vblank();
        t++;
        j = svc_joystick();
        now = (unsigned char)((j & (MOVE_FIRE1 | MOVE_FIRE2)) != 0);
        if (now) { if (!prev) return; }
        prev = now;
    }
}

// =====================================================================
unsigned int overlay_main(unsigned int arg) {
    unsigned int i;
    unsigned char nt[32];

    (void)arg;

    // La figura. Pattern e colore vanno in VRAM COSI' COME SONO: sono gia'
    // nell'ordine delle celle, e i tre blocchi da 2KB sono contigui.
    svc_vwrite(ff1_bridge_pattern, 0x0000, FF1_BRIDGE_BYTES);
    svc_vwrite(ff1_bridge_color,   0x2000, FF1_BRIDGE_BYTES);

    // La name table: NT[i] = i & 0xFF, cioe' ogni cella punta alla propria
    // tile. Si scrive una riga alla volta -- 32 byte di pila invece di 768.
    for (i = 0; i < 24; i++) {
        unsigned char k;
        for (k = 0; k < 32; k++) nt[k] = (unsigned char)((i * 32 + k) & 0xFF);
        svc_vwrite(nt, 0x1800 + i * 32, 32);
    }

    // Gli sprite non servono e vanno tolti di mezzo: qui arriva il mapman
    // dell'overworld, che resterebbe appeso in mezzo al cielo.
    for (i = 0; i < 8; i++) svc_put_sprite16((unsigned char)i, 0, 200, 0, 1);

    for (i = 0; i < FF1_STORY_PAGES; i++) {
        draw_page(i);
        wait_page();
        clear_page();
    }

    return 0;
}
