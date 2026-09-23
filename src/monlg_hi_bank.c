// =====================================================================
//  monlg_hi_bank.c -- BANCO 14: nemici GRANDI, pagine CHR 8-15
// =====================================================================
// Gemello di monlg_lo_bank.c (banco 13), stessa struttura e stesse dimensioni;
// la' ci sono le pagine 0-7, qui le 8-15. La ragione del taglio per pagina, e
// il motivo per cui le palette restano nel banco 12, sono spiegati nel gemello.
// =====================================================================

#define FF1_MONLG_HI_DEFINE_DATA
#include "ff1_monlg_hi.h"

const unsigned char *const monlghi_pattern = ff1_monlg_hi_pattern;
const unsigned char *const monlghi_rowval  = ff1_monlg_hi_rowval;

int main(void) { return 0; }
