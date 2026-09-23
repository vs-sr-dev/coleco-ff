# build_megacart.ps1
#
# Take a standard ColecoVision 32KB ROM (linked at $8000-$FFFF) and repackage
# it into a ColecoVision MegaCart ROM image of N x 16KB banks.
#
# MegaCart layout (ColecoVision standard, verified against mecha_8.rom +
# CoolCV/MAME bundled MegaCart reference):
#   - The LAST 16KB of the ROM file is the FIXED bank, mapped to $8000-$BFFF.
#     The cart header ($55 $AA) lives at the START of the last bank (= file
#     offset (size - 16384)), which is $8000 in CPU view at power-on.
#   - Earlier 16KB blocks are banks 0..(N-2), mapped to $C000-$FFFF via bank
#     switching. AT POWER-ON BOTH WINDOWS SHOW THE LAST BANK -- the cart
#     bootstrap MUST switch a real bank to $C000-$FFFF before accessing data
#     there. The sgm_megacart_crt0.asm does this via `ld a,($FFC0)` (selects
#     bank 0 for the upper window).
#   - Bank switch trigger: read from $FFC0+N selects bank N for $C000-$FFFF.
#
# Phase 1 packaging:
#   - bytes [0..16383]      of input = address $8000-$BFFF -> LAST bank (end of file)
#   - bytes [16384..32767]  of input = address $C000-$FFFF -> bank 0 (start of file)
#   - all intermediate banks padded with $FF.
#
# At runtime, after crt0's bank-0 select, the CPU sees the same 32KB it
# would have seen on a stock 32KB cart.
#
# Usage:
#   .\build_megacart.ps1 -In ..\build\slice41.rom -Out ..\build\slice41_mc.rom
#   .\build_megacart.ps1 -In ..\build\slice41.rom -Out ..\build\slice41_mc.rom -RomKB 1024

param(
    [string]$In    = "$PSScriptRoot\..\build\slice41.rom",
    [string]$Out   = "$PSScriptRoot\..\build\slice41_mc.rom",
    [int]$RomKB    = 1024,
    # Optional bank blobs. Each is a 32KB ROM from z88dk (content at file
    # offset 0x4000..0x7FFF) OR a raw 16KB blob, placed at the corresponding
    # MC bank's file region. Bank N -> file offset N * 16384.
    # (Bank 0 = first 16KB of input In's $C000+ half; bank 7 = last 16KB of MC
    # ROM = code bank, from input In's $8000+ half. Both come from -In.)
    [string]$Bank1 = '',
    [string]$Bank2 = '',
    [string]$Bank3 = '',
    [string]$Bank4 = '',
    [string]$Bank5 = '',
    [string]$Bank6 = '',
    # Generic form, for ROMs larger than 128KB where banks 7..N-2 also become
    # switchable: -Banks '7=path\a.bin','8=path\b.rom'
    # (At 128KB bank 7 IS the fixed bank and cannot be spliced this way; at
    # 256KB the fixed bank is 15, so 7..14 are free.)
    [string[]]$Banks = @()
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $In)) { throw "input not found: $In" }
$src = [System.IO.File]::ReadAllBytes($In)
if ($src.Length -ne 32768) {
    throw ("expected 32768-byte input, got {0}" -f $src.Length)
}

$validSizes = @(64, 128, 256, 512, 1024)
if ($validSizes -notcontains $RomKB) {
    throw ("RomKB must be one of: {0} (got {1})" -f ($validSizes -join ', '), $RomKB)
}

$romBytes = $RomKB * 1024
$bankSize = 16384
$nBanks   = $romBytes / $bankSize
Write-Host ("Target ROM: {0} KB = {1} banks of 16KB" -f $RomKB, $nBanks)

# Allocate output, fill with $FF. Note: PowerShell is CASE-INSENSITIVE for
# variable names so a local `$out` would clobber the typed `$Out` parameter
# (which is [string], silently triggering ToString() coercion). We use $rom
# instead.
$rom = [System.Array]::CreateInstance([byte], $romBytes)
for ($i = 0; $i -lt $romBytes; $i++) { $rom[$i] = [byte]0xFF }

# Bank 0 = input upper half (linker's $C000-$FFFF data) -> start of file
[Array]::Copy($src, $bankSize, $rom, 0, $bankSize)

# Last bank (fixed) = input lower half (linker's $8000-$BFFF code + boot header)
$fixedOffset = $romBytes - $bankSize
[Array]::Copy($src, 0, $rom, $fixedOffset, $bankSize)

