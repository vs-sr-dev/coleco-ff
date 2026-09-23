# extract_monster_gfx.ps1
#
# Grafica dei nemici PICCOLI di FF1, tutte le 16 pagine CHR, in forma
# utilizzabile dal TMS9918 -- con il colore DENTRO la sagoma.
#
# PERCHE' NON BASTAVA extract_monsters.ps1
#   Quello faceva l'OR dei due piani NES e buttava via l'informazione a 2 bit:
#   il risultato e' una sagoma che sa DOVE c'e' un pixel ma non QUALE dei tre
#   colori della palette fosse. Da li' si puo' solo dipingere a tinta piatta,
#   ed e' esattamente il divario che si vedeva a schermo fra i mostri
#   (monocromi) e i personaggi (a piu' colori dalla slice30).
#
#   Qui la sagoma resta la stessa, ma accanto si tiene, PER OGNI RIGA DI OGNI
#   TILE, quale voce di palette (1, 2 o 3) domina fra i pixel accesi. E' la
#   "dominante per riga" di slice30 applicata ai nemici.
#
# PERCHE' LA VOCE DI PALETTE E NON IL COLORE FINALE
#   In FF1 la stessa grafica si ricolora per fare le varianti: IMP e GrIMP
#   sono lo stesso disegno con due palette diverse. Se qui si salvasse il
#   colore TMS gia' risolto, quell'asse si perderebbe e servirebbe una copia
#   dei dati per variante. Salvando l'INDICE (1-3) il colore si risolve a
#   runtime con la palette che la formazione assegna a quel gruppo:
#
#       fg = ff1_pal_tms[palette_id * 4 + rowval]
#
#   Cosi' lo swap di palette continua a funzionare come sul NES E ogni sagoma
#   ha i suoi colori interni.
#
# LAYOUT DELLA SORGENTE (verificato su bank_0F.asm LoadBattleBGCHRAndPalettes
# e bank_0B.asm DrawSmallEnemy)
#   BANK_BATTLECHR = $07 -> bank_07.dat contiene le pagine 0-7
#                           bank_08.dat contiene le pagine 8-15
#   Ogni pagina = $800 byte:  $000-$11F backdrop, poi la CHR dei nemici.
#   Nemico piccolo gfx0 = tile $12 -> offset pagina + $120  (16 tile, 4x4)
#   Nemico piccolo gfx1 = tile $22 -> offset pagina + $220
#   Ordine tile: row-major, 4 per riga, 4 righe (DrawSmallEnemy).
#
# I nemici GRANDI (6x6 = 36 tile, offset $320 e $560) NON sono qui: servono
# un'altra disposizione a schermo e un altro budget di tile. Vedi il TODO in
# docs/enemies_next_session.md.
#
# USCITA: src/ff1_monster_gfx.h, protetto da FF1_MONGFX_DEFINE_DATA cosi' che
# solo il .c del banco ne istanzi i dati (schema dei banchi dati, vedi
# memoria [[multi-bank-architecture]]).

param(
    [string]$Disasm = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [string]$OutHdr = "$PSScriptRoot\..\src\ff1_monster_gfx.h"
)

$ErrorActionPreference = 'Stop'

$N_PAGES  = 16
$N_GFX    = 2      # due nemici piccoli per pagina
$N_TILES  = 16     # 4x4
$TMS_BLACK = 1

$NAME_LEN = 9      # 8 caratteri (DrawBattleSubString_Max8) + terminatore

$chrLow  = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_07.dat'))
$chrHigh = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_08.dat'))
$palRaw  = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bin\0C_8F20_battlepalettes.bin'))
$nameRaw = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bin\0B_94E0_enemynames.bin'))

if ($chrLow.Length  -ne 16384) { throw "bank_07.dat: attesi 16384 byte, trovati $($chrLow.Length)" }
if ($chrHigh.Length -ne 16384) { throw "bank_08.dat: attesi 16384 byte, trovati $($chrHigh.Length)" }
if ($palRaw.Length  -lt 256)   { throw "palette di battaglia: attesi >=256 byte, trovati $($palRaw.Length)" }

