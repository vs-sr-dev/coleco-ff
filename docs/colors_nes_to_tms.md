# Colors mapping NES → TMS9918 (Coleco)

**Stato:** spec v1, session 6 (2026-05-08). Validato visualmente da slice25 sui 6 class battle sprite.

## Hardware reminder

**NES PPU palette:**
- 64 colori master indicizzati `$00-$3F` (formato `$HL`: H = brightness 0-3, L = hue 0-15).
- 8 sub-palette di 4 colori ciascuna = 32 byte totali in `cur_pal` ($03C0-$03DF):
  - `cur_pal+$00..$0F` = 4 sub-pal background
  - `cur_pal+$10..$1F` = 4 sub-pal sprite
- Color 0 di ogni sub-pal = transparent (sprite) o universal bg (BG layer).
- OAM byte attr bits 0-1 selezionano la sub-pal per ogni sprite.
- BG attribute table seleziona la sub-pal per gruppi di 2x2 metatile (16x16 px).

**TMS9918 mode 2 (Coleco target):**
- 16 colori FISSI (palette hardcoded, no possibilità di rimappare):
  ```
  0: transparent   1: black         2: medium green  3: light green
  4: dark blue     5: light blue    6: dark red      7: cyan
  8: medium red    9: light red    10: dark yellow  11: light yellow
  12: dark green  13: magenta      14: gray         15: white
  ```
- Per ogni tile BG: 8 pattern bytes + 8 color bytes (1 byte per row, formato `(fg << 4) | bg`).
- Per ogni sprite: 1 colore solo (no per-pixel palette su sprite).
- Schermo diviso in 3 bande verticali (rows 0-7, 8-15, 16-23) ciascuna con propri pattern + color table — replicare ogni asset 3 volte se deve apparire ovunque.

## Strategia attuale: OR-plane silhouette → 2-color tile

Per asset NES 4-color → TMS9918 2-color (validata pipeline session 1, vedi `asset_pipeline.md`):

1. **OR planes:** `tms_byte = nes_low_plane | nes_high_plane` per ogni riga. Collassa NES color 1/2/3 in 1 fg, NES color 0 resta bg.
2. **Color bytes per row:** scegli 1 fg + 1 bg per riga (8 byte color/tile).

Effetto: i 4 colori della sub-pal NES diventano 2. Si perde dettaglio interno (es. distinzione gi/cintura per BlackBelt) ma si preserva la silhouette + 1 accent color.

## Mapping tabella NES master color → TMS9918 (lookup)

Ridotta a casi che incontriamo realmente nei sprite (espandere se necessario):

| NES `$XY` | descrittivo               | TMS9918 idx | nome      |
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

