# Run this script once to generate placeholder brand icons.
# Requires Windows with .NET (System.Drawing) — standard on Windows 10+.
# Run from repo root: powershell -ExecutionPolicy Bypass -File assets\brand\generate_icons.ps1

Add-Type -AssemblyName System.Drawing

$outDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function New-Icon {
    param([int]$Size, [string]$OutPath, [bool]$Transparent = $false)

    $bmp = New-Object System.Drawing.Bitmap $Size, $Size
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode   = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    if ($Transparent) {
        $g.Clear([System.Drawing.Color]::Transparent)
    } else {
        $g.Clear([System.Drawing.Color]::FromArgb(0x0F, 0x17, 0x29))
    }

    $fontSize  = [int]($Size * 0.60)
    $font      = New-Object System.Drawing.Font('Consolas', $fontSize, [System.Drawing.FontStyle]::Bold)
    $brush     = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(0x00, 0xE5, 0xFF))
    $sf        = New-Object System.Drawing.StringFormat
    $sf.Alignment     = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center

    $rect = [System.Drawing.RectangleF]::new(0, 0, $Size, $Size)
    $g.DrawString('P', $font, $brush, $rect, $sf)

    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    Write-Host "Created: $OutPath ($Size x $Size)"
}

# 1024x1024 opaque — для App Store / Google Play и как master source
New-Icon -Size 1024 -OutPath "$outDir\icon_source.png"

# 1024x1024 transparent foreground — для Android adaptive icon foreground layer
New-Icon -Size 1024 -OutPath "$outDir\icon_foreground.png" -Transparent $true

# 512x512 opaque — для splash screen
New-Icon -Size 512  -OutPath "$outDir\splash_logo.png"

Write-Host ""
Write-Host "Done. Place icon_source.png into flutter_launcher_icons config when ready."