# ---------------------------------------------------------------------------
#  NES master color -> inchiostro TMS9918
#  Copia fedele di Map-NESToTMS in extract_battle_sprites.ps1: i mostri e i
#  personaggi DEVONO usare la stessa mappa, altrimenti lo stesso colore NES
#  esce diverso nelle due meta' dello schermo.
# ---------------------------------------------------------------------------
function Map-NESToTMS([byte]$nes) {
    $h = $nes -shr 4
    $l = $nes -band 0x0F
    if ($l -eq 0x0F -or $l -eq 0x0E -or $l -eq 0x0D) { return 1 }
    if ($l -eq 0) {
        switch ($h) {
            0 { return 14 }
            1 { return 14 }
            2 { return 14 }
            3 { return 15 }
            default { return 14 }
        }
    }
    $isDark = ($h -le 1)
    switch ($l) {
        1  { if ($isDark) { return 4  } else { return 5  } }
        2  { if ($isDark) { return 4  } else { return 5  } }
        3  { return 13 }
        4  { return 13 }
        5  { if ($isDark) { return 6  } else { return 9  } }
        6  { if ($isDark) { return 6  } else { return 9  } }
        7  { if ($isDark) { return 8  } else { return 9  } }
        8  { if ($isDark) { return 10 } else { return 11 } }
        9  { if ($isDark) { return 10 } else { return 11 } }
        10 { if ($isDark) { return 12 } else { return 3  } }
        11 { if ($isDark) { return 12 } else { return 3  } }
        12 { return 7 }
        default { return 1 }
    }
}

# ---------------------------------------------------------------------------
#  RGB veri, per sciogliere le collisioni di palette
# ---------------------------------------------------------------------------
# Map-NESToTMS e' una mappa a zone: piu' colori NES vicini cadono sullo stesso
# inchiostro TMS. Per i personaggi non era un problema (le loro due sotto-
# palette non collidono), per i nemici si': 13 palette su 64 mandano DUE delle
# tre voci sullo stesso inchiostro, e fra queste c'e' la palette 0, cioe'
# proprio quella dell'IMP del primo incontro. Il risultato sarebbe una sagoma
# a due colori invece che a tre -- meta' del guadagno buttato via.
#
# Qui la mappa a zone resta la sorgente primaria (cosi' i colori restano
# coerenti con quelli dei personaggi, gia' validati), e interviene una seconda
# passata SOLO quando due voci collidono: si tiene sull'inchiostro conteso la
# voce cromaticamente piu' vicina, e l'altra scivola sull'inchiostro TMS libero
# piu' vicino in RGB. Nessuna palette senza collisione viene toccata.
$NES_RGB = @(
    @(124,124,124),@(0,0,252),@(0,0,188),@(68,40,188),@(148,0,132),@(168,0,32),@(168,16,0),@(136,20,0),
    @(80,48,0),@(0,120,0),@(0,104,0),@(0,88,0),@(0,64,88),@(0,0,0),@(0,0,0),@(0,0,0),
    @(188,188,188),@(0,120,248),@(0,88,248),@(104,68,252),@(216,0,204),@(228,0,88),@(248,56,0),@(228,92,16),
    @(172,124,0),@(0,184,0),@(0,168,0),@(0,168,68),@(0,136,136),@(0,0,0),@(0,0,0),@(0,0,0),
    @(248,248,248),@(60,188,252),@(104,136,252),@(152,120,248),@(248,120,248),@(248,88,152),@(248,120,88),@(252,160,68),
    @(248,184,0),@(184,248,24),@(88,216,84),@(88,248,152),@(0,232,216),@(120,120,120),@(0,0,0),@(0,0,0),
    @(252,252,252),@(164,228,252),@(184,184,248),@(216,184,248),@(248,184,248),@(248,164,192),@(240,208,176),@(252,224,168),
    @(248,216,120),@(216,248,120),@(184,248,184),@(184,248,216),@(0,252,252),@(216,216,216),@(0,0,0),@(0,0,0)
)
# TMS9918: indice 0 = trasparente, non e' un colore e non entra nei confronti.
$TMS_RGB = @(
    @(0,0,0),        # 0 trasparente (segnaposto)
    @(0,0,0),        # 1 nero
    @(33,200,66),    # 2 verde medio
    @(94,220,120),   # 3 verde chiaro
    @(84,85,237),    # 4 blu scuro
    @(125,118,252),  # 5 blu chiaro
    @(212,82,77),    # 6 rosso scuro
    @(66,235,245),   # 7 ciano
    @(252,85,84),    # 8 rosso medio
    @(255,121,120),  # 9 rosso chiaro
    @(212,193,84),   # 10 giallo scuro
    @(230,206,128),  # 11 giallo chiaro
    @(33,176,59),    # 12 verde scuro
    @(201,91,186),   # 13 magenta
    @(204,204,204),  # 14 grigio
    @(255,255,255)   # 15 bianco
)
# Distanza "redmean": approssimazione percettiva a basso costo, non euclidea.
#
# NON e' un vezzo. Con la distanza euclidea l'incarnato dell'IMP (NES $36,
# 240/208/176) finiva sul GRIGIO invece che sul giallo chiaro, perche' il
# grigio non ha croma e quindi risulta artificialmente vicino a tutto. E' lo
# stesso errore che extract_battle_sprites.ps1 aveva gia' dovuto correggere a
# mano, con un caso speciale che forzava $36 -> giallo chiaro per la pelle dei
# personaggi. Redmean ci arriva da solo, senza casi speciali.
function Get-RgbDist($a, $b) {
    $dr = $a[0] - $b[0]; $dg = $a[1] - $b[1]; $db = $a[2] - $b[2]
    $rmean = ($a[0] + $b[0]) / 2.0
    return (2.0 + $rmean / 256.0) * $dr * $dr +
           4.0 * $dg * $dg +
           (2.0 + (255.0 - $rmean) / 256.0) * $db * $db
}
# Inchiostro libero piu' vicino. Il nero (1) e' escluso: lo sfondo dell'arena
# e' nero, quindi una voce mappata li' non schiarirebbe la sagoma -- la
# farebbe sparire a pezzi.
function Get-NearestFreeInk([byte]$nes, $taken) {
    $target = $NES_RGB[$nes -band 0x3F]
    $best = -1; $bestD = [double]::MaxValue
    for ($i = 2; $i -le 15; $i++) {
        if ($taken -contains $i) { continue }
        $d = Get-RgbDist $target $TMS_RGB[$i]
        if ($d -lt $bestD) { $bestD = $d; $best = $i }
    }
    if ($best -lt 0) { return 15 }
    return $best
}

