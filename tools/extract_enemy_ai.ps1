# =====================================================================
#  extract_enemy_ai.ps1 -- la tabella dell'IA nemica di FF1, byte-exact
# =====================================================================
# Sorgente: FF1Disassembly-master/.../bin/0C_9020_aidata.bin (704 byte).
# Uscita:   src/data/enemy_ai.h
#
# Formato di una voce, 16 byte (decodificato da `Enemy_DoAi`,
# bank_0C.asm:6892-6975 -- NON dai commenti, che non lo esplicitano):
#
#   byte $00      probabilita' di lanciare un INCANTESIMO, su 128
#   byte $01      probabilita' di ATTACCO SPECIALE, su 128
#   byte $02-$09  8 caselle di incantesimo, ciclate a giro ($FF = fine lista,
#                 si riparte da capo)
#   byte $0A      non usato
#   byte $0B-$0E  4 caselle di attacco speciale; l'id va sommato a $42 perche'
#                 le voci $00-$3F della tabella della magia sono incantesimi e
#                 $40/$41 sono le due pozioni
#   byte $0F      non usato
#
# Le due probabilita' si tirano con rand[0,128] < valore
# (`EnemyAi_ShouldPerformAction`, bank_0C.asm:6873): la magia si prova per
# prima, l'attacco speciale solo se la magia non e' uscita, il colpo normale
# solo se non e' uscito nessuno dei due.
#
# ATTENZIONE PowerShell (vedi memory/feedback_powershell_format_op.md): niente
# operatore -f e niente range .., si usa .ToString('X2') dentro l'interpolazione.

param(
    [string]$Bin = "FF1Disassembly-master\Final Fantasy Disassembly\bin\0C_9020_aidata.bin",
    [string]$Out = "src\data\enemy_ai.h"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$binPath = Join-Path $root $Bin
$outPath = Join-Path $root $Out

if (-not (Test-Path $binPath)) { throw "non trovo $binPath" }

$bytes = [System.IO.File]::ReadAllBytes($binPath)
if ($bytes.Length % 16 -ne 0) { throw "dimensione $($bytes.Length) non multipla di 16" }
$n = $bytes.Length / 16
Write-Host "  $($bytes.Length) byte = $n voci di IA"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('// AUTO-GENERATO da tools/extract_enemy_ai.ps1 -- non modificare a mano')
$lines.Add('// Sorgente: bin/0C_9020_aidata.bin del disassembly Disch, byte-exact.')
$lines.Add('//')
$lines.Add('// Una voce = 16 byte, indicizzata da ENROMSTAT_AI ($FF = nessuna IA,')
$lines.Add('// il nemico picchia e basta). Formato decodificato da Enemy_DoAi')
$lines.Add('// (bank_0C.asm:6892):')
$lines.Add('//   $00      probabilita di incantesimo, su 128')
$lines.Add('//   $01      probabilita di attacco speciale, su 128')
$lines.Add('//   $02-$09  8 caselle di incantesimo ($FF = fine, si ricomincia)')
$lines.Add('//   $0B-$0E  4 caselle di attacco speciale (id + $42 nella tabella magia)')
$lines.Add('')
$lines.Add('#ifndef FF1_ENEMY_AI_H')
$lines.Add('#define FF1_ENEMY_AI_H')
$lines.Add('')
$lines.Add('#define ENEMY_AI_SIZE      16')
$lines.Add("#define ENEMY_AI_COUNT     $n")
$lines.Add('#define ENEMY_AI_MAGRATE    0')
$lines.Add('#define ENEMY_AI_ATKRATE    1')
$lines.Add('#define ENEMY_AI_SPELLS     2   /* 8 caselle */')
$lines.Add('#define ENEMY_AI_ATTACKS   11   /* 4 caselle, $0B */')
$lines.Add('#define ENEMY_AI_ATK_BASE  0x42 /* offset degli attacchi speciali nella tabella magia */')
$lines.Add('')
$lines.Add('#ifdef FF1_ENEMY_AI_DEFINE_DATA')
$lines.Add('')
$lines.Add('static const unsigned char lut_EnemyAi[] = {')

for ($e = 0; $e -lt $n; $e++) {
    $off = $e * 16
    $hex = @()
    for ($k = 0; $k -lt 16; $k++) {
        $hex += '0x' + $bytes[$off + $k].ToString('X2')
    }
    $row = '    ' + ($hex -join ', ') + ','
    $magRate = $bytes[$off]
    $atkRate = $bytes[$off + 1]
    # Quante caselle davvero piene, per rendere leggibile il commento.
    $nsp = 0
    for ($k = 2; $k -lt 10; $k++) { if ($bytes[$off + $k] -ne 0xFF) { $nsp++ } }
    $nat = 0
    for ($k = 11; $k -lt 15; $k++) { if ($bytes[$off + $k] -ne 0xFF) { $nat++ } }
    $lines.Add($row)
    $lines.Add("// IA `$$($e.ToString('X2'))  magia $magRate/128 ($nsp caselle)  speciale $atkRate/128 ($nat caselle)")
}

$lines.Add('};')
$lines.Add('')
$lines.Add('#endif /* FF1_ENEMY_AI_DEFINE_DATA */')
$lines.Add('#endif /* FF1_ENEMY_AI_H */')

[System.IO.File]::WriteAllLines($outPath, $lines)
Write-Host "  scritto $Out"
