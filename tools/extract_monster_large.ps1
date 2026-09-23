# extract_monster_large.ps1
#
# Grafica dei nemici GRANDI di FF1 (6x6 tile, 48x48 px), tutte e 16 le pagine
# CHR, nella stessa forma dei piccoli: sagoma + dominante per riga.
#
# E' il gemello di extract_monster_gfx.ps1 e ne condivide ogni scelta di
# metodo -- OR dei piani per la sagoma, voce di palette DOMINANTE per riga
# invece del colore gia' risolto, cosi' lo swap di palette del NES continua a
# funzionare a runtime (memoria [[slice55-enemies-color]]). Qui cambiano solo
# tre cose: l'offset nella pagina, il numero di tile e l'ordine di lettura.
#
# LAYOUT DELLA SORGENTE (bank_0B.asm DrawLargeEnemy)
#   Pagina da $800:  grande gfx0 a $320, grande gfx1 a $560.
#   36 tile l'uno ($240 byte), row-major, 6 per riga, 6 righe -- i due blocchi
#   sono contigui e stanno dentro la pagina ($560 + $240 = $7A0).
#
# PERCHE' DUE BANCHI E NON UNO
#   32 slot x 36 tile x 8 byte = 9216 byte di sagome, altrettanti di dominanti:
#   18432 in tutto, contro i 16384 di un banco. La divisione NON e'
#   pattern-di-qua / colore-di-la': sarebbe il taglio sbagliato, perche'
#   caricare una tile vuole entrambi e costringerebbe a due cambi di banco per
#   ogni tile. Si taglia invece per PAGINA CHR -- pagine 0-7 nel banco basso,
#   8-15 nell'alto -- perche' una formazione vive tutta dentro una pagina sola:
#   qualunque battaglia tocca un banco solo, e lo mappa una volta.
#
# USCITA: src/ff1_monlg_lo.h e src/ff1_monlg_hi.h, ciascuno protetto dalla
# propria macro, cosi' solo il .c del rispettivo banco ne istanzia i dati.

param(
    [string]$Disasm = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [string]$OutDir = "$PSScriptRoot\..\src"
)

$ErrorActionPreference = 'Stop'

$N_PAGES      = 16
$N_GFX        = 2       # due nemici grandi per pagina
$N_TILES      = 36      # 6x6
$PAGES_PER_HALF = 8
$LARGE_OFF    = @(0x320, 0x560)

$chrLow  = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_07.dat'))
$chrHigh = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_08.dat'))

if ($chrLow.Length  -ne 16384) { throw "bank_07.dat: attesi 16384 byte, trovati $($chrLow.Length)" }
if ($chrHigh.Length -ne 16384) { throw "bank_08.dat: attesi 16384 byte, trovati $($chrHigh.Length)" }

# --- identiche a extract_monster_gfx.ps1: le due estrazioni DEVONO produrre
#     la stessa convenzione, altrimenti un grande e un piccolo della stessa
#     palette uscirebbero di due colori diversi nella stessa arena. ---------
function Decode-NesTilePixels([byte[]]$src, [int]$off) {
    $px = New-Object 'int[,]' 8, 8
    for ($r = 0; $r -lt 8; $r++) {
        $lo = $src[$off + $r]
        $hi = $src[$off + 8 + $r]
        for ($c = 0; $c -lt 8; $c++) {
            $bit = 7 - $c
            $px[$r, $c] = (((($hi -shr $bit) -band 1) -shl 1) -bor (($lo -shr $bit) -band 1))
        }
    }
    return ,$px
}

function Get-Silhouette([byte[]]$src, [int]$off) {
    $out = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $out[$r] = ($src[$off + $r] -bor $src[$off + 8 + $r]) -band 0xFF
    }
    return $out
}

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
#  Estrazione, una meta' per volta
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

$slotsPerHalf = $PAGES_PER_HALF * $N_GFX     # 16
$slotBytes    = $N_TILES * 8                 # 288