# Decodifica una tile NES (16 byte planari 2bpp) in 8x8 valori 0-3.
function Decode-NesTilePixels([byte[]]$src, [int]$off) {
    $px = New-Object 'int[,]' 8, 8
    for ($r = 0; $r -lt 8; $r++) {
        $lo = $src[$off + $r]
        $hi = $src[$off + 8 + $r]
        for ($c = 0; $c -lt 8; $c++) {
            $bit = 7 - $c
            $bL = ($lo -shr $bit) -band 1
            $bH = ($hi -shr $bit) -band 1
            $px[$r, $c] = ($bH -shl 1) -bor $bL
        }
    }
    return ,$px
}

# Sagoma: OR dei due piani, un byte per riga.
function Get-Silhouette([byte[]]$src, [int]$off) {
    $out = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $out[$r] = ($src[$off + $r] -bor $src[$off + 8 + $r]) -band 0xFF
    }
    return $out
}

# Dominante per riga: per ogni riga, la voce di palette (1-3) piu' frequente
# fra i pixel accesi. Le righe vuote NON restano a 0: prendono la dominante
# dell'intera tile, cosi' a runtime non serve nessun caso speciale e una riga
# vuota non introduce uno stacco di colore se la sagoma riprende sotto.
# Tile completamente vuota -> 1, valore innocuo (non si vede nulla comunque).
function Get-RowValues([byte[]]$src, [int]$off) {
    $px = Decode-NesTilePixels $src $off

    $tileCounts = @(0, 0, 0)
    for ($r = 0; $r -lt 8; $r++) {
        for ($c = 0; $c -lt 8; $c++) {
            $v = $px[$r, $c]
            if ($v -gt 0) { $tileCounts[$v - 1]++ }
        }
    }
    $tileMax = 0
    if ($tileCounts[1] -gt $tileCounts[$tileMax]) { $tileMax = 1 }
    if ($tileCounts[2] -gt $tileCounts[$tileMax]) { $tileMax = 2 }
    $fallback = if ($tileCounts[$tileMax] -gt 0) { $tileMax + 1 } else { 1 }

    $out = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $rowCounts = @(0, 0, 0)
        for ($c = 0; $c -lt 8; $c++) {
            $v = $px[$r, $c]
            if ($v -gt 0) { $rowCounts[$v - 1]++ }
        }
        $rowMax = 0
        if ($rowCounts[1] -gt $rowCounts[$rowMax]) { $rowMax = 1 }
        if ($rowCounts[2] -gt $rowCounts[$rowMax]) { $rowMax = 2 }
        if ($rowCounts[$rowMax] -gt 0) { $out[$r] = [byte]($rowMax + 1) }
        else                           { $out[$r] = [byte]$fallback }
    }
    return $out
}

