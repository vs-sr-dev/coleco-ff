// =====================================================================
//  ovl_battle.c -- schermata di battaglia, overlay di CODICE (banco 20)
// =====================================================================
// Nato in slice52 come travaso della schermata di slice49: il motore di
// battaglia deve poter vivere fuori dalla finestra fissa $8000-$BFFF, dove
// restavano ~1.7KB liberi. Lo stato passa per la RAM SGM, non per puntatori a
// rodata, che sotto un altro banco sono invisibili.
//
// SEGUE LA SLICE PIU' RECENTE, non e' congelato: e' compilato insieme a lei.
// Un accoppiamento di versioni sbagliate lo intercetta il magic in
// battle_state.h, che cambia a ogni cambio di layout -> a schermo compare
// "BAD BATTLE STATE" invece di campi letti agli offset sbagliati.
//
// Stato a slice53:
//   - schermata completa (sprite a colori, striscia, comandi, area mostri);
//   - musica di battaglia sng50 dal banco 10 e sequenza di vittoria (sng53 +
//     esultanza);
//   - HP VERI letti da PARTY ($6100): niente piu' HP inventati. A schermo
//     restano solo nome e HP, come sul NES -- statistiche e cariche di magia
//     si vedono nel menu e nel sottomenu magia, non qui.
//   - NIENTE combattimento: il turno avanza, ma nessuno fa danno.
//
// -- cosa NON puo' fare questo file --------------------------------------
// * NIENTE mc_select_bank. L'overlay E' il banco 20: cambiarlo lo smonta
//   mentre gira. Tutto cio' che deve leggere un altro banco (le CHR dei
//   personaggi nel banco 2) passa da una svc_ del banco fisso, che il
//   cambio banco lo fa e lo disfa restando visibile per tutto il tempo.
// * NIENTE `static const` di aggregati che il compilatore possa piazzare
//   in DATA: la DATA dell'overlay non viene MAI inizializzata (non c'e'
//   crt0_init qui). Percio' le posizioni dei comandi sono #define e
//   switch, non una tabella -- stessa trappola di
//   [[rodata-trap-small-arrays]], per una ragione diversa.
//   Gli array `static const char[]` monodimensionali finiscono in RODATA,
//   nel banco 20, e sono leciti: validato in slice51 con ovl_audio.
// =====================================================================

#define SVC_OVERLAY
#include "svc_api.h"
#include "battle_state.h"
#include "party_state.h"   // slice53: le statistiche vere vivono qui ($6100)
#include "battle_ibstats.h" // slice70: e quelle della sola battaglia qui ($6400)

// Costanti di games.h ricopiate: l'overlay non linka nulla della libreria,
// chiama solo attraverso le svc_.
#define MOVE_RIGHT 1
#define MOVE_LEFT  2
#define MOVE_DOWN  4
#define MOVE_UP    8
#define MOVE_FIRE1 16
#define MOVE_FIRE2 32

// =====================================================================
//  Formato delle tabelle di regole (banco 11)
// =====================================================================
// Stanno in cima e non accanto al codice che le usa perche' le macro di
// prelievo servono gia' a `load_enemy_info`, che e' la prima cosa a girare.
//
// L'overlay non include enemy_data.h / magic_data.h coi dati: quelli sono un
// banco. Qui ci sono solo gli offset, con i nomi di Constants.inc.
#define ENROMSTAT_SIZE     20
#define ENROMSTAT_MORALE   0x06
#define ENROMSTAT_AI       0x07
#define ENROMSTAT_EVADE    0x08
#define ENROMSTAT_ABSORB   0x09
#define ENROMSTAT_NUMHITS  0x0A
#define ENROMSTAT_HITRATE  0x0B
#define ENROMSTAT_DAMAGE   0x0C
#define ENROMSTAT_CRITRATE 0x0D
/* L'alterazione che il mostro lascia addosso col COLPO, non con la magia
   (slice69). Sul NES e' il byte che il commento di Disch saluta con "curse
   you, Sorcerers!!!". */
#define ENROMSTAT_ATTACKAIL 0x0F
#define ENROMSTAT_MAGDEF   0x11
#define ENROMSTAT_ELEMWEAK 0x12
#define ENROMSTAT_ELEMRES  0x13

// ---- magia (slice60) -------------------------------------------------
// Gli 8 byte di una voce della tabella magia. Le voci sono 92: $00-$3F i 64
// incantesimi, $40-$41 le due pozioni, $42-$5B i 26 attacchi speciali dei
// nemici. Da qui la costante ENEMY_AI_ATK_BASE.
#define MAG_STAT_SIZE 8
#define MAG_HITRATE   0
#define MAG_POWER     1
#define MAG_ELEMENT   2
#define MAG_TARGET    3
#define MAG_EFFECT    4

// Maschera dei bersagli, sempre dal punto di vista di CHI LANCIA. Per un
// nemico "tutti i nemici" vuol dire tutto il gruppo: e' l'inversione che
// rende leggibile una tabella sola per le due parti del campo.
#define MAGTGT_ALL_FOES   0x01
#define MAGTGT_ONE_FOE    0x02
#define MAGTGT_CASTER     0x04
#define MAGTGT_ALL_ALLIES 0x08
#define MAGTGT_ONE_ALLY   0x10

// Gli effetti che questo lato del campo sa fare. Il danno c'e' da slice60; le
// due alterazioni da slice69, e sono il grosso di quello che i mostri hanno in
// tabella: dei 26 attacchi speciali, TREDICI usano l'effetto $03 (pietra,
// paralisi, cecita', morte, sonno) e finora dicevano tutti NOTHING HAPPENS.
#define MAGEFF_DAMAGE     0x01
#define MAGEFF_AILMENT    0x03
#define MAGEFF_AILMENT2   0x12

// Voce di IA nemica, 16 byte (tools/extract_enemy_ai.ps1).
#define ENEMY_AI_SIZE      16
#define ENEMY_AI_COUNT     44
#define ENEMY_AI_MAGRATE    0
#define ENEMY_AI_ATKRATE    1
#define ENEMY_AI_SPELLS     2
#define ENEMY_AI_ATTACKS   11
#define ENEMY_AI_ATK_BASE  0x42

// Le tre tabelle del banco 11, come le numera svc_fetch_btl. L'offset in byte
// lo calcola CHI CHIAMA: nella finestra fissa una moltiplicazione per una
// lunghezza variabile chiamerebbe un aiuto di libreria, e li' i byte sono
// contati. Qui le lunghezze sono costanti, quindi diventa uno spostamento.
#define BTLTAB_ENEMY   0
#define BTLTAB_MAGIC   1
#define BTLTAB_AI      2

#define fetch_enemy_stat(id, dst) \
    svc_fetch_btl(BTLTAB_ENEMY, (unsigned int)(id) * ENROMSTAT_SIZE, \
                  ENROMSTAT_SIZE, (dst))
#define fetch_spell(id, dst) \
    svc_fetch_btl(BTLTAB_MAGIC, (unsigned int)(id) * MAG_STAT_SIZE, \
                  MAG_STAT_SIZE, (dst))
#define fetch_ai(id, dst) \
    svc_fetch_btl(BTLTAB_AI, (unsigned int)(id) * ENEMY_AI_SIZE, \
                  ENEMY_AI_SIZE, (dst))

// Il secondo overlay di battaglia (slice68). Ci si entra da qui con
// svc_run_overlay MENTRE questo overlay e' vivo: e' il primo annidamento vero
// del progetto, e funziona perche' quella primitiva rimette il banco LETTO
// all'ingresso e non lo zero (slice61). Il numero sta qui e non in un header
// condiviso perche' questo file e' l'unico che entra li' dentro.
#define BTLMAGIC_BANK    23

#define NT_BASE          0x1800
#define SPR_TILE_BASE    0x80
#define CHEER_TILE_BASE  0xA4
#define ACC_HANDLE_STAND 1
#define ACC_HANDLE_CHEER 5

// Animazione di esultanza, cadenza presa da PlayFanfareAndCheer
// (bank_0C.asm:2435): 64 iterazioni da 2 frame l'una = 128 frame, e la posa
// alterna fra ESULTANZA e IN PIEDI ogni 8 iterazioni = ogni 16 frame.
#define CHEER_FRAMES     128
#define CHEER_PERIOD     16

#define N_COMMANDS       5
#define SPR_COL_BACK     18
#define SPR_COL_FORWARD  16
#define STAT_COL         25

// ---- arena dei nemici (slice55) --------------------------------------
// Quattro tipi da 16 tile a partire da $A4. Il numero e' il massimo che una
// formazione puo' chiedere, perche' i gruppi nei 16 byte sono quattro.
// MON_TILE_BASE / MON_TILE_END / MON_TILES / MON_TILES_LARGE stanno in
// battle_state.h da slice69: li usano tre file e tre copie di un confine di
// VRAM sono tre modi di sovrascrivere il font.
// Un nemico grande e' 6x6 tile (48x48 px), contro il 4x4 di uno piccolo.
#define MON_LARGE_W      6
// Griglia 3x3, celle da 4x4 tile: colonne a 2/6/10, righe a 0/4/8. Sono le
// stesse proporzioni del NES (@lut_NTAddress: colonne a 2/6/10, righe a
// 6/10/14 di una nametable piu' alta), traslate in alto perche' qui l'arena
// finisce a riga 15.
#define GRID_BASE_COL    2
#define GRID_BASE_ROW    0
#define GRID_CELL_W      4
#define GRID_CELL_H      4
#define GRID_LAST_ROW    11
// Ultima colonna dell'arena. La 16 e' occupata dagli sprite del gruppo, e il
// 4large ci arriva a filo: colonna 10 piu' sei tile fa 15.
#define GRID_RIGHT_COL   15

// Posizioni dei comandi: immediati nel flusso di codice, mai una tabella.
#define CMD_COL_MAIN     12
#define CMD_COL_RUN      19
#define CMD_ROW_FIGHT    17
#define CMD_ROW_RUN      17

static const char cmd_fight[] = "FIGHT";
static const char cmd_magic[] = "MAGIC";
static const char cmd_drink[] = "DRINK";
static const char cmd_item[]  = "ITEM";
static const char cmd_run[]   = "RUN";

static const char *cmd_label(int idx) {
    switch (idx) {
        case 0:  return cmd_fight;
        case 1:  return cmd_magic;
        case 2:  return cmd_drink;
        case 3:  return cmd_item;
        default: return cmd_run;
    }
}
static unsigned char cmd_col(int idx) {
    return (unsigned char)((idx == 4) ? CMD_COL_RUN : CMD_COL_MAIN);
}
static unsigned char cmd_row(int idx) {
    return (unsigned char)((idx == 4) ? CMD_ROW_RUN : (CMD_ROW_FIGHT + idx));
}

// ---------------------------------------------------------------------
//  Primitive di testo, costruite sulle sole svc_ VDP
// ---------------------------------------------------------------------
static unsigned int nt_at(unsigned char col, unsigned char row) {
    return (unsigned int)NT_BASE + (unsigned int)row * 32 + col;
}
static void ov_string(unsigned char col, unsigned char row, const char *s) {
    unsigned int len = 0;
    while (s[len]) len++;
    if (len) svc_vwrite((const void *)s, nt_at(col, row), len);
}
static void ov_char(unsigned char col, unsigned char row, char c) {
    unsigned char b = (unsigned char)c;
    svc_vwrite(&b, nt_at(col, row), 1);
}
static void ov_tile(unsigned char col, unsigned char row, unsigned char tid) {
    svc_vwrite(&tid, nt_at(col, row), 1);
}
static void ov_fill_row(unsigned char row, unsigned char col_start,
                        unsigned char col_end, unsigned char ch) {
    int n = (int)col_end - (int)col_start + 1;
    if (n <= 0) return;
    svc_vfill(nt_at(col_start, row), ch, (unsigned int)n);
}
static void ov_u3(unsigned char col, unsigned char row, unsigned int v) {
    char buf[4];
    int i;
    if (v > 999) v = 999;
    for (i = 2; i >= 0; i--) { buf[i] = (char)('0' + (v % 10)); v /= 10; }
    buf[3] = 0;
    for (i = 0; i < 2; i++) { if (buf[i] == '0') buf[i] = ' '; else break; }
    ov_string(col, row, buf);
}
/* ov_hex2 e hexdig sono spariti in slice55: servivano solo a stampare l'id
   della formazione come segnaposto, al posto dei nomi dei nemici. Ora i nomi
   ci sono davvero e il segnaposto non serve piu'. */

