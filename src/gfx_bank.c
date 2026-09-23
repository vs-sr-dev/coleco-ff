// gfx_bank.c — MegaCart bank 2: battle sprite + accent CHR data.
//
// Contiene:
//   - ff1_class_sprite      (288 byte): STAND tile pattern 6 classi x 6 tile
//   - ff1_class_sprite_color (288 byte): per-row dominant TMS color (battle bg fill)
//   - ff1_class_accent       (288 byte): OAM accent mask 6 classi x 6 tile
//   - ff1_class_accent_color   (6 byte): per-class OAM color
//
// Total: ~870 byte di dati che prima vivevano in slice main code (vincolato a
// 32KB). Spostandoli qui in bank 2, slice main code recupera ROM budget.
//
// Linker: -crt0=sgm_bank_crt0 (rombase=$C000, romsize=16384).
// build_megacart.ps1 -Bank2 gfx_bank.rom -> splicia a file offset 0x8000.
//
// Slice main code legge tramite gfx_bank_symbols.h (#define GFX_FF1_*_ADDR)
// con mc_select_bank(2) attivo. Pattern d'uso: a battle entry, switcha a
// bank 2, carica CHR + cache accent_color in RAM locale, switcha back a 0.

// Activate the data definitions in the shared header (gated to avoid
// double-emission in slice main code which doesn't define this macro).
#define FF1_BATTLE_SPRITES_DEFINE_DATA
#include "ff1_battle_sprites.h"

// Posa di ESULTANZA (slice52). Stessa forma piatta+gated e stessa ragione.
// NB dal disassembly (bank_0C.asm:2858-2859): la voce $14 della tabella delle
// pose, usata per lanciare le MAGIE, punta alle stesse tile $0E $10 $12 della
// posa di esultanza. Quando arrivera' la magia, queste CHR sono gia' caricate.
#define FF1_CHEER_SPRITES_DEFINE_DATA
#include "ff1_cheer_sprites.h"

// Re-export with gfx_ prefix as plain const pointers so the linker writes
// them in the .map. gen_bank_symbols.ps1 -Prefix gfx_ extracts these.
// Arrays are now flat [288] (1-D) so sccz80 keeps them in rodata (bank ROM),
// not the DATA section (RAM, never copied in a bank blob). Slice access is
// flat-offset already: idx = (cls*6 + tile)*8 + byte.
const unsigned char *const gfx_ff1_class_sprite       = ff1_class_sprite;
const unsigned char *const gfx_ff1_class_sprite_color = ff1_class_sprite_color;
const unsigned char *const gfx_ff1_class_accent       = ff1_class_accent;
const unsigned char *const gfx_ff1_class_accent_color = ff1_class_accent_color;
const unsigned char *const gfx_ff1_class_cheer        = ff1_class_cheer;
const unsigned char *const gfx_ff1_class_cheer_color  = ff1_class_cheer_color;
const unsigned char *const gfx_ff1_class_cheer_accent = ff1_class_cheer_accent;

// Dummy main: linker requires _main symbol. Never executed (this bank is
// data-only; never JMP'd to).
int main(void) { return 0; }