# ---------------------------------------------------------------------------
#  Estrazione
# ---------------------------------------------------------------------------
$slotCount = $N_PAGES * $N_GFX                      # 32 grafiche piccole
$pattern = New-Object byte[] ($slotCount * $N_TILES * 8)
$rowval  = New-Object byte[] ($slotCount * $N_TILES * 8)

$nonEmpty = 0
for ($page = 0; $page -lt $N_PAGES; $page++) {
    if ($page -lt 8) { $srcBytes = $chrLow;  $pageBase = $page * 0x800 }
    else             { $srcBytes = $chrHigh; $pageBase = ($page - 8) * 0x800 }

    for ($g = 0; $g -lt $N_GFX; $g++) {
        $gfxBase = $pageBase + 0x120 + ($g * 0x100)     # gfx0 -> $120, gfx1 -> $220
        $slot    = ($page * $N_GFX) + $g
        $any     = $false
        for ($t = 0; $t -lt $N_TILES; $t++) {
            $tileOff = $gfxBase + ($t * 16)
            $sil = Get-Silhouette $srcBytes $tileOff
            $rvs = Get-RowValues  $srcBytes $tileOff
            $dst = (($slot * $N_TILES) + $t) * 8
            for ($r = 0; $r -lt 8; $r++) {
                $pattern[$dst + $r] = $sil[$r]
                $rowval[$dst + $r]  = $rvs[$r]
                if ($sil[$r] -ne 0) { $any = $true }
            }
        }
        if ($any) { $nonEmpty++ }
    }
}

# ---------------------------------------------------------------------------
#  Palette: 64 x 4 inchiostri TMS.
#  La voce 0 di ogni palette NES e' il colore di sfondo (trasparente in
#  battaglia): qui diventa nero, cosi' l'indice 0 non e' mai un caso speciale.
# ---------------------------------------------------------------------------
$palTms = New-Object byte[] (64 * 4)
$fixed  = 0
for ($p = 0; $p -lt 64; $p++) {
    $palTms[$p * 4] = [byte]$TMS_BLACK

    $ink = New-Object int[] 4
    for ($e = 1; $e -lt 4; $e++) { $ink[$e] = Map-NESToTMS $palRaw[$p * 4 + $e] }

    # Passata di collisione: per ogni inchiostro conteso da piu' voci, resta
    # quella cromaticamente piu' vicina; le altre scivolano su un inchiostro
    # libero. Si procede per inchiostro, non per voce, cosi' l'esito non
    # dipende dall'ordine in cui si scorrono le voci.
    for ($e = 1; $e -lt 4; $e++) {
        $sharers = @()
        for ($f = 1; $f -lt 4; $f++) { if ($ink[$f] -eq $ink[$e]) { $sharers += $f } }
        if ($sharers.Count -lt 2) { continue }

        $contested = $ink[$e]
        $keep = $sharers[0]; $keepD = [double]::MaxValue
        foreach ($f in $sharers) {
            $d = Get-RgbDist $NES_RGB[$palRaw[$p * 4 + $f] -band 0x3F] $TMS_RGB[$contested]
            if ($d -lt $keepD) { $keepD = $d; $keep = $f }
        }
        foreach ($f in $sharers) {
            if ($f -eq $keep) { continue }
            $taken = @()
            for ($g = 1; $g -lt 4; $g++) { if ($g -ne $f) { $taken += $ink[$g] } }
            $ink[$f] = Get-NearestFreeInk $palRaw[$p * 4 + $f] $taken
            $fixed++
        }
    }

    for ($e = 1; $e -lt 4; $e++) { $palTms[$p * 4 + $e] = [byte]$ink[$e] }
}

