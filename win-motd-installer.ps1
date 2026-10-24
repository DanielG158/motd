# ============================================================
#   RDP Warning Banner + Login Info Installer - Windows
#   Pakai (PowerShell sebagai Administrator):
#   irm https://raw.githubusercontent.com/DanielG158/motd/main/win-motd-installer.ps1 | iex
#   Uninstall: $env:RDP_MOTD_UNINSTALL=1; irm ... | iex
# ============================================================
& {
$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host 'Jalankan PowerShell sebagai Administrator.' -ForegroundColor Red; return }

$Dir    = "$env:ProgramData\rdp-motd"
$Script = "$Dir\motd.ps1"
$PolKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$RunKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'

# ── Uninstall ───────────────────────────────────────────────
if ($env:RDP_MOTD_UNINSTALL) {
    Remove-ItemProperty -Path $RunKey -Name 'RdpMotd' -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $PolKey -Name LegalNoticeCaption -Value ''
    Set-ItemProperty -Path $PolKey -Name LegalNoticeText -Value ''
    Remove-Item $Dir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\RDP_MOTD_UNINSTALL
    Write-Host 'RDP MOTD dihapus.' -ForegroundColor Green
    return
}

New-Item -ItemType Directory -Force -Path $Dir | Out-Null

# ── 1. Banner sebelum login (Legal Notice) ──────────────────
Set-ItemProperty -Path $PolKey -Name LegalNoticeCaption -Value '!! WINDOWS SERVER - PRIVATE !!'
Set-ItemProperty -Path $PolKey -Name LegalNoticeText -Value (
    'WARNING: This is a PRIVATE Windows host. ' +
    'Your IP address and location are recorded upon connection. ' +
    'All activity is monitored, logged, and may be reported to authorities. ' +
    'If you are not an authorized user, DISCONNECT NOW.')
Write-Host 'Legal notice (banner pre-login) terpasang.' -ForegroundColor Green

# ── 2. Popup info login setelah masuk RDP ───────────────────
$body = @'
$ErrorActionPreference = 'SilentlyContinue'
# Hanya untuk sesi RDP, bukan login konsol
if ($env:SESSIONNAME -notlike 'RDP-Tcp*') { return }

$me  = $env:USERNAME
$sid = (Get-Process -Id $PID).SessionId

# IP asal: event 21 (logon) / 25 (reconnect) dari Remote Desktop Services
$ip = 'Unknown'
$lsm = Get-WinEvent -LogName 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational' -MaxEvents 50 |
       Where-Object { $_.Id -in 21,25 }
foreach ($e in $lsm) {
    $x = [xml]$e.ToXml()
    $u = $x.Event.UserData.EventXML.User
    $s = $x.Event.UserData.EventXML.SessionID
    if ($u -like "*\$me" -and [int]$s -eq $sid) { $ip = $x.Event.UserData.EventXML.Address; break }
}

$city='N/A'; $region='N/A'; $country='N/A'; $isp='N/A'
if ($ip -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|127\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.|::1$|fe80:|f[cd]|LOCAL)') {
    $city = '(private network)'
} elseif ($ip -ne 'Unknown') {
    try {
        $j = Invoke-RestMethod -Uri "https://ipapi.co/$ip/json/" -TimeoutSec 3 -UseBasicParsing
        if (-not $j.error) {
            if ($j.city) { $city = $j.city }; if ($j.region) { $region = $j.region }
            if ($j.country_name) { $country = $j.country_name }; if ($j.org) { $isp = $j.org }
        }
    } catch {}
}

# Riwayat dari Security log (butuh hak admin)
$last = 'N/A'; $failed = '(admin only)'; $lastFail = '(admin only)'
try {
    $xp = "*[System[EventID=4624] and EventData[Data[@Name='LogonType']='10' and Data[@Name='TargetUserName']='$me']]"
    $ok = Get-WinEvent -LogName Security -FilterXPath $xp -MaxEvents 2 -ErrorAction Stop | Select-Object -Skip 1 -First 1
    if ($ok) {
        $a = ([xml]$ok.ToXml()).Event.EventData.Data | Where-Object Name -eq 'IpAddress'
        $last = "{0:yyyy-MM-dd HH:mm} from {1}" -f $ok.TimeCreated, $a.'#text'
    }
    $since = [int]((Get-Date) - (Get-Date).AddDays(-1)).TotalMilliseconds
    $bad = @(Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4625 and TimeCreated[timediff(@SystemTime) <= $since]]]" -ErrorAction SilentlyContinue)
    $failed = "$($bad.Count) in last 24h"
    $lastFail = 'None'
    if ($bad.Count -gt 0) {
        $d = ([xml]$bad[0].ToXml()).Event.EventData.Data
        $lastFail = "{0:yyyy-MM-dd HH:mm} {1} from {2}" -f $bad[0].TimeCreated,
            ($d | Where-Object Name -eq 'TargetUserName').'#text', ($d | Where-Object Name -eq 'IpAddress').'#text'
    }
} catch {}

