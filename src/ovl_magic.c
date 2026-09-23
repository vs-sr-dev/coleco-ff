// =====================================================================
//  ovl_magic.c -- la magia FUORI dalla battaglia, overlay di CODICE (banco 25)
// =====================================================================
// SESTO overlay del progetto, e il SECONDO annidato: ci si entra dal menu
// (banco 24) con `svc_run_overlay(25, chi | in_town)`.
//
// PERCHE' UN BANCO SUO. Il banco 24 aveva 3328 byte liberi dopo slice74 e
// questa schermata ne chiede piu' o meno altrettanti: ci starebbe *a pelo*,
// che e' il modo in cui il problema si scopre a meta' lavoro. Un banco costa
// 16KB su 512 e non ne mancano.
//
// LA REGOLA CHE VALE SOLO PER GLI OVERLAY ANNIDATI, e qui e' assoluta:
// **NIENTE `static` MUTABILI**. La BSS degli overlay e' la stessa per tutti
// ($6C00, crt/overlay_crt0.asm), e mentre questo file gira il banco 24 ha le
// sue variabili ancora vive -- `prev_bits`, `nm_buf`, la lista dello zaino. Un
// `static` qui dentro ci scriverebbe sopra. E' la trappola di slice68, e la
// risposta e' la stessa: tutto in locali, compresi i due byte dei fronti di
// pressione, che viaggiano dentro `edge_t`.
//
// COSA FA. Le tredici magie che FF1 permette di lanciare fuori dalla
// battaglia, cioe' l'ultima voce rimasta nella lista dei "NOTHING HAPPENS"
// dichiarati:
//   CURE CUR2 CUR3   HP a UNO, tiro casuale
//   CUR4             HP al massimo a UNO
//   HEAL HEL2 HEL3   HP a TUTTI, tiro casuale
//   LIFE LIF2        rialzano un caduto (1 HP / HP pieni)
//   PURE SOFT        tolgono veleno e pietra
//   WARP EXIT        riportano in overworld -- da una citta'
//
// DUE FIX DI INTENTO rispetto al NES, tutti e due schedati in
// docs/Coleco_improvements.md:
//   1. CUR4 non controlla le alterazioni (il disassembly stesso scrive
//      "BUGGED", bank_0E.asm:6547): sul NES riempie gli HP di un morto, che
//      resta morto. Qui rifiuta come tutta la famiglia CURE.
//   2. WARP/EXIT dove non c'e' un posto dove andare CONSUMANO comunque la
//      carica sul NES. Qui il rifiuto arriva prima di pagare.
//
// UN BUG DEL NES CHE DA NOI NON PUO' ESISTERE: il calcolo dell'id
// dell'incantesimo scelto usa `ORA` dove voleva `ADC` (bank_0E.asm:6404), e
// l'ottava magia di ogni livello prende l'id della prima del livello dopo. Sul
// NES non si vede perche' l'ottava e' sempre magia nera, che fuori dalla
// battaglia non si lancia. Noi facciamo `livello*8 + (valore-1)` da slice68,
// che e' la formula giusta e vale per tutte e otto.
// =====================================================================

#define SVC_OVERLAY
#include "svc_api.h"
#include "party_state.h"
#include "data/item_names.h"   // SOLO le macro degli id (nessun dato)

// Costanti di games.h: l'overlay non linka nulla della libreria.
#define MOVE_RIGHT  1
#define MOVE_LEFT   2
#define MOVE_DOWN   4
#define MOVE_UP     8
#define MOVE_FIRE1 16
#define MOVE_FIRE2 32

#define INK_DARK_BLUE  0x04

// --- la pianta dello schermo, 32x24 ----------------------------------
#define ROW_TITLE     1
#define ROW_L0        3      /* otto livelli, righe 3-10 */
#define COL_CELL0     8      /* tre caselle per livello, passo 7 */
#define CELL_STEP     7
#define ROW_PARTY     13     /* i quattro personaggi: bersaglio e HP */
#define ROW_PROMPT    18
#define ROW_MSG       21
#define ROW_HINT      23

#define N_LEVELS  PARTY_SPELL_LEVELS
#define N_COLS    PARTY_SPELLS_PER_LEVEL
#define SPELL_NAME_LEN 4     /* i nomi delle magie sono quattro lettere */

