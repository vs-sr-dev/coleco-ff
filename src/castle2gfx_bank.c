// =====================================================================
//  castle2gfx_bank.c -- BANCO 18: Coneria Castle 2F (mappa 24, tileset 1)
// =====================================================================
// Vedi castle1gfx_bank.c: stessa forma, piano di sopra. Qui vivono il Re,
// la principessa salvata (id $12, che COMINCIA nascosta) e la stanza dove
// Talk_Princess1 teletrasporta il gruppo (NORM $3F, casella 12,7).
// =====================================================================

#define FF1_CASTLE2GFX_DEFINE_DATA
#include "ff1_castle2gfx.h"

const unsigned char *const castle2gfx_pattern = ff1_castle2gfx_pattern;
const unsigned char *const castle2gfx_color   = ff1_castle2gfx_color;
const unsigned char *const castle2gfx_tsa_ul  = ff1_castle2gfx_tsa_ul;
const unsigned char *const castle2gfx_tsa_ur  = ff1_castle2gfx_tsa_ur;
const unsigned char *const castle2gfx_tsa_dl  = ff1_castle2gfx_tsa_dl;
const unsigned char *const castle2gfx_tsa_dr  = ff1_castle2gfx_tsa_dr;
const unsigned char *const castle2gfx_map     = ff1_castle2gfx_map;
const unsigned char *const castle2gfx_prop    = ff1_castle2gfx_prop;
const unsigned char *const castle2gfx_npc_pattern = ff1_castle2gfx_npc_pattern;
const unsigned char *const castle2gfx_npc_color   = ff1_castle2gfx_npc_color;
const unsigned char *const castle2gfx_npc_slots   = ff1_castle2gfx_npc_slots;
const unsigned char *const castle2gfx_npc_sprite  = ff1_castle2gfx_npc_sprite;

int main(void) { return 0; }
