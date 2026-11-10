<#
.SYNOPSIS
  Install or update LiveCues ReaperRemote (LCRR) into REAPER's web interface root and Scripts folder (Windows).
.DESCRIPTION
  Lays every web slice (shared\www, apps\<app>\www) over REAPER's web root: the lcrr*.html entry pages go at the
  top level (REAPER lists only those as "Default interface"), and each lcrr\<part> folder goes under lcrr\.
  Lays every reaper slice (apps\<app>\reaper and shared\reaper, mirrors of REAPER's resource path) over the resource
  path: each Scripts\LCRR\<part> folder goes to <Resource>\Scripts\LCRR\<part>, scripts and their lib\ together.
  The shared Lua lands as Scripts\LCRR\shared, a sibling of the app folders, which the bridge scripts reach by
  adding their parent folder to package.path.
  Each install replaces the whole lcrr\ and Scripts\LCRR\ trees, so a file deleted or renamed in the repo
  disappears from REAPER too. Re-run to update. Run from a PowerShell prompt on the Windows host:
      .\scripts\install.ps1
  The bridges (LCRR_Arrange_Bridge.lua, LCRR_IEM_Bridge.lua, LCRR_Snapshots_Bridge.lua) start with REAPER through one marked line each in
  Scripts\__startup.lua, which install adds (or replaces) and -Uninstall removes; the rest of that file is left alone.
  New Lua scripts must be loaded once in REAPER (Actions > Show action list > New action > Load ReaScript);
  already-loaded ones pick up changes on their next run.
.PARAMETER Root
  REAPER web root. Default: %APPDATA%\REAPER\reaper_www_root, the folder opened by 'User pages...' in REAPER's
  web interface settings. Never use REAPER's Program Files\...\Plugins folder (internal path).
.PARAMETER Resource
  REAPER resource path (Options > Show REAPER resource path in explorer). Default: %APPDATA%\REAPER. A portable
  install keeps it beside reaper.exe. Its Scripts folder must already exist.
.PARAMETER Link
  Symbolic links instead of copies (entry pages as file links, lcrr\<part> and Scripts\LCRR\<part> as folder
  links), so edits show up on browser refresh or the script's next run. Needs Developer Mode or an elevated prompt.
.PARAMETER Uninstall
  Remove the installed lcrr*.html pages, the lcrr folder and Scripts\LCRR. REAPER keeps any Action list entries
  for the removed scripts until you delete them there.
.PARAMETER Port
  The port of REAPER's web interface. Only used to print the URL (default 80, which is left out of the URL).
#>
[CmdletBinding()]
param(
  [string]$Root = (Join-Path $env:APPDATA 'REAPER\reaper_www_root'),
  [string]$Resource = (Join-Path $env:APPDATA 'REAPER'),
  [switch]$Link,
  [switch]$Uninstall,
  [int]$Port = 80
)
$ErrorActionPreference = 'Stop'

$repo = Join-Path $PSScriptRoot '..' | Resolve-Path
$slices = @(Join-Path $repo 'shared\www') + @(Get-ChildItem (Join-Path $repo 'apps') -Directory |
  ForEach-Object { Join-Path $_.FullName 'www' } | Where-Object { Test-Path $_ })
# shared\reaper is the shared Lua (Scripts\LCRR\shared), laid in beside the apps' folders like any other part.
$reaperSlices = @(@(Join-Path $repo 'shared\reaper') + @(Get-ChildItem (Join-Path $repo 'apps') -Directory |
  ForEach-Object { Join-Path $_.FullName 'reaper' }) | Where-Object { Test-Path $_ })
$scripts = Join-Path $Resource 'Scripts'
$scriptsLcrr = Join-Path $scripts 'LCRR'

# A reaper slice may only hold Scripts\LCRR\<part> folders: anything else would land outside what -Uninstall removes.
foreach ($slice in $reaperSlices) {
  Get-ChildItem $slice -Recurse -Depth 2 -Force | ForEach-Object {
    $rel = $_.FullName.Substring($slice.Length + 1)
    $ok = ($rel -eq 'Scripts') -or ($rel -eq 'Scripts\LCRR') -or ($_.PSIsContainer -and $rel -match '^Scripts\\LCRR\\[^\\]+$')
    if (-not $ok) { throw "$slice\$rel`: a reaper slice may only contain Scripts\LCRR\<part> folders" }
  }
}

# A symlink is removed as a link (never recursing into its target); a real file or folder is removed normally.
function Remove-Entry([string]$p) {
  $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
  if (-not $item) { return }
  if ($item.LinkType) { $item.Delete() }
  else { Remove-Item -LiteralPath $p -Recurse -Force }
}

# The bridges (Arrange, IEM Setup, Snapshots) run in the background from REAPER's start (Scripts\__startup.lua). That file may hold
# the user's own lines, so ours are marked lines, one per bridge: each is replaced on every install and removed on
# uninstall, nothing else is touched. __startup.lua cannot just dofile a bridge, because get_action_context() would then
# name __startup.lua and the bridge could not find its lib\; it registers the bridge as an action and runs that (same
# command id each start).
$startupFile = Join-Path $scripts '__startup.lua'
$bridges = @(
  @{ Name = 'Arrange'; Id = 'LCRR-ARRANGE-BRIDGE'; Marker = '-- LCRR-ARRANGE-BRIDGE (managed by install.ps1)'; Script = 'arrange/LCRR_Arrange_Bridge.lua' },
  @{ Name = 'IEM Setup'; Id = 'LCRR-IEM-BRIDGE'; Marker = '-- LCRR-IEM-BRIDGE (managed by install.ps1)'; Script = 'iem/LCRR_IEM_Bridge.lua' },
  @{ Name = 'Snapshots'; Id = 'LCRR-SNAPSHOTS-BRIDGE'; Marker = '-- LCRR-SNAPSHOTS-BRIDGE (managed by install.ps1)'; Script = 'snapshots/LCRR_Snapshots_Bridge.lua' }
)
foreach ($b in $bridges) {
  $b.Line = 'do local p = reaper.GetResourcePath() .. "/Scripts/LCRR/' + $b.Script + '"; ' +
    'local id = reaper.AddRemoveReaScript(true, 0, p, true); if id ~= 0 then reaper.Main_OnCommand(id, 0) end end ' + $b.Marker
}

# Lines are matched by the bridge Id only, so lines written by the ReaPack action "LCRR: Install startup hook"
# (shared/startup/hook.lua, a different marker suffix) are replaced and removed too (test/startup-ids.test.js).
# Present: the bridge's line is (re)written. Absent: it is removed. Other bridges' lines and the user's lines are kept.
function Set-StartupLine($bridge, [bool]$present) {
  $kept = @()
  if (Test-Path -LiteralPath $startupFile) {
    $kept = @(Get-Content -LiteralPath $startupFile | Where-Object { $_ -notlike "*$($bridge.Id)*" })
  }
  if ($present) { $kept += $bridge.Line }
  if ($kept.Count -eq 0) {
    if (Test-Path -LiteralPath $startupFile) { Remove-Item -LiteralPath $startupFile -Force }
    return
  }
  [System.IO.File]::WriteAllText($startupFile, (($kept -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))
}

function Remove-Installed {
  Get-ChildItem $Root -File -Filter 'lcrr*.html' -ErrorAction SilentlyContinue | ForEach-Object { Remove-Entry $_.FullName }
  $lcrr = Join-Path $Root 'lcrr'
  if (Test-Path $lcrr) {
    Get-ChildItem $lcrr -Force | ForEach-Object { Remove-Entry $_.FullName }
    Remove-Entry $lcrr
  }
  if (Test-Path $scriptsLcrr) {
    Get-ChildItem $scriptsLcrr -Force | ForEach-Object { Remove-Entry $_.FullName }
    Remove-Entry $scriptsLcrr
  }
  if (Test-Path -LiteralPath $startupFile) { foreach ($b in $bridges) { Set-StartupLine $b $false } }
}

if ($Uninstall) {
  Remove-Installed
  Write-Host "Removed LiveCues ReaperRemote from $Root and $scriptsLcrr"
  return
}

if (-not (Test-Path $Root)) {
  New-Item -ItemType Directory -Path $Root | Out-Null
  Write-Warning "Created $Root - make sure REAPER's web interface is pointed at this folder."
}

if ($reaperSlices.Count -and -not (Test-Path $scripts)) {
  throw "REAPER Scripts folder not found: $scripts. Pass -Resource with REAPER's resource path."
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

$count = 0
foreach ($slice in $reaperSlices) {
  $parts = Join-Path $slice 'Scripts\LCRR'
  if (-not (Test-Path $parts)) { continue }
  if (-not (Test-Path $scriptsLcrr)) { New-Item -ItemType Directory -Path $scriptsLcrr | Out-Null }
  foreach ($part in Get-ChildItem $parts -Directory) {
    $t = Join-Path $scriptsLcrr $part.Name
    if (Test-Path $t) { throw "Scripts\LCRR\$($part.Name) is shipped by two slices" }
    if ($Link) { New-Item -ItemType SymbolicLink -Path $t -Target $part.FullName | Out-Null }
    else { Copy-Item $part.FullName $t -Recurse }
    $count++
  }
}
if ($count) {
  Write-Host ("{0} {1} script folders into {2}" -f ($(if ($Link) {'Linked'} else {'Copied'}), $count, $scriptsLcrr))
  Write-Host "New scripts: in REAPER, Actions > Show action list > New action > Load ReaScript, from $scriptsLcrr\<app>."
}
foreach ($b in $bridges) {
  if (Test-Path -LiteralPath (Join-Path $scriptsLcrr ($b.Script -replace '/', '\'))) {
    Set-StartupLine $b $true
    Write-Host "$($b.Name) bridge: starts with REAPER (marked line in $startupFile). Restart REAPER, or run $(Split-Path -Leaf $b.Script) once from the Action list."
  }
}

$ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
  Select-Object -ExpandProperty IPAddress
$portPart = if ($Port -eq 80) { '' } else { ":$Port" }
Write-Host "`nOpen:"
Write-Host "  http://localhost$portPart/"
foreach ($ip in $ips) { Write-Host "  http://$ip$portPart/" }
Write-Host "`nREAPER must have the web interface enabled on port $Port (see README), with lcrr.html as the Default interface."
if ($Port -ne 80) { Write-Host "Printed for port $Port. If your REAPER web interface uses another port, add it to the URL or re-run with -Port." }
else { Write-Host "Printed for port 80. If your REAPER web interface uses another port, add it to the URL (for example :8080) or re-run with -Port." }
