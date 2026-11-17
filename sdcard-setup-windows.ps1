# ============================================================================
# sdcard-setup-windows.ps1 — Windows 1-Click SD Card Installer for MPI3501
# ============================================================================
# Run this script on Windows right after flashing Raspberry Pi OS with
# Raspberry Pi Imager — OR on an SD card you have already booted!
#
# What it does:
#   1. Auto-detects the Raspberry Pi SD card 'bootfs' drive on Windows
#   2. Installs pre-compiled overlays\mpi3501.dtbo directly into
#      <SD_CARD>:\overlays\mpi3501.dtbo and copies the full driver suite
#      to <SD_CARD>:\mpi3501\ (available on the Pi at /boot/firmware/mpi3501/)
#   3. Patches config.txt and cmdline.txt on the SD card so the 3.5" screen
#      and calibrated XPT2046 touch controller initialize immediately on boot
#   4. Sets up a one-time systemd boot hook (or hooks firstrun.sh) so the Pi
#      automatically configures X11, sets ili9486 as PrimaryGPU, applies the
#      corrected XPT2046 touch CalibrationMatrix, and boots straight into
#      the Desktop on the 3.5" screen!
# ============================================================================

param(
    [string]$DriveLetter = "",
    [ValidateSet("180", "0", "90", "270")]
    [string]$Rotation = "180",
    [int]$Speed = 16000000
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  MPI3501 3.5`" Display — Windows 1-Click SD Card Setup" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# 1. Auto-detect Raspberry Pi bootfs partition
$BootRoot = $null
if ($DriveLetter -ne "") {
    $CleanLetter = $DriveLetter.TrimEnd(':', '\')
    $Candidate = "${CleanLetter}:\"
    if (Test-Path (Join-Path $Candidate "config.txt")) {
        $BootRoot = $Candidate
    } else {
        Write-Host "[ERROR] config.txt not found on drive $Candidate" -ForegroundColor Red
        exit 1
    }
} else {
    $Volumes = Get-Volume | Where-Object { $_.DriveLetter -ne $null }
    foreach ($Vol in $Volumes) {
        $Root = "$($Vol.DriveLetter):\"
        if ((Test-Path (Join-Path $Root "config.txt")) -and (Test-Path (Join-Path $Root "overlays"))) {
            $BootRoot = $Root
            break
        }
    }
}

if (-not $BootRoot) {
    Write-Host "[ERROR] Could not auto-detect a Raspberry Pi SD card (bootfs)." -ForegroundColor Red
    Write-Host "        Make sure the microSD card is inserted and visible in File Explorer." -ForegroundColor Yellow
    Write-Host "        Or specify the drive letter manually: .\sdcard-setup-windows.ps1 -DriveLetter E" -ForegroundColor Yellow
    exit 1
}

Write-Host "[1/4] Found Raspberry Pi boot partition at: $BootRoot" -ForegroundColor Green

# 2. Install pre-built mpi3501.dtbo and copy MPI3501 driver files onto the SD card
$TargetDir = Join-Path $BootRoot "mpi3501"
$TargetOverlays = Join-Path $TargetDir "overlays"
$BootOverlays = Join-Path $BootRoot "overlays"
New-Item -ItemType Directory -Force -Path $TargetOverlays | Out-Null

$FilesToCopy = @("MPI3501-show", "MPI3501-hdmi", "MPI3501-rotate", "MPI3501-calibrate", "MPI3501-diag", "LCD35-show", "LCD-hdmi", "README.md")
foreach ($File in $FilesToCopy) {
    $Src = Join-Path $ScriptDir $File
    if (Test-Path $Src) {
        $Content = [System.IO.File]::ReadAllText($Src) -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText((Join-Path $TargetDir $File), $Content, (New-Object System.Text.UTF8Encoding($false)))
    }
}

$DtsSrc = Join-Path $ScriptDir "overlays\mpi3501-overlay.dts"
if (Test-Path $DtsSrc) {
    $DtsContent = [System.IO.File]::ReadAllText($DtsSrc) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText((Join-Path $TargetOverlays "mpi3501-overlay.dts"), $DtsContent, (New-Object System.Text.UTF8Encoding($false)))
}

$DtboSrc = Join-Path $ScriptDir "overlays\mpi3501.dtbo"
if (Test-Path $DtboSrc) {
    Copy-Item -Force $DtboSrc (Join-Path $TargetOverlays "mpi3501.dtbo")
    Copy-Item -Force $DtboSrc (Join-Path $BootOverlays "mpi3501.dtbo")
    Write-Host "[2/4] Installed custom mpi3501.dtbo -> ${BootOverlays}\mpi3501.dtbo" -ForegroundColor Green
} else {
    Write-Host "[2/4] Copied MPI3501 driver suite -> ${TargetDir}" -ForegroundColor Green
}

# 3. Patch config.txt on the SD card
$ConfigPath = Join-Path $BootRoot "config.txt"
$BackupPath = Join-Path $BootRoot "config.txt.mpi3501.bak"
if (-not (Test-Path $BackupPath)) {
    Copy-Item $ConfigPath $BackupPath
}

$ConfigText = [System.IO.File]::ReadAllText($ConfigPath) -replace "`r`n", "`n"

# Comment out active dtoverlay=vc4-kms-v3d or vc4-fkms-v3d
$ConfigText = [regex]::Replace($ConfigText, '(?m)^[ \t]*(dtoverlay=vc4-f?kms-v3d.*)$', '#$1 # [mpi3501-disabled]')

# Remove any old MPI3501 block
$ConfigText = [regex]::Replace($ConfigText, '(?s)\n?# --- BEGIN MPI3501 DRIVER ---.*?# --- END MPI3501 DRIVER ---\n?', '')

$OverlayLine = "dtoverlay=mpi3501,speed=$Speed,rotate=$Rotation"

$DriverBlock = @"

# --- BEGIN MPI3501 DRIVER ---
[all]
dtparam=spi=on
$OverlayLine
# --- END MPI3501 DRIVER ---
"@ -replace "`r`n", "`n"

$ConfigText = $ConfigText.TrimEnd() + "`n" + $DriverBlock + "`n"
[System.IO.File]::WriteAllText($ConfigPath, $ConfigText, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[3/4] Patched config.txt ($OverlayLine)" -ForegroundColor Green

# 4. Configure automatic boot installer (via firstrun.sh OR systemd.run one-shot)
$CmdlinePath = Join-Path $BootRoot "cmdline.txt"
$FirstRunPath = Join-Path $BootRoot "firstrun.sh"
$SetupScriptPath = Join-Path $BootRoot "mpi3501-setup.sh"

$SetupScript = @"
#!/bin/bash
set +e
# 1. Immediately clean up systemd.run from cmdline.txt so this only runs ONCE
for CMD in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
    if [ -f "`$CMD" ]; then
        sed -i -e 's| systemd.run=/boot/firmware/mpi3501-setup.sh||g' \
               -e 's| systemd.run=/boot/mpi3501-setup.sh||g' \
               -e 's| systemd.run_success_action=reboot||g' \
               -e 's| systemd.unit=kernel-command-line.target||g' "`$CMD"
    fi
done

# 2. Run the full MPI3501-show installer (installs DTBO, switches Wayland->X11, configures PrimaryGPU + Touch)
if [ -f /boot/firmware/mpi3501/MPI3501-show ]; then
    bash /boot/firmware/mpi3501/MPI3501-show $Rotation --speed $Speed --no-reboot
elif [ -f /boot/mpi3501/MPI3501-show ]; then
    bash /boot/mpi3501/MPI3501-show $Rotation --speed $Speed --no-reboot
fi

rm -f /boot/firmware/mpi3501-setup.sh /boot/mpi3501-setup.sh
sync
exit 0
"@ -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($SetupScriptPath, $SetupScript, (New-Object System.Text.UTF8Encoding($false)))

if (Test-Path $FirstRunPath) {
    $FirstRunText = [System.IO.File]::ReadAllText($FirstRunPath) -replace "`r`n", "`n"
    if ($FirstRunText -notmatch "mpi3501-setup\.sh") {
        $Hook = @"

# --- MPI3501 First-Boot Auto-Setup ---
if [ -f /boot/firmware/mpi3501-setup.sh ]; then
    bash /boot/firmware/mpi3501-setup.sh
elif [ -f /boot/mpi3501-setup.sh ]; then
    bash /boot/mpi3501-setup.sh
fi
"@ -replace "`r`n", "`n"
        if ($FirstRunText -match 'rm -f .*firstrun\.sh') {
            $FirstRunText = $FirstRunText -replace '(rm -f .*firstrun\.sh)', "$Hook`n`$1"
        } else {
            $FirstRunText = $FirstRunText -replace '(?m)^exit 0\s*$', "$Hook`nexit 0"
        }
        [System.IO.File]::WriteAllText($FirstRunPath, $FirstRunText, (New-Object System.Text.UTF8Encoding($false)))
    }
    if (Test-Path $CmdlinePath) {
        $Cmdline = ([System.IO.File]::ReadAllText($CmdlinePath) -replace "`r`n", "`n").Trim()
        $Cmdline = [regex]::Replace($Cmdline, '\s*fbcon=map:[0-9]+', '')
        $Cmdline = [regex]::Replace($Cmdline, '\s*fbcon=font:\S+', '')
        $Cmdline = "$Cmdline fbcon=map:10 fbcon=font:ProFont6x11`n"
        [System.IO.File]::WriteAllText($CmdlinePath, $Cmdline, (New-Object System.Text.UTF8Encoding($false)))
    }
    Write-Host "[4/4] Hooked into firstrun.sh for automatic first-boot X11 & Touch setup!" -ForegroundColor Green
} elseif (Test-Path $CmdlinePath) {
    $CmdlineBackup = Join-Path $BootRoot "cmdline.txt.mpi3501.bak"
    if (-not (Test-Path $CmdlineBackup)) {
        Copy-Item $CmdlinePath $CmdlineBackup
    }
    $Cmdline = ([System.IO.File]::ReadAllText($CmdlinePath) -replace "`r`n", "`n").Trim()
    $Cmdline = [regex]::Replace($Cmdline, '\s*fbcon=map:[0-9]+', '')
    $Cmdline = [regex]::Replace($Cmdline, '\s*fbcon=font:\S+', '')
    $Cmdline = [regex]::Replace($Cmdline, '\s*systemd\.run=\S+', '')
    $Cmdline = [regex]::Replace($Cmdline, '\s*systemd\.run_success_action=\S+', '')
    $Cmdline = [regex]::Replace($Cmdline, '\s*systemd\.unit=\S+', '')
    $Cmdline = "$Cmdline fbcon=map:10 fbcon=font:ProFont6x11 systemd.run=/boot/firmware/mpi3501-setup.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target`n"
    [System.IO.File]::WriteAllText($CmdlinePath, $Cmdline, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "[4/4] Configured one-time auto-setup in cmdline.txt (Zero SSH/HDMI needed!)" -ForegroundColor Green
}

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  SD Card Patched Successfully!" -ForegroundColor Green
Write-Host "  1. Safely eject the SD card from Windows." -ForegroundColor White
Write-Host "  2. Plug the SD card & 3.5`" MPI3501 display into your Pi 4B." -ForegroundColor White
Write-Host "  3. Power on! The Pi will apply the updated touch driver, reboot once," -ForegroundColor White
Write-Host "     and launch straight into the Desktop on the 3.5`" screen." -ForegroundColor White
Write-Host "========================================================" -ForegroundColor Cyan
