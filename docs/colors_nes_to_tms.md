# Colors mapping NES → TMS9918 (Coleco)

**Status:** spec v1, session 6 (2026-05-08). Visually validated by slice25 on the 6 class battle sprites.

## Hardware reminder

**NES PPU palette:**
- 64 master colours indexed `$00-$3F` (format `$HL`: H = brightness 0-3, L = hue 0-15).
- 8 sub-palettes of 4 colours each = 32 bytes total in `cur_pal` ($03C0-$03DF):
  - `cur_pal+$00..$0F` = 4 background sub-pals
  - `cur_pal+$10..$1F` = 4 sprite sub-pals
- Color 0 of each sub-pal = transparent (sprites) or universal bg (BG layer).
- OAM attr byte bits 0-1 select the sub-pal for each sprite.
- The BG attribute table selects the sub-pal for groups of 2x2 metatiles (16x16 px).

**TMS9918 mode 2 (Coleco target):**
- 16 FIXED colours (hardcoded palette, no way to remap):
  ```
  0: transparent   1: black         2: medium green  3: light green
  4: dark blue     5: light blue    6: dark red      7: cyan
  8: medium red    9: light red    10: dark yellow  11: light yellow
  12: dark green  13: magenta      14: gray         15: white
  ```
- For each BG tile: 8 pattern bytes + 8 color bytes (1 byte per row, format `(fg << 4) | bg`).
- For each sprite: only 1 colour (no per-pixel palette on sprites).
- The screen is split into 3 vertical bands (rows 0-7, 8-15, 16-23), each with its own pattern + color table — replicate every asset 3 times if it must appear anywhere on screen.

## Current strategy: OR-plane silhouette → 2-color tile

For NES 4-color assets → TMS9918 2-color (pipeline validated in session 1, see `asset_pipeline.md`):

1. **OR planes:** `tms_byte = nes_low_plane | nes_high_plane` for each row. Collapses NES colours 1/2/3 into 1 fg; NES color 0 stays bg.
2. **Color bytes per row:** pick 1 fg + 1 bg per row (8 color bytes/tile).

Effect: the 4 colours of the NES sub-pal become 2. Internal detail is lost (e.g. the gi/belt distinction for BlackBelt), but the silhouette + 1 accent color are preserved.

## NES master color → TMS9918 mapping table (lookup)

Reduced to the cases we actually meet in the sprites (expand if needed):

| NES `$XY` | description               | TMS9918 idx | name      |
|-----------|---------------------------|-------------|-----------|
| `$0F`     | black                     | 1           | black     |
| `$0D`     | blacker (illegal)         | 1           | black     |
| `$00`     | grey medium               | 14          | gray      |
| `$10`     | grey light                | 14          | gray      |
| `$20`     | grey lighter              | 14          | gray      |
| `$30`     | white                     | 15          | white     |
| `$01`     | dark blue                 | 4           | dark blue |
| `$11`     | medium blue               | 4           | dark blue |
| `$12`     | medium dark blue          | 4           | dark blue |
| `$21`     | light blue                | 5           | light blue|
| `$22`     | bright blue               | 5           | light blue|
| `$15-16`  | red                       | 6/8         | dark red / medium red |
| `$26`     | bright red                | 9           | light red |
| `$36`     | pink                      | 9           | light red |
| `$28`     | tan / skin                | 11          | light yellow |
| `$18`     | dark olive                | 10          | dark yellow |
| `$19`     | olive green               | 12          | dark green |
| `$2A`     | medium green              | 2/3         | medium/light green |

Some mappings are forced choices (e.g. `$28` skin → light yellow is the best TMS approximation, but the result will look yellowish; there is no real "peach/skin tone").

## Battle sprite palettes (decoded from bank_0F.asm:10347)

The 4 sprite sub-palettes of the battle screen, hardcoded:

```
sub-pal 0: $0F $28 $18 $21   (black, skin, dark olive, light blue)
sub-pal 1: $0F $16 $30 $36   (black, red, white, pink)
sub-pal 2: $0F $30 $22 $12   (black, white, blue, dark blue)
sub-pal 3: $0F $30 $10 $00   (black, white, grey, grey)
```

Only 0 and 1 are used by the class battle sprites (sub-pal 2/3 = magic effects + cursor).

