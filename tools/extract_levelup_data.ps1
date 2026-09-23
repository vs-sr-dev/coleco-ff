# extract_levelup_data.ps1 -- curva EXP e dati di passaggio di livello di FF1.
#
# FONTI (disassembly Disch, bank_0B.asm):
#   lut_ExpToAdvance    riga ~63: 49 valori .FARADDR (3 byte l'uno), EXP TOTALI
#                       richiesti per passare al livello successivo. L'indice e'
#                       il livello 0-based: entry 0 = 40 = da L1 a L2.
#   data_LevelUpData    bin/0B_9094_levelupdata.bin, 588 byte
#                       = 6 classi x 49 livelli x 2 byte.
#                       byte 0: bit5 livello "forte" (+rand[20,25] HP)
#                               bit4 forza, bit3 agilita', bit2 intelligenza,
#                               bit1 vitalita', bit0 fortuna garantite
#                       byte 1: una carica di magia per ogni bit acceso
#                               (bit 0 = livello 1 ... bit 7 = livello 8)
#   lut_LvlUpHitRateBonus / lut_LvlUpMagDefBonus  righe ~1185/1197: 12 byte
#                       (6 classi base + 6 promosse).
#
# Le tabelle si leggono direttamente dal TESTO dell'asm dove sono scritte come
# numeri: cosi' l'estrazione resta verificabile a occhio contro il sorgente.
#
# Array 1-D e dietro una macro di gate, come ff1_cheer_sprites.h: sccz80 mette
# i const multidimensionali in sezione DATA, che in un banco MegaCart non viene
# mai inizializzata.

param(
    [string]$disasm = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [string]$outPath = "$PSScriptRoot\..\src\data\levelup_data.h"
)

$ErrorActionPreference = 'Stop'
$root = $disasm
$asm  = Get-Content (Join-Path $root 'bank_0B.asm')

# --- lut_ExpToAdvance: righe .FARADDR dopo l'etichetta ---
$exp = @()
$inTable = $false
foreach ($l in $asm) {
    if ($l -match '^lut_ExpToAdvance:') { $inTable = $true; continue }
    if ($inTable) {
        if ($l -match '^\s*\.FARADDR\s+(.+)$') {
            foreach ($v in ($Matches[1] -split ',')) {
                $t = $v.Trim()
                if ($t -ne '') { $exp += [int]$t }
            }
        } elseif ($l.Trim() -ne '') { break }
    }
}
if ($exp.Count -ne 49) { throw "attesi 49 valori in lut_ExpToAdvance, trovati $($exp.Count)" }

# --- tabelle di bonus a 12 byte ---
function Get-ByteTable([string]$label) {
    $found = $false
    foreach ($l in $asm) {
        if ($l -match ("^" + [regex]::Escape($label) + ":")) { $found = $true; continue }
        if ($found) {
            if ($l -match '^\s*\.BYTE\s+(.+)$') {
                $vals = @()
                foreach ($v in ($Matches[1] -split ',')) {
                    $t = $v.Trim()
                    if ($t -ne '') { $vals += [int]$t }
                }
                return $vals
            }
            if ($l.Trim() -ne '' -and $l -notmatch '^\s*;') { break }
        }
    }
    throw "tabella non trovata: $label"
}
$hitBonus = Get-ByteTable 'lut_LvlUpHitRateBonus'
$mdefBonus = Get-ByteTable 'lut_LvlUpMagDefBonus'
if ($hitBonus.Count -ne 12 -or $mdefBonus.Count -ne 12) { throw "tabelle bonus non da 12 byte" }

# --- dati di livello, binario grezzo ---
$lvl = [System.IO.File]::ReadAllBytes((Join-Path $root 'bin\0B_9094_levelupdata.bin'))
if ($lvl.Length -ne 588) { throw "0B_9094_levelupdata.bin: attesi 588 byte, trovati $($lvl.Length)" }

$sb = New-Object System.Text.StringBuilder
function W($s) { [void]$sb.AppendLine($s) }