// ---------------------------------------------------------------------
//  Sprite dei personaggi (BG silhouette + strato accento in OAM)
// ---------------------------------------------------------------------
static unsigned char party_spr_row(int chr) { return (unsigned char)(chr * 3); }
static unsigned char stat_row(int chr)      { return (unsigned char)(chr * 4); }

// `tile_base` sceglie la posa: SPR_TILE_BASE = in piedi, CHEER_TILE_BASE =
// esultanza. Le CHR di entrambe sono gia' in VRAM (le carica
// svc_battle_load_gfx), quindi cambiare posa costa 6 celle di nametable --
// e non un accesso al banco 2, che da qui sarebbe impossibile.
static void draw_pose_at(int chr, unsigned char col, unsigned char tile_base) {
    unsigned char r    = party_spr_row(chr);
    unsigned char base = (unsigned char)(tile_base + PARTY.chr[chr].cls * 6);
    ov_tile(col,     r,     (unsigned char)(base + 0));
    ov_tile(col + 1, r,     (unsigned char)(base + 1));
    ov_tile(col,     r + 1, (unsigned char)(base + 2));
    ov_tile(col + 1, r + 1, (unsigned char)(base + 3));
    ov_tile(col,     r + 2, (unsigned char)(base + 4));
    ov_tile(col + 1, r + 2, (unsigned char)(base + 5));
}
static void draw_sprite_at(int chr, unsigned char col) {
    draw_pose_at(chr, col, SPR_TILE_BASE);
}
static void clear_sprite_at(int chr, unsigned char col) {
    unsigned char r = party_spr_row(chr);
    svc_vfill(nt_at(col, r),     ' ', 2);
    svc_vfill(nt_at(col, r + 1), ' ', 2);
    svc_vfill(nt_at(col, r + 2), ' ', 2);
}
// L'entrata SAT resta la stessa (1+chr); cambia il GENERATORE di pattern:
// handle 1-4 = accento della posa in piedi, 5-8 = accento dell'esultanza.
static void put_accent_pose(int chr, unsigned char col, unsigned char acc_base) {
    svc_put_sprite16((unsigned char)(ACC_HANDLE_STAND + chr),
                     (int)col * 8,
                     (int)party_spr_row(chr) * 8,
                     (unsigned char)(acc_base + chr),
                     BST.accent_color[PARTY.chr[chr].cls]);
}
static void put_accent_at(int chr, unsigned char col) {
    put_accent_pose(chr, col, ACC_HANDLE_STAND);
}
// La colonna a cui il personaggio si trova ADESSO: avanti se tocca a lui,
// altrimenti in fila. Un solo posto che lo decide, perche' il lampeggio di
// slice59 deve cancellare e ridisegnare esattamente dove la sagoma sta -- e
// ricalcolarlo per conto proprio vorrebbe dire due regole che possono
// divergere.
static unsigned char spr_col(int chr) {
    return (unsigned char)((chr == (int)BST.turn_chr) ? SPR_COL_FORWARD
                                                      : SPR_COL_BACK);
}
static void render_party_sprite(int chr) {
    unsigned char col = spr_col(chr);
    draw_sprite_at(chr, col);
    put_accent_at(chr, col);
}
static void step_forward(int chr) {
    clear_sprite_at(chr, SPR_COL_BACK);
    draw_sprite_at(chr, SPR_COL_FORWARD);
    put_accent_at(chr, SPR_COL_FORWARD);
}
static void step_back(int chr) {
    clear_sprite_at(chr, SPR_COL_FORWARD);
    draw_sprite_at(chr, SPR_COL_BACK);
    put_accent_at(chr, SPR_COL_BACK);
}

// ---------------------------------------------------------------------
//  Il nome dell'alterazione (slice69)
// ---------------------------------------------------------------------
// UNA sola, la piu' grave, come sul NES: la finestra di stato non elenca, mostra
// la condizione che comanda. L'ordine e' quello in cui contano -- chi e' morto
// non e' anche "avvelenato", e chi e' pietrificato non e' anche "cieco".
//
// Le stringhe sono lunghe SETTE caratteri tutte, spazi compresi, e non e' pigrizia:
// `ov_string` scrive esattamente i caratteri che riceve, quindi una parola corta
// dopo una lunga lascerebbe in VRAM la coda di quella prima ("POISON" sopra
// "CONFUSE" darebbe "POISONE"). Sette e' anche la larghezza esatta della
// striscia, dalla colonna 25 alla 31.
//
// Un `static const char *[]` sarebbe piu' corto da scrivere e SBAGLIATO qui: un
// array di puntatori finisce in DATA, che negli overlay non viene mai
// inizializzata (regola 4 di [[code-overlay-architecture]]). Lo switch e' la
// stessa forma di `cmd_label` qui sopra, e per la stessa ragione.
static const char ail_dead[]  = "DEAD   ";
static const char ail_stone[] = "STONE  ";
static const char ail_stun[]  = "STUN   ";
static const char ail_sleep[] = "SLEEP  ";
static const char ail_conf[]  = "CONFUSE";
static const char ail_mute[]  = "MUTE   ";
static const char ail_dark[]  = "DARK   ";
static const char ail_pois[]  = "POISON ";
static const char ail_none[]  = "       ";

static const char *ail_name(unsigned char a) {
    if (a & AIL_DEAD)   return ail_dead;
    if (a & AIL_STONE)  return ail_stone;
    if (a & AIL_STUN)   return ail_stun;
    if (a & AIL_SLEEP)  return ail_sleep;
    if (a & AIL_CONF)   return ail_conf;
    if (a & AIL_MUTE)   return ail_mute;
    if (a & AIL_DARK)   return ail_dark;
    if (a & AIL_POISON) return ail_pois;
    return ail_none;
}

// ---------------------------------------------------------------------
//  Blocchi della schermata
// ---------------------------------------------------------------------
static void render_status_block(int chr) {
    chr_t *c = &PARTY.chr[chr];
    unsigned char r = stat_row(chr);
    ov_char(24, r, (chr == (int)BST.turn_chr) ? '>' : ' ');
    ov_string(STAT_COL, r,     c->name);
    ov_string(STAT_COL, r + 1, "HP ");
    ov_u3(STAT_COL + 3, r + 1, c->curhp);
    ov_string(STAT_COL, r + 2, " / ");
    ov_u3(STAT_COL + 3, r + 2, c->maxhp);
    // ---- riga 4 del blocco: l'alterazione di stato (slice69) -------------
    // Le righe di un blocco sono quattro e la quarta era vuota; e' l'unico
    // posto della striscia dove ci sta una PAROLA invece di una lettera, e una
    // lettera sola non si distingue -- "S" varrebbe sia STONE sia STUN sia
    // SLEEP. Non e' informazione in piu' rispetto al NES: li' il nome del
    // personaggio cambia colore e la finestra di stato lo scrive per esteso.
    ov_string(STAT_COL, r + 3, ail_name(c->ailments));
    // NIENTE MP qui. Due ragioni, la seconda piu' forte della prima:
    //   1. parita': la schermata di battaglia FF1 mostra solo nome e HP; gli
    //      MP si vedono nel sottomenu della magia, le statistiche nel menu.
    //   2. in FF1 non esistono MP "standard": sono CARICHE PER LIVELLO di
    //      magia (curmp[0..7]). Un numero unico sotto gli HP rappresenterebbe
    //      male il sistema, non lo riassumerebbe.
    // Il posto giusto e' il sottomenu magia, otto livelli con le loro cariche.
}
static void render_status_strip(void) {
    int i;
    for (i = 0; i < (int)PARTY.n; i++) render_status_block(i);
}
static void render_command_at(int idx, int sel) {
    unsigned char col = cmd_col(idx);
    unsigned char row = cmd_row(idx);
    ov_char((unsigned char)(col - 1), row, sel ? '>' : ' ');
    ov_string(col, row, cmd_label(idx));
}
// I due riquadri in basso, disegnati invece che scritti (slice69).
//
// Erano dodici stringhe letterali -- "+-------------+" e compagnia -- per un
// totale di ~160 byte di rodata piu' dodici chiamate a ov_string. Disegnarli
// costa una funzione di novanta byte e li rende parametrici. Non e' pulizia:
// e' l'unico modo in cui le alterazioni di stato entravano nel banco 20, che
// era a 229 byte liberi. Il riquadro dei premi, che ha la stessa cornice, adesso
// la chiede a questa invece di riscriversela.
//
// `w` e' la larghezza INTERNA. Le righe sono sempre 16-21, che e' la fascia
// bassa dello schermo di battaglia.
// ATTENZIONE al terzo argomento di `ov_fill_row`: e' **col_end**, la colonna
// FINALE compresa, non un numero di caselle. La funzione omonima
// dell'overlay della magia (banco 23) prende invece un CONTEGGIO -- due
// funzioni con lo stesso nome, la stessa forma e la terza posizione che vuol
// dire due cose diverse.
//
// Passandogli `w` come se fosse un conteggio, questo riquadro usciva
// `+---          +`: tre trattini invece di tredici, perche' 11..13 sono tre
// colonne. E il difetto era **invisibile nel riquadro dei bersagli**, che sta a
// colonna 0 -- li' `col_end` e `conteggio` danno lo stesso numero, e quello e'
// anche il riquadro che si guarda per primo. Ci sono volute due corse e la
// lettura dell'assembly, dove il prototipo dice `col_end` a chiare lettere.
//
// `w` qui e' la larghezza INTERNA; le colonne piene vanno da `col+1` a `col+w`.
static void ov_box(unsigned char col, unsigned char w) {
    unsigned char r;
    unsigned char right = (unsigned char)(col + w + 1);
    unsigned char in    = (unsigned char)(col + 1);
    unsigned char last  = (unsigned char)(col + w);
    // Due passaggi: le quattro righe interne, poi i due bordi srotolati. Una
    // forcella dentro il ciclo (`r == 16 || r == 21`) andrebbe valutata sei
    // volte per due caratteri, e in questo overlay ogni `?:` in un ciclo si e'
    // misurato in decine di byte.
    for (r = 17; r <= 20; r++) {
        ov_char(col,   r, '|');
        ov_char(right, r, '|');
        ov_fill_row(r, in, last, ' ');
    }
    ov_char(col,   16, '+');
    ov_char(right, 16, '+');
    ov_fill_row(16, in, last, '-');
    ov_char(col,   21, '+');
    ov_char(right, 21, '+');
    ov_fill_row(21, in, last, '-');
}

static void render_command_box(void) {
    int i;
    ov_box(10, 13);
    for (i = 0; i < N_COMMANDS; i++) render_command_at(i, i == (int)BST.command_idx);
}
// LISTA BERSAGLI: i nomi dei nemici della formazione, uno per riga, come su
// NES. Non e' lavoro nuovo -- in slice31 il riquadro elencava gia' IMP /
// GrIMP / WOLF / GrWOLF; poi slice36 ha ricostruito la overworld e la
// battaglia e' tornata scaffold, lasciando qui l'id esadecimale della
// formazione. Questo e' il recupero di quella lista.
//
// I nomi arrivano da BST, gia' convertiti dal charset custom $8A-$BD: la
// tabella ff1_enemy_names e' rodata della slice, quindi da qui invisibile.
//
// Il riquadro e' largo 10 (colonne 0-9) e non 9 come prima: l'interno deve
// tenere 8 caratteri, che e' il limite dei nomi sul NES
// (DrawBattleSubString_Max8). Il riquadro dei comandi comincia a colonna 10,
// quindi i due si toccano senza sovrapporsi.
//
// Niente statistiche qui. Per un giro c'erano ed erano sbagliate per parita':
// in FF1 le statistiche si vedono SOLO nel menu. Le formule del turno fisico
// si controllano con la sonda in RAM (tools/mame_drive_battle.lua), non
// mettendo a schermo numeri che il gioco originale non mostra.
static void render_target_box(void) {
    int t;
    ov_box(0, 8);
    for (t = 0; t < (int)BST.n_types && t < 4; t++) {
        ov_string(1, (unsigned char)(17 + t), BST.type_name[t]);
    }
}

// =====================================================================
//  Decodifica della formazione -- TRASLOCATA nel banco 23 (slice69)
// =====================================================================
// `decode_formation` e `load_enemy_info` stavano qui e adesso stanno in
// ovl_btlmagic.c, dietro BTLMAG_MODE_SETUP. Erano 1402 byte -- il secondo e il
// quinto pezzo piu' grosso dell'overlay -- e servono UNA VOLTA SOLA, prima che
// la battaglia cominci, mentre occupavano posto in un banco che deve tenerci
// tutto il round.
//
// Che potessero andarsene si vede da cosa NON toccano: ne' VRAM, ne' sprite,
// ne' tastiera. Leggono i sedici byte grezzi della formazione da BST e
// riempiono altri campi di BST, piu' due svc_ per i nomi e le statistiche. Sono
// esattamente il tipo di codice che sta bene ovunque -- e quindi sta dove c'e'
// posto.
//
// Qui restano le costanti delle tile e il generatore, che servono al round.

