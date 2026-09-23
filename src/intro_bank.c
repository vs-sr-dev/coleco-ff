// intro_bank.c â€” MegaCart bank 1 dei asset di intro per slice42+.
//
// Contenuto:
//   - Songs sng41 (Prelude) + sng42 (Prologue), accessed via NMI mentre
//     bank 1 e' selezionato in $C000-$FFFF.
//   - Prologue text strings (la storia "The world is veiled in darkness...")
//   - Nomi classe + nomi PG default
//
// Linker config: rombase=$C000, romsize=16384 (1 banco 16KB). Output:
//   intro_bank.rom (16KB) -- viene splicato a file offset 16384 in MC ROM
//   tramite build_megacart.ps1 -Bank1.
//
// Symbol manifest: tutti i simboli static const usati dal main slice42
// devono essere esposti via il map file. tools/gen_bank_symbols.ps1 parse
// il .map e genera intro_bank_symbols.h con #define _SYM 0xC0xx per ciascuno.

typedef struct { unsigned int period; unsigned char frames; } note_event_t;

#include "songs/sng41.h"   // Prelude â€” used in title + class select
#include "songs/sng42.h"   // Prologue â€” used in prologue scene
#include "songs/sng47.h"   // Town theme â€” slice43b: moved here to free slice43b rodata budget

// Re-export as global symbols (sng41.h / sng42.h declare static) so the
// linker writes them in the .map for the symbol-extraction tool.
const note_event_t *const intro_sng41_sq1 = sng41_sq1;
const note_event_t *const intro_sng41_sq2 = sng41_sq2;
const note_event_t *const intro_sng41_tri = sng41_tri;
const note_event_t *const intro_sng42_sq1 = sng42_sq1;
const note_event_t *const intro_sng42_sq2 = sng42_sq2;
const note_event_t *const intro_sng42_tri = sng42_tri;
const note_event_t *const intro_sng47_sq1 = sng47_sq1;
const note_event_t *const intro_sng47_sq2 = sng47_sq2;
const note_event_t *const intro_sng47_tri = sng47_tri;

// I TESTI NON SONO PIU' QUI (slice62). Stavano in questo banco perche' la
// scena che li disegna girava col banco 1 mappato, per via del Prelude. Da
// slice62 la scena vive nell'overlay del banco 21, e da li' il banco 1 non si
// vede: i testi sono diventati rodata di src/ovl_intro.c, accanto al codice
// che li usa. Qui resta solo cio' che serve davvero al banco 1: la musica.

// Dummy main: il linker vuole il simbolo _main. Non viene mai eseguito
// (banco di soli dati, nessuno ci salta dentro).
int main(void) { return 0; }
