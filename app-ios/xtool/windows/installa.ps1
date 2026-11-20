# Compila e installa Recomp (iPhone + Apple Watch) dal PC Windows. Da PowerShell, nella cartella del repository:
#   powershell -ExecutionPolicy Bypass -File app-ios\xtool\windows\installa.ps1            rinnovo e aggiornamento (iPhone + orologio)
#   ... installa.ps1 orologio    rifà solo l'installazione sull'orologio
#   ... installa.ps1 compila     controlla che compili, senza telefono
# Prima: iPhone collegato col cavo e sbloccato, orologio sbloccato e al polso.
param([string]$Cosa = 'tutto')
$qui = Split-Path -Parent $MyInvocation.MyCommand.Path
$xtool = Split-Path -Parent $qui

if ($Cosa -ne 'compila') {
    # il servizio Apple di Windows (app «Apple Devices») deve essere acceso: è lui che parla con l'iPhone
    Start-Process 'shell:AppsFolder\AppleInc.AppleDevices_nzyj5cx40ttqa!App' -ErrorAction SilentlyContinue
    Start-Sleep 4
    # se l'iPhone è «prestato» a Linux con usbipd, restituiscilo a Windows
    $usbipd = 'C:\Program Files\usbipd-win\usbipd.exe'
    if (Test-Path $usbipd) {
        $riga = & $usbipd list 2>$null | Select-String 'Apple Mobile Device.*Attached'
        if ($riga) { & $usbipd detach --busid ($riga.Line -split '\s+')[0] }
    }
}

wsl -d Ubuntu -u root --cd $xtool -- bash ./installa.sh $Cosa
