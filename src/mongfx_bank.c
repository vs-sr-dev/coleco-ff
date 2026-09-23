// =====================================================================
//  mongfx_bank.c -- BANCO 12: grafica dei nemici piccoli + palette
// =====================================================================
// Contiene quello che produce tools/extract_monster_gfx.ps1:
//   sagome 4096 + dominante per riga 4096 + palette 256 = 8448 byte.
//
// Tutte e 16 le pagine CHR sono qui, non solo quelle che servono adesso: il
// censimento delle 128 formazioni dice che ne usano 13, e tenerle tutte costa
// 8KB su un banco da 16KB. Con [[megacart-bank-ceiling]] a 512KB i dati non
// sono piu' il vincolo, mentre andare a ripescare una pagina mancante mesi
// dopo lo sarebbe.
//
// PERCHE' LE PALETTE STANNO QUI E NON IN ff1_palettes.h
// Non e' una duplicazione per comodita'. Chi carica la grafica dei nemici e'
// una svc_ del banco fisso che, mentre lavora, ha mappato QUESTO banco: in
// quel momento la rodata della slice (banco 0, dove vive ff1_palettes.h) non
// esiste. Se la tabella delle palette stesse la', la svc_ leggerebbe byte a
// caso proprio mentre decide di che colore sono i mostri. Tenendo sagome,
// dominanti e palette nello stesso banco, il caricamento e' una lettura sola
// senza cambi di banco in mezzo.
//
// Re-export come `const unsigned char *const`, MAI array multidimensionali:
// quelli finirebbero in sezione DATA, che in un banco non viene mai copiata
// in RAM -- non gira nessun crt0_init qui. Bug #3 di slice44, vedi
// [[slice44-real-root-causes]].
// =====================================================================

#define FF1_MONGFX_DEFINE_DATA
#include "ff1_monster_gfx.h"
// La tabella delle formazioni sta qui e non nella slice: erano 2048 byte di
// rodata nel banco 0, e il banco 0 era arrivato a 396 byte liberi. Sta accanto
// alla grafica perche' i due dati si consultano nello stesso momento --
// all'ingresso in battaglia -- e cosi' il prelievo e' un cambio di banco solo.
#define FF1_FORMATIONS_DEFINE_DATA
#include "ff1_encounter.h"

const unsigned char *const mongfx_pattern = ff1_mon_pattern;
const unsigned char *const mongfx_rowval  = ff1_mon_rowval;
const unsigned char *const mongfx_pal_tms = ff1_pal_tms;
const unsigned char *const mongfx_names   = ff1_mon_names;
const unsigned char *const mongfx_forms   = ff1_battle_formations;

int main(void) { return 0; }