Alcune mappe forzano scelte (es. `$28` skin → light yellow è la migliore approssimazione TMS, ma il rendering apparirà giallastro; non c'è un vero "pesca/skin tone").

## Battle sprite palettes (decoded da bank_0F.asm:10347)

Le 4 sub-palette sprite del battle screen, hardcoded:

```
sub-pal 0: $0F $28 $18 $21   (black, skin, dark olive, light blue)
sub-pal 1: $0F $16 $30 $36   (black, red, white, pink)
sub-pal 2: $0F $30 $22 $12   (black, white, blue, dark blue)
sub-pal 3: $0F $30 $10 $00   (black, white, grey, grey)
```

Solo 0 e 1 usate dai class battle sprite (sub-pal 2/3 = magic effects + cursor).

`lutClassBatSprPalette` (bank_0F.asm:10537), per classe → indice 0 o 1:
```
                         FT TH BB RM WM BM
unpromoted (idx 0..5)  : 01 00 00 01 01 00
promoted   (idx 6..11) : 01 01 00 01 01 00
```

→ FT/RM/WM/Knight/Master/Ninja = sub-pal 1 (white/red).
→ TH/BB/BM/Black-Mage-promoted = sub-pal 0 (skin/olive/blue).

## TMS9918 schema colori per classe — slice25 (v1) → slice25b (v2 final)

### v1 (slice25, abbandonato): bg colorato per classe

Tentativo iniziale: bg-color diverso per classe come "secondo asse di differenziazione":
| FT/WM | TH | BB | RM | BM |
| white/dk_red | lt_yel/dk_green | lt_yel/dk_yel | white/med_red | lt_yel/dk_blue |

Problema visuale: alone colorato attorno alle silhouette (rosso/verde/blu rect attorno al PG) — molto poco NES-like. NES usa color 0 sub-pal = backdrop frame ($0F = nero), quindi le aree "transparenti" del sprite mostrano lo sfondo battle (che è nero).

### v2 (slice25b, current): bg=BLACK uniforme (NES parity)

Cambiamento richiesto da utente 2026-05-08: tutto il battle screen va in nero come NES. Solo il fg differenzia classi.

| Classe       | NES sub-pal | TMS fg          | TMS bg   |
|--------------|-------------|-----------------|----------|
| Fighter      | 1 (red/wh)  | 15 white        | 1 black  |
| Thief        | 0 (skin/bl) | 3 light green   | 1 black  |
| BlackBelt    | 0 (skin/bl) | 11 light yellow | 1 black  |
| RedMage      | 1 (red/wh)  | 9 light red     | 1 black  |
| WhiteMage    | 1 (red/wh)  | 15 white        | 1 black  |
| BlackMage    | 0 (skin/bl) | 5 light blue    | 1 black  |

FT e WM condividono fg=white (entrambe NES sub-pal 1 white-dominant) — distinte solo dalla SILHOUETTE CHR (armor vs robe). Stessa cosa NES.

Anche il border schermo (`vdp_color`) e il color table globale sono BLACK: l'intero battle screen è nero con scritte e silhouette colorate — parity NES.

**Limite TMS9918 OR-plane:** 1 colore per silhouette, 1 colore di sfondo. Distinzione interna del personaggio (es. piuma rossa di Fighter sopra armatura bianca) = persa. Recoverable in 2 modi:

1. **Per-row dominant color** (futuro slice25c): per ogni riga del tile, scegli il colore NES dominante → fino a 3 zone-colore verticali per personaggio. Slice non ancora pianificato. Costo: re-extraction battle sprite con generation di 8 color byte per tile.

2. **OAM sprite layering** (futuro avanzato): 1 OAM sprite mono-color sopra il BG silhouette aggiunge 1 accent color. Limite TMS9918 = 4 sprite per scanline.
   - Layout slice24/25: party stackato verticalmente (rows 0-2, 3-5, 6-8, 9-11), monster stackati verticalmente sx → su ogni scanline al massimo **1 PG + 1 monster** = 2 character-slot.
   - Budget: 1-2 OAM accent per character è safe (2-4 sprite/scanline = al limit ma OK), 3+ è over.
   - Trade-off: 1 OAM accent per PG/monster = 1 accent color extra (es. piuma FT). Combinato con per-row dominant = 2-3 colori per character.

## Prossimi passi (post-slice25)

1. **Mapman OW colors:** stesso approccio per i 6 mapman (16 tile/classe, 4 direzioni). NES usa `lut_MapmanPalettes` (bank_0F.asm:5949) che assegna 2 byte per classe (fg+secondary). Decodare e applicare.
2. **OW backdrop colors:** NES OW palette per-tile. TMS9918: per-row significa colori per fascia orizzontale di 8 pixel — non per-tile. Strategia: per ogni "metatile color group" NES decidere fg+bg dominanti.
3. **Battle backdrop colors:** background NES battle = stripes orizzontali colorate, perfettamente compatibili con TMS9918 per-row coloring. Win nativo.
4. **Magic effects palettes:** sub-pal 2 e 3 — TBD quando arriveremo agli effetti magia.

## Filosofia

Default: rimanere visualmente vicini al NES quando possibile (skin tone giallastro è accettabile, hue dominanti vanno preservati). Quando le 2 sub-pal NES sono troppo "uguali" su TMS9918 (FT/RM/WM tutte red+white), variare il bg-color per classe — è una libertà Coleco add-on documentata in `Coleco_improvements.md` §1 (UX/visual aids).
