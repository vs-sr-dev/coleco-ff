// =====================================================================
//  mapman_bank.c -- BANCO 9: sprite del mapman a colori (6 classi)
// =====================================================================
// Dati generati da tools/extract_mapman_v3.ps1: tre strati (meta' alta,
// meta' bassa, incarnato) x 6 classi x 8 frame x 32 byte = 4608 byte,
// piu' 18 byte di colori.
//
// Il rendering sovrappone tre sprite: sul TMS9918 l'indice SAT piu' basso
// sta davanti, quindi l'incarnato va in SAT[0] e "buca" le due meta' del
// corpo. Alto e basso non si sovrappongono fra loro.
//
// I re-export sono puntatori in rodata, mai array multidimensionali: quelli
// finirebbero in DATA, che in un banco non viene mai inizializzata.
// =====================================================================

#define FF1_MAPMAN_DEFINE_DATA
#include "ff1_mapman_flat.h"

const unsigned char *const mapman_top          = ff1_mapman_top_flat;
const unsigned char *const mapman_bot          = ff1_mapman_bot_flat;
const unsigned char *const mapman_accent       = ff1_mapman_accent_flat;
const unsigned char *const mapman_outline      = ff1_mapman_outline_flat;
const unsigned char *const mapman_top_color    = ff1_mapman_top_color_flat;
const unsigned char *const mapman_bot_color    = ff1_mapman_bot_color_flat;
const unsigned char *const mapman_accent_color = ff1_mapman_accent_color_flat;

int main(void) { return 0; }
