# Una tantum (e dopo un riavvio del PC, se l'iPhone non si raggiunge più): apre alla rete di WSL la porta 27015
# del servizio Apple di Windows (quello dell'app «Apple Devices»), così Linux parla con l'iPhone attraverso Windows.
# Serve il permesso di amministratore: se non ce l'hai, lo script si rilancia e Windows chiede conferma.
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    exit
}
$alias = 'vEthernet (WSL (Hyper-V firewall))'
$ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias $alias).IPAddress
Write-Host "Indirizzo di Windows visto da Linux: $ip"
if (-not (Get-NetFirewallRule -DisplayName 'WSL iPhone 27015' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'WSL iPhone 27015' -Direction Inbound -InterfaceAlias $alias -Protocol TCP -LocalPort 27015 -Action Allow | Out-Null
}
netsh interface portproxy delete v4tov4 listenport=27015 listenaddress=$ip 2>$null | Out-Null
netsh interface portproxy add v4tov4 listenport=27015 listenaddress=$ip connectaddress=127.0.0.1 connectport=27015
Write-Host ''
netsh interface portproxy show v4tov4
Write-Host ''
Read-Host 'Fatto: premi Invio per chiudere'