# Helper: splice a bank ROM into the MC image at bank N (file offset N * 16384).
$lastBank = $nBanks - 1
$spliced  = New-Object System.Collections.ArrayList
function Splice-Bank {
    param([byte[]]$Rom, [int]$N, [string]$Path)
    if ($Path -eq '') { return }
    if (-not (Test-Path $Path)) { throw "bank$N file not found: $Path" }
    if ($N -lt 1 -or $N -gt ($script:lastBank - 1)) {
        throw ("bank index $N out of range: switchable banks are 1..{0} for a {1}KB ROM (bank {2} is the FIXED code bank)" -f ($script:lastBank - 1), $script:RomKB, $script:lastBank)
    }
    $src = [System.IO.File]::ReadAllBytes($Path)
    $dstOff = $N * 16384
    if ($src.Length -eq 32768) {
        Write-Host ("Bank{0} source is 32KB; extracting bytes [0x4000..0x7FFF] as the actual bank content" -f $N)
        [Array]::Copy($src, 0x4000, $Rom, $dstOff, 16384)
    } elseif ($src.Length -eq 16384) {
        Write-Host ("Bank{0} source is 16KB raw blob; copying directly" -f $N)
        [Array]::Copy($src, 0, $Rom, $dstOff, 16384)
    } else {
        throw ("bank$N must be 16384 or 32768 bytes (got {0})" -f $src.Length)
    }
    [void]$script:spliced.Add($N)
}

Splice-Bank -Rom $rom -N 1 -Path $Bank1
Splice-Bank -Rom $rom -N 2 -Path $Bank2
Splice-Bank -Rom $rom -N 3 -Path $Bank3
Splice-Bank -Rom $rom -N 4 -Path $Bank4
Splice-Bank -Rom $rom -N 5 -Path $Bank5
Splice-Bank -Rom $rom -N 6 -Path $Bank6

foreach ($spec in $Banks) {
    if ($spec -eq '') { continue }
    $eq = $spec.IndexOf('=')
    if ($eq -lt 1) { throw "-Banks entries must look like 'N=path' (got '$spec')" }
    $bn = [int]$spec.Substring(0, $eq)
    $bp = $spec.Substring($eq + 1)
    Splice-Bank -Rom $rom -N $bn -Path $bp
}

# Safety check: bank-switch trigger addresses live at $FFC0-$FFFF (= last 64
# bytes of the SWITCHED upper window). Whatever bank is currently mapped at
# $C000-$FFFF has its last 64 bytes acting as "switch register reads", so no
# bank may carry meaningful data there. Check bank 0 plus every spliced bank.
$checkList = @(0) + ($spliced | Sort-Object)
foreach ($bn in $checkList) {
    $tail = ($bn * $bankSize) + $bankSize - 64
    $nonFF = 0
    for ($i = $tail; $i -lt $tail + 64; $i++) { if ($rom[$i] -ne 0xFF) { $nonFF++ } }
    if ($nonFF -gt 0) {
        $msg = "WARN: bank $bn last 64 bytes have $nonFF non-FF bytes -- reads at " + [char]36 + "FFC0-" + [char]36 + "FFFF while bank $bn is mapped may bounce to another bank"
        Write-Host $msg -ForegroundColor Yellow
    } else {
        Write-Host "bank $bn trigger-zone tail is all FF (safe)"
    }
}

# Verify the boot header is at the start of the last bank
if ($rom[$fixedOffset] -eq 0x55 -and $rom[$fixedOffset + 1] -eq 0xAA) {
    $hex = '0x{0:X5}' -f $fixedOffset
    Write-Host "boot header 55 AA found at file offset $hex (last bank -> CPU 8000 at power-on)"
} elseif ($rom[$fixedOffset] -eq 0xAA -and $rom[$fixedOffset + 1] -eq 0x55) {
    $hex = '0x{0:X5}' -f $fixedOffset
    Write-Host "boot header AA 55 found at file offset $hex (skip-BIOS variant)"
} else {
    $b0 = $rom[$fixedOffset].ToString('X2'); $b1 = $rom[$fixedOffset + 1].ToString('X2')
    Write-Host "WARN: boot bytes at last bank start are $b0 $b1 -- expected 55 AA or AA 55" -ForegroundColor Red
}

$romDir = Split-Path $Out -Parent
if (-not (Test-Path $romDir)) { New-Item -ItemType Directory -Path $romDir -Force | Out-Null }
[System.IO.File]::WriteAllBytes($Out, $rom)
Write-Host ("Wrote {0} ({1} bytes = {2} KB)" -f $Out, $rom.Length, ($rom.Length / 1024))