W "// AUTO-GENERATO da tools/extract_levelup_data.ps1 (disassembly Disch, bank_0B)"
W "// Curva EXP e dati di passaggio di livello di FF1, byte-exact."
W "//"
W "// lut_ExpToAdvance: EXP TOTALI per passare al livello dopo. Indice = livello"
W "// 0-based, 3 byte little-endian l'uno (FF1 arriva a 989641, che in 16 bit non"
W "// ci sta). entry 0 = 40 = da L1 a L2."
W "//"
W "// data_LevelUpData: 6 classi x 49 livelli x 2 byte."
W "//   byte 0: bit5 livello forte (+rand[20,25] HP), bit4 STR, bit3 AGL,"
W "//           bit2 INT, bit1 VIT, bit0 LUCK garantiti (gli altri 25%)"
W "//   byte 1: una carica di magia per bit acceso (bit0 = livello 1)"
W "//"
W "// Array 1-D dietro macro di gate: i const multidimensionali finiscono in"
W "// sezione DATA, mai inizializzata in un banco MegaCart."
W ""
W "#ifndef FF1_LEVELUP_DATA_H"
W "#define FF1_LEVELUP_DATA_H"
W ""
W "#define LVLUP_MAX_LEVEL   50"
W "#define LVLUP_N_LEVELS    49    /* voci nelle tabelle: da L1->L2 fino a L49->L50 */"
W "#define LVLUP_N_CLASSES    6"
W "#define LVLUP_REC          2    /* byte per livello */"
W "/* bit del byte 0 */"
W "#define LVLUP_STRONG   0x20"
W "#define LVLUP_STR      0x10"
W "#define LVLUP_AGL      0x08"
W "#define LVLUP_INT      0x04"
W "#define LVLUP_VIT      0x02"
W "#define LVLUP_LUCK     0x01"
W ""
W "#ifdef FF1_LEVELUP_DEFINE_DATA"
W ""
W "// 49 x 3 byte little-endian"
W "static const unsigned char lut_ExpToAdvance[49 * 3] = {"
for ($i = 0; $i -lt 49; $i += 1) {
    $v = $exp[$i]
    $b0 = $v -band 0xFF; $b1 = ($v -shr 8) -band 0xFF; $b2 = ($v -shr 16) -band 0xFF
    W ("    0x{0:X2},0x{1:X2},0x{2:X2},   // L{3} -> L{4} = {5}" -f $b0, $b1, $b2, ($i + 1), ($i + 2), $v)
}
W "};"
W ""
W "// 6 classi x 49 livelli x 2 byte"
W "static const unsigned char data_LevelUpData[588] = {"
$classNames = @("FT","TH","BB","RM","WM","BM")
for ($c = 0; $c -lt 6; $c++) {
    W ("  // [$c] " + $classNames[$c])
    for ($lv = 0; $lv -lt 49; $lv += 7) {
        $line = "    "
        for ($k = 0; $k -lt 7; $k++) {
            $off = ($c * 49 + $lv + $k) * 2
            $line += ("0x{0:X2},0x{1:X2}, " -f $lvl[$off], $lvl[$off + 1])
        }
        W $line.TrimEnd()
    }
}
W "};"
W ""
W "// Bonus per classe applicati a ogni passaggio di livello (12 = 6 base + 6 promosse)"
W ("static const unsigned char lut_LvlUpHitRateBonus[12] = { " + ($hitBonus -join ", ") + " };")
W ("static const unsigned char lut_LvlUpMagDefBonus[12] = { " + ($mdefBonus -join ", ") + " };")
W ""
W "#endif // FF1_LEVELUP_DEFINE_DATA"
W ""
W "#endif // FF1_LEVELUP_DATA_H"

$dest = $outPath
[System.IO.File]::WriteAllText($dest, $sb.ToString())
Write-Host "Scritto: $dest"
Write-Host ("  curva EXP: L1->L2 = {0}, L49->L50 = {1}" -f $exp[0], $exp[48])
Write-Host ("  dati livello: 588 byte, bonus hit/mdef: 12+12")
