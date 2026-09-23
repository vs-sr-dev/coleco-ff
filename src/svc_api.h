// =====================================================================
//  svc_api.h -- i servizi che il banco FISSO espone agli overlay
// =====================================================================
// Un'unica dichiarazione per entrambe le parti, cosi' le due firme non
// possono divergere in silenzio (divergere = argomenti storti sullo stack =
// spazzatura, senza nessun errore di compilazione).
//
//   - la slice principale include questo header SENZA definire SVC_OVERLAY:
//     ottiene i prototipi, e il compilatore verifica le sue definizioni;
//   - l'overlay lo include DOPO aver definito SVC_OVERLAY: ottiene macro che
//     chiamano attraverso i puntatori presi da main_symbols.h (rigenerato a
//     ogni build dalla .map della slice, vedi tools/build_all.ps1).
//
// REGOLA D'ORO (crt/overlay_crt0.asm): una svc_ non deve MAI toccare rodata
// del banco 0 -- mentre l'overlay e' mappato, il banco 0 non esiste. Solo
// VDP, RAM e argomenti. Le uniche svc_ che cambiano banco sono quelle che lo
// rimettono a posto prima di tornare (svc_battle_load_gfx).
// =====================================================================

#ifndef SVC_API_H
#define SVC_API_H

#ifdef SVC_OVERLAY

#include "main_symbols.h"

#define svc_vwrite \
    ((void (*)(const void *, unsigned int, unsigned int))SVC_VWRITE_ADDR)
#define svc_vfill \
    ((void (*)(unsigned int, unsigned char, unsigned int))SVC_VFILL_ADDR)
#define svc_put_sprite16 \
    ((void (*)(unsigned char, int, int, unsigned char, unsigned char))SVC_PUT_SPRITE16_ADDR)
#define svc_wait_vblank \
    ((void (*)(void))SVC_WAIT_VBLANK_ADDR)
#define svc_joystick \
    ((unsigned int (*)(void))SVC_JOYSTICK_ADDR)
#define svc_battle_load_gfx \
    ((void (*)(void))SVC_BATTLE_LOAD_GFX_ADDR)
#define svc_battle_start_music \
    ((void (*)(void))SVC_BATTLE_START_MUSIC_ADDR)
#define svc_battle_victory_music \
    ((void (*)(void))SVC_BATTLE_VICTORY_MUSIC_ADDR)
#define svc_battle_load_enemy_gfx \
    ((void (*)(void))SVC_BATTLE_LOAD_ENEMY_GFX_ADDR)
#define svc_battle_load_cheer \
    ((void (*)(void))SVC_BATTLE_LOAD_CHEER_ADDR)
#define svc_battle_fetch_formdata \
    ((void (*)(void))SVC_BATTLE_FETCH_FORMDATA_ADDR)
#define svc_fetch_enemy_name \
    ((void (*)(unsigned char, unsigned char *))SVC_FETCH_ENEMY_NAME_ADDR)
#define svc_battle_rng \
    ((unsigned char (*)(void))SVC_BATTLE_RNG_ADDR)
#define svc_fetch_btl \
    ((void (*)(unsigned char, unsigned int, unsigned char, unsigned char *))SVC_FETCH_BTL_ADDR)
#define svc_run_overlay \
    ((unsigned int (*)(unsigned char, unsigned int))SVC_RUN_OVERLAY_ADDR)
#define svc_equip_recalc \
    ((void (*)(unsigned char))SVC_EQUIP_RECALC_ADDR)
#define svc_shop_fetch \
    ((void (*)(unsigned char))SVC_SHOP_FETCH_ADDR)
#define svc_shop_load_icons \
    ((void (*)(unsigned char))SVC_SHOP_LOAD_ICONS_ADDR)
#define svc_border \
    ((void (*)(unsigned char))SVC_BORDER_ADDR)

#else

void svc_vwrite(const void *srcp, unsigned int addr, unsigned int len);
void svc_vfill(unsigned int addr, unsigned char val, unsigned int len);
void svc_put_sprite16(unsigned char id, int x, int y,
                      unsigned char handle, unsigned char color);
void svc_wait_vblank(void);
/* Joystick + tastierino del giocatore 1: L = bit MOVE_*, H = tasto ASCII.
   NON usa joystick() della libreria -- la sua tabella di decodifica del
   tastierino sta in rodata oltre $C000, quindi sotto l'overlay tornerebbe
   spazzatura. Vedi src/joy.asm. */