# ---------------------------------------------------------------------------
#  Nomi dei nemici: charset custom $8A-$BD -> ASCII del font BIOS
# ---------------------------------------------------------------------------
# FF1 non usa ASCII: le maiuscole partono da $8A e le minuscole da $A4, e la
# tabella dei puntatori sta in testa al file, a $94E0. La conversione era gia'
# stata risolta in extract_monsters.ps1 (in slice31 la lista bersagli mostrava
# IMP / GrIMP / WOLF / GrWOLF); qui viene ripresa tale e quale.
#
# L'array esce PIATTO (128 * 9 byte) e non a due dimensioni. Non e' uno stile:
# sccz80 mette gli array `static const` multidimensionali in sezione DATA, e la
# DATA di un banco non viene MAI copiata in RAM perche' li' non gira nessun
# crt0_init. Un `[128][9]` in un banco si leggerebbe come spazzatura -- vedi
# [[coleco-data-section-overflow]] e il bug #3 di [[slice44-real-root-causes]].
# Oltre alle lettere il charset ha punteggiatura, e serve davvero: sette nomi
# la usano, fra cui R.SAHAG, che senza diventava "R SAHAG".
# La corrispondenza viene dalla tastiera di inserimento nome in bank_0E.asm:3359
#   .BYTE $9E,$FF,$9F,...,$A3,$FF,$BE,$FF,$BF,$FF,$C0,$FF,$FF  ; U - Z ; , . <spazio>
# cioe' $BE=';' $BF=',' $C0='.' e $FF=spazio (usato dentro otto nomi).
function Decode-EnemyName([byte[]]$src, [int]$off) {
    $s = ''
    for ($j = 0; $j -lt 8; $j++) {
        $b = $src[$off + $j]
        if ($b -eq 0) { break }
        if     ($b -ge 0x8A -and $b -le 0xA3) { $s += [char]([byte][char]'A' + $b - 0x8A) }
        elseif ($b -ge 0xA4 -and $b -le 0xBD) { $s += [char]([byte][char]'a' + $b - 0xA4) }
        elseif ($b -eq 0xBE) { $s += ';' }
        elseif ($b -eq 0xBF) { $s += ',' }
        elseif ($b -eq 0xC0) { $s += '.' }
        elseif ($b -eq 0xFF) { $s += ' ' }
        else { $s += ' ' }
    }
    return $s
}

$names = New-Object byte[] (128 * $NAME_LEN)
$namesShown = @()
for ($i = 0; $i -lt 128; $i++) {
    $addr = ([int]$nameRaw[$i * 2 + 1] * 256) + [int]$nameRaw[$i * 2]
    $off  = $addr - 0x94E0
    if ($off -ge 0 -and $off -lt $nameRaw.Length) { $nm = Decode-EnemyName $nameRaw $off }
    else { $nm = '' }
    # Riempito di spazi fino a 8: cosi' scrivere un nome corto sopra uno lungo
    # nella lista bersagli cancella i caratteri che avanzano, senza pulire prima.
    while ($nm.Length -lt 8) { $nm += ' ' }
    for ($j = 0; $j -lt 8; $j++) { $names[$i * $NAME_LEN + $j] = [byte][char]$nm[$j] }
    $names[$i * $NAME_LEN + 8] = 0
    if ($i -lt 6) { $namesShown += $nm.Trim() }
}