// RandAX del NES (bank_0B.asm:$9F17): non e' un modulo ma una moltiplicazione
// di cui si tiene il byte alto, quindi la distribuzione e' quella
// dell'originale, asimmetrie comprese.
static unsigned char rand_ax(unsigned char lo, unsigned char hi) {
    unsigned int range;
    if (hi < lo) hi = lo;          /* dato malformato: non sottrarre sotto zero */
    range = (unsigned int)hi + 1u - (unsigned int)lo;
    return (unsigned char)((unsigned int)lo +
           (((unsigned int)svc_battle_rng() * range) >> 8));
}

// ---------------------------------------------------------------------
//  I nemici in campo
// ---------------------------------------------------------------------
// Posizione secondo @lut_NTAddress del NES (bank_0B.asm:$A4C9). Due cose non
// ovvie, entrambe volute:
//   - si riempie per COLONNE, non per righe: i nemici 0,1,2 stanno tutti
//     nella colonna di sinistra;
//   - dentro la colonna l'ordine e' MEZZO, ALTO, BASSO -- il nemico 0 e' in
//     mezzo. E' il motivo per cui il NES ha bisogno di lut_EnemyIndex9Small
//     per tradurre la posizione del cursore in indice di nemico.
// Tre IMP finiscono percio' incolonnati a sinistra, esattamente come
// nell'originale.
//
// Da slice56 ci sono tre disposizioni, una per tipo di formazione, tutte prese
// dalle LUT del NES e traslate in alto di 6 righe -- l'arena del NES parte a
// riga 6, la nostra a riga 0, e la differenza e' costante:
//
//   9small  @lut_NTAddress   colonne 2/6/10, righe 0/4/8   (3x3 celle 4x4)
//   4large  $20C2 $2182 $20CA $218A   colonne 2/10, righe 0/6
//   mix     grandi $20C2 $2182 (colonna 2, righe 0/6)
//           piccoli @lut_SmallEn_DrawPos  colonne 8/12, righe 4/0/8
//
// Il limite destro e' la colonna 16, dove cominciano gli sprite del gruppo: il
// 4large arriva alla 15 (colonna 10 + 6 tile) e il mix pure. Ci sta esatto.
//
// L'ordine dentro una colonna e' sempre MEZZO, ALTO, BASSO, anche per i
// piccoli del mix: e' la stessa convenzione del 9small.
static unsigned char within_col_row(int k) {
    /* switch e non tabella: la DATA dell'overlay non viene mai inizializzata */
    switch (k) {
        case 0:  return 1;   /* mezzo */
        case 1:  return 0;   /* alto  */
        default: return 2;   /* basso */
    }
}
static unsigned char enemy_col(int e) {
    if (BST.btl_type == BTL_TYPE_4LARGE) return (unsigned char)(2 + (e / 2) * 8);
    if (BST.btl_type == BTL_TYPE_MIX) {
        if (e < 2) return 2;                          /* i due grandi */
        return (unsigned char)(8 + ((e - 2) / 3) * GRID_CELL_W);
    }
    return (unsigned char)(GRID_BASE_COL + (e / 3) * GRID_CELL_W);
}
static unsigned char enemy_row(int e) {
    if (BST.btl_type == BTL_TYPE_4LARGE) return (unsigned char)((e % 2) * 6);
    if (BST.btl_type == BTL_TYPE_MIX) {
        if (e < 2) return (unsigned char)(e * 6);     /* i due grandi */
        return (unsigned char)(GRID_BASE_ROW + within_col_row((e - 2) % 3) * GRID_CELL_H);
    }
    return (unsigned char)(GRID_BASE_ROW + within_col_row(e % 3) * GRID_CELL_H);
}

// Disegna un nemico. Le tile del tipo sono consecutive e in ordine row-major,
// sia per il 4x4 dei piccoli sia per il 6x6 dei grandi, quindi una riga alla
// volta in una scrittura sola: la larghezza e' l'unica cosa che cambia.
static int render_enemy(int e) {
    unsigned char t, base, c0, r0, w;
    int row, col;
    unsigned char buf[MON_LARGE_W];

    t = BST.enemy_type[e];
    if (t == BST_NO_ENEMY || t >= BST_MAX_TYPES) return 0;
    base = BST.type_tile_base[t];
    if (base == 0xFF) return 0;             /* tipo senza grafica (fiend/chaos) */

    w    = (unsigned char)((BST.type_gfx[t] & 0x01) ? MON_LARGE_W : 4);
    c0   = enemy_col(e);
    r0   = enemy_row(e);
    for (row = 0; row < (int)w; row++) {
        for (col = 0; col < (int)w; col++) {
            buf[col] = (unsigned char)(base + row * w + col);
        }
        svc_vwrite(buf, nt_at(c0, (unsigned char)(r0 + row)), (unsigned int)w);
    }
    return 1;
}

static void render_monster_area(void) {
    int e, drawn = 0;
    // Si scorrono gli SLOT, non i nemici: nel "mix" i grandi stanno negli slot
    // 0-1 e i piccoli dal 2, quindi con un solo grande in campo lo slot 1 e'
    // vuoto ma il 2 e' pieno. Contare fino a n_enemies salterebbe l'ultimo.
    for (e = 0; e < BST_MAX_ENEMIES; e++) drawn += render_enemy(e);

    // Onesta' a schermo: Fiend e Chaos hanno una grafica TSA con un percorso di
    // disegno tutto suo, non ancora fatta. Meglio dirlo che lasciare l'arena
    // vuota e far pensare a un guasto del motore -- il resto (nome, HP, bottino)
    // e' corretto anche in questo caso.
    if (drawn == 0 && BST.n_enemies > 0) {
        ov_string(2, 4, "BOSS GFX TBD");
        ov_string(2, 6, BST.type_name[0]);
    }
}

// Ripulisce l'arena. Serve alla vittoria, prima di caricare l'esultanza:
// quelle CHR si scrivono sopra le tile dei primi due tipi di nemico, e se le
// celle restassero a schermo mostrerebbero pezzi di personaggio che esulta al
// posto dei mostri.
static void clear_monster_area(void) {
    unsigned char r;
    // Fino alla colonna 15, non alla 13: dalla slice56 il 4large arriva a 15
    // (colonna 10 piu' sei tile) e cosi' i piccoli del mix. La 16 e' il limite,
    // li' cominciano gli sprite del gruppo.
    for (r = 0; r <= GRID_LAST_ROW; r++) {
        ov_fill_row(r, GRID_BASE_COL, GRID_RIGHT_COL, ' ');
    }
}
// =====================================================================
//  Il turno fisico (slice57)
// =====================================================================
// Formula da `DoPhysicalAttack` (`bank_0C.asm:4296`), con i correttivi del
// digest AstralEsper ([[ff1-engine-intent-priorities]]). Cosa NON si copia
// dal NES, e perche':
//
//   * il NES tronca la probabilita' di colpire a 255 DOPO aver sommato il
//     tiro dell'attaccante e PRIMA di sottrarre l'evasione del difensore.
//     E' il fix #2 del digest: un nemico molto evasivo diventa cosi'
//     immune-ma-non-troppo in modo arbitrario, perche' il troncamento butta
//     via proprio i punti che l'evasione avrebbe dovuto mangiare. Qui il
//     conto sta in un `int` a 16 bit dall'inizio alla fine e non si tronca
//     mai: e' il comportamento inteso, ed e' anche quello che in C viene
//     naturale -- il bug del NES nasceva dal lavorare a 8 bit.
//
//   * il tasso di critico sul NES e' l'INDICE dell'arma equipaggiata invece
//     del suo byte di critico (fix #1). Qui non e' ancora osservabile perche'
//     il gruppo e' disarmato -- in FF1 si parte senza equipaggiamento -- e
//     arma 0 da' critico 0 in entrambe le letture. La strada giusta e' gia'
//     scritta: quando l'equipaggiamento arrivera', si legge il byte, non
//     l'indice.
//
// Da slice59 il round non e' piu' solo del gruppo: c'e' l'ordine di iniziativa
// e i nemici rispondono. Resta fuori la magia -- e con essa la parte di
// Enemy_DoAi che sceglie fra incantesimo, attacco speciale e colpo normale
// (vedi la nota su enemy_turn).

#define BTL_MAX_MSG 25

static void render_message(const char *m) {
    ov_fill_row(23, 0, 24, ' ');
    ov_string(0, 23, m);
}

// Un nemico e' vivo se il suo slot e' occupato e ha ancora HP.
static int enemy_alive(int slot) {
    if (slot < 0 || slot >= BST_MAX_ENEMIES) return 0;
    if (BST.enemy_type[slot] == BST_NO_ENEMY) return 0;
    return BST.enemy_hp[slot] != 0;
}

static int count_alive_enemies(void) {
    int s, n = 0;
    for (s = 0; s < BST_MAX_ENEMIES; s++) n += enemy_alive(s);
    return n;
}

// Slot -> posizione VISIVA e ritorno. Serve al cursore, che deve muoversi come
// li vede il giocatore e non come stanno in memoria: dentro una colonna gli
// slot sono in ordine MEZZO, ALTO, BASSO (@lut_NTAddress del NES), quindi il
// nemico 0 e' quello di mezzo. E' lo stesso motivo per cui il NES ha bisogno di
// `lut_EnemyIndex9Small`.
//
// La conversione e' un'involuzione -- scambia 0 e 1 e lascia fermo 2 -- quindi
// la stessa funzione traduce nei due sensi e non ne servono due.
static int visual_swap(int k) {
    switch (k % 3) {
        case 0:  return (k / 3) * 3 + 1;
        case 1:  return (k / 3) * 3 + 0;
        default: return (k / 3) * 3 + 2;
    }
}
// Nel "mix" i due grandi occupano gli slot 0-1 in ordine gia' visivo, e la
// griglia a tre righe comincia dallo slot 2.
static int slot_from_visual(int v) {
    if (BST.btl_type == BTL_TYPE_4LARGE) return v;
    if (BST.btl_type == BTL_TYPE_MIX) {
        if (v < 2) return v;
        return 2 + visual_swap(v - 2);
    }
    return visual_swap(v);
}
static int visual_from_slot(int s) {
    if (BST.btl_type == BTL_TYPE_4LARGE) return s;
    if (BST.btl_type == BTL_TYPE_MIX) {
        if (s < 2) return s;
        return 2 + visual_swap(s - 2);
    }
    return visual_swap(s);
}

// Primo slot vivo a partire da `from` in ordine visivo, con `step` +1 o -1.
// Gira in tondo e si ferma comunque: se non c'e' nessun vivo torna -1 invece di
// avvitarsi.
static int next_alive(int from_slot, int step) {
    int v = visual_from_slot(from_slot);
    int i;
    for (i = 0; i < BST_MAX_ENEMIES; i++) {
        v += step;
        if (v < 0) v = BST_MAX_ENEMIES - 1;
        if (v >= BST_MAX_ENEMIES) v = 0;
        if (enemy_alive(slot_from_visual(v))) return slot_from_visual(v);
    }
    return enemy_alive(from_slot) ? from_slot : -1;
}

// Cursore di bersaglio: una cella di sfondo alla sinistra del nemico, a meta'
// della sua altezza. Non uno sprite OAM, e non per pigrizia: gli sprite in
// battaglia sono gia' quattro (uno strato di accento per personaggio) e il
// TMS9918 ne disegna al massimo quattro per scanline. Una cella di sfondo non
// entra in quel bilancio.
static void draw_target_cursor(int slot, int on) {
    unsigned char c, r, h;
    if (slot < 0 || BST.enemy_type[slot] == BST_NO_ENEMY) return;
    h = (unsigned char)((BST.type_gfx[BST.enemy_type[slot]] & 0x01) ? MON_LARGE_W : 4);
    c = enemy_col(slot);
    r = (unsigned char)(enemy_row(slot) + (h >> 1));
    if (c == 0) return;
    ov_char((unsigned char)(c - 1), r, (char)(on ? '>' : ' '));
}

