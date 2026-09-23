// =====================================================================
//  towngfx_bank.c -- BANCO 15: Coneria a colori veri, mappa compresa
// =====================================================================
// Generato da tools/extract_sm_colors.ps1:
//   pattern 2048 + color 2048 + 4 TSA da 128 + mappa 64x64 = 8704 byte.
//
// PERCHE' ANCHE LA MAPPA STA QUI, e non e' un dettaglio di comodo: durante il
// disegno della citta' si mappa UN banco solo. Mappa e TSA rimappata sono
// prodotte dallo stesso strumento nella stessa passata proprio perche' non
// possano disallinearsi -- un disallineamento fra le due non da' errore, da'
// una citta' con la geometria giusta e i tile sbagliati. E' gia' successo in
// slice40 ([[ff1-sm-tsa-layout]]).
//
// I re-export sono `const unsigned char *const`: puntatori in RODATA, MAI
// array multidimensionali -- quelli finirebbero in DATA, che in un banco non
// viene mai copiata in RAM (nessun crt0_init gira qui). Bug #3 di slice44,
// [[slice44-real-root-causes]].
// =====================================================================

#define FF1_TOWNGFX_DEFINE_DATA
#include "ff1_towngfx.h"

const unsigned char *const towngfx_pattern = ff1_towngfx_pattern;
const unsigned char *const towngfx_color   = ff1_towngfx_color;
const unsigned char *const towngfx_tsa_ul  = ff1_towngfx_tsa_ul;
const unsigned char *const towngfx_tsa_ur  = ff1_towngfx_tsa_ur;
const unsigned char *const towngfx_tsa_dl  = ff1_towngfx_tsa_dl;
const unsigned char *const towngfx_tsa_dr  = ff1_towngfx_tsa_dr;
const unsigned char *const towngfx_map     = ff1_towngfx_map;
// slice64: le proprieta' dei macrotile (collisioni, porte, uscita) vengono
// da qui e non da ff1_town_coneria.h, che le aveva come `[128][2]` -- cioe'
// in DATA, che in un banco non viene mai copiata in RAM.
const unsigned char *const towngfx_prop    = ff1_towngfx_prop;
// slice76: gli abitanti. Le loro tile stanno QUI e non in un banco proprio
// perche' sono cotte SOPRA il terreno della citta' -- vengono dalla stessa
// passata di extract_sm_colors.ps1 che produce pattern e colore, e dividerle
// vorrebbe dire poterle disallineare dal tileset su cui poggiano.
// La tabella degli slot le accompagna per la stessa ragione: dice su quale
// macrotile ogni abitante sta, cioe' quale terreno gli e' stato cotto sotto.
const unsigned char *const towngfx_npc_pattern = ff1_towngfx_npc_pattern;
const unsigned char *const towngfx_npc_color   = ff1_towngfx_npc_color;
const unsigned char *const towngfx_npc_slots   = ff1_towngfx_npc_slots;
// Il contorno nero, come sprite 16x16. Non e' una rifinitura: in Mode 2 una
// riga di tile ha DUE colori e per un abitante ne servono tre -- terreno,
// corpo, contorno. Il fondo porta i primi due, lo sprite il terzo.
const unsigned char *const towngfx_npc_sprite  = ff1_towngfx_npc_sprite;

int main(void) { return 0; }
