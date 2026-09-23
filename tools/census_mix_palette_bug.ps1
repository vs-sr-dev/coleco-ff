# census_mix_palette_bug.ps1
#
# Quanto pesa davvero il bug di palette del gruppo 2 nelle formazioni "mix".
#
# IL BUG (bank_0B.asm:2576-2583, segnalato dal disassembly stesso)
#   L'assegnazione di palette sta nel nibble alto del byte $0D: il gruppo i
#   legge il bit (7-i). Tutte le altre routine lo fanno giusto -- il ramo
#   9small/4large usa ROL x2,x3,x4,x5 per i gruppi 0,1,2,3, cioe' bit 7,6,5,4.
#   Il ramo "mix" pero' per il gruppo 2 fa SEI LSR invece di cinque, e quindi
#   porta a bit 0 il bit 6: legge la scelta del GRUPPO 1 al posto della propria.
#
#   Il gruppo 3, subito sotto, e' corretto (LSR x4 -> bit 4). E' proprio un
#   refuso isolato, non una convenzione diversa.
#
# QUANDO SI VEDE
#   Servono tre condizioni insieme:
#     1. formazione di tipo "mix"
#     2. il gruppo 2 esiste davvero (quantita' massima > 0)
#     3. il bit 5 e il bit 6 sono DIVERSI -- altrimenti sbagliare bit non
#        cambia nulla
#   e in piu' le due palette (byte $0A e $0B) devono essere diverse fra loro,
#   se no anche scegliere quella sbagliata da' lo stesso colore.
#
# Lo script conta i casi che superano tutti i filtri e dice CHI cambia colore.

param(
    [string]$Disasm = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly"
)

$ErrorActionPreference = 'Stop'

$formations = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bin\0B_8400_battleformations.bin'))
$nameBytes  = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bin\0B_94E0_enemynames.bin'))
$palRaw     = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bin\0C_8F20_battlepalettes.bin'))

function Decode-Name([byte[]]$src, [int]$off) {
    $s = ''
    for ($j = 0; $j -lt 8; $j++) {
        $b = $src[$off + $j]
        if ($b -eq 0) { break }
        if     ($b -ge 0x8A -and $b -le 0xA3) { $s += [char]([byte][char]'A' + $b - 0x8A) }
        elseif ($b -ge 0xA4 -and $b -le 0xBD) { $s += [char]([byte][char]'a' + $b - 0xA4) }
        elseif ($b -eq 0xC0) { $s += '.' }
        elseif ($b -eq 0xFF) { $s += ' ' }
    }
    return $s.Trim()
}
$enemyNames = New-Object string[] 128
for ($i = 0; $i -lt 128; $i++) {
    $addr = ([int]$nameBytes[$i*2+1] * 256) + [int]$nameBytes[$i*2]
    $off  = $addr - 0x94E0
    if ($off -ge 0 -and $off -lt $nameBytes.Length) { $enemyNames[$i] = Decode-Name $nameBytes $off }
    else { $enemyNames[$i] = '?' }
}

function Pal-String([int]$id) {
    $p = @()
    for ($e = 1; $e -lt 4; $e++) { $p += '$' + $palRaw[$id * 4 + $e].ToString('X2') }
    return ($p -join '/')
}

$mixTotal = 0; $g2exists = 0; $bitsDiffer = 0; $visible = 0
$hits = @()

for ($id = 0; $id -lt 256; $id++) {
    $isB = [bool]($id -band 0x80)
    $row = $id -band 0x7F
    $b = New-Object byte[] 16
    [Array]::Copy($formations, $row * 16, $b, 0, 16)
    # La variante B ha solo i gruppi 0 e 1: il gruppo 2 non esiste, quindi il
    # bug non la tocca mai. Si scarta subito.
    if ($isB) { continue }
    if (($b[0] -shr 4) -ne 2) { continue }        # solo "mix"
    $mixTotal++

    $qty2 = $b[8]                                  # quantita' del gruppo 2
    if (($qty2 -band 0x0F) -eq 0 -and ($qty2 -shr 4) -eq 0) { continue }
    $g2exists++

    $bit5 = ($b[0x0D] -shr 5) -band 1              # quello GIUSTO per il gruppo 2
    $bit6 = ($b[0x0D] -shr 6) -band 1              # quello che il NES legge davvero
    if ($bit5 -eq $bit6) { continue }
    $bitsDiffer++

    $palGood = if ($bit5) { $b[0x0B] } else { $b[0x0A] }
    $palNes  = if ($bit6) { $b[0x0B] } else { $b[0x0A] }
    if (($palGood -band 0x3F) -eq ($palNes -band 0x3F)) { continue }
    $visible++

    $hits += [pscustomobject]@{
        Id = $id; Enemy = $enemyNames[$b[4]]
        Slot = ($b[1] -shr 4) -band 3
        PalNes = $palNes -band 0x3F; PalGood = $palGood -band 0x3F
    }
}

Write-Host ""
Write-Host "=== bug di palette del gruppo 2 nel tipo mix ===" -ForegroundColor Cyan
Write-Host ("  formazioni mix (variante A)          : {0}" -f $mixTotal)
Write-Host ("  ...in cui il gruppo 2 esiste         : {0}" -f $g2exists)
Write-Host ("  ...in cui bit5 e bit6 differiscono   : {0}" -f $bitsDiffer)
Write-Host ("  ...in cui il COLORE cambia davvero   : {0}" -f $visible) -ForegroundColor Yellow

if ($hits.Count) {
    Write-Host ""
    Write-Host "  chi cambia colore:" -ForegroundColor Yellow
    foreach ($h in $hits) {
        Write-Host ("    form {0}  {1,-9} slot{2}   NES pal {3,2} ({4})   corretto pal {5,2} ({6})" -f `
            $h.Id.ToString('X2'), $h.Enemy, $h.Slot,
            $h.PalNes, (Pal-String $h.PalNes), $h.PalGood, (Pal-String $h.PalGood))
    }
}
