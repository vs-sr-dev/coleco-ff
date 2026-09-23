# extract_teleports.ps1 -- le tre famiglie di teletrasporti di FF1, byte-exact.
#
# Sorgente: bank_00.dat (mappato a $8000: offset di file = indirizzo - $8000).
#   lut_EntrTele_X/Y/Map = $AC00/$AC20/$AC40  (32 voci: overworld -> mappa)
#   lut_ExitTele_X/Y     = $AC60/$AC70        (16 voci: mappa -> overworld)
#   lut_NormTele_X/Y/Map = $AD00/$AD40/$AD80  (64 voci: mappa -> mappa)
#
# Escono in UN array piatto solo (320 byte), con gli offset delle otto fette
# come #define: il consumatore e' svc_fetch_btl, che copia a offset -- e un
# array solo e' una tabella sola nel suo dispatch.
#
# Le coordinate NES portano il bit 7 di "wrap": la mappa e' 64x64 e le X/Y
# utili stanno in 6 bit. Si copiano COM'E' e si maschera alla lettura, come fa
# il NES -- mascherare qui vorrebbe dire un estrattore che sa piu' cose del
# motore che lo legge.

param(
    [string]$Rom = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bank_00.dat",
    [string]$OutHdr = "$PSScriptRoot\..\src\data\teleport_data.h"
)
$ErrorActionPreference = 'Stop'

$d = [System.IO.File]::ReadAllBytes($Rom)
if ($d.Length -ne 16384) { throw "bank_00.dat: attesi 16384 byte, letti $($d.Length)" }

# (nome fetta, offset nel file, lunghezza) nell'ordine in cui vanno in ROM.
$slices = @(
    @('NORM_X',  0x2D00, 64),
    @('NORM_Y',  0x2D40, 64),
    @('NORM_MAP',0x2D80, 64),
    @('EXIT_X',  0x2C60, 16),
    @('EXIT_Y',  0x2C70, 16),
    @('ENTR_X',  0x2C00, 32),
    @('ENTR_Y',  0x2C20, 32),
    @('ENTR_MAP',0x2C40, 32)
)

$out = New-Object System.Collections.Generic.List[string]
$out.Add('// AUTO-GENERATO da tools/extract_teleports.ps1 -- non modificare a mano.')
$out.Add('//')
$out.Add('// I teletrasporti di FF1, byte-exact da bank_00.dat. Un array piatto di')
$out.Add('// 320 byte: le otto fette si raggiungono con gli offset qui sotto.')
$out.Add('// Le coordinate portano il bit 7 di wrap del NES: mascherare con 0x3F.')
$out.Add('//')
$out.Add('// Header GATED: i dati escono solo con FF1_TELEPORT_DEFINE_DATA definito.')
$out.Add('')
$out.Add('#ifndef FF1_TELEPORT_DATA_H')
$out.Add('#define FF1_TELEPORT_DATA_H')
$out.Add('')

$off = 0
foreach ($s in $slices) {
    $out.Add(('#define FF1_TELE_{0,-9} {1,3}' -f $s[0], $off))
    $off += $s[2]
}
$out.Add(('#define FF1_TELE_TOTAL    {0,3}' -f $off))
$out.Add('')
$out.Add('#ifdef FF1_TELEPORT_DEFINE_DATA')
$out.Add('')
$out.Add("static const unsigned char ff1_teleport_data[FF1_TELE_TOTAL] = {")

foreach ($s in $slices) {
    $out.Add(('    /* {0} */' -f $s[0]))
    $bytes = @()
    for ($i = 0; $i -lt $s[2]; $i++) { $bytes += ('0x' + $d[[int]$s[1] + $i].ToString('X2')) }
    for ($i = 0; $i -lt $bytes.Count; $i += 16) {
        $n = [Math]::Min(16, $bytes.Count - $i)
        $out.Add('    ' + (($bytes[$i..($i + $n - 1)]) -join ',') + ',')
    }
}
$out.Add('};')
$out.Add('')
$out.Add('#endif // FF1_TELEPORT_DEFINE_DATA')
$out.Add('#endif // FF1_TELEPORT_DATA_H')

[System.IO.File]::WriteAllLines($OutHdr, $out)
Write-Host "scritto $OutHdr ($off byte di dati)"
