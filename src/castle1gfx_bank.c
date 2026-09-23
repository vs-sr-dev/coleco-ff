// =====================================================================
//  castle1gfx_bank.c -- BANCO 17: Coneria Castle 1F (mappa 8, tileset 1)
// =====================================================================
// Stessa forma di towngfx_bank.c, che e' il capostipite: pattern + color +
// 4 TSA + mappa + proprieta' + abitanti, tutti dalla stessa passata di
// tools/extract_sm_colors.ps1 -- vedi la' per il perche' stanno insieme.
//
// UNA MAPPA = UN BANCO (slice77). I due piani del castello NON condividono il
// tileset pur avendo lo stesso tileset NES: unire le coppie tile/palette
// costerebbe un calcolo in piu' per risparmiare 16KB su 512, che non e' un
// vincolo da [[megacart-bank-ceiling]].
// =====================================================================

#define FF1_CASTLE1GFX_DEFINE_DATA
#include "ff1_castle1gfx.h"

const unsigned char *const castle1gfx_pattern = ff1_castle1gfx_pattern;
const unsigned char *const castle1gfx_color   = ff1_castle1gfx_color;
const unsigned char *const castle1gfx_tsa_ul  = ff1_castle1gfx_tsa_ul;
const unsigned char *const castle1gfx_tsa_ur  = ff1_castle1gfx_tsa_ur;
const unsigned char *const castle1gfx_tsa_dl  = ff1_castle1gfx_tsa_dl;
const unsigned char *const castle1gfx_tsa_dr  = ff1_castle1gfx_tsa_dr;
const unsigned char *const castle1gfx_map     = ff1_castle1gfx_map;
const unsigned char *const castle1gfx_prop    = ff1_castle1gfx_prop;
const unsigned char *const castle1gfx_npc_pattern = ff1_castle1gfx_npc_pattern;
const unsigned char *const castle1gfx_npc_color   = ff1_castle1gfx_npc_color;
const unsigned char *const castle1gfx_npc_slots   = ff1_castle1gfx_npc_slots;
const unsigned char *const castle1gfx_npc_sprite  = ff1_castle1gfx_npc_sprite;

int main(void) { return 0; }