$os = Get-CimInstance Win32_OperatingSystem
$up = (Get-Date) - $os.LastBootUpTime

$W = 58; $out = New-Object System.Text.StringBuilder
function L($label, $val) { $s = "$label$val"; if ($s.Length -gt $W) { $s = $s.Substring(0,$W) }; [void]$out.AppendLine("║  " + $s.PadRight($W) + " ║") }
function C($t) { $l = [int](($W - $t.Length)/2); [void]$out.AppendLine("║  " + (' ' * $l) + $t.PadRight($W - $l) + " ║") }
function S { [void]$out.AppendLine("╠" + ('═' * 62) + "╣") }

[void]$out.AppendLine("╔" + ('═' * 62) + "╗")
C "!! WINDOWS SERVER - PRIVATE !!"; S
L "Host:       " $env:COMPUTERNAME
L "User:       " "$env:USERDOMAIN\$me"
L "Date:       " (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
L "Uptime:     " ("{0} days, {1} hours, {2} minutes" -f $up.Days, $up.Hours, $up.Minutes)
L "OS:         " $os.Caption
S; C "-- Login Details --"; S
L "From IP:    " $ip
L "Client:     " $env:CLIENTNAME
L "City:       " $city
L "Region:     " $region
L "Country:    " $country
L "ISP:        " $isp
S; C "-- Session History --"; S
L "Last Login:       " $last
L "Failed Attempts:  " $failed
L "Last Failed:      " $lastFail
S
L "" "Unauthorized access is strictly prohibited."
L "" "All sessions are monitored and logged."
[void]$out.Append("╚" + ('═' * 62) + "╝")

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$f = New-Object Windows.Forms.Form
$f.Text = 'Login Information'; $f.StartPosition = 'CenterScreen'; $f.TopMost = $true
$f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
$f.BackColor = [Drawing.Color]::Black
$t = New-Object Windows.Forms.TextBox
$t.Multiline = $true; $t.ReadOnly = $true; $t.BorderStyle = 'None'
$t.Font = New-Object Drawing.Font('Consolas', 10); $t.Text = $out.ToString()
$t.BackColor = [Drawing.Color]::Black; $t.ForeColor = [Drawing.Color]::LightGreen
$size = [Windows.Forms.TextRenderer]::MeasureText($t.Text, $t.Font)
$t.SetBounds(12, 12, $size.Width + 10, $size.Height + 6)
$b = New-Object Windows.Forms.Button
$b.Text = 'OK'; $b.ForeColor = [Drawing.Color]::White; $b.SetBounds(($size.Width / 2) - 30, $size.Height + 28, 80, 28)
$b.Add_Click({ $f.Close() }); $f.AcceptButton = $b
$f.Controls.AddRange(@($t, $b))
$f.ClientSize = New-Object Drawing.Size(($size.Width + 34), ($size.Height + 70))
$f.Add_Shown({ $b.Focus() })
[void]$f.ShowDialog()
'@
Set-Content -Path $Script -Value $body -Encoding UTF8

# Jalankan otomatis saat logon semua user (script sendiri mengecek apakah sesi RDP)
Set-ItemProperty -Path $RunKey -Name 'RdpMotd' -Value (
    "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Script`"")
Write-Host 'Popup login RDP terpasang.' -ForegroundColor Green

# Cek audit logon gagal (supaya event 4625 tercatat)
$aud = (auditpol /get /subcategory:"{0CCE9215-69AE-11D9-BED3-505054503030}" 2>$null) -join ' '
if ($aud -notmatch 'Failure') {
    Write-Host "Audit 'Logon' Failure belum aktif. Aktifkan dengan:" -ForegroundColor Yellow
    Write-Host '  auditpol /set /subcategory:"{0CCE9215-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable'
}

Write-Host "`nSelesai. Tes popup sekarang: powershell -ExecutionPolicy Bypass -File `"$Script`" (dari sesi RDP)" -ForegroundColor Green
}
