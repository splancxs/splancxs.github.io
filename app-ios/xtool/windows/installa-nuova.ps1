# Rinnova «Recomp 2» (l'app SwiftUI, iPhone + Apple Watch) dal PC Windows. Da lanciare da PowerShell:
#   powershell -ExecutionPolicy Bypass -File app-ios\xtool\windows\installa-nuova.ps1            iPhone + orologio
#   ... installa-nuova.ps1 iphone    solo iPhone     ... installa-nuova.ps1 orologio    solo l'app Watch
#   ... installa-nuova.ps1 watch     ricompila solo l'orologio     ... installa-nuova.ps1 compila    controlla che compili, senza installare
# Prima: iPhone collegato col cavo e sbloccato, orologio sbloccato e al polso.
param([string]$Cosa = 'tutto', [string]$Come = '')
$qui = Split-Path -Parent $MyInvocation.MyCommand.Path
$xtool = Split-Path -Parent $qui

# il servizio Apple di Windows (app «Apple Devices») deve essere acceso: è lui che parla con l'iPhone
Start-Process 'shell:AppsFolder\AppleInc.AppleDevices_nzyj5cx40ttqa!App' -ErrorAction SilentlyContinue
Start-Sleep 4

# se l'iPhone è «prestato» a Linux con usbipd, restituiscilo a Windows
$usbipd = 'C:\Program Files\usbipd-win\usbipd.exe'
if (Test-Path $usbipd) {
    $riga = & $usbipd list 2>$null | Select-String 'Apple Mobile Device.*Attached'
    if ($riga) { & $usbipd detach --busid ($riga.Line -split '\s+')[0] }
}

wsl -d Ubuntu -u root --cd $xtool -- bash ./installa-nuova.sh $Cosa $Come