// --- gli id delle tredici, in chiaro ---------------------------------
// L'id e' `nome_in_item_names - $B0`: i 64 incantesimi occupano $B0-$EF.
// Scritti a mano e non calcolati perche' e' cosi' anche sul NES (MG_CURE e
// compagnia sono costanti) e perche' un elenco si rilegge; una formula che
// mappa tredici casi sparsi, no.
#define MG_CURE  0
#define MG_CUR2 16
#define MG_HEAL 19
#define MG_PURE 24
#define MG_CUR3 32
#define MG_LIFE 33
#define MG_HEL2 35
#define MG_WARP 38
#define MG_SOFT 40
#define MG_EXIT 41
#define MG_CUR4 48
#define MG_HEL3 51
#define MG_LIF2 56

static const char txt_title[]   = "MAGIC";
static const char txt_hint[]    = "FIRE1 CAST   FIRE2 BACK";
static const char txt_hint_who[]= "FIRE1 OK     FIRE2 BACK";
static const char txt_choose[]  = "WHICH SPELL?";
static const char txt_who[]     = "ON WHOM?";
static const char txt_empty[]   = "NOTHING THERE";
static const char txt_nomp[]    = "NOT ENOUGH MP";
static const char txt_nothere[] = "IT DOES NOTHING HERE";
static const char txt_nouse[]   = "THAT ONE IS FOR BATTLE";
static const char txt_better[]  = "FEELING BETTER!";
static const char txt_allwell[] = "THE PARTY FEELS BETTER!";
static const char txt_alive[]   = "BACK ON HIS FEET!";
static const char txt_cured[]   = "THE POISON IS GONE";
static const char txt_soften[]  = "THE STONE CRUMBLES";
static const char txt_noneed[]  = "THAT ONE DOESN'T NEED IT";
static const char txt_warp[]    = "THE PARTY IS PULLED AWAY";
static const char txt_dead[]    = "DEAD";
static const char txt_stone[]   = "STON";
static const char txt_pois[]    = "PSN";
static const char txt_dashes[]  = "----";

// =====================================================================
//  Primitive di schermo
// =====================================================================
// Copiate dagli altri overlay e non condivise: un .h di helper linkato in due
// overlay finirebbe due volte in ROM comunque -- i banchi non si vedono fra
// loro -- e in cambio farebbe credere che esista un modulo comune.
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

static void render_num_right(unsigned char col, unsigned char row, unsigned int v) {
    unsigned char buf[6];
    int n = 0, k;
    if (v == 0) { buf[0] = '0'; n = 1; }
    while (v > 0 && n < 6) { buf[n] = (unsigned char)('0' + (v % 10)); v /= 10; n++; }
    for (k = 0; k < n; k++) {
        svc_vwrite(&buf[k], 0x1800 + (unsigned int)row * 32 + col - k, 1);
    }
}

// I FRONTI DI PRESSIONE IN UNA STRUTTURA LOCALE, non in due `static`: vedi
// l'intestazione. Il primo `read_edge` di una schermata parte con `pb = 0xFF`,
// cosi' tutto quello che e' gia' premuto vale come tenuto -- entrando si sta
// ancora premendo il FIRE1 che ha scelto la voce del menu.
typedef struct { unsigned char pb, pk; } edge_t;

