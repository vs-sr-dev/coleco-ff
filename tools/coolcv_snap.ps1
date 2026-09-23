# coolcv_snap.ps1
#
# Lancia CoolCV con una ROM, attende N secondi, cattura SOLO la finestra di
# CoolCV in un PNG e chiude l'emulatore.
#
# Serve a rendere automatico il cross-check CoolCV (permissivo) contro MAME
# (severo). Cattura la sola area della finestra dell'emulatore, non il
# desktop: nessun altro contenuto dello schermo finisce nell'immagine.
#
# Uso:
#   .\coolcv_snap.ps1 -Rom ..\build\slice45_probe256.rom -Out ..\build\snap.png
#   .\coolcv_snap.ps1 -Rom ... -Out ... -WaitSec 25

param(
    [Parameter(Mandatory = $true)][string]$Rom,
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$WaitSec = 20,
    [string]$Exe = "$PSScriptRoot\..\CoolCV\CoolCV.exe"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Rom)) { throw "ROM non trovata: $Rom" }
if (-not (Test-Path $Exe)) { throw "CoolCV non trovato: $Exe" }

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinApi {
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

$proc = Start-Process -FilePath $Exe -ArgumentList $Rom -PassThru
try {
    # Attesa: BIOS Coleco (~12s) + tempo perche' la slice disegni.
    $deadline = $WaitSec
    for ($i = 0; $i -lt $deadline; $i++) {
        Start-Sleep -Seconds 1
        $proc.Refresh()
        if ($proc.HasExited) { throw "CoolCV e' uscito prematuramente (exit $($proc.ExitCode))" }
    }

    $hwnd = $proc.MainWindowHandle
    if ($hwnd -eq [IntPtr]::Zero) { throw "finestra CoolCV non trovata (MainWindowHandle nullo)" }

    [void][WinApi]::SetForegroundWindow($hwnd)
    Start-Sleep -Milliseconds 600

    $rect = New-Object WinApi+RECT
    if (-not [WinApi]::GetWindowRect($hwnd, [ref]$rect)) { throw "GetWindowRect fallita" }
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    if ($w -le 0 -or $h -le 0) { throw "dimensioni finestra non valide: ${w}x${h}" }

    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $w, $h))
    $gfx.Dispose()

    $outDir = Split-Path $Out -Parent
    if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host ("snapshot CoolCV -> {0} ({1}x{2})" -f $Out, $w, $h)
}
finally {
    $proc.Refresh()
    if (-not $proc.HasExited) { $proc.CloseMainWindow() | Out-Null; Start-Sleep -Milliseconds 800 }
    $proc.Refresh()
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
}
