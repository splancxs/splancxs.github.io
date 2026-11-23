# Debug di Recomp sull'iPhone dal PC (vedi app-ios/xtool/debug.sh). Da PowerShell, nella cartella del repository:
#   powershell -ExecutionPolicy Bypass -File app-ios\xtool\windows\debug.ps1 prepara
#   ... debug.ps1 apri pasto:3       ... debug.ps1 foto C:\percorso\foto.png       ... debug.ps1 registro 30
#   ... debug.ps1 prova "aggiungi:3:parmigiano;avvia:TA" scheda 600     (copia dei dati, vedi debug.sh)
#   ... debug.ps1 stato "scambia:3:0:pollo" pasto:3      lo stato dell'app in testo (numeri esatti), in pochi secondi
#   ... debug.ps1 giro C:\percorso\cartella [testo]     giro di controllo con giro.txt (testo: solo lo stato)
#   ... debug.ps1 crash                                  gli ultimi crash di Recomp
#   ... debug.ps1 controlli                              i conti dell'app provati sul PC, senza telefono
param([string]$Cosa = '', [string]$Arg = '', [string]$Arg2 = '', [string]$Arg3 = '', [string]$Arg4 = '')
$qui = Split-Path -Parent $MyInvocation.MyCommand.Path
$xtool = Split-Path -Parent $qui
# screenshot e giro salvano dove dici tu, anche con un percorso di Windows: WSL lo vede sotto /mnt/c/…
function Linux([string]$p) { if ($p -match '^[A-Za-z]:\\') { '/mnt/' + $p.Substring(0, 1).ToLower() + ($p.Substring(2) -replace '\\', '/') } else { $p } }
if ($Cosa -eq 'foto' -or $Cosa -eq 'giro') { $Arg = Linux $Arg; $Arg2 = Linux $Arg2 }
if ($Cosa -eq 'controlli') {
    wsl -d Ubuntu -u root --cd $xtool --exec bash ./controlli.sh $Arg
    exit $LASTEXITCODE
}
wsl -d Ubuntu -u root --cd $xtool --exec bash ./debug.sh $Cosa "$Arg" "$Arg2" "$Arg3" "$Arg4"
exit $LASTEXITCODE