// Cancella il nemico dallo schermo quando muore. L'area e' quella della sua
// sagoma: 4x4 o 6x6 a seconda della taglia.
static void erase_enemy(int slot) {
    unsigned char c, r, h, i;
    if (BST.enemy_type[slot] == BST_NO_ENEMY) return;
    h = (unsigned char)((BST.type_gfx[BST.enemy_type[slot]] & 0x01) ? MON_LARGE_W : 4);
    c = enemy_col(slot);
    r = enemy_row(slot);
    for (i = 0; i < h; i++) {
        ov_fill_row((unsigned char)(r + i), c, (unsigned char)(c + h - 1), ' ');
    }
}

static void wait_frames(int n) {
    while (n-- > 0) svc_wait_vblank();
}

// Scrive un nome di 8 caratteri nel buffer del messaggio, senza gli spazi di
// riempimento che ff1_mon_names porta con se'.
static int msg_name(char *dst, int k, const char *src) {
    int i;
    for (i = 0; i < 8 && src[i] && src[i] != ' '; i++) dst[k++] = src[i];
    return k;
}
static int msg_lit(char *dst, int k, const char *s) {
    while (*s) dst[k++] = *s++;
    return k;
}

// Il colpo vero e proprio. Ritorna il danno totale inflitto; 0 = mancato.
// Il CUORE del colpo, una volta sola per entrambe le direzioni del campo.
//
// Fino a slice59 questo ciclo esisteva due volte, identico, e le due copie
// differivano solo per DA DOVE arrivavano i cinque numeri: da PARTY e dalle
// statistiche del nemico, o viceversa. `DoPhysicalAttack` sul NES e' una
// routine sola proprio per questo -- le due `EnemyAttackPlayer_Physical` /
// `PlayerAttackEnemy_Physical` non fanno altro che riempire le stesse
// variabili da due parti diverse e poi chiamarla.
//
// Separarlo non e' solo ordine: nell'overlay lo spazio e' finito (era il
// vincolo aperto a fine slice59) e questa e' la duplicazione piu' grossa che
// c'era. Le due funzioni qui sotto sono adesso solo la raccolta dei numeri.
// Il "tiro" a 200 facce, che in questo file serve a tre cose diverse: se una
// magia di UTILITA' atterra, se una magia di DANNO fa critico (quelle
// colpiscono sempre, `bank_0C.asm:8284`), e da slice69 se l'alterazione appesa
// a un colpo prende. Sta qui, in cima, perche' da slice69 il primo a usarlo e'
// il colpo fisico e non piu' la magia.
static int magic_roll(int chance) {
    int roll = (int)rand_ax(0, 200);
    if (roll == 200) return 0;          /* 200 esatto = fallito sicuro */
    return chance >= roll;
}

// Quanti colpi sono andati a segno nell'ultima scarica. Serve alle alterazioni
// da colpo (slice69) e sta in una variabile invece che fra i valori di ritorno
// per una ragione di byte: aggiungere un parametro d'uscita a `strike_core`
// costa a ogni chiamata, una statica costa una volta. Negli overlay le statiche
// si possono usare -- la trappola della BSS condivisa riguarda il banco 23, che
// gira DENTRO questo, non questo (vedi l'intestazione di ovl_btlmagic.c).
static int hits_connected;

static unsigned int strike_core(int basedmg, int hitchance, int critchance,
                                int numhits, int absorb) {
    unsigned int total = 0;
    int h;

    hits_connected = 0;
    if (numhits < 1) numhits = 1;
    if (hitchance < 1) hitchance = 1;
    // Il critico non puo' uscire su un colpo mancato. Limitandolo qui, piu'
    // avanti basta confrontare i due tiri senza rifare il ragionamento.
    if (critchance > hitchance) critchance = hitchance;

    for (h = 0; h < numhits; h++) {
        int randhit, roll, dmg;

        randhit = (int)rand_ax(0, 200);
        if (randhit == 200) continue;        /* 200 esatto = mancato sicuro */

        // Danno grezzo fra [base, base*2], come sul NES.
        roll = basedmg + (int)rand_ax(0, (unsigned char)((basedmg > 255) ? 255 : basedmg));
        if (roll > 255) roll = 255;

        dmg = 0;
        if (hitchance >= randhit) {
            dmg = roll - absorb;
            if (dmg < 1) dmg = 1;            /* minimo 1 su un colpo andato a segno */
            hits_connected++;
        }
        if (critchance >= randhit) dmg += roll;

        total += (unsigned int)dmg;
    }
    return total;
}

// I due contributi che le ALTERAZIONI danno al colpo fisico (slice69), scritti
// una volta sola perche' valgono identici nelle due direzioni del campo
// (`DoPhysicalAttack`, bank_0C.asm:4319-4370).
//
//   CECITA' sul tiro, in DUE punti e con segni opposti: chi e' cieco colpisce
//   con -40, chi e' cieco viene colpito con +40. Sono due controlli separati e
//   si sommano: un cieco che ne colpisce un altro torna a 168 netti.
//
//   SONNO o PARALISI sul DANNO: chi non si muove le prende con +25% di danno
//   base. Il quarto si prende dal danno base, non dal totale.
static int dark_delta(unsigned char atk_ail, unsigned char def_ail) {
    int d = 0;
    if (atk_ail & AIL_DARK) d -= 40;
    if (def_ail & AIL_DARK) d += 40;
    return d;
}
static int immobile_dmg(int base, unsigned char def_ail) {
    if (def_ail & (AIL_STUN | AIL_SLEEP)) {
        base += base >> 2;
        if (base > 255) base = 255;
    }
    return base;
}

// DA slice70 I NUMERI ARRIVANO DAL BLOCCO IB, NON PIU' DA PARTY E DALLA ROM.
// Danno, tiro ed evasione di un personaggio, danno ed evasione di un mostro:
// sono esattamente i campi che TMPR, RUSE, LOCK e FAST sanno muovere, e
// leggerli dal posto vecchio vorrebbe dire scrivere un potenziamento che poi
// non legge nessuno. Cio' che NON puo' cambiare -- classe, livello, critico,
// numero di colpi di base -- si continua a leggere dov'era.
static unsigned int resolve_physical(int chr, int tgt) {
    chr_t *c = &PARTY.chr[chr];
    ibstat_t *a = &IBC(chr);
    ibstat_t *d = &IBE(tgt);
    unsigned char st[20];
    unsigned char def_ail = BST.enemy_ail[tgt];
    int critchance, numhits;

    fetch_enemy_stat(BST.type_enemy[BST.enemy_type[tgt]], st);

    // Colpi = tiro/32 + 1 (`bank_0C.asm:5656`).
    numhits = ((int)a->hitrate >> 5) + 1;
    // Il monaco a mani nude: critico pari al doppio del livello e colpi
    // raddoppiati (`bank_0C.asm:5738`). E' l'unico caso in cui un gruppo
    // disarmato ha un critico diverso da zero, ed e' per questo che vale la
    // pena scriverlo adesso invece che con l'equipaggiamento.
    critchance = 0;
    if (c->cls == CLS_BB) {
        critchance = (int)c->level * 2;
        numhits   *= 2;
    }
    // FAST e SLOW, per ultimi: il moltiplicatore si applica al totale, dopo il
    // raddoppio del monaco (`btl_attacker_numhitsmult`, bank_0C.asm:4147).
    numhits *= (int)a->hits_mult;

    // Base 168, cecita', poi tiro dell'attaccante meno evasione del difensore.
    // NIENTE troncamento a 255 in mezzo: e' il fix #2 (vedi il blocco in testa).
    //
    // DEVIAZIONE DAL NES, e non e' una semplificazione. Li' il tiro
    // dell'attaccante si somma SOLO se il difensore e' sveglio: il ramo
    // `@DefenderMobile` (bank_0C.asm:4370) e' l'`else` del bonus del 25%, e il
    // disassembly stesso ci mette sopra un "Is this BUGGED?". Vuol dire che
    // addormentare un nemico PEGGIORA la propria mira, il che non e' un
    // compromesso di gioco: e' un `JMP` che salta troppo. Qui il tiro si somma
    // sempre, come dice la formula quando la si legge senza il salto.
    // Politica gia' decisa per le formule di combattimento
    // ([[ff1-engine-intent-priorities]]); scheda in docs/Coleco_improvements.md.
    return strike_core(immobile_dmg((int)a->dmg, def_ail),
                       168 + dark_delta(c->ailments, def_ail)
                           + (int)a->hitrate - (int)d->evade,
                       critchance, numhits, (int)d->absorb);
}

// Applica il danno e aggiorna lo schermo. Separata dal calcolo perche' cosi'
// la formula si puo' leggere (e un giorno provare) senza trascinarsi dietro la
// VRAM.
// Il messaggio del colpo, una volta sola per entrambe le direzioni.
// Ritorna 1 se il colpo e' andato a segno.
//
// ASIMMETRIA VOLUTA: sul colpo mancato l'attesa la fa lei, sul colpo a segno
// no. Le due direzioni infatti riempiono quel tempo in modo diverso -- il
// nemico ci mette in mezzo il lampeggio della sagoma colpita -- e imporre qui
// una pausa uguale vorrebbe dire farla due volte da una parte.
static int report_strike(const char *atk, const char *def, unsigned int dmg) {
    char msg[BTL_MAX_MSG + 1];
    int k = msg_name(msg, 0, atk);

    if (dmg == 0) {
        k = msg_lit(msg, k, " MISSES");
        msg[k] = 0;
        render_message(msg);
        wait_frames(45);
        return 0;
    }
    k = msg_lit(msg, k, " HITS ");
    k = msg_name(msg, k, def);
    msg[k] = 0;
    render_message(msg);
    ov_u3(21, 23, (dmg > 999) ? 999 : dmg);
    return 1;
}

static void report_death(const char *who) {
    char msg[BTL_MAX_MSG + 1];
    int k = msg_name(msg, 0, who);
    k = msg_lit(msg, k, " DIES");
    msg[k] = 0;
    render_message(msg);
    wait_frames(45);
}

static void apply_and_report(int chr, int tgt, unsigned int dmg) {
    const char *dname = BST.type_name[BST.enemy_type[tgt]];

    if (!report_strike(PARTY.chr[chr].name, dname, dmg)) return;

    if (dmg >= BST.enemy_hp[tgt]) BST.enemy_hp[tgt] = 0;
    else                          BST.enemy_hp[tgt] -= dmg;
    wait_frames(45);

    if (BST.enemy_hp[tgt] == 0) {
        erase_enemy(tgt);
        report_death(dname);
    }
}

// =====================================================================
//  Lo strato nemico (slice59)
// =====================================================================

// "In piedi" da slice69 non vuol piu' dire "ha HP": vuol dire che non e' ne'
// morto ne' pietrificato (`CheckForBattleEnd` fa `AND #AIL_DEAD|AIL_STONE`,
// bank_0C.asm:3294). La differenza si vede il giorno in cui un nemico lancia
// BRAK: un gruppo tutto di pietra ha ancora tutti gli HP, e senza questa riga
// la battaglia continuerebbe con quattro statue che non possono scegliere --
// cioe' si pianterebbe.
static int count_alive_party(void) {
    int i, n = 0;
    for (i = 0; i < (int)PARTY.n; i++) n += !(PARTY.chr[i].ailments & AIL_OUT);
    return n;
}

// Bersaglio del nemico, con la distribuzione FRONTALE del NES
// (`GetRandomPlayerTarget`, bank_0C.asm:6997): 4/8 al primo, 2/8 al secondo,
// 1/8 al terzo, 1/8 al quarto. Non e' un dettaglio da riprodurre per scrupolo
// -- e' la ragione per cui in FF1 il Fighter si mette in cima alla lista, e
// quindi e' una regola di gioco che il giocatore conosce.
//
// Il NES ritira all'infinito finche' non pesca un bersaglio valido. Qui il
// ciclo e' limitato: un gruppo interamente morto lo farebbe girare per sempre,
// e su Coleco un ciclo infinito e' una macchina piantata, non un'eccezione.
// Il chiamante non ci arriva mai (controlla prima la fine della battaglia), ma
// il costo del limite e' due byte e il costo di sbagliarsi e' l'utente che
// spegne la console.
static int random_player_target(void) {
    int tries, i;
    for (tries = 0; tries < 64; tries++) {
        unsigned char r = svc_battle_rng();
        int t = 0;
        if (r < 0x20) t++;
        if (r < 0x40) t++;
        if (r < 0x80) t++;
        if (t < (int)PARTY.n && !(PARTY.chr[t].ailments & AIL_OUT)) return t;
    }
    for (i = 0; i < (int)PARTY.n; i++) if (!(PARTY.chr[i].ailments & AIL_OUT)) return i;
    return -1;
}