# ---------------------------------------------------------------------------
#  Emissione
# ---------------------------------------------------------------------------
function Emit-ByteArray($sb, [string]$decl, [byte[]]$data) {
    [void]$sb.AppendLine("$decl = {")
    for ($i = 0; $i -lt $data.Length; $i += 16) {
        $n = [Math]::Min(16, $data.Length - $i)
        $parts = @()
        for ($j = 0; $j -lt $n; $j++) { $parts += '0x' + $data[$i + $j].ToString('X2') }
        $line = '    ' + ($parts -join ',')
        if (($i + $n) -lt $data.Length) { $line += ',' }
        [void]$sb.AppendLine($line)
    }
    [void]$sb.AppendLine('};')
}

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('// AUTO-GENERATO da tools/extract_monster_gfx.ps1 -- non modificare a mano.')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('// Grafica dei nemici PICCOLI di FF1: 16 pagine CHR x 2 grafiche x 16 tile.')
[void]$sb.AppendLine('// Indice dello slot = pagina * 2 + gfx, dove gfx e'' 0 oppure 1 (le due')
[void]$sb.AppendLine('// grafiche piccole della pagina). Lo slot grafico che la formazione')
[void]$sb.AppendLine('// assegna a un gruppo vale 0-3: i valori PARI sono piccoli (0 -> gfx0,')
[void]$sb.AppendLine('// 2 -> gfx1), i DISPARI sono nemici grandi e qui non ci sono.')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('//   ff1_mon_pattern  sagoma, 8 byte per tile (OR dei piani NES)')
[void]$sb.AppendLine('//   ff1_mon_rowval   voce di palette dominante (1-3) per ogni riga')
[void]$sb.AppendLine('//   ff1_pal_tms      64 palette x 4 inchiostri TMS9918 (voce 0 = nero)')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('// Il colore di una riga si ottiene combinando le due:')
[void]$sb.AppendLine('//   fg = ff1_pal_tms[pal_id * 4 + ff1_mon_rowval[...]];')
[void]$sb.AppendLine('// e questo e'' cio'' che tiene in piedi lo swap di palette del NES')
[void]$sb.AppendLine('// (IMP/GrIMP = stessa sagoma, due palette) senza duplicare i dati.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('#ifndef FF1_MONSTER_GFX_H')
[void]$sb.AppendLine('#define FF1_MONSTER_GFX_H')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("#define FF1_MON_PAGES        $N_PAGES")
[void]$sb.AppendLine("#define FF1_MON_GFX_PER_PAGE $N_GFX")
[void]$sb.AppendLine("#define FF1_MON_SLOTS        $slotCount")
[void]$sb.AppendLine("#define FF1_MON_TILES        $N_TILES")
[void]$sb.AppendLine('#define FF1_MON_SLOT_BYTES   (FF1_MON_TILES * 8)')
[void]$sb.AppendLine("#define FF1_MON_NAME_LEN     $NAME_LEN")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('#ifdef FF1_MONGFX_DEFINE_DATA')
[void]$sb.AppendLine('')
Emit-ByteArray $sb 'const unsigned char ff1_mon_pattern[FF1_MON_SLOTS * FF1_MON_SLOT_BYTES]' $pattern
[void]$sb.AppendLine('')
Emit-ByteArray $sb 'const unsigned char ff1_mon_rowval[FF1_MON_SLOTS * FF1_MON_SLOT_BYTES]' $rowval
[void]$sb.AppendLine('')
Emit-ByteArray $sb 'const unsigned char ff1_pal_tms[64 * 4]' $palTms
[void]$sb.AppendLine('')
Emit-ByteArray $sb 'const unsigned char ff1_mon_names[128 * FF1_MON_NAME_LEN]' $names
[void]$sb.AppendLine('')
[void]$sb.AppendLine('#endif  /* FF1_MONGFX_DEFINE_DATA */')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('#endif  /* FF1_MONSTER_GFX_H */')

[System.IO.File]::WriteAllText($OutHdr, $sb.ToString())

Write-Host ("Scritto {0}" -f $OutHdr)
Write-Host ("  ff1_mon_pattern  = {0} byte ({1} slot x {2} tile x 8)" -f $pattern.Length, $slotCount, $N_TILES)
Write-Host ("  ff1_mon_rowval   = {0} byte" -f $rowval.Length)
Write-Host ("  ff1_pal_tms      = {0} byte" -f $palTms.Length)
Write-Host ("  TOTALE           = {0} byte" -f ($pattern.Length + $rowval.Length + $palTms.Length))
Write-Host ("  slot con pixel   = {0} su {1}" -f $nonEmpty, $slotCount)
Write-Host ("  ff1_mon_names    = {0} byte" -f $names.Length)
Write-Host ("  voci di palette spostate per collisione = {0}" -f $fixed)
Write-Host ("  primi nomi       : {0}" -f ($namesShown -join ', '))