`lutClassBatSprPalette` (bank_0F.asm:10537), per class → index 0 or 1:
```
                         FT TH BB RM WM BM
unpromoted (idx 0..5)  : 01 00 00 01 01 00
promoted   (idx 6..11) : 01 01 00 01 01 00
```

→ FT/RM/WM/Knight/Master/Ninja = sub-pal 1 (white/red).
→ TH/BB/BM/Black-Mage-promoted = sub-pal 0 (skin/olive/blue).

## TMS9918 per-class colour scheme — slice25 (v1) → slice25b (v2 final)

### v1 (slice25, abandoned): per-class coloured bg

Initial attempt: a different bg-color per class as a "second axis of differentiation":
| FT/WM | TH | BB | RM | BM |
| white/dk_red | lt_yel/dk_green | lt_yel/dk_yel | white/med_red | lt_yel/dk_blue |

Visual problem: a coloured halo around the silhouettes (red/green/blue rect around the character) — very un-NES-like. The NES uses sub-pal color 0 = backdrop frame ($0F = black), so the "transparent" areas of the sprite show the battle background (which is black).

### v2 (slice25b, current): uniform bg=BLACK (NES parity)

Change requested by the user 2026-05-08: the whole battle screen goes black like the NES. Only the fg differentiates the classes.

| Class        | NES sub-pal | TMS fg          | TMS bg   |
|--------------|-------------|-----------------|----------|
| Fighter      | 1 (red/wh)  | 15 white        | 1 black  |
| Thief        | 0 (skin/bl) | 3 light green   | 1 black  |
| BlackBelt    | 0 (skin/bl) | 11 light yellow | 1 black  |
| RedMage      | 1 (red/wh)  | 9 light red     | 1 black  |
| WhiteMage    | 1 (red/wh)  | 15 white        | 1 black  |
| BlackMage    | 0 (skin/bl) | 5 light blue    | 1 black  |

FT and WM share fg=white (both NES sub-pal 1, white-dominant) — told apart only by the CHR SILHOUETTE (armor vs robe). Same as on the NES.

The screen border (`vdp_color`) and the global color table are BLACK too: the whole battle screen is black with coloured text and silhouettes — NES parity.

**TMS9918 OR-plane limit:** 1 colour per silhouette, 1 background colour. Internal distinctions within the character (e.g. Fighter's red plume over white armor) = lost. Recoverable in 2 ways:

1. **Per-row dominant color** (future slice25c): for each row of the tile, pick the dominant NES colour → up to 3 vertical colour zones per character. Slice not yet planned. Cost: re-extraction of the battle sprites, generating 8 color bytes per tile.

2. **OAM sprite layering** (advanced, future): 1 mono-color OAM sprite over the BG silhouette adds 1 accent color. TMS9918 limit = 4 sprites per scanline.
   - slice24/25 layout: party stacked vertically (rows 0-2, 3-5, 6-8, 9-11), monsters stacked vertically on the left → each scanline has at most **1 character + 1 monster** = 2 character slots.
   - Budget: 1-2 OAM accents per character is safe (2-4 sprites/scanline = at the limit but OK), 3+ is over.
   - Trade-off: 1 OAM accent per character/monster = 1 extra accent color (e.g. FT's plume). Combined with per-row dominant = 2-3 colours per character.

## Next steps (post-slice25)

1. **Mapman OW colors:** same approach for the 6 mapmen (16 tiles/class, 4 directions). The NES uses `lut_MapmanPalettes` (bank_0F.asm:5949), which assigns 2 bytes per class (fg+secondary). Decode and apply.
2. **OW backdrop colors:** NES OW palette is per-tile. TMS9918: per-row means colours per horizontal 8-pixel band — not per-tile. Strategy: for each NES "metatile color group", decide the dominant fg+bg.
3. **Battle backdrop colors:** the NES battle background = coloured horizontal stripes, perfectly compatible with TMS9918 per-row coloring. A native win.
4. **Magic effects palettes:** sub-pal 2 and 3 — TBD when we get to the magic effects.

## Philosophy

Default: stay visually close to the NES whenever possible (a yellowish skin tone is acceptable; dominant hues must be preserved). When the 2 NES sub-pals look too "alike" on the TMS9918 (FT/RM/WM all red+white), vary the bg-color per class — this is a Coleco add-on liberty documented in `Coleco_improvements.md` §1 (UX/visual aids).
