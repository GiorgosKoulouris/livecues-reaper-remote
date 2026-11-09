<#
.SYNOPSIS
  Install or update LiveCues ReaperRemote (LCRR) into REAPER's web interface root (Windows).
.DESCRIPTION
  Lays every slice (shared\www, apps\<app>\www) over REAPER's web root: the lcrr*.html entry pages go at the
  top level (REAPER lists only those as "Default interface"), and each lcrr\<part> folder goes under lcrr\.
  Re-run to update. Run from a PowerShell prompt on the Windows host, from any location:
      .\scripts\install.ps1
.PARAMETER Root
  REAPER web root. Default: %APPDATA%\REAPER\reaper_www_root, the folder opened by 'User pages...' in REAPER's
  web interface settings. Never use REAPER's Program Files\...\Plugins folder (internal path).
.PARAMETER Link
  Symbolic links instead of copies (entry pages as file links, lcrr\<part> as folder links), so edits show up
  on browser refresh. Needs Developer Mode or an elevated prompt.
.PARAMETER Uninstall
  Remove the installed lcrr*.html pages and the lcrr folder.
.PARAMETER Port
  Only used to print the URL (default 8080).
#>
[CmdletBinding()]
param(
  [string]$Root = (Join-Path $env:APPDATA 'REAPER\reaper_www_root'),
  [switch]$Link,
  [switch]$Uninstall,
  [int]$Port = 8080
)
$ErrorActionPreference = 'Stop'

$repo = Join-Path $PSScriptRoot '..' | Resolve-Path
$slices = @(Join-Path $repo 'shared\www') + @(Get-ChildItem (Join-Path $repo 'apps') -Directory |
  ForEach-Object { Join-Path $_.FullName 'www' } | Where-Object { Test-Path $_ })

# A symlink is removed as a link (never recursing into its target); a real file or folder is removed normally.
function Remove-Entry([string]$p) {
  $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
  if (-not $item) { return }
  if ($item.LinkType) { $item.Delete() }
  else { Remove-Item -LiteralPath $p -Recurse -Force }
}

function Remove-Installed {
  Get-ChildItem $Root -File -Filter 'lcrr*.html' -ErrorAction SilentlyContinue | ForEach-Object { Remove-Entry $_.FullName }
  $lcrr = Join-Path $Root 'lcrr'
  if (Test-Path $lcrr) {
    Get-ChildItem $lcrr -Force | ForEach-Object { Remove-Entry $_.FullName }
    Remove-Entry $lcrr
  }
}

if ($Uninstall) {
  Remove-Installed
  Write-Host "Removed LiveCues ReaperRemote from $Root"
  return
}

if (-not (Test-Path $Root)) {
  New-Item -ItemType Directory -Path $Root | Out-Null
  Write-Warning "Created $Root - make sure REAPER's web interface is pointed at this folder."
}

Remove-Installed
New-Item -ItemType Directory -Path (Join-Path $Root 'lcrr') | Out-Null
$count = 0
foreach ($slice in $slices) {
  foreach ($page in Get-ChildItem $slice -File -Filter 'lcrr*.html') {
    $t = Join-Path $Root $page.Name
    if ($Link) { New-Item -ItemType SymbolicLink -Path $t -Target $page.FullName | Out-Null }
    else { Copy-Item $page.FullName $t }
    $count++
  }
  $parts = Join-Path $slice 'lcrr'
  if (-not (Test-Path $parts)) { continue }
  foreach ($part in Get-ChildItem $parts -Directory) {
    $t = Join-Path $Root "lcrr\$($part.Name)"
    if (Test-Path $t) { throw "lcrr\$($part.Name) is shipped by two slices" }
    if ($Link) { New-Item -ItemType SymbolicLink -Path $t -Target $part.FullName | Out-Null }
    else { Copy-Item $part.FullName $t -Recurse }
    $count++
  }
}
Write-Host ("{0} {1} entries into {2}" -f ($(if ($Link) {'Linked'} else {'Copied'}), $count, $Root))

$ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
  Select-Object -ExpandProperty IPAddress
Write-Host "`nOpen:"
Write-Host "  http://localhost:$Port/lcrr.html"
foreach ($ip in $ips) { Write-Host "  http://${ip}:$Port/lcrr.html" }
Write-Host "`nREAPER must have the web interface enabled on port $Port (see README). Pick lcrr.html as the Default interface."