static unsigned int read_edge(edge_t *e) {
    unsigned int j;
    unsigned char bits, key, ebits, ekey;
    svc_wait_vblank();
    j    = svc_joystick();
    bits = (unsigned char)(j & 0x00FF);
    key  = (unsigned char)(j >> 8);
    ebits = (unsigned char)(bits & ~e->pb);
    ekey = 0;
    if (key != 0) {
        if (key != e->pk) ekey = key;
    }
    e->pb = bits;
    e->pk = key;
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

// =====================================================================
//  Il tiro, e la scelta di non usare il contatore dei quadri
// =====================================================================
// Sul NES la quantita' curata viene dal FRAME COUNTER mascherato
// (`UseMagic_CURE`, bank_0E.asm:6474: "use the frame counter as a make-shift
// pRNG"). E' un ripiego, dichiarato tale dal commento del disassembly: fuori
// dalla battaglia il generatore vero non e' inizializzato.
//
// Qui si usa `svc_battle_rng`, che c'e' gia' ed e' un generatore vero. Gli
// INTERVALLI restano quelli del NES esatti -- CURE 16-31, CUR2 32-63,
// CUR3 64-127, HEAL 16-23, HEL2 32-47, HEL3 64-95 -- quindi cio' che cambia
// non e' quanto si cura, e' solo che il numero non dipende piu' da QUANDO si
// preme il tasto. Sul NES quella dipendenza e' sfruttabile: contando i quadri
// si sceglie la cura massima.
static unsigned char roll(unsigned char lo, unsigned char hi) {
    unsigned int range = (unsigned int)hi + 1u - (unsigned int)lo;
    return (unsigned char)((unsigned int)lo +
        (((unsigned int)svc_battle_rng() * range) >> 8));
}

// =====================================================================
//  Dalla casella all'incantesimo
// =====================================================================
// `ch_spells` fuori battaglia tiene 1-8: QUALE degli otto del livello, non il
// posto. La formula e' quella di ConvertOBStatsToIB (bank_0B.asm:379), la
// stessa di ovl_btlmagic.c. Vedi anche il bug dell'`ORA` nell'intestazione.
static unsigned char spell_id_of(chr_t *c, unsigned char lvl, unsigned char col) {
    unsigned char v = c->spells[(unsigned int)lvl * N_COLS + col];
    if (v == 0) return 0xFF;
    return (unsigned char)(lvl * 8 + (v - 1));
}

// Il nome, quattro lettere, dal banco 11 (tabella 4 di svc_fetch_btl). Il
// buffer e' del CHIAMANTE: qui non ci sono `static`.
static void fetch_spell_name(unsigned char mid, unsigned char *dst) {
    svc_fetch_btl(4, ((unsigned int)(FF1_ITEM_SPELL_BASE + mid)) << 3,
                  FF1_ITEM_NAME_LEN, dst);
    dst[SPELL_NAME_LEN] = 0;
}

// =====================================================================
//  La griglia degli otto livelli
// =====================================================================
static void draw_level(chr_t *c, unsigned char lvl) {
    unsigned char row = (unsigned char)(ROW_L0 + lvl);
    unsigned char k, id;
    unsigned char nm[FF1_ITEM_NAME_LEN];

    clear_row(row);
    render_tile(0, row, 'L');
    render_tile(1, row, (unsigned char)('1' + lvl));
    // Le cariche del livello. In FF1 gli "MP" non sono un serbatoio unico: sono
    // otto contatori separati, ed e' il motivo per cui la griglia e' fatta a
    // righe di livello invece che a lista di incantesimi ([[feedback-hud-parity]]).
    // Le tre colonne sono CONTIGUE: 3, 4, 5. `render_num_right` allinea a
    // destra della colonna che riceve, quindi il massimo va alla 5 e non alla
    // 6 -- con la 6 esce "9/ 9", che a schermo sembra un carattere sporco piu'
    // che un numero mal messo. Trovato dalla VRAM, come i tre difetti di
    // slice73: a occhio quello spazio non si nota.
    render_num_right(3, row, c->curmp[lvl]);
    render_tile(4, row, '/');
    render_num_right(5, row, c->maxmp[lvl]);
    for (k = 0; k < N_COLS; k++) {
        unsigned char col = (unsigned char)(COL_CELL0 + k * CELL_STEP);
        id = spell_id_of(c, lvl, k);
        if (id == 0xFF) {
            render_string((unsigned char)(col + 1), row, txt_dashes);
        } else {
            fetch_spell_name(id, nm);
            render_string((unsigned char)(col + 1), row, (const char *)nm);
        }
    }
}

static void draw_grid(chr_t *c) {
    unsigned char lvl;
    for (lvl = 0; lvl < N_LEVELS; lvl++) draw_level(c, lvl);
}

// Cursore: un carattere per cella, tutte e ventiquattro. Non si tiene traccia
// di dov'era prima -- ripulire "quella di prima" e' il modo in cui restano due
// cursori a schermo il giorno che una schermata si ridisegna in mezzo.
static void draw_grid_cursor(unsigned char lvl, unsigned char col,
                             unsigned char on) {
    unsigned char l, k, ch;
    for (l = 0; l < N_LEVELS; l++) {
        for (k = 0; k < N_COLS; k++) {
            ch = ' ';
            if (on) {
                if (l == lvl) {
                    if (k == col) ch = '>';
                }
            }
            render_tile((unsigned char)(COL_CELL0 + k * CELL_STEP),
                        (unsigned char)(ROW_L0 + l), ch);
        }
    }
}

// =====================================================================
//  La striscia del gruppo
// =====================================================================
// Il TAG dell'alterazione non e' un abbellimento: e' l'unica cosa che
// distingue "LIFE non ha funzionato" da "quello non era morto".
static void draw_ail_tag(unsigned char col, unsigned char row, unsigned char ail) {
    clear_span(col, row, 4);
    if (ail & AIL_DEAD)        render_string(col, row, txt_dead);
    else if (ail & AIL_STONE)  render_string(col, row, txt_stone);
    else if (ail & AIL_POISON) render_string(col, row, txt_pois);
}

static void draw_party(void) {
    unsigned char i;
    for (i = 0; i < PARTY.n; i++) {
        chr_t *c = &PARTY.chr[i];       /* il puntatore una volta sola */
        unsigned char row = (unsigned char)(ROW_PARTY + i);
        clear_row(row);
        render_tile(1, row, (unsigned char)('1' + i));
        render_string(3, row, c->name);
        render_string(11, row, "HP");
        render_num_right(18, row, c->curhp);
        render_tile(19, row, '/');
        render_num_right(24, row, c->maxhp);
        draw_ail_tag(26, row, c->ailments);
    }
}

static void draw_party_cursor(unsigned char who, unsigned char on) {
    unsigned char i, ch;
    for (i = 0; i < PARTY.n; i++) {
        ch = ' ';
        if (on) {
            if (i == who) ch = '>';
        }
        render_tile(0, (unsigned char)(ROW_PARTY + i), ch);
    }
}

// Scelta del bersaglio. Torna l'indice, o 0xFF se si rinuncia. Il tastierino
// sceglie in un tasto solo -- e' il vantaggio del Coleco ([[design-input]]).
static unsigned char pick_target(edge_t *e) {
    unsigned int ev;
    unsigned char bits, key, who;

    who = 0;
    draw_prompt(txt_who);
    draw_hint(txt_hint_who);
    draw_party_cursor(who, 1);
    while (1) {
        ev   = read_edge(e);
        bits = (unsigned char)(ev & 0x00FF);
        key  = (unsigned char)(ev >> 8);
        if (bits & MOVE_FIRE2) { draw_party_cursor(who, 0); return 0xFF; }
        if (bits & (MOVE_UP | MOVE_DOWN)) {
            who = (unsigned char)((bits & MOVE_UP)
                    ? (who ? who - 1 : PARTY.n - 1)
                    : ((who + 1 >= PARTY.n) ? 0 : who + 1));
            draw_party_cursor(who, 1);
        } else if (key >= '1' && key < (unsigned char)('1' + PARTY.n)) {
            who = (unsigned char)(key - '1');
            draw_party_cursor(who, 1);
        } else if (bits & MOVE_FIRE1) {
            draw_party_cursor(who, 0);
            return who;
        }
    }
}

// =====================================================================
//  Gli effetti
// =====================================================================
// HP a uno, senza sfondare il massimo. `MenuRecoverHP_Abs` del NES non guarda
// gli HP correnti ne' le alterazioni: il controllo lo fa il chiamante, ed e'
// proprio dove il NES lo dimentica per CUR4.
static void recover_hp(chr_t *c, unsigned int amount) {
    c->curhp = (unsigned int)(c->curhp + amount);
    if (c->curhp > c->maxhp) c->curhp = c->maxhp;
}

// Le sei della famiglia CURE/CUR4 e le tre di LIFE/PURE/SOFT: tutte su UN
// bersaglio, tutte con un rifiuto diverso. Torna il messaggio, e 0 se la
// carica NON va consumata.
static const char *cast_on_one(unsigned char mid, unsigned char who) {
    chr_t *c = &PARTY.chr[who];

    if (mid == MG_LIFE || mid == MG_LIF2) {
        if (!(c->ailments & AIL_DEAD)) return 0;
        c->ailments = (unsigned char)(c->ailments & ~AIL_DEAD);
        // LIFE da' UN HP, LIF2 li rimette tutti. La differenza fra le due e'
        // solo questa riga -- sul NES sono due routine gemelle.
        if (mid == MG_LIFE) c->curhp = 1;
        else                c->curhp = c->maxhp;
        return txt_alive;
    }
    if (mid == MG_PURE) {
        if (!(c->ailments & AIL_POISON)) return 0;
        c->ailments = (unsigned char)(c->ailments & ~AIL_POISON);
        return txt_cured;
    }
    if (mid == MG_SOFT) {
        if (!(c->ailments & AIL_STONE)) return 0;
        c->ailments = (unsigned char)(c->ailments & ~AIL_STONE);
        // Un HP, come fa la clinica e come fa l'oggetto SOFT: in FF1 un vivo a
        // zero HP non e' uno stato che esiste.
        if (c->curhp == 0) c->curhp = 1;
        return txt_soften;
    }
    // Famiglia CURE, CUR4 compresa. SU UN CADUTO O UN PIETRIFICATO NON SI USA,
    // e per CUR4 questo e' il fix #1 dell'intestazione: il NES non controlla
    // (bank_0E.asm:6547 dice "BUGGED") e riempie gli HP di un morto, che resta
    // morto -- una carica di sesto livello spesa per niente, con la schermata
    // che mostra il numero salito.
    if (c->ailments & AIL_OUT) return 0;
    if (mid == MG_CUR4)      c->curhp = c->maxhp;
    else if (mid == MG_CURE) recover_hp(c, roll(16, 31));
    else if (mid == MG_CUR2) recover_hp(c, roll(32, 63));
    else                     recover_hp(c, roll(64, 127));
    return txt_better;
}

// Le tre della famiglia HEAL: HP a TUTTI, un tiro solo per tutti. E' cosi'
// anche sul NES (`MenuRecoverPartyHP` riceve un valore gia' tirato), e non e'
// un dettaglio: tre tiri diversi renderebbero la magia piu' forte a parita' di
// media, perche' chi ne ha bisogno prende il suo.
static const char *cast_on_party(unsigned char mid) {
    unsigned char i;
    unsigned int amount;
    if (mid == MG_HEAL)      amount = roll(16, 23);
    else if (mid == MG_HEL2) amount = roll(32, 47);
    else                     amount = roll(64, 95);
    for (i = 0; i < PARTY.n; i++) {
        chr_t *c = &PARTY.chr[i];
        // Chi e' fuori dal campo non si cura: `MenuRecoverPartyHP` salta i
        // caduti, ed e' la stessa regola della tenda.
        if (c->ailments & AIL_OUT) continue;
        recover_hp(c, amount);
    }
    return txt_allwell;
}

// =====================================================================
//  L'ingresso
// =====================================================================
// arg: bit 0-1 = chi lancia, bit 2 = si e' dentro una citta'.
// Torna 1 se il gruppo e' stato portato via (WARP/EXIT): il menu si chiude e
// la citta' esce in overworld. Torna 0 in tutti gli altri casi.
unsigned int overlay_main(unsigned int arg) {
    edge_t e;
    unsigned int ev;
    unsigned char bits, key, lvl, col, in_town, who, mid;
    chr_t *c;
    const char *msg;

    who     = (unsigned char)(arg & 3);
    in_town = (unsigned char)((arg >> 2) & 1);
    c       = &PARTY.chr[who];
    e.pb    = 0xFF;    /* NIENTE inizializzatori nella DATA di un overlay */
    e.pk    = 0;
    lvl     = 0;
    col     = 0;

    svc_vfill(0x1800, 0x20, 768);
    render_string(1, ROW_TITLE, txt_title);
    render_string(8, ROW_TITLE, c->name);
    draw_grid(c);
    draw_party();
    draw_prompt(txt_choose);
    draw_hint(txt_hint);
    draw_grid_cursor(lvl, col, 1);

    while (1) {
        ev   = read_edge(&e);
        bits = (unsigned char)(ev & 0x00FF);
        key  = (unsigned char)(ev >> 8);

        if (bits & MOVE_FIRE2) return 0;

        if (bits & (MOVE_UP | MOVE_DOWN)) {
            lvl = (unsigned char)((bits & MOVE_UP)
                    ? (lvl ? lvl - 1 : N_LEVELS - 1)
                    : ((lvl + 1 >= N_LEVELS) ? 0 : lvl + 1));
            draw_grid_cursor(lvl, col, 1);
        } else if (bits & (MOVE_LEFT | MOVE_RIGHT)) {
            col = (unsigned char)((bits & MOVE_LEFT)
                    ? (col ? col - 1 : N_COLS - 1)
                    : ((col + 1 >= N_COLS) ? 0 : col + 1));
            draw_grid_cursor(lvl, col, 1);
        } else if (key >= '1' && key <= '8') {
            // Il tastierino salta al livello: con otto righe e tre colonne
            // contare i passi del cursore e' proprio il lavoro da evitare.
            lvl = (unsigned char)(key - '1');
            draw_grid_cursor(lvl, col, 1);
        } else if (bits & MOVE_FIRE1) {
            msg = 0;
            mid = spell_id_of(c, lvl, col);
            if (mid == 0xFF) {
                draw_msg(txt_empty);
                continue;
            }
            // LE CARICHE SI CONTROLLANO PRIMA DELL'EFFETTO E SI SCALANO DOPO.
            // Il NES fa lo stesso (`UseMagic_GetRequiredMP` prima, `DEC
            // ch_magicdata` dentro ogni routine, dopo che l'effetto e'
            // riuscito): un incantesimo rifiutato non deve costare niente.
            if (c->curmp[lvl] == 0) {
                draw_msg(txt_nomp);
                continue;
            }

            if (mid == MG_WARP || mid == MG_EXIT) {
                // "Torna alla mappa precedente" e "esci dal sotterraneo": da
                // una citta' sono la stessa cosa, l'overworld -- ed e' cosi'
                // anche sul NES, dove WARP con la catena dei teletrasporti
                // corta salta dentro il codice di EXIT (bank_0E.asm:6719).
                // In overworld non c'e' nessun posto dove andare: il NES
                // consuma la carica lo stesso, noi no (fix #2).
                if (!in_town) {
                    draw_msg(txt_nothere);
                    continue;
                }
                c->curmp[lvl]--;
                draw_msg(txt_warp);
                // Qualche quadro perche' la scritta si legga: si torna al menu,
                // che si chiude, e poi la citta' ridisegna l'overworld.
                {
                    unsigned char k;
                    for (k = 0; k < 90; k++) svc_wait_vblank();
                }
                return 1;
            }

            if (mid == MG_HEAL || mid == MG_HEL2 || mid == MG_HEL3) {
                msg = cast_on_party(mid);
                c->curmp[lvl]--;
                draw_party();
                draw_level(c, lvl);
                draw_grid_cursor(lvl, col, 1);
                draw_msg(msg);
                continue;
            }

            if (mid == MG_CURE || mid == MG_CUR2 || mid == MG_CUR3 ||
                mid == MG_CUR4 || mid == MG_LIFE || mid == MG_LIF2 ||
                mid == MG_PURE || mid == MG_SOFT) {
                unsigned char t = pick_target(&e);
                draw_prompt(txt_choose);
                draw_hint(txt_hint);
                if (t != 0xFF) {
                    msg = cast_on_one(mid, t);
                    // `0` = il bersaglio non ne aveva bisogno. La carica resta:
                    // e' la stessa scelta del NES, che in quel caso torna al
                    // ciclo dei bersagli senza toccare `ch_magicdata`.
                    if (msg) {
                        c->curmp[lvl]--;
                        draw_level(c, lvl);
                    } else {
                        msg = txt_noneed;
                    }
                    draw_party();
                }
                draw_grid_cursor(lvl, col, 1);
                draw_msg(msg);
                continue;
            }

            // Tutto il resto e' magia da battaglia. DICHIARATO, non silenzioso:
            // sul NES e' la descrizione $33, "can't cast that here".
            draw_msg(txt_nouse);
        }
    }
}
