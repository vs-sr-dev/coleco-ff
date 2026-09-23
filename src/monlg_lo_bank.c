// =====================================================================
//  monlg_lo_bank.c -- BANCO 13: nemici GRANDI, pagine CHR 0-7
// =====================================================================
// 16 slot x 36 tile x 8 byte di sagome, altrettanti di dominanti per riga:
// 9216 byte. La meta' alta delle pagine sta nel banco 14, identico a questo.
//
// PERCHE' IL TAGLIO E' PER PAGINA E NON PER TIPO DI DATO
// Sagome di qua e colori di la' sarebbe il taglio sbagliato: caricare una tile
// vuole entrambi, quindi ogni singola tile costerebbe due cambi di banco.
// Tagliando invece per pagina CHR il vincolo diventa favorevole, perche' una
// formazione dichiara UNA pagina sola (nibble basso del byte 0): qualunque
// battaglia tocca un banco solo e lo mappa una volta.
//
// Le palette NON sono qui: stanno nel banco 12 accanto ai nemici piccoli. Sono
// le stesse per grandi e piccoli, e duplicarle vorrebbe dire poterle
// disallineare -- un grande e un piccolo della stessa palette uscirebbero di
// due colori diversi nella stessa arena.
//
// Re-export come `const unsigned char *const`, MAI array multidimensionali:
// quelli finirebbero in sezione DATA, che in un banco non viene mai copiata in
// RAM perche' qui non gira nessun crt0_init. Vedi [[slice44-real-root-causes]].
// =====================================================================

#define FF1_MONLG_LO_DEFINE_DATA
#include "ff1_monlg_lo.h"

const unsigned char *const monlglo_pattern = ff1_monlg_lo_pattern;
const unsigned char *const monlglo_rowval  = ff1_monlg_lo_rowval;

int main(void) { return 0; }
