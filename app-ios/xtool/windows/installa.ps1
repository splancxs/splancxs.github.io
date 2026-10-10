# Rinnova Recomp (iPhone + Apple Watch) dal PC Windows. Da lanciare da PowerShell, anche senza permessi di amministratore:
#   powershell -ExecutionPolicy Bypass -File app-ios\xtool\windows\installa.ps1            iPhone + orologio
#   ... installa.ps1 iphone       solo iPhone        ... installa.ps1 orologio     solo l'app Watch
# Prima: iPhone collegato col cavo e sbloccato, orologio sbloccato e al polso.
param([string]$Cosa = 'tutto')
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

# --cd accetta il percorso di Windows; cwd fuori dal repository non serve, ma installa.sh calcola i percorsi da solo
wsl -d Ubuntu -u root --cd $xtool -- bash ./installa.sh $Cosa