unsigned int svc_joystick(void);
void svc_battle_load_gfx(void);
/* Avvia sng50 dal banco 10. Da chiamare DOPO aver disegnato la schermata. */
void svc_battle_start_music(void);
/* Fanfara di vittoria (sng53, stesso banco). */
void svc_battle_victory_music(void);
/* svc_award_exp NON C'E' PIU' (slice76). Le ricompense di fine battaglia sono
   passate nel banco 23, modo BTLMAG_MODE_AWARDEXP: erano 1539 byte di finestra
   fissa per girare una volta a battaglia vinta -- la leva 1 di
   [[fixed-window-full]]. Le tre tabelle dei livelli, che erano la sola ragione
   per cui quel codice doveva stare nella finestra fissa, arrivano all'overlay
   con svc_fetch_btl (tabelle 9, 10, 11). */
/* Sagome dei nemici a colori nelle tile $A4+, una tacca da 16 per tipo.
   Legge la formazione gia' decodificata in BST e mappa il banco 12. */
void svc_battle_load_enemy_gfx(void);
/* Posa di esultanza nelle tile $A4-$C7, che durante il combattimento
   appartengono ai nemici. Da chiamare SOLO a battaglia vinta e SOLO dopo aver
   ripulito l'arena -- e prima della fanfara, perche' azzera audio_enabled. */
void svc_battle_load_cheer(void);
/* I 16 byte grezzi della formazione BST.formation, dal banco 12 a BST.formdata.
   La DECODIFICA sta nell'overlay: qui il banco fisso e' pieno. */
void svc_battle_fetch_formdata(void);
/* 9 byte del nome del nemico `id`, gia' convertito (banco 12). */
void svc_fetch_enemy_name(unsigned char id, unsigned char *dst);
/* Il generatore della battaglia, separato da quello dell'encounter. */
unsigned char svc_battle_rng(void);
/* Prelievo dalle tabelle di regole del banco 11. UNA funzione per tutte e
   cinque (0 = statistiche nemico, 1 = incantesimo, 2 = voce di IA,
   3 = permessi di magia, 4 = nomi degli oggetti): affiancarne una seconda a quella dei nemici era
   costato 166 byte di finestra fissa.
   L'offset e' in BYTE e lo calcola il chiamante -- una moltiplicazione per una
   lunghezza variabile qui dentro chiamerebbe un aiuto di libreria.
   Da slice67 rimette `main_bank`, non il banco della battaglia: e' cio' che la
   rende chiamabile da un overlay qualunque, e il negozio di magia e' il primo
   che non e' quello di battaglia. Rimette anche `audio_enabled` com'era. */
void svc_fetch_btl(unsigned char table, unsigned int off,
                   unsigned char len, unsigned char *dst);
/* Entra nell'overlay del banco `bank` (ingresso fisso $C000) e ripristina il
   banco che era mappato prima -- non lo zero, ma `main_bank` com'era: e' cio'
   che rende la chiamata annidabile da dentro un altro overlay.
   E' l'UNICO modo previsto di entrare in un banco di codice: la sequenza fatta
   a mano ha una finestra in cui `main_bank` e il banco mappato non concordano,
   e una NMI caduta li' dentro lascia mappato il banco sbagliato. */
unsigned int svc_run_overlay(unsigned char bank, unsigned int arg);

// Ricalcola le sotto-statistiche effettive di un personaggio dalle sue basi
// piu' l'equipaggiamento indossato. Va chiamata dopo OGNI cambiamento delle
// caselle o delle basi. Mappa il banco 16 e rimette quello di partenza, quindi
// non si puo' chiamare in mezzo a un'escursione altrui.
void svc_equip_recalc(unsigned char who);

// Compone il listino del negozio nel blocco condiviso (shop_state.h) e porta
// in VRAM le tile delle icone di tipo. Le tabelle stanno nel banco 16, che
// l'overlay del negozio non puo' mappare: mentre gira, il banco e' lui.
void svc_shop_fetch(unsigned char shop_id);
void svc_shop_load_icons(unsigned char tile_base);
/* Colore del bordo (costanti VDP_INK_*). Serve alle scene che stanno in un
   overlay: i due OUT che scrivono un registro del VDP vanno serializzati con
   la NMI dell'audio, che il VDP lo tocca a ogni frame. */
void svc_border(unsigned char color);

#endif

#endif