$report = @()
foreach ($half in @(
    @{ Tag = 'lo'; FirstPage = 0; Guard = 'FF1_MONLG_LO_H'; Macro = 'FF1_MONLG_LO_DEFINE_DATA' },
    @{ Tag = 'hi'; FirstPage = 8; Guard = 'FF1_MONLG_HI_H'; Macro = 'FF1_MONLG_HI_DEFINE_DATA' }
)) {
    $pattern = New-Object byte[] ($slotsPerHalf * $slotBytes)
    $rowval  = New-Object byte[] ($slotsPerHalf * $slotBytes)
    $nonEmpty = 0
    $blankTiles = 0

    for ($p = 0; $p -lt $PAGES_PER_HALF; $p++) {
        $page = $half.FirstPage + $p
        if ($page -lt 8) { $srcBytes = $chrLow;  $pageBase = $page * 0x800 }
        else             { $srcBytes = $chrHigh; $pageBase = ($page - 8) * 0x800 }

        for ($g = 0; $g -lt $N_GFX; $g++) {
            $gfxBase = $pageBase + $LARGE_OFF[$g]
            $slot    = ($p * $N_GFX) + $g          # indice DENTRO la meta'
            $any     = $false
            for ($t = 0; $t -lt $N_TILES; $t++) {
                $tileOff = $gfxBase + ($t * 16)
                $sil = Get-Silhouette $srcBytes $tileOff
                $rvs = Get-RowValues  $srcBytes $tileOff
                $dst = (($slot * $N_TILES) + $t) * 8
                $tileAny = $false
                for ($r = 0; $r -lt 8; $r++) {
                    $pattern[$dst + $r] = $sil[$r]
                    $rowval[$dst + $r]  = $rvs[$r]
                    if ($sil[$r] -ne 0) { $any = $true; $tileAny = $true }
                }
                if (-not $tileAny) { $blankTiles++ }
            }
            if ($any) { $nonEmpty++ }
        }
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('// AUTO-GENERATO da tools/extract_monster_large.ps1 -- non modificare a mano.')
    [void]$sb.AppendLine('//')
    [void]$sb.AppendLine("// Nemici GRANDI di FF1, pagine CHR $($half.FirstPage)-$($half.FirstPage + 7).")
    [void]$sb.AppendLine('// 8 pagine x 2 grafiche x 36 tile (6x6). Indice dello slot DENTRO la meta'':')
    [void]$sb.AppendLine('//   slot = (pagina - prima_pagina_della_meta) * 2 + gfx')
    [void]$sb.AppendLine('// dove gfx vale 0 o 1 ed e'' lo slot grafico della formazione diviso 2.')
    [void]$sb.AppendLine('//')
    [void]$sb.AppendLine('// Ordine delle tile: row-major, 6 per riga, come DrawLargeEnemy.')
    [void]$sb.AppendLine('// Il colore si risolve a runtime esattamente come per i piccoli:')
    [void]$sb.AppendLine('//   fg = ff1_pal_tms[pal_id * 4 + rowval[...]]')
    [void]$sb.AppendLine('// e ff1_pal_tms sta nel banco 12 accanto ai piccoli, non qui: le palette')
    [void]$sb.AppendLine('// sono le stesse e duplicarle vorrebbe dire poterle disallineare.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("#ifndef $($half.Guard)")
    [void]$sb.AppendLine("#define $($half.Guard)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("#define FF1_MONLG_TILES       $N_TILES")
    [void]$sb.AppendLine('#define FF1_MONLG_SLOT_BYTES  (FF1_MONLG_TILES * 8)')
    [void]$sb.AppendLine("#define FF1_MONLG_SLOTS_HALF  $slotsPerHalf")
    [void]$sb.AppendLine("#define FF1_MONLG_PAGES_HALF  $PAGES_PER_HALF")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("#ifdef $($half.Macro)")
    [void]$sb.AppendLine('')
    Emit-ByteArray $sb "const unsigned char ff1_monlg_$($half.Tag)_pattern[FF1_MONLG_SLOTS_HALF * FF1_MONLG_SLOT_BYTES]" $pattern
    [void]$sb.AppendLine('')
    Emit-ByteArray $sb "const unsigned char ff1_monlg_$($half.Tag)_rowval[FF1_MONLG_SLOTS_HALF * FF1_MONLG_SLOT_BYTES]" $rowval
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("#endif  /* $($half.Macro) */")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("#endif  /* $($half.Guard) */")

    $out = Join-Path $OutDir "ff1_monlg_$($half.Tag).h"
    [System.IO.File]::WriteAllText($out, $sb.ToString())

    $report += [pscustomobject]@{
        File = $out; Bytes = $pattern.Length * 2
        NonEmpty = $nonEmpty; Blank = $blankTiles
    }
}

foreach ($r in $report) {
    Write-Host ("Scritto {0}" -f $r.File)
    Write-Host ("  {0} byte in banco ({1} slot x {2} tile x 8, sagome + dominanti)" -f `
        $r.Bytes, $slotsPerHalf, $N_TILES)
    Write-Host ("  slot con pixel: {0} su {1}   tile completamente vuote: {2} su {3}" -f `
        $r.NonEmpty, $slotsPerHalf, $r.Blank, ($slotsPerHalf * $N_TILES))
}
