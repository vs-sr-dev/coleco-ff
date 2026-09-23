// =====================================================================
//  world_state.h -- il mondo fuori dal gruppo, in RAM SGM (slice76)
// =====================================================================
// Due cose che non appartengono ne' al gruppo ne' a una battaglia, e che devono
// essere leggibili da un overlay senza che nessuno gli passi puntatori:
//
//   1. `game_flags`, i 208 byte di FF1 -- uno per id di oggetto. Tre bit:
//      visibile, evento fatto, forziere aperto. Sono la memoria di TUTTO cio'
//      che nel gioco succede una volta sola, e per questo non stanno in nessun
//      banco: si SCRIVONO.
//   2. `NPCS`, gli abitanti della mappa in cui si sta adesso. Li copia qui la
//      slice all'ingresso, leggendoli dal banco della mappa; li usano la slice
//      (per disegnarli, per bloccarci il passo, per capire chi si ha davanti)
//      e il banco 26 (per sapere QUALE dialogo esce).
//
// MAPPA DELLA RAM SGM, aggiornata:
//   $2000-$5FFF  world_cells, la mappa espansa in celle (16KB pieni)
//   $6000-$60FF  stato di battaglia (battle_state.h)
//   $6100-$62FF  il gruppo (party_state.h) -- ne usa 350 su 512
//   $6300-$63FF  il listino del negozio (shop_state.h)
//   $6400-$64FF  statistiche di sola battaglia (battle_ibstats.h)
//   $6500-$65FF  QUI, il mondo
//   $6C00        BSS degli overlay (crt/overlay_crt0.asm)
// =====================================================================

#ifndef WORLD_STATE_H
#define WORLD_STATE_H

#define WORLD_STATE_ADDR   0x6500
//   0x1D01 = slice76 (game_flags + gli abitanti della mappa corrente)
#define WORLD_STATE_MAGIC  0x1D01

/* $D0 come sul NES: gli id di oggetto arrivano a $CF. La tabella e' indicizzata
   per ID DI OGGETTO, non per slot -- due slot con lo stesso id (le due guardie
   di Coneria Castle, id $20) condividono lo stesso flag, ed e' voluto: il NES
   nasconde "un oggetto qualunque con quell'id" (HideMapObject). */
#define GAME_FLAG_COUNT   0xD0

/* Constants.inc:126. Il bit 0 deve restare il bit 0: CheckGameEventFlag lo
   fa scorrere fuori con due LSR, e IsObjectVisible con uno solo. */
#define GMFLG_OBJVISIBLE  0x01
#define GMFLG_EVENT       0x02
#define GMFLG_TCOPEN      0x04

/* 15 come sul NES: LoadMapObjects carica esattamente $0F oggetti per mappa
   (bank_0F.asm:9438), e le tile degli NPC sono allocate in VRAM su questo
   numero -- non su quanti abitanti ha davvero la mappa. */
#define NPC_MAX           15

/* Prima tile TMS degli NPC. La mappa dei 256 tile della citta':
     0  - 92    il tileset vero (93 coppie tile/palette, misurate)
     96 - 155   4 tile per slot NPC, cotte sopra il terreno
     160- 254   il font del BIOS, caratteri $20-$7E
   I due buchi (93-95 e 156-159) sono margine: il tileset di un'altra mappa
   puo' arrivare a 96 coppie senza rifare i conti, e l'extractor si ferma con
   un errore se li supera. */
#define NPC_TILE_BASE     96
#define TOWN_FONT_BASE    160
#define TOWN_FONT_FIRST   0x20    /* primo carattere ASCII del font BIOS */
/* La barra verticale del riquadro di dialogo. NON e' il carattere '|': nel
   font del BIOS il glifo $7C si disegna come '>' ([[coleco-bios-pipe-glyph]]).
   Vive in uno dei quattro tile di margine fra gli NPC e il font, e le due
   parti che la usano -- la slice che la carica e il banco 26 che la scrive --
   prendono il numero da qui, non da due costanti gemelle. */
#define TOWN_VBAR_TILE    159

/* I progressi che sul NES NON stanno in `game_flags` ne' nell'inventario: sono
   variabili loro (`bridge_vis`, `ship_vis`, `airship_vis`, `canal_vis`,
   `has_canoe` in variables.inc). Qui diventano cinque bit di un byte solo --
   il conto e' identico e la mappa della RAM resta leggibile.
   Cio' che invece NON e' qui: gli OGGETTI CHIAVE e le QUATTRO SFERE, che sul
   NES stanno in `items` e da noi stanno gia' in `PARTY.item[]` byte per byte
   (ITEM_LUTE, ITEM_ORB_FIRST...). Duplicarli sarebbe due verita' sulla stessa
   cosa. */
#define WPROG_BRIDGE   0x01
#define WPROG_SHIP     0x02
#define WPROG_AIRSHIP  0x04
#define WPROG_CANAL    0x08
#define WPROG_CANOE    0x10

typedef struct {
    unsigned int  magic;
    unsigned char progress;       /* WPROG_* */
    /* Quanti slot ha la mappa corrente (compresi quelli vuoti: si scorre
       sempre fino a `count` e si salta chi ha id 0). */
    unsigned char count;
    unsigned char id[NPC_MAX];    /* id di oggetto; 0 = slot vuoto */
    unsigned char x[NPC_MAX];     /* in MACROtile */
    unsigned char y[NPC_MAX];
    unsigned char flags[GAME_FLAG_COUNT];
} world_t;

#define WORLD (*(world_t *)WORLD_STATE_ADDR)

/* Le tre domande che le routine di dialogo fanno ai flag. Sono macro e non
   funzioni perche' le usano tutte e due le parti (finestra fissa e banco 26) e
   una funzione andrebbe duplicata o esportata come `svc_` -- 3 byte di conto
   dietro 166 byte di servizio ([[svc-generalize-rule]] al contrario). */
#define OBJ_VISIBLE(id)   ((WORLD.flags[id] & GMFLG_OBJVISIBLE) != 0)
#define OBJ_EVENT(id)     ((WORLD.flags[id] & GMFLG_EVENT) != 0)

/* slice77: gli EFFETTI che una routine di dialogo chiede al motore. Il banco
   26 scrive da solo cio' che e' RAM (flag, LUTE, ponte); fanfara, battaglia e
   teletrasporto invece hanno bisogno di banchi che l'overlay non puo' mappare,
   quindi tornano come bit ALTI del valore di ritorno -- il byte basso resta
   l'id del dialogo mostrato, come da slice76. Li esegue town_tick al rientro.
   Stanno QUI perche' li scrivono due parti (banco 26 e finestra fissa) e due
   costanti gemelle sono due posti dove divergere. */
#define TALK_FX_FANFARE 0x0100   /* sng54, il "got an important item!" */
#define TALK_FX_FIGHT   0x0200   /* la battaglia di Garland ($7F) */
#define TALK_FX_TELE    0x0400   /* il ritorno della principessa (NORM $3F) */

#endif