// Nasconde sagoma e strato di accento di un personaggio: serve al lampeggio e
// serve alla morte, che e' un lampeggio che non torna indietro.
static void hide_character(int chr) {
    clear_sprite_at(chr, spr_col(chr));
    svc_put_sprite16((unsigned char)(ACC_HANDLE_STAND + chr), 0, 200,
                     (unsigned char)(ACC_HANDLE_STAND + chr), 0);
}

// `FlashCharacterSprite` (bank_0C.asm:3099): 16 frame, visibilita' commutata
// ogni 2 -- quattro lampeggi. Sul NES nasconde le 6 sprite OAM del
// personaggio; qui la sagoma e' fatta di celle di sfondo piu' UNO sprite di
// accento, quindi vanno spenti tutti e due, altrimenti l'accento resterebbe
// sospeso sul vuoto.
static void flash_character(int chr) {
    unsigned char col = spr_col(chr);
    int f;
    for (f = 0; f < 16; f++) {
        if ((f & 0x02) == 0) {
            draw_sprite_at(chr, col);
            put_accent_at(chr, col);
        } else {
            /* Fuori schermo, come il #$F0 del NES: la SAT resta valida. */
            hide_character(chr);
        }
        svc_wait_vblank();
    }
    draw_sprite_at(chr, col);
    put_accent_at(chr, col);
}

// Il colpo del nemico. Stessa `DoPhysicalAttack` del lato giocatore, con le
// statistiche prese dall'altra parte del campo (`EnemyAttackPlayer_Physical`,
// bank_0C.asm:4103):
//   danno base   = ENROMSTAT_DAMAGE  (che sul NES diventa en_strength)
//   colpi        = ENROMSTAT_NUMHITS (x moltiplicatore FAST, che vale 1)
//   tiro, critico= ENROMSTAT_HITRATE / ENROMSTAT_CRITRATE
// contro evasione e assorbimento del personaggio.
//
// Due bonus della routine non compaiono qui, e non per semplificazione:
// nella direzione nemico -> giocatore sono SEMPRE spenti. Il +40/+4 da
// debolezza confronta l'elemento dell'attaccante con la debolezza del
// difensore, e un personaggio non ne ha (`btlch_elemweak` forzato a zero,
// bank_0C.asm:5668); la categoria, uguale. Scriverli sarebbe codice che non
// puo' mai essere eseguito. Torneranno con la magia, dove le due parti si
// scambiano i ruoli.
// Da slice69 il +-40 da CECITA' c'e' anche di qua, ed e' la direzione in cui
// si vede per prima: DARK e' un attacco NEMICO (EnAtk_04 e EnAtk_15), mentre
// il gruppo la cecita' la subisce molto prima di poterla infliggere.
static unsigned int enemy_physical(const unsigned char *st, int chr,
                                   unsigned char atk_ail, int slot) {
    chr_t *c = &PARTY.chr[chr];
    ibstat_t *a = &IBE(slot);
    ibstat_t *d = &IBC(chr);
    return strike_core(immobile_dmg((int)a->dmg, c->ailments),
                       168 + dark_delta(atk_ail, c->ailments)
                           + (int)st[ENROMSTAT_HITRATE] - (int)d->evade,
                       (int)st[ENROMSTAT_CRITRATE],
                       (int)st[ENROMSTAT_NUMHITS] * (int)a->hits_mult,
                       (int)d->absorb);
}

// Il colpo che porta gli HP a zero deve anche accendere AIL_DEAD (slice69).
// Non e' ridondanza: CURE guarda il BIT, non gli HP (`BtlMag_Effect_RecoverHP`
// esce subito se AIL_DEAD e' acceso), e senza questa riga si potrebbe curare un
// caduto riportandolo in piedi -- che e' il mestiere di LIFE, non di CURE.
// Il verso opposto non serve: gli HP a zero non si rialzano da soli.
static void chr_hurt(chr_t *c, unsigned int dmg) {
    if (dmg >= c->curhp) { c->curhp = 0; c->ailments |= AIL_DEAD; }
    else                 { c->curhp -= dmg; }
}

// L'alterazione che viaggia sul COLPO, non sull'incantesimo (slice69).
// E' la strada per cui il gruppo si ritrova avvelenato o cieco davvero
// giocando: il byte $0F delle statistiche di un mostro
// (`ENROMSTAT_ATTACKAIL`, "curse you, Sorcerers!!!" nel disassembly) dice cosa
// lascia addosso quando le sue zanne arrivano. Senza questo, le alterazioni del
// gruppo sarebbero raggiungibili solo dalla magia nemica, che nel primo
// continente non esiste quasi.
//
// Chance = 100, azzerata dalla resistenza elementale del difensore, meno la sua
// difesa magica, con un minimo di 1 (bank_0C.asm:4530-4590). L'elemento
// dell'attaccante nel colpo fisico di un mostro non e' tabellato -- il NES lo
// prende da `btl_attacker_element`, che per un nemico resta zero -- quindi il
// ramo della resistenza non puo' scattare e non lo scriviamo.
//
// FIX #7 della lista di intenti. Sul NES basta che UNO dei colpi precedenti sia
// andato a segno, e da li' in poi anche le mancate possono avvelenare: il
// controllo e' su `battle_hitsconnected`, che e' cumulativo, e il disassembly lo
// segna come bug. Qui l'alterazione si prova solo se la scarica ha morso.
static void attack_ailment(int chr, unsigned char m) {
    chr_t *c = &PARTY.chr[chr];
    int chance;

    if (m == 0 || hits_connected == 0) return;
    /* Gia' caduto, o ce l'ha gia': in nessuno dei due casi c'e' qualcosa da
       dire. Il NES sul primo stampa "Ineffective" (bank_0C.asm:4460); qui il
       riquadro l'ha appena occupato il colpo, e sovrascriverlo direbbe una cosa
       meno utile di quella che c'e' gia'. */
    if (c->ailments & (AIL_OUT | m)) return;

    chance = 100 - (int)c->magdef;
    if (chance < 1) chance = 1;
    if (!magic_roll(chance)) return;

    c->ailments |= m;
    BST.ail_set++;
    BST.ail_last = m;
    if (m & AIL_DEAD) { c->curhp = 0; hide_character(chr); }
    render_status_block(chr);
    render_message(ail_name(m));
    wait_frames(45);
}

static void enemy_apply_and_report(int slot, int chr, unsigned int dmg) {
    chr_t *c = &PARTY.chr[chr];

    if (!report_strike(BST.type_name[BST.enemy_type[slot]], c->name, dmg)) return;

    chr_hurt(c, dmg);

    flash_character(chr);
    render_status_block(chr);          /* gli HP sullo schermo, subito */
    wait_frames(30);

    if (c->curhp == 0) {
        hide_character(chr);
        report_death(c->name);
    }
}

// =====================================================================
//  Magia dei nemici (slice60, TRASLOCATA nel banco 23 in slice69)
// =====================================================================
// Il MOTORE non e' piu' qui. Da slice69 il lancio -- di qualunque parte del
// campo -- sta tutto in ovl_btlmagic.c, e qui resta una chiamata piu' quel
// poco che di la' non si puo' fare.
//
// PERCHE' SI E' MOSSO. La ragione immediata e' che il banco 20 era finito: le
// alterazioni di stato aggiungevano ~1200 byte a un banco che ne aveva 229
// liberi. Ma la ragione buona e' un'altra, e si e' vista provando: le due
// direzioni del campo facevano le STESSE cose in due file diversi -- il tiro a
// 200 facce, il danno elementale, la maschera dei bersagli, e ora anche i due
// modi di appiccicare un'alterazione. Erano gia' due copie in slice68 (il
// commento in testa a ovl_btlmagic.c le chiamava "gemelle"); con slice69
// sarebbero diventate quattro. Una divergenza fra le due copie non si vede
// giocando: si vede come "i mostri resistono piu' dei personaggi", che e'
// anche quello che fa un motore GIUSTO.
//
// COSA RESTA DI QUA, e sempre lo stesso elenco: cio' che sa DOVE stanno le
// sagome. Il lampeggio del colpito, la sagoma da spegnere quando cade, la
// striscia da rinfrescare. Il banco 23 scrive HP e alterazioni in RAM e
// restituisce una MASCHERA di chi ha toccato; a farla vedere si pensa qui.
static int enemy_cast(unsigned char spell_id, int slot) {
    unsigned int mask;
    int i;

    // Il contatore e l'id sono le due sonde di slice60, e vanno scritti QUI:
    // l'incantesimo puo' non partire (bersaglio impossibile, effetto non
    // implementato) e il test deve poter distinguere "l'IA non ha tirato" da
    // "ha tirato e non ha fatto niente". L'id serve anche al banco 23, che lo
    // rilegge da qui invece di farselo passare: nell'argomento di
    // svc_run_overlay c'e' posto per un byte solo, e quel byte e' lo slot.
    BST.cast_count++;
    BST.last_spell = spell_id;

    mask = svc_run_overlay(BTLMAGIC_BANK,
                           (unsigned int)(BTLMAG_MODE_ENEMYCAST | slot));

    for (i = 0; i < (int)PARTY.n; i++) {
        if (mask & (1u << i)) flash_character(i);
        if (PARTY.chr[i].ailments & AIL_OUT) hide_character(i);
    }
    render_status_strip();
    return (count_alive_party() == 0) ? BATTLE_RESULT_DEFEAT : 0;
}

// `Enemy_DoAi` (bank_0C.asm:6892). L'ordine non e' simmetrico e va rispettato:
// si prova PRIMA la magia, poi l'attacco speciale, e il colpo normale solo se
// non e' uscito nessuno dei due. Chi ha una probabilita' di magia alta quindi
// non arriva quasi mai a considerare lo speciale.
//
// Le caselle si scorrono A GIRO, e la posizione e' per SLOT: due nemici della
// stessa specie hanno contatori indipendenti. Una casella $FF non e' "niente
// da fare", e' fine lista -- si riazzera e si ricomincia dalla prima.
//
// Ritorna -1 per dire "nessuna azione speciale, tira il colpo normale".
static int enemy_ai_turn(int slot, const unsigned char *st) {
    unsigned char ai[ENEMY_AI_SIZE];
    unsigned char id = st[ENROMSTAT_AI];
    int pos, tries;

    if (id == 0xFF) return -1;                  /* nessuna IA */
    if (id >= ENEMY_AI_COUNT) return -1;        /* indice fuori tabella */
    fetch_ai(id, ai);

    /* rand[0,128] < tasso => si fa (`EnemyAi_ShouldPerformAction`, 6873) */
    if ((int)rand_ax(0, 128) < (int)ai[ENEMY_AI_MAGRATE]) {
        for (tries = 0; tries < 8; tries++) {
            pos = (int)(BST.enemy_aimagpos[slot] & 0x07);
            BST.enemy_aimagpos[slot] = (unsigned char)(pos + 1);
            if (ai[ENEMY_AI_SPELLS + pos] != 0xFF) {
                return enemy_cast(ai[ENEMY_AI_SPELLS + pos], slot);
            }
            BST.enemy_aimagpos[slot] = 0;
        }
        return -1;      /* tutte vuote: il NES non ci arriva mai, noi si' */
    }
    if ((int)rand_ax(0, 128) < (int)ai[ENEMY_AI_ATKRATE]) {
        for (tries = 0; tries < 4; tries++) {
            pos = (int)(BST.enemy_aiatkpos[slot] & 0x03);
            BST.enemy_aiatkpos[slot] = (unsigned char)(pos + 1);
            if (ai[ENEMY_AI_ATTACKS + pos] != 0xFF) {
                return enemy_cast((unsigned char)(ai[ENEMY_AI_ATTACKS + pos]
                                                  + ENEMY_AI_ATK_BASE), slot);
            }
            BST.enemy_aiatkpos[slot] = 0;
        }
        return -1;
    }
    return -1;
}

