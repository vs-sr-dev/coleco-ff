# mame_path.ps1 -- dove sta MAME, senza cablarlo negli script.
#
# Si include con il dot-sourcing (. "$PSScriptRoot\mame_path.ps1") e si chiama
# Resolve-Mame. Ordine di ricerca:
#   1. il valore passato esplicitamente (es. -Mame di run_regressions);
#   2. la variabile d'ambiente MAME;
#   3. $MameExe in tools/local.ps1 (escluso dal repo: vedi local.ps1.example);
#   4. mame.exe nel PATH.

function Resolve-Mame([string]$Hint = '') {
    if ($Hint) { return $Hint }
    if ($env:MAME) { return $env:MAME }
    $local = Join-Path $PSScriptRoot 'local.ps1'
    if (Test-Path $local) {
        . $local
        if ($MameExe) { return $MameExe }
    }
    $cmd = Get-Command mame -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "MAME non trovato: passa -Mame, imposta `$env:MAME, o crea tools\local.ps1 (vedi local.ps1.example)"
}
