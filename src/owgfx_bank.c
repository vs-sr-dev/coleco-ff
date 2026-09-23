// =====================================================================
//  owgfx_bank.c -- BANCO 8: grafica overworld a colori veri
// =====================================================================
// Contiene i dati generati da tools/extract_ow_colors.ps1:
//   pattern 2048 + color 2048 + 4 tabelle TSA da 128 = 4608 byte.
//
// Perche' in un banco e non nella slice: la slice principale aveva ~500 byte
// liberi su 32KB. Spostare qui la grafica OW libera anche i 2560 byte del
// vecchio ff1_owbg.h, che era rodata della slice.
//
// I re-export sono `const unsigned char *const`: puntatori in RODATA, MAI
// array multidimensionali -- quelli finirebbero in sezione DATA, che in un
// banco non viene mai copiata in RAM (nessun crt0_init gira qui). E' il bug
// #3 di slice44, vedi memoria [[slice44-real-root-causes]].
// =====================================================================

#define FF1_OWGFX_DEFINE_DATA
#include "ff1_owgfx.h"

const unsigned char *const owgfx_pattern = ff1_owgfx_pattern;
const unsigned char *const owgfx_color   = ff1_owgfx_color;
const unsigned char *const owgfx_tsa_ul  = ff1_owgfx_tsa_ul;
const unsigned char *const owgfx_tsa_ur  = ff1_owgfx_tsa_ur;
const unsigned char *const owgfx_tsa_dl  = ff1_owgfx_tsa_dl;
const unsigned char *const owgfx_tsa_dr  = ff1_owgfx_tsa_dr;

// slice78: le quattro tile del PONTE, cotte sopra il macrotile dell'oceano su
// cui poggia (tools/extract_bridge_tile.ps1). Stanno QUI e non in un banco
// loro perche' sono grafica di overworld a tutti gli effetti: le carica lo
// stesso load_ow_chr_palette, nella stessa escursione, negli slot 236-239 che
// il tileset lascia liberi. 64 byte in un banco che ne ha migliaia.
#define FF1_BRIDGE_TILE_DEFINE_DATA
#include "ff1_bridge_tile.h"
const unsigned char *const owgfx_bridge_pattern = ff1_bridge_tile_pattern;
const unsigned char *const owgfx_bridge_color   = ff1_bridge_tile_color;

int main(void) { return 0; }