// La fuga per morale bassa (bank_0C.asm:6782). La formula del NES:
//   L = 2 x livello del PRIMO personaggio (il capogruppo, morto o vivo)
//   se morale < L                    -> scappa
//   V = (morale - L) + rand[0,$32]
//   se V sta in 8 bit e V < $50      -> scappa
// Un nemico che scappa NON e' un nemico ucciso: il NES gli azzera EXP e oro
// (bank_0C.asm:6818) prima di liberare lo slot. Qui la stessa cosa si fa
// sottraendo la sua quota dai totali, che load_enemy_info aveva sommato per
// tutti gli slot all'inizio della battaglia.
// ATTENZIONE al livello. Il NES fa `LDA ch_level / ASL A`, e `ch_level` nel
// blocco FUORI battaglia e' 0-BASED (`variables.inc:395`: "OB this is 0 based,
// IB this is 1 based"). Il nostro `level` in party_state.h e' 1-based, quindi
// va tolto uno: senza, ogni nemico si crederebbe di fronte a un gruppo di due
// livelli piu' alto e scapperebbe prima del dovuto. E' il tipo di scarto che
// non da' nessun sintomo finche' non si e' abbastanza forti da vederlo.
// Il morale si legge dal blocco IB da slice70, ed e' cio' che fa esistere FEAR:
// quella magia non fa altro che abbassarlo, e finche' il numero veniva dalla
// ROM abbassarlo non voleva dire niente. Adesso una FEAR ben piazzata manda via
// i mostri davvero -- che e' l'unico modo in cui il giocatore la vede
// funzionare, perche' il morale a schermo non c'e'.
static int enemy_try_run(int slot, const unsigned char *st) {
    int lead = ((int)PARTY.chr[0].level - 1) * 2;
    int morale = (int)IBE(slot).morale;
    int v;

    if (morale >= lead) {
        v = (morale - lead) + (int)rand_ax(0, 0x32);
        if (v > 255)   return 0;
        if (v >= 0x50) return 0;
    }

    {
        char msg[BTL_MAX_MSG + 1];
        unsigned int e = (unsigned int)st[0] | ((unsigned int)st[1] << 8);
        unsigned int g = (unsigned int)st[2] | ((unsigned int)st[3] << 8);
        int k = msg_name(msg, 0, BST.type_name[BST.enemy_type[slot]]);
        k = msg_lit(msg, k, " RUNS AWAY");
        msg[k] = 0;
        render_message(msg);

        BST.exp_total = (BST.exp_total > e) ? (BST.exp_total - e) : 0;
        BST.gp_total  = (BST.gp_total  > g) ? (BST.gp_total  - g) : 0;

        erase_enemy(slot);                 /* prima: legge ancora il tipo */
        BST.enemy_hp[slot]   = 0;
        BST.enemy_type[slot] = BST_NO_ENEMY;
        wait_frames(45);
    }
    return 1;
}

// Il turno di un nemico.
//
// Da slice60 passa anche per `enemy_ai_turn`: chi ha una voce di IA puo'
// lanciare un incantesimo o un attacco speciale prima di ripiegare sul colpo.
static int enemy_turn(int slot) {
    unsigned char st[20];
    unsigned char ail;
    int chr, r;

    if (!enemy_alive(slot)) return 0;

    // Chi dorme, chi e' paralizzato e chi e' confuso non agisce: prova a
    // uscirne e il turno finisce li' (`Battle_DoEnemyTurn`, bank_0C.asm:6672).
    // Il tiro sta nel banco 23 insieme a quello dei personaggi, che e' lo
    // stesso tiro: due copie divergerebbero, e una divergenza fra le due parti
    // del campo e' esattamente il genere di cosa che non si vede giocando.
    ail = BST.enemy_ail[slot];
    if (ail & (AIL_SLEEP | AIL_STUN | AIL_CONF)) {
        svc_run_overlay(BTLMAGIC_BANK, (unsigned int)(BTLMAG_MODE_AILTURN | slot));
        return 0;
    }

    fetch_enemy_stat(BST.type_enemy[BST.enemy_type[slot]], st);

    if (enemy_try_run(slot, st)) {
        return (count_alive_enemies() == 0) ? BATTLE_RESULT_VICTORY : 0;
    }

    /* Magia o attacco speciale. -1 = non e' uscito niente, si picchia. */
    r = enemy_ai_turn(slot, st);
    if (r >= 0) return r;

    chr = random_player_target();
    if (chr < 0) return BATTLE_RESULT_DEFEAT;

    enemy_apply_and_report(slot, chr, enemy_physical(st, chr, ail, slot));
    attack_ailment(chr, st[ENROMSTAT_ATTACKAIL]);
    return (count_alive_party() == 0) ? BATTLE_RESULT_DEFEAT : 0;
}

// Il turno di un personaggio: il corpo che fino a slice58 stava nel ciclo del
// round, estratto perche' adesso lo chiama la coda dell'iniziativa.
static int player_turn(int chr) {
    chr_t *c = &PARTY.chr[chr];
    unsigned char ail = c->ailments;
    int tgt;

    if (ail & AIL_OUT) return 0;                 /* caduto durante il round */

    // Sonno e paralisi si provano a scrollare QUI, nel proprio turno, e non
    // all'inizio del round: e' un'azione, e infatti la consuma. L'ordine conta
    // -- il tiro si fa PRIMA di guardare se c'era un comando scelto, perche' un
    // personaggio addormentato il comando non l'ha mai potuto scegliere
    // (next_undecided lo salta) e senza questo non si sveglierebbe mai piu'.
    if (ail & (AIL_SLEEP | AIL_STUN)) {
        svc_run_overlay(BTLMAGIC_BANK,
                        (unsigned int)(BTLMAG_MODE_AILTURN | BTGT_IS_CHR | chr));
        render_status_block(chr);
        return 0;
    }

    if (!BST.chr_chosen[chr]) return 0;

    // MUTO: la magia non esce, il turno e' perso. Sul NES il controllo e' al
    // momento di scegliere (bank_0C.asm:7428) e li' il comando MAGIC proprio
    // non si apre; qui si controlla ANCHE adesso, perche' fra la scelta e il
    // turno passa mezzo round e in mezzo puo' esserci arrivata una MUTE.
    // Bevande e oggetti restano permessi: il NES li blocca insieme alle magie
    // ed e' quasi certamente un bug (il silenzio non impedisce di bere).
    if (BST.chr_cmd[chr] == BCMD_MAGIC && (ail & AIL_MUTE)) {
        render_message("SILENCED");
        wait_frames(45);
        return 0;
    }

    // ---- MAGIA (slice68): il lancio sta nel banco 23 --------------------
    // Qui resta solo cio' che di la' non si puo' fare: ripulire l'arena dai
    // nemici che l'incantesimo ha ucciso e rinfrescare la striscia di stato.
    // La geometria della griglia vive in QUESTO overlay e in nessun altro
    // (vedi l'intestazione di ovl_btlmagic.c), quindi il banco 23 abbassa gli
    // HP in RAM e chi guarda chi e' morto e' questo ciclo.
    if (BST.chr_cmd[chr] == BCMD_MAGIC) {
        int s;
        if (count_alive_enemies() == 0) return BATTLE_RESULT_VICTORY;
        // Il bersaglio scelto puo' essere morto sotto i colpi di un compagno
        // che ha agito prima -- stessa regola del colpo fisico qui sotto, e
        // per la stessa ragione: pianificare il round non deve essere una
        // punizione. Solo per il bersaglio SINGOLO nemico: gli altri codici
        // ($80|n, $FE, $FF) non sono slot.
        if (BST.chr_tgt[chr] < BST_MAX_ENEMIES && !enemy_alive((int)BST.chr_tgt[chr])) {
            int nt = next_alive((int)BST.chr_tgt[chr], 1);
            if (nt < 0) return BATTLE_RESULT_VICTORY;
            BST.chr_tgt[chr] = (unsigned char)nt;
        }
        svc_run_overlay(BTLMAGIC_BANK, (unsigned int)(BTLMAG_MODE_CAST | chr));
        for (s = 0; s < BST_MAX_ENEMIES; s++) {
            if (BST.enemy_type[s] == BST_NO_ENEMY) continue;
            if (BST.enemy_hp[s] == 0) erase_enemy(s);
        }
        render_status_strip();
        return (count_alive_enemies() == 0) ? BATTLE_RESULT_VICTORY : 0;
    }

    if (BST.chr_cmd[chr] != BCMD_FIGHT) return 0;  /* DRINK/ITEM non ci sono */
    if (count_alive_enemies() == 0) return BATTLE_RESULT_VICTORY;

    tgt = (int)BST.chr_tgt[chr];
    // Il bersaglio scelto puo' essere morto sotto i colpi di un compagno che
    // ha agito prima: si passa al primo vivo invece di sprecare il turno. E'
    // quello che fa il NES, e senza sarebbe una punizione per aver pianificato
    // il round in anticipo. Da slice59 vale anche in senso inverso: fra la
    // scelta e l'azione puo' essersi messo di mezzo un nemico che ha agito
    // prima, o che e' scappato.
    if (!enemy_alive(tgt)) tgt = next_alive(tgt, 1);
    if (tgt < 0) return BATTLE_RESULT_VICTORY;

    apply_and_report(chr, tgt, resolve_physical(chr, tgt));
    return (count_alive_enemies() == 0) ? BATTLE_RESULT_VICTORY : 0;
}

// L'ordine di iniziativa (`DoBattleRound`, bank_0C.asm:3199-3244).
//
// Tredici caselle -- 9 slot nemico piu' 4 personaggi -- mescolate con SEDICI
// scambi di due posizioni pescate a caso in [0,12]. Non e' un mescolamento
// uniforme, e il disassembly stesso lo annota: una casella ha buone
// probabilita' di non essere mai toccata, e siccome i personaggi partono in
// FONDO alla lista, tendono a restarci. In pratica i nemici agiscono per primi
// piu' spesso di quanto un mescolamento onesto darebbe.
//
// Lo teniamo COSI', e la ragione non e' la fedelta' per se':
//   - il numero di estrazioni fa parte della sequenza. Sedici scambi = 32
//     chiamate al generatore; un mescolamento alla Fisher-Yates ne farebbe 12 e
//     sposterebbe ogni tiro successivo della battaglia. La parity dell'intero
//     combattimento passa di qui.
//   - non e' un refuso come LOK2, che fa il CONTRARIO di quel che dice: questo
//     ciclo fa esattamente cio' che dichiara, mescolare. Mescola male.
//   - e la penalita' e' distribuita su tutta la partita, non su un caso
//     singolo: e' parte del ritmo di FF1, non un incidente.
static void init_turn_order(void) {
    int i, n;
    for (i = 0; i < BST_MAX_ENEMIES; i++) {
        BST.turn_order[i] = (unsigned char)i;
    }
    for (i = 0; i < 4; i++) {
        BST.turn_order[BST_MAX_ENEMIES + i] = (unsigned char)(BST_TURN_IS_CHR | i);
    }
    for (n = 0; n < 16; n++) {
        unsigned char a = rand_ax(0, 12);
        unsigned char b = rand_ax(0, 12);
        unsigned char t = BST.turn_order[a];
        BST.turn_order[a] = BST.turn_order[b];
        BST.turn_order[b] = t;
    }
}

// Il round: si esegue quando TUTTI i vivi hanno scelto. Ritorna il risultato
// della battaglia, o 0 se continua.
// Fine del round: il veleno (`ApplyEndOfRoundEffects`, bank_0C.asm:3463).
// Due HP a testa, e puo' uccidere -- il NES lo dice esplicitamente ("poison may
// have killed the party") e infatti ricontrolla la fine dello scontro subito
// dopo, che e' quello che fa il chiamante qui sotto.
//
// SOLO IL GRUPPO, e il perche' merita una riga perche' contraddice il fix #15
// della lista di intenti ("veleno bidirezionale"). Quella voce da' per scontato
// che qualcosa possa avvelenare un mostro, e nei dati di FF1 non c'e': fra i 64
// incantesimi e i 26 attacchi speciali NESSUNO ha effetto $03 con
// effectivity $04 rivolto ai nemici -- PURE lo toglie, niente lo mette. Il ramo
// nemico sarebbe codice che non puo' mai essere eseguito, e questo file ha gia'
// una regola su quelli (vedi enemy_physical e il bonus da debolezza). Il giorno
// che un oggetto o un'arma avvelenasse, e' un ciclo di quattro righe.
static void apply_poison(void) {
    int i, any = 0;
    for (i = 0; i < (int)PARTY.n; i++) {
        chr_t *c = &PARTY.chr[i];
        if (c->ailments & AIL_OUT) continue;
        if (!(c->ailments & AIL_POISON)) continue;
        chr_hurt(c, 2);
        BST.ail_poison = (unsigned char)(BST.ail_poison + 2);
        any = 1;
        if (c->curhp == 0) { hide_character(i); report_death(c->name); }
    }
    if (any) render_status_strip();
}

static int resolve_round(void) {
    int chr, r;

    init_turn_order();

    for (BST.cur_turn = 0; BST.cur_turn < BST_TURN_ENTRIES; BST.cur_turn++) {
        unsigned char e = BST.turn_order[BST.cur_turn];
        r = (e & BST_TURN_IS_CHR) ? player_turn((int)(e & 3))
                                  : enemy_turn((int)e);
        if (r) return r;
    }

    apply_poison();

    for (chr = 0; chr < 4; chr++) BST.chr_chosen[chr] = 0;
    BST.round_num++;

    if (count_alive_enemies() == 0) return BATTLE_RESULT_VICTORY;
    if (count_alive_party()   == 0) return BATTLE_RESULT_DEFEAT;
    return 0;
}

// Passa al prossimo personaggio che deve ancora scegliere. Se non ce n'e' piu'
// nessuno ritorna -1, ed e' il segnale che il round puo' partire.
static int next_undecided(int from) {
    int i, c;
    for (i = 1; i <= (int)PARTY.n; i++) {
        c = (from + i) % (int)PARTY.n;
        // Da slice69 non sceglie nemmeno chi dorme, chi e' paralizzato e chi e'
        // di pietra: e' la maschera AIL_NOACT, la stessa che il NES applica in
        // due punti diversi (bank_0C.asm:328 e 560). Chi e' saltato qui non
        // perde il turno -- il turno gli arriva lo stesso, ed e' li' che tira
        // per svegliarsi.
        if (PARTY.chr[c].ailments & AIL_NOACT) continue;
        if (!BST.chr_chosen[c]) return c;
    }
    return -1;
}

// Impegna la scelta di un personaggio e passa al successivo -- e se non ce
// n'e' piu' nessuno, fa partire il round. Ritorna il risultato della
// battaglia, o 0 se continua.
//
// Estratta in slice68 dalla fase BERSAGLIO, dove era scritta in linea. Il
// motivo non e' l'eleganza: la magia impegna la scelta da DUE punti diversi --
// dopo il cursore sui nemici, come FIGHT, oppure subito, quando
// l'incantesimo il bersaglio se lo sceglie da solo (tutti i nemici, il
// gruppo, chi lancia). Due copie di questo blocco vorrebbero dire due modi di
// far partire il round, e il round e' la cosa che in questo file e' costata
// di piu' mettere a posto.
// Il cursore dei comandi torna su FIGHT a ogni personaggio. E' PARITA', non
// una preferenza: sul NES il menu principale passa da `MenuSelection_2x4`
// (bank_0C.asm:2190), che comincia con `LDA #$00 / STA btlcurs_x / STA
// btlcurs_y` -- il cursore e' azzerato a ogni chiamata, e una chiamata c'e'
// per ogni personaggio.
// Fino a slice67 restava dov'era, e non si notava perche' l'unico comando che
// faceva qualcosa era il primo. Con la magia si nota subito: il mago sceglie
// MAGIC, e il guerriero dopo di lui si trova il cursore su MAGIC.
static void reset_command_cursor(void) {
    if (BST.command_idx == BCMD_FIGHT) return;
    render_command_at((int)BST.command_idx, 0);
    BST.command_idx = BCMD_FIGHT;
    render_command_at(BCMD_FIGHT, 1);
}

static int commit_choice(int chr, unsigned char cmd, unsigned char tgt) {
    int nxt_chr;

    BST.chr_cmd[chr]    = cmd;
    BST.chr_tgt[chr]    = tgt;
    BST.chr_chosen[chr] = 1;
    BST.phase = BPHASE_CMD;

    nxt_chr = next_undecided(chr);
    if (nxt_chr < 0) {
        int outcome;
        step_back(chr);
        ov_char(24, stat_row(chr), ' ');
        outcome = resolve_round();
        if (outcome) return outcome;
        nxt_chr = next_undecided(-1);
        if (nxt_chr < 0) nxt_chr = 0;
    } else {
        // Solo su questo ramo. Sull'altro il passo indietro e' gia' stato
        // fatto PRIMA del round, e rifarlo adesso ridisegnerebbe la sagoma di
        // chi nel frattempo e' caduto: da slice59 il round puo' uccidere
        // anche di qua.
        step_back(chr);
        ov_char(24, stat_row(chr), ' ');
    }
    BST.turn_chr = (unsigned char)nxt_chr;
    step_forward(nxt_chr);
    ov_char(24, stat_row(nxt_chr), '>');
    render_status_strip();
    reset_command_cursor();
    render_message("FIRE1=OK  FIRE2=RUN");
    return 0;
}

static void render_battle_screen(void) {
    int i;
    svc_vfill(NT_BASE, 0x20, 768);
    for (i = 0; i < 16; i++) ov_char(24, (unsigned char)i, '|');
    render_monster_area();
    for (i = 0; i < (int)PARTY.n; i++) render_party_sprite(i);
    ov_fill_row(15, 0, 23, '-');
    render_target_box();
    render_command_box();
    render_status_strip();
    render_message("FIRE1=OK  FIRE2=RUN");
}

// ---------------------------------------------------------------------
//  VITTORIA -- fanfara + esultanza
// ---------------------------------------------------------------------
// Ricalca PlayFanfareAndCheer del NES (bank_0C.asm:2435): parte sng53, i
// personaggi alternano posa di esultanza e posa in piedi per 128 frame, poi
// tornano tutti alla posa naturale (SetAllNaturalPose).
//
// Sul NES a questo punto compare il riquadro con EXP e GP. Qui non c'e' ancora
// niente da assegnare -- non esiste il combattimento -- quindi si mostra solo
// la riga di vittoria e si aspetta FIRE1. Il riquadro arrivera' con la slice
// delle ricompense.
// Riquadro di fine battaglia, al posto della griglia dei comandi. Sul NES
// sono riquadri in sequenza, uno per volta, con un tasto fra l'uno e l'altro
// ("Monsters perished" / EXP / GP / "Level up!"); qui per ora e' un pannello
// solo. La sequenza vera arriva quando ci sara' anche il testo di battaglia.
static void render_reward_box(void) {
    int chr, row;
    ov_box(10, 13);
    ov_string(11, 17, "EXP");
    ov_u3(15, 17, BST.exp_award);
    ov_string(11, 18, "GP");
    ov_u3(15, 18, BST.gp_award);

    // Chi e' salito di livello. Due righe: se salgono in piu' di due, le altre
    // non si vedono -- limite noto del pannello unico.
    row = 19;
    for (chr = 0; chr < (int)PARTY.n && row <= 20; chr++) {
        if (!BST.new_level[chr]) continue;
        ov_string(11, (unsigned char)row, PARTY.chr[chr].name);
        ov_string(18, (unsigned char)row, "L");
        ov_u3(19, (unsigned char)row, BST.new_level[chr]);
        row++;
    }
}

static void run_victory(void) {
    int i, chr;
    unsigned char cheering, prev_cheering;

    // Ordine obbligatorio, e la ragione e' la VRAM, non la logica:
    //   1. si svuota l'arena, perche' le tile dei primi due tipi di nemico
    //      stanno per essere sovrascritte;
    //   2. si caricano le CHR dell'esultanza sopra quelle tile ($A4-$C7);
    //   3. poi la fanfara -- e non prima, perche' svc_battle_load_cheer
    //      azzera audio_enabled per attraversare il banco 2 in sicurezza, e
    //      farlo dopo taglierebbe la musica appena partita.
    clear_monster_area();
    svc_battle_load_cheer();
    svc_battle_victory_music();

    // Nessuno e' piu' "di turno": tutti tornano in riga.
    for (chr = 0; chr < (int)PARTY.n; chr++) {
        clear_sprite_at(chr, SPR_COL_FORWARD);
        draw_sprite_at(chr, SPR_COL_BACK);
        put_accent_at(chr, SPR_COL_BACK);
        ov_char(24, stat_row(chr), ' ');
    }
    render_message("VICTORY!");

    prev_cheering = 0;
    for (i = 0; i < CHEER_FRAMES; i++) {
        svc_wait_vblank();
        cheering = (unsigned char)((i / CHEER_PERIOD) & 1);
        if (i == 0 || cheering != prev_cheering) {
            for (chr = 0; chr < (int)PARTY.n; chr++) {
                if (cheering) {
                    draw_pose_at(chr, SPR_COL_BACK, CHEER_TILE_BASE);
                    put_accent_pose(chr, SPR_COL_BACK, ACC_HANDLE_CHEER);
                } else {
                    draw_pose_at(chr, SPR_COL_BACK, SPR_TILE_BASE);
                    put_accent_pose(chr, SPR_COL_BACK, ACC_HANDLE_STAND);
                }
            }
            prev_cheering = cheering;
        }
    }

    // Posa naturale (SetAllNaturalPose sul NES).
    for (chr = 0; chr < (int)PARTY.n; chr++) {
        draw_pose_at(chr, SPR_COL_BACK, SPR_TILE_BASE);
        put_accent_pose(chr, SPR_COL_BACK, ACC_HANDLE_STAND);
    }

    // Ricompense. Da slice76 il calcolo NON e' piu' nella finestra fissa: EXP,
    // oro e passaggi di livello erano 1539 byte per girare una volta a
    // battaglia vinta, e sono passati nel banco 23 -- lo stesso che questo
    // overlay chiama gia' per la magia. Qui si stampa solo l'esito, che arriva
    // in BST come prima.
    svc_run_overlay(BTLMAGIC_BANK, BTLMAG_MODE_AWARDEXP);
    render_reward_box();
    render_message("FIRE1=CONTINUE");

    // Fronte di salita, non livello: il FIRE1 tenuto premuto dal comando
    // precedente non deve chiudere subito la schermata.
    while (svc_joystick() & MOVE_FIRE1) svc_wait_vblank();
    while (!(svc_joystick() & MOVE_FIRE1)) svc_wait_vblank();
}

// Il gruppo e' caduto (slice59).
//
// Sul NES la risposta a un massacro e' "ricarica il salvataggio", e noi un
// salvataggio non ce l'abbiamo ancora. Qualunque cosa si faccia qui e' quindi
// un SEGNAPOSTO, e tanto vale che sia quello dichiarato: si mostra la fine, si
// aspetta il tasto, e il gruppo torna in piedi con tutti gli HP.
//
// Il ripristino sta QUI e non nella slice per una ragione di bilancio: PARTY
// vive nella RAM SGM a $6100, che l'overlay scrive direttamente, mentre nel
// banco fisso restano 169 byte e non e' il posto dove spendere per un
// segnaposto. Sparira' insieme al Continue vero.
//
// Manca il silenzio: il tema di battaglia continua a suonare sotto la scritta,
// perche' fermarlo vorrebbe dire una svc_ nuova, cioe' byte nella finestra
// fissa. Va con la sessione dei VFX, insieme allo scuotimento dello schermo.
static void run_defeat(void) {
    int chr;

    for (chr = 0; chr < (int)PARTY.n; chr++) {
        clear_sprite_at(chr, SPR_COL_FORWARD);
        clear_sprite_at(chr, SPR_COL_BACK);
        svc_put_sprite16((unsigned char)(ACC_HANDLE_STAND + chr), 0, 200,
                         (unsigned char)(ACC_HANDLE_STAND + chr), 0);
        ov_char(24, stat_row(chr), ' ');
    }
    clear_monster_area();
    // Anche i due riquadri in basso: il listino dei comandi e quello dei
    // bersagli restavano a schermo sotto la scritta di fine, e offrivano di
    // combattere a un gruppo che non c'e' piu'.
    {
        unsigned char r;
        for (r = 16; r <= 21; r++) ov_fill_row(r, 0, 24, ' ');
    }

    ov_string(4, 10, "THE PARTY PERISHED");
    render_message("FIRE1=CONTINUE");

    while (svc_joystick() & MOVE_FIRE1) svc_wait_vblank();
    while (!(svc_joystick() & MOVE_FIRE1)) svc_wait_vblank();

    for (chr = 0; chr < (int)PARTY.n; chr++) {
        PARTY.chr[chr].curhp    = PARTY.chr[chr].maxhp;
        // Anche le alterazioni, da slice69. Senza, il gruppo si rialzerebbe
        // con gli HP pieni e la scritta DEAD ancora addosso: la battaglia dopo
        // non partirebbe nemmeno, perche' count_alive_party guarda quel bit e
        // non gli HP. Sparisce col Continue vero, come il resto di questa
        // funzione.
        PARTY.chr[chr].ailments = 0;
    }
}

// ---------------------------------------------------------------------
//  Un frame di battaglia. Ritorna 1 quando la battaglia finisce.
// ---------------------------------------------------------------------
static unsigned int prev_j;
static unsigned char prev_key;

static int battle_tick(void) {
    unsigned int j;
    unsigned char joy, key, joy_edges, key_edges;

    j   = svc_joystick();
    joy = (unsigned char)(j & 0xFF);
    key = (unsigned char)((j >> 8) & 0xFF);

    joy_edges = (unsigned char)(joy & ~(unsigned char)(prev_j & 0xFF));
    key_edges = (key && key != prev_key) ? key : 0;

    // ---- fase BERSAGLIO ------------------------------------------------
    // Le quattro direzioni fanno tutte la stessa cosa: scorrere i nemici VIVI
    // in ordine visivo, avanti o indietro. Sul NES il cursore si muove nella
    // griglia, ma la griglia ha buchi (i morti) e navigarla a due assi vuol
    // dire inseguirli. Qui la scorciatoia c'e' gia' ed e' migliore: i tasti
    // 1-9 del tastierino puntano il nemico direttamente, che e' esattamente
    // l'uso per cui [[design-input]] voleva il tastierino.
    if (BST.phase == BPHASE_TARGET) {
        int cur = (int)BST.cursor_tgt;
        int nxt = cur;

        if (joy_edges & (MOVE_DOWN | MOVE_RIGHT)) nxt = next_alive(cur, 1);
        if (joy_edges & (MOVE_UP | MOVE_LEFT))    nxt = next_alive(cur, -1);
        if (key_edges >= '1' && key_edges <= '9') {
            int s = slot_from_visual(key_edges - '1');
            if (enemy_alive(s)) nxt = s;
        }
        if (nxt >= 0 && nxt != cur) {
            draw_target_cursor(cur, 0);
            BST.cursor_tgt = (unsigned char)nxt;
            draw_target_cursor(nxt, 1);
            render_message(BST.type_name[BST.enemy_type[nxt]]);
        }

        // FIRE2 torna indietro senza impegnare il personaggio: si puo'
        // cambiare idea sul comando.
        if (joy_edges & MOVE_FIRE2) {
            draw_target_cursor((int)BST.cursor_tgt, 0);
            BST.phase = BPHASE_CMD;
            render_message("FIRE1=OK  FIRE2=RUN");
        } else if (joy_edges & MOVE_FIRE1) {
            int outcome;
            draw_target_cursor((int)BST.cursor_tgt, 0);
            // `command_idx` e non BCMD_FIGHT: di qui passa anche la magia che
            // vuole UN nemico, e in quel caso il comando impegnato deve
            // restare MAGIC. L'incantesimo scelto e' gia' in BST.chr_spell.
            prev_j = j; prev_key = key;
            outcome = commit_choice((int)BST.turn_chr, BST.command_idx, BST.cursor_tgt);
            if (outcome) return outcome;
        }

        prev_j = j; prev_key = key;
        return 0;
    }

    // ---- fase COMANDO ---------------------------------------------------
    if (joy_edges & MOVE_UP) {
        int prev_cmd = (int)BST.command_idx;
        BST.command_idx = (unsigned char)((prev_cmd + N_COMMANDS - 1) % N_COMMANDS);
        render_command_at(prev_cmd, 0);
        render_command_at((int)BST.command_idx, 1);
    }
    if (joy_edges & MOVE_DOWN) {
        int prev_cmd = (int)BST.command_idx;
        BST.command_idx = (unsigned char)((prev_cmd + 1) % N_COMMANDS);
        render_command_at(prev_cmd, 0);
        render_command_at((int)BST.command_idx, 1);
    }
    // Salto diretto al CHR col tastierino: la ragione per cui il round NON
    // puo' assumere l'ordine lineare -- vedi [[battle-round-start-todo]].
    // Da slice57 si puo' saltare solo su chi deve ANCORA scegliere: su chi ha
    // gia' deciso non ci sarebbe niente da fare, e il round parte comunque
    // solo quando hanno scelto tutti.
    if (key_edges >= '1' && key_edges <= '4') {
        int new_chr = key_edges - '1';
        if (new_chr < (int)PARTY.n && new_chr != (int)BST.turn_chr &&
            !BST.chr_chosen[new_chr] &&
            !(PARTY.chr[new_chr].ailments & AIL_NOACT)) {
            int prev = (int)BST.turn_chr;
            step_back(prev);
            BST.turn_chr = (unsigned char)new_chr;
            step_forward(new_chr);
            ov_char(24, stat_row(prev),     ' ');
            ov_char(24, stat_row(new_chr),  '>');
            reset_command_cursor();
        }
    }
    if (joy_edges & MOVE_FIRE1) {
        if (BST.command_idx == BCMD_FIGHT) {
            int first = enemy_alive((int)BST.cursor_tgt)
                            ? (int)BST.cursor_tgt : next_alive(0, 1);
            if (first >= 0) {
                BST.cursor_tgt = (unsigned char)first;
                BST.phase = BPHASE_TARGET;
                draw_target_cursor(first, 1);
                render_message(BST.type_name[BST.enemy_type[first]]);
            }
        } else if (BST.command_idx == BCMD_MAGIC &&
                   (PARTY.chr[BST.turn_chr].ailments & AIL_MUTE)) {
            // Il muto non apre nemmeno il sottomenu, come sul NES
            // (bank_0C.asm:7428). Dirlo QUI e non dopo aver scelto
            // l'incantesimo e' la differenza fra un divieto e uno scherzo.
            render_message("SILENCED");
        } else if (BST.command_idx == BCMD_MAGIC) {
            // ---- slice68: il sottomenu sta nel banco 23 -------------------
            // Si entra in un overlay da DENTRO un overlay. Al ritorno la meta'
            // bassa dello schermo e' quella del sottomenu, quindi i due
            // riquadri si ridisegnano SEMPRE -- anche quando si e' tornati
            // indietro senza scegliere niente, perche' il sottomenu li ha
            // cancellati comunque.
            int chr = (int)BST.turn_chr;
            unsigned int r = svc_run_overlay(BTLMAGIC_BANK,
                                             (unsigned int)(BTLMAG_MODE_SELECT | chr));
            render_target_box();
            render_command_box();
            render_status_strip();
            // La riga 22 e' il suggerimento del SOTTOMENU e in battaglia non
            // esiste: senza questa riga resta scritto "FIRE1 CAST FIRE2 BACK"
            // sotto il riquadro dei comandi, cioe' un'istruzione che non vale
            // piu'. I due riquadri qui sopra coprono le righe 16-21 e il
            // messaggio la 23: la 22 non la ridisegna nessuno.
            ov_fill_row(22, 0, 24, ' ');

            if (r == BTLMAG_CANCELLED) {
                render_message("FIRE1=OK  FIRE2=RUN");
            } else {
                unsigned char tgt = (unsigned char)(r >> 8);
                BST.chr_spell[chr] = (unsigned char)(r & 0x00FF);
                if (tgt == BTGT_PICK_FOE) {
                    // Il bersaglio nemico lo sceglie la fase che c'e' gia': il
                    // cursore sull'arena e' di questo overlay e resta suo.
                    int first = enemy_alive((int)BST.cursor_tgt)
                                    ? (int)BST.cursor_tgt : next_alive(0, 1);
                    if (first >= 0) {
                        BST.cursor_tgt = (unsigned char)first;
                        BST.phase = BPHASE_TARGET;
                        draw_target_cursor(first, 1);
                        render_message(BST.type_name[BST.enemy_type[first]]);
                    }
                } else {
                    int outcome;
                    prev_j = j; prev_key = key;
                    outcome = commit_choice(chr, BCMD_MAGIC, tgt);
                    if (outcome) return outcome;
                }
            }
        } else if (BST.command_idx == BCMD_RUN) {
            prev_j = j; prev_key = key;
            return BATTLE_RESULT_ESCAPE;
        } else {
            // DRINK/ITEM: dichiarati mancanti invece di fingere. Il comando
            // resta selezionabile perche' la griglia e' quella del NES, e
            // sparira' da qui quando ci sara' un inventario.
            render_message("NOT YET");
        }
    }
    if (joy_edges & MOVE_FIRE2) {
        prev_j = j; prev_key = key;
        return BATTLE_RESULT_ESCAPE;
    }

    prev_j = j; prev_key = key;
    return 0;
}

// ---------------------------------------------------------------------
//  Ingresso: il primo byte del banco 20 e' `jp _overlay_main` ($C000).
//  Ritorna quando la battaglia finisce; il `ret` torna nel banco fisso.
// ---------------------------------------------------------------------
unsigned int overlay_main(unsigned int arg) {
    unsigned int j;

    (void)arg;

    if (BST.magic != BATTLE_STATE_MAGIC) {
        // Prova a schermo che il canale non ha funzionato, invece di
        // disegnare una schermata costruita su valori a caso.
        svc_vfill(NT_BASE, 0x20, 768);
        ov_string(0, 10, "BAD BATTLE STATE AT 6000");
        while (1) { svc_wait_vblank(); }
    }

    // Le CHR dei personaggi stanno nel banco 2: solo il banco fisso puo'
    // andarcele a prendere. Al ritorno il banco 20 e' di nuovo mappato,
    // altrimenti questa riga non esisterebbe piu'.
    svc_battle_load_gfx();

    // Chi ho davanti. L'ordine e' obbligato:
    //   1. i 16 byte grezzi arrivano dal banco 12;
    //   2. si decodificano qui, e solo adesso si sa quanti tipi ci sono;
    //   3. nomi, HP e bottino, che dipendono dagli id appena estratti;
    //   4. le sagome, che dipendono da tipo e palette -- e DOPO load_gfx, che
    //      riazzera pattern e color table: invertire cancellerebbe i mostri
    //      appena caricati.
    svc_battle_fetch_formdata();
    svc_run_overlay(BTLMAGIC_BANK, BTLMAG_MODE_SETUP);
    svc_battle_load_enemy_gfx();

    // Stato del round. Va azzerato QUI e non dichiarato inizializzato: il
    // blocco vive in RAM SGM e nessuno lo ripulisce fra una battaglia e
    // l'altra, quindi senza questo la seconda battaglia partirebbe con le
    // scelte della prima gia' impegnate.
    {
        int c;
        BST.phase      = BPHASE_CMD;
        BST.cursor_tgt = 0;
        for (c = 0; c < 4; c++) { BST.chr_chosen[c] = 0; BST.chr_cmd[c] = 0; BST.chr_tgt[c] = 0; }
        // Le caselle dell'IA ripartono da capo (slice60). Senza, il primo
        // incantesimo del secondo incontro riprenderebbe da dove era arrivato
        // il primo: la RAM SGM non la pulisce nessuno fra una battaglia e
        // l'altra, ed e' la stessa trappola gia' pagata con le scelte del
        // round.
        for (c = 0; c < BST_MAX_ENEMIES; c++) {
            BST.enemy_aimagpos[c] = 0;
            BST.enemy_aiatkpos[c] = 0;
            // Le alterazioni dei MOSTRI si azzerano qui e quelle del GRUPPO no,
            // ed e' una differenza di sostanza, non di comodo: questi mostri
            // non esistevano un minuto fa, mentre il veleno addosso a un
            // personaggio se lo porta in giro per la mappa -- e' proprio il
            // motivo per cui PURE si vende in negozio.
            BST.enemy_ail[c] = 0;
        }
        BST.cast_count = 0;
        BST.last_spell = 0xFF;
        // Le stesse due, lato giocatore (slice68). Azzerate qui per la stessa
        // ragione di tutto il resto: la RAM SGM non la pulisce nessuno fra una
        // battaglia e l'altra.
        BST.pc_cast_count = 0;
        BST.pc_last_spell = 0xFF;
        BST.ail_set    = 0;
        BST.ail_last   = 0;
        BST.ail_turns  = 0;
        BST.ail_poison = 0;
        BST.buff_set   = 0;
        BST.buff_last  = 0;
        for (c = 0; c < 4; c++) BST.chr_spell[c] = 0xFF;
    }

    render_battle_screen();

    // La musica entra insieme all'immagine, non durante il caricamento delle
    // CHR. Suona dal banco 10 mentre questo codice gira dal banco 20: la NMI
    // salta fra i due a ogni frame -- schema validato in slice51.
    svc_battle_start_music();

    // Il primo frame serve solo a fotografare lo stato dei pulsanti: senza,
    // il FIRE1 che ha chiuso il passo in overworld verrebbe letto qui come
    // un fronte di salita e sceglierebbe subito un comando.
    svc_wait_vblank();
    j = svc_joystick();
    prev_j   = j;
    prev_key = (unsigned char)((j >> 8) & 0xFF);

    for (;;) {
        int outcome;
        svc_wait_vblank();
        outcome = battle_tick();
        if (outcome == 0) continue;
        if (outcome == BATTLE_RESULT_VICTORY) run_victory();
        if (outcome == BATTLE_RESULT_DEFEAT)  run_defeat();
        BST.result = (unsigned char)outcome;
        return (unsigned int)outcome;
    }
}
