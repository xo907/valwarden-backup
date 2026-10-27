@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ==========================================================================
rem  run.bat - Bitwarden / Vaultwarden automated backup helper  (v2)
rem
rem  Double-click for the menu, or run unattended:
rem      run.bat /backup              back up all active accounts
rem      run.bat /backup NICKNAME    back up one account
rem      run.bat /setup               open the configuration menu
rem  Exit codes: 0 = OK, 1 = some exports failed, 2 = configuration/fatal error
rem
rem  Folder layout (created next to this file):
rem      bin\       Bitwarden CLI (bw.exe), downloaded and verified automatically
rem      scripts\   PowerShell scripts, extracted from the bottom of this file
rem      config\    settings.json (destinations, retention, file names, ...)
rem                 vault_accounts.json (accounts; secrets encrypted with DPAPI)
rem      data\      per-account Bitwarden CLI state (keep this folder private)
rem      logs\      backup.log, setup.log, tasks.log, last_run.json
rem
rem  This file must keep Windows (CRLF) line endings.
rem ==========================================================================

title Vaultwarden Backup
set "SELF=%~f0"
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "SCRIPTS=%ROOT%\scripts"
set "LOGS=%ROOT%\logs"
set "LOGFILE=%LOGS%\launcher.log"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"

if not exist "%SCRIPTS%" md "%SCRIPTS%"
if not exist "%LOGS%" md "%LOGS%"
call :Log "===== run.bat started ====="

call :ExtractScripts
if errorlevel 1 goto FATAL_EXTRACT

if /I "%~1"=="/backup" goto CLI_BACKUP
if /I "%~1"=="/setup" goto CLI_SETUP

call :EnsureBw
if errorlevel 1 pause
call :CheckVbs
goto MAINMENU

rem --------------------------------------------------------------------------
rem  Unattended entry points
rem --------------------------------------------------------------------------
:CLI_BACKUP
call :EnsureBw || exit /b 2
if "%~2"=="" (
  call :Ps bitwarden_backup_all.ps1
) else (
  call :Ps bitwarden_backup_all.ps1 -Account "%~2"
)
exit /b %errorlevel%

:CLI_SETUP
call :EnsureBw
call :Ps bitwarden_backup_setup.ps1
exit /b %errorlevel%

:FATAL_EXTRACT
echo.
echo [ERROR] Could not extract the helper scripts into the scripts folder.
echo         Make sure this folder is writable and that run.bat is not damaged.
call :Log "ERROR: script extraction failed."
if /I not "%~1"=="/backup" pause
exit /b 2

rem --------------------------------------------------------------------------
rem  Main menu
rem --------------------------------------------------------------------------
:MAINMENU
cls
echo ==========================================
echo   Bitwarden / Vaultwarden Backup Helper
echo ==========================================
if defined VBSWARN (
  echo.
  echo   WARNING: the scheduled-task runner script is broken - a bug in the
  echo   previous version overwrote it - so scheduled backups are NOT running.
  echo   Re-create the task: option 5, then pick a schedule.
)
echo.
echo   1^) Configure accounts, organizations, destinations ^& settings
echo   2^) Run backup now ^(all active accounts^)
echo   3^) Run backup for one account
echo   4^) View last backup result
echo   5^) Scheduler ^(create / view / run / remove task^)
echo   6^) Install / update Bitwarden CLI
echo   7^) Open logs folder
echo   8^) Exit
echo.
choice /C 12345678 /N /M "Choose an option [1-8]: "
set "SEL=%errorlevel%"
if "%SEL%"=="1" goto DO_SETUP
if "%SEL%"=="2" goto DO_RUN
if "%SEL%"=="3" goto DO_RUN_ONE
if "%SEL%"=="4" goto DO_STATUS
if "%SEL%"=="5" goto SCHEDMENU
if "%SEL%"=="6" goto DO_UPDATE
if "%SEL%"=="7" goto DO_LOGS
if "%SEL%"=="8" goto END
goto MAINMENU

:DO_SETUP
call :Log "Menu: setup"
call :Ps bitwarden_backup_setup.ps1
goto MAINMENU

:DO_RUN
cls
call :Log "Menu: run backup (all)"
call :EnsureBw || goto PAUSE_MENU
call :Ps bitwarden_backup_all.ps1
call :ShowResult
goto PAUSE_MENU

:DO_RUN_ONE
cls
call :Log "Menu: run backup (one account)"
call :EnsureBw || goto PAUSE_MENU
call :Ps bitwarden_backup_all.ps1 -SelectAccount
call :ShowResult
goto PAUSE_MENU

:DO_STATUS
cls
call :Ps bitwarden_backup_all.ps1 -ShowLastRun
goto PAUSE_MENU

:DO_UPDATE
cls
call :Log "Menu: install/update bw"
call :Ps install_bw.ps1 -Update
goto PAUSE_MENU

:DO_LOGS
start "" "%LOGS%"
goto MAINMENU

:PAUSE_MENU
echo.
pause
goto MAINMENU

rem --------------------------------------------------------------------------
rem  Scheduler menu
rem --------------------------------------------------------------------------
:SCHEDMENU
cls
set "TASKARGS="
echo ==========================================
echo   Scheduler
echo ==========================================
echo.
echo   Create or replace the scheduled task:
echo     1^) Every hour
echo     2^) Every 30 minutes
echo     3^) Every N minutes ^(you choose^)
echo     4^) Once a day at a set time
echo     5^) Every minute ^(testing only^)
echo.
echo     6^) View task status
echo     7^) Run the task now
echo     8^) Remove the task
echo     9^) Back
echo.
choice /C 123456789 /N /M "Choose an option [1-9]: "
set "SEL=%errorlevel%"
if "%SEL%"=="1" set "TASKARGS=-Action Create -Schedule Interval -Minutes 60"
if "%SEL%"=="2" set "TASKARGS=-Action Create -Schedule Interval -Minutes 30"
if "%SEL%"=="3" set "TASKARGS=-Action Create -Schedule Interval -Minutes 0"
if "%SEL%"=="4" set "TASKARGS=-Action Create -Schedule Daily"
if "%SEL%"=="5" set "TASKARGS=-Action Create -Schedule Interval -Minutes 1"
if "%SEL%"=="6" set "TASKARGS=-Action View"
if "%SEL%"=="7" set "TASKARGS=-Action Run"
if "%SEL%"=="8" set "TASKARGS=-Action Remove"
if "%SEL%"=="9" goto MAINMENU
if not defined TASKARGS goto SCHEDMENU
echo.
call :Log "Scheduler: %TASKARGS%"
call :Ps bitwarden_tasks.ps1 %TASKARGS%
if %SEL% LEQ 5 call :CheckVbs
echo.
pause
goto SCHEDMENU

:END
call :Log "Exiting."
endlocal
exit /b 0

rem --------------------------------------------------------------------------
rem  Helpers
rem --------------------------------------------------------------------------

:Ps
rem Usage: call :Ps script.ps1 [args]. Runs one of the extracted PowerShell scripts and returns its exit code.
set "PSFILE=%~1"
shift
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\%PSFILE%" %1 %2 %3 %4 %5 %6 %7 %8
exit /b %errorlevel%

:ShowResult
set "RC=%errorlevel%"
echo.
if "%RC%"=="0" echo [OK] Backup finished successfully.
if "%RC%"=="1" echo [WARNING] Some exports failed. Details are above and in logs\backup.log
if %RC% GEQ 2 echo [ERROR] Backup could not run - exit code %RC%. See logs\backup.log
call :Log "Backup finished with exit code %RC%."
exit /b %RC%

:EnsureBw
if exist "%ROOT%\bin\bw.exe" exit /b 0
call :Log "Bitwarden CLI not found; installing."
echo Bitwarden CLI not found - downloading it now...
call :Ps install_bw.ps1
if errorlevel 1 goto EnsureBwFailed
exit /b 0
:EnsureBwFailed
call :Log "ERROR: Bitwarden CLI install failed."
echo.
echo [ERROR] Could not install the Bitwarden CLI. See logs\setup.log
echo         You can retry from the main menu, option 6.
exit /b 1

:CheckVbs
rem Detects the empty runner stub that the previous version wrote on every start.
set "VBSWARN="
if not exist "%SCRIPTS%\run_bitwarden_backup_all.vbs" exit /b 0
type "%SCRIPTS%\run_bitwarden_backup_all.vbs" | find /I "shell.Run" >nul || set "VBSWARN=1"
exit /b 0

:Log
>>"%LOGFILE%" echo [%date% %time%] %~1
exit /b 0

:ExtractScripts
rem Writes each #BEGIN_SCRIPT block below to scripts\, only when the content changed.
set "VWB_SELF=%SELF%"
set "VWB_DIR=%SCRIPTS%"
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $map=@{'COMMON'='bw_common.ps1';'BACKUP'='bitwarden_backup_all.ps1';'SETUP'='bitwarden_backup_setup.ps1';'TASKS'='bitwarden_tasks.ps1';'INSTALL'='install_bw.ps1'}; $enc=New-Object Text.UTF8Encoding($true); $cur=$null; $buf=$null; $seen=@{}; foreach($l in [IO.File]::ReadAllLines($env:VWB_SELF)){ $t=$l.Trim(); if($t.StartsWith('#BEGIN_SCRIPT ')){ $cur=$t.Substring(14).Trim(); $buf=New-Object Collections.Generic.List[string]; continue }; if($t -eq '#END_SCRIPT'){ if($cur -and $map.ContainsKey($cur)){ $p=Join-Path $env:VWB_DIR $map[$cur]; $new=($buf -join [Environment]::NewLine)+[Environment]::NewLine; $old=$null; if(Test-Path -LiteralPath $p){ $old=[IO.File]::ReadAllText($p) }; if($old -cne $new){ [IO.File]::WriteAllText($p,$new,$enc); Write-Host ('  updated scripts\'+$map[$cur]) }; $seen[$cur]=1 }; $cur=$null; continue }; if($null -ne $cur){ $buf.Add($l) } }; foreach($k in $map.Keys){ if(-not $seen.ContainsKey($k)){ throw ('embedded script missing: '+$k) } } } catch { Write-Host ('Extraction failed: '+$_.Exception.Message) -ForegroundColor Red; exit 1 }"
exit /b %errorlevel%

rem ==========================================================================
rem  Embedded PowerShell scripts. Never executed by cmd: everything above
rem  exits before reaching this point.
rem ==========================================================================
goto :EOF

#BEGIN_SCRIPT COMMON
# bw_common.ps1 - shared helpers, dot-sourced by the other scripts.
# Generated by run.bat. Edit run.bat instead: this file is rewritten when it differs.

$script:Root         = Split-Path $PSScriptRoot -Parent
$script:BinDir       = Join-Path $script:Root 'bin'
$script:BwPath       = Join-Path $script:BinDir 'bw.exe'
$script:ScriptsDir   = Join-Path $script:Root 'scripts'
$script:ConfigDir    = Join-Path $script:Root 'config'
$script:AccountsPath = Join-Path $script:ConfigDir 'vault_accounts.json'
$script:SettingsPath = Join-Path $script:ConfigDir 'settings.json'
$script:LogsDir      = Join-Path $script:Root 'logs'
$script:DataDir      = Join-Path $script:Root 'data'
$script:WorkDir      = Join-Path $script:Root 'work'
$script:StatusPath   = Join-Path $script:LogsDir 'last_run.json'
if (-not (Get-Variable -Name LogFile -Scope Script -ErrorAction SilentlyContinue)) { $script:LogFile = $null }

# Windows PowerShell 5.1 quirk: without this, ConvertTo-Json can emit arrays as {"value":[...],"Count":n}.
Remove-TypeData -TypeName System.Array -ErrorAction SilentlyContinue

function Initialize-Dirs {
  New-Item -ItemType Directory -Force -Path $script:ConfigDir, $script:LogsDir, $script:DataDir, $script:WorkDir | Out-Null
}

# ------------------------------------------------------------------ logging

function Write-Log {
  param([string]$Message = '', [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')][string]$Level = 'INFO')
  if ($Message -eq '') { Write-Host ''; return }
  $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level.PadRight(5), $Message
  $color = switch ($Level) { 'WARN' { 'Yellow' } 'ERROR' { 'Red' } 'OK' { 'Green' } default { 'Gray' } }
  Write-Host $line -ForegroundColor $color
  if ($script:LogFile) {
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { }
  }
}

function Invoke-LogRotation {
  param([string]$Path, [double]$MaxMB = 5, [int]$Keep = 5)
  try {
    if ($MaxMB -le 0 -or -not (Test-Path -LiteralPath $Path)) { return }
    if ((Get-Item -LiteralPath $Path).Length -lt ($MaxMB * 1MB)) { return }
    if ($Keep -lt 1) { $Keep = 1 }
    Remove-Item -LiteralPath "$Path.$Keep" -Force -ErrorAction SilentlyContinue
    for ($i = $Keep - 1; $i -ge 1; $i--) {
      if (Test-Path -LiteralPath "$Path.$i") { Move-Item -LiteralPath "$Path.$i" -Destination "$Path.$($i + 1)" -Force }
    }
    Move-Item -LiteralPath $Path -Destination "$Path.1" -Force
  } catch { }
}

# ------------------------------------------------------------------ object helpers

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $p = $Object.PSObject.Properties[$Name]
  if ($null -eq $p -or $null -eq $p.Value) { return $Default }
  return $p.Value
}

function Set-Prop {
  # Sets or adds a property without wrapping arrays (Add-Member wrapping makes Windows
  # PowerShell 5.1 serialize arrays as {"value":[...],"Count":n}).
  param($Object, [string]$Name, $Value)
  $p = $Object.PSObject.Properties[$Name]
  if ($p) { $p.Value = $Value }
  else { $Object.PSObject.Properties.Add([Management.Automation.PSNoteProperty]::new($Name, $Value)) }
}

function Test-IsObject($Value) {
  return ($null -ne $Value) -and ($Value -is [System.Management.Automation.PSCustomObject])
}

function Merge-Defaults {
  # Fills in any setting missing from $Target (recursively) without touching what is there.
  param($Target, $Defaults)
  foreach ($p in $Defaults.PSObject.Properties) {
    $cur = $Target.PSObject.Properties[$p.Name]
    if ($null -eq $cur -or $null -eq $cur.Value) {
      Set-Prop $Target $p.Name $p.Value
    } elseif ((Test-IsObject $p.Value) -and (Test-IsObject $cur.Value)) {
      Merge-Defaults $cur.Value $p.Value
    }
  }
}

function ConvertTo-SafeName {
  param([string]$Text, [string]$Fallback = 'item')
  if ($null -eq $Text) { $Text = '' }
  $t = ($Text.Trim() -replace '\s+', '_') -replace '[^\w\-\.]', ''
  $t = $t.Trim([char[]]'._-')
  if ([string]::IsNullOrWhiteSpace($t)) { return $Fallback }
  return $t
}

function Get-ShortId([string]$Id) {
  if ([string]::IsNullOrEmpty($Id)) { return 'unknown' }
  if ($Id.Length -gt 8) { return $Id.Substring(0, 8) }
  return $Id
}

function Normalize-Url([string]$Url) {
  if ([string]::IsNullOrWhiteSpace($Url)) { return '' }
  return $Url.Trim().TrimEnd('/')
}

# ------------------------------------------------------------------ secrets (Windows DPAPI, current user)

function Unprotect-Secret([string]$Blob) {
  if ([string]::IsNullOrWhiteSpace($Blob)) { return '' }
  $ss = ConvertTo-SecureString $Blob
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# ------------------------------------------------------------------ JSON files

function Read-JsonFile([string]$Path) {
  $raw = [IO.File]::ReadAllText($Path)
  if ([string]::IsNullOrWhiteSpace($raw)) { throw "File is empty: $Path" }
  return ($raw | ConvertFrom-Json)
}

function Save-JsonFile {
  # Atomic-ish save that keeps the previous version as .bak
  param([string]$Path, $Object)
  $json = $Object | ConvertTo-Json -Depth 12
  $tmp = "$Path.tmp"
  [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
  if (Test-Path -LiteralPath $Path) { Copy-Item -LiteralPath $Path -Destination "$Path.bak" -Force }
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# ------------------------------------------------------------------ settings

function Get-DefaultSettings {
  [pscustomobject]@{
    version                = 2
    destinations           = @(
      [pscustomobject]@{
        name        = 'local'
        path        = 'exports'
        enabled     = $true
        optional    = $false
        writeLatest = $true
        keepLast    = 24
        keepDaily   = 14
        keepWeekly  = 8
        keepMonthly = 12
      }
    )
    fileNameTemplate       = '{account}\{account}-{scope}-{timestamp}.json'
    latestFileNameTemplate = '{account}-{scope}-latest.json'
    timestampFormat        = 'yyyy-MM-dd_HHmmss'
    exportFormat           = 'password'
    sessionMode            = 'logout'
    timeouts               = [pscustomobject]@{ login = 120; unlock = 90; sync = 300; export = 900; other = 60 }
    log                    = [pscustomobject]@{ maxSizeMB = 5; keepFiles = 5 }
    task                   = [pscustomobject]@{ name = 'BitwardenVaultBackup'; runner = 'auto'; requireNetwork = $true; executionLimitMinutes = 120 }
  }
}

function Test-Settings {
  param($Settings)
  $errors = New-Object System.Collections.Generic.List[string]
  $names = @{}
  foreach ($d in @(Get-Prop $Settings 'destinations' @())) {
    $n = [string](Get-Prop $d 'name' '')
    if ([string]::IsNullOrWhiteSpace($n)) { $errors.Add('A destination has no name.'); continue }
    if ($names.ContainsKey($n.ToLower())) { $errors.Add("Duplicate destination name '$n'.") }
    $names[$n.ToLower()] = $true
    if ([string]::IsNullOrWhiteSpace([string](Get-Prop $d 'path' ''))) { $errors.Add("Destination '$n' has no path.") }
    foreach ($k in 'keepLast', 'keepDaily', 'keepWeekly', 'keepMonthly') {
      $v = Get-Prop $d $k 0
      if (-not ($v -is [int] -or $v -is [long]) -or $v -lt 0) { $errors.Add("Destination '$n': $k must be a whole number >= 0.") }
    }
  }
  foreach ($k in 'fileNameTemplate', 'latestFileNameTemplate') {
    $problem = Test-FileTemplate ([string](Get-Prop $Settings $k '')) -AllowTimeTokens:($k -eq 'fileNameTemplate')
    if ($problem) { $errors.Add("${k}: $problem") }
  }
  $fmt = [string](Get-Prop $Settings 'timestampFormat' '')
  try {
    $sample = (Get-Date).ToString($fmt)
    if ([string]::IsNullOrWhiteSpace($fmt) -or $sample.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $sample.Contains(':')) {
      $errors.Add("timestampFormat '$fmt' produces characters that are not allowed in file names.")
    }
  } catch { $errors.Add("timestampFormat '$fmt' is not a valid .NET date format.") }
  if (@('password', 'account') -notcontains [string](Get-Prop $Settings 'exportFormat' '')) { $errors.Add("exportFormat must be 'password' or 'account'.") }
  if (@('logout', 'lock') -notcontains [string](Get-Prop $Settings 'sessionMode' '')) { $errors.Add("sessionMode must be 'logout' or 'lock'.") }
  if (@('auto', 'vbs', 'conhost', 'powershell') -notcontains [string](Get-Prop (Get-Prop $Settings 'task') 'runner' '')) { $errors.Add("task.runner must be auto, vbs, conhost or powershell.") }
  foreach ($p in (Get-Prop $Settings 'timeouts').PSObject.Properties) {
    if (-not ($p.Value -is [int] -or $p.Value -is [long]) -or $p.Value -lt 5) { $errors.Add("timeouts.$($p.Name) must be a whole number of seconds >= 5.") }
  }
  return , $errors.ToArray()
}

function Load-Settings {
  if (-not (Test-Path -LiteralPath $script:SettingsPath)) {
    $s = Get-DefaultSettings
    Save-JsonFile $script:SettingsPath $s
    return $s
  }
  try { $s = Read-JsonFile $script:SettingsPath }
  catch { throw "settings.json could not be parsed: $($_.Exception.Message)" }
  Merge-Defaults $s (Get-DefaultSettings)
  Set-Prop $s 'destinations' @(Get-Prop $s 'destinations' @())
  $errors = Test-Settings $s
  if ($errors.Count -gt 0) { throw ("settings.json has problems:`n  - " + ($errors -join "`n  - ")) }
  return $s
}

function Save-Settings($Settings) { Save-JsonFile $script:SettingsPath $Settings }

# ------------------------------------------------------------------ accounts

function Load-AccountStore {
  if (-not (Test-Path -LiteralPath $script:AccountsPath)) {
    return [pscustomobject]@{ version = 2; accounts = @() }
  }
  try { $store = Read-JsonFile $script:AccountsPath }
  catch { throw "vault_accounts.json could not be parsed: $($_.Exception.Message)" }

  $changed = $false
  $accounts = @(Get-Prop $store 'accounts' @())
  foreach ($a in $accounts) {
    # Migrate older (v1) account entries in place.
    if (-not (Get-Prop $a 'id')) { Set-Prop $a 'id' ([guid]::NewGuid().ToString('N')); $changed = $true }
    if (-not (Get-Prop $a 'authMethod')) { Set-Prop $a 'authMethod' 'password'; $changed = $true }
    if ($null -eq (Get-Prop $a 'includePersonal')) { Set-Prop $a 'includePersonal' $true; $changed = $true }
    if ($null -eq (Get-Prop $a 'frozen')) { Set-Prop $a 'frozen' $false; $changed = $true }
    Set-Prop $a 'organizations' @(Get-Prop $a 'organizations' @())
    Set-Prop $a 'destinations' @(Get-Prop $a 'destinations' @())
  }
  Set-Prop $store 'accounts' $accounts
  if ((Get-Prop $store 'version' 1) -lt 2) { Set-Prop $store 'version' 2; $changed = $true }
  if ($changed) { Save-AccountStore $store }
  return $store
}

function Save-AccountStore($Store) { Save-JsonFile $script:AccountsPath $Store }

function Get-AccountDataDir($Account) {
  $d = Join-Path $script:DataDir ('bw\' + (Get-Prop $Account 'id' 'default'))
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}

function Get-OrgScopes {
  # Returns one entry per enabled organization with a unique, file-name-safe scope name.
  param($Account)
  $orgs = @(Get-Prop $Account 'organizations' @() | Where-Object { $_ -and (Get-Prop $_ 'id') -and (Get-Prop $_ 'enabled' $true) })
  $result = @()
  $seen = @{}
  foreach ($o in $orgs) {
    $id = [string]$o.id
    $label = [string](Get-Prop $o 'name' $id)
    $scope = 'org-' + (ConvertTo-SafeName $label ('org_' + (Get-ShortId $id))).ToLower()
    if ($seen.ContainsKey($scope)) { $scope = $scope + '-' + (Get-ShortId $id) }
    $seen[$scope] = $true
    $result += [pscustomobject]@{ Id = $id; Name = $label; Scope = $scope }
  }
  return $result
}

# ------------------------------------------------------------------ destinations and file names

function Resolve-DestinationRoot([string]$Path) {
  $p = [Environment]::ExpandEnvironmentVariables($Path.Trim())
  if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $script:Root $p }
  return $p
}

function Get-AccountDestinations {
  param($Settings, $Account)
  $all = @(Get-Prop $Settings 'destinations' @() | Where-Object { Get-Prop $_ 'enabled' $true })
  $wanted = @(Get-Prop $Account 'destinations' @() | Where-Object { $_ })
  if ($wanted.Count -eq 0) { return $all }
  $lower = $wanted | ForEach-Object { ([string]$_).ToLower() }
  return @($all | Where-Object { $lower -contains ([string]$_.name).ToLower() })
}

function Test-FileTemplate {
  param([string]$Template, [switch]$AllowTimeTokens)
  if ([string]::IsNullOrWhiteSpace($Template)) { return 'must not be empty.' }
  $t = $Template.Replace('/', '\')
  if ([IO.Path]::IsPathRooted($t) -or $t.StartsWith('\')) { return 'must be a relative path (it is placed inside each destination).' }
  foreach ($seg in $t.Split('\')) { if ($seg -eq '..' -or $seg -eq '.' -or $seg -eq '') { return "contains an invalid path segment ('$seg')." } }
  $stripped = [regex]::Replace($t, '\{(account|scope|timestamp|date|host)\}', 'x')
  if ($stripped -match '[{}]') { return 'contains an unknown {token}. Allowed: {account} {scope} {timestamp} {date} {host}.' }
  if ($stripped.Replace('\', '').IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { return 'contains characters that are not allowed in file names.' }
  if (-not $AllowTimeTokens -and $t -match '\{(timestamp|date)\}') { return 'must not contain {timestamp} or {date}.' }
  $dir = Split-Path $t -Parent
  if ($dir -and $dir -match '\{(timestamp|date)\}') { return '{timestamp}/{date} may only be used in the file name part, not in folder names.' }
  if ($t -notmatch '\{scope\}') { return 'must contain {scope}, otherwise personal and organization exports overwrite each other.' }
  return $null
}

function Expand-FileTemplate {
  param([string]$Template, [hashtable]$Tokens)
  $r = $Template.Replace('/', '\')
  foreach ($k in $Tokens.Keys) { $r = $r.Replace('{' + $k + '}', [string]$Tokens[$k]) }
  return $r
}

function ConvertTo-FormatRegex([string]$Format) {
  $sb = New-Object Text.StringBuilder
  foreach ($c in $Format.ToCharArray()) {
    if ('yMdHhmsfF'.IndexOf($c) -ge 0) { [void]$sb.Append('\d') }
    elseif ($c -eq 't') { [void]$sb.Append('[AaPp]') }
    else { [void]$sb.Append([regex]::Escape([string]$c)) }
  }
  return $sb.ToString()
}

function Get-RetentionMatcher {
  # Builds the folder, a wildcard and an exact regex matching earlier versions of one backup series.
  param([string]$Template, [hashtable]$Tokens, [string]$TimestampFormat)
  $m1 = [char]1; $m2 = [char]2
  $t = $Template.Replace('/', '\').Replace('{timestamp}', [string]$m1).Replace('{date}', [string]$m2)
  if ($t.IndexOf($m1) -lt 0 -and $t.IndexOf($m2) -lt 0) { return $null }
  $rel = Expand-FileTemplate $t $Tokens
  $leaf = Split-Path $rel -Leaf
  $dir = Split-Path $rel -Parent
  $wild = $leaf.Replace([string]$m1, '*').Replace([string]$m2, '*')
  $rx = [regex]::Escape($leaf).Replace([string]$m1, (ConvertTo-FormatRegex $TimestampFormat)).Replace([string]$m2, (ConvertTo-FormatRegex 'yyyy-MM-dd'))
  return [pscustomobject]@{ RelDir = $dir; Wildcard = $wild; Regex = '^' + $rx + '$' }
}

function Select-FilesToKeep {
  # Grandfather-father-son selection. Files must be sorted newest first.
  param([object[]]$Files, [int]$KeepLast, [int]$KeepDaily, [int]$KeepWeekly, [int]$KeepMonthly)
  $keep = New-Object 'System.Collections.Generic.HashSet[string]'
  if ($Files.Count -eq 0) { return , $keep }
  if (($KeepLast + $KeepDaily + $KeepWeekly + $KeepMonthly) -le 0) {
    foreach ($f in $Files) { [void]$keep.Add($f.FullName) }
    return , $keep
  }
  [void]$keep.Add($Files[0].FullName)
  for ($i = 0; $i -lt [Math]::Min($KeepLast, $Files.Count); $i++) { [void]$keep.Add($Files[$i].FullName) }
  $rules = @(
    [pscustomobject]@{ Limit = $KeepDaily; KeyFn = { param($d) $d.ToString('yyyy-MM-dd') } },
    [pscustomobject]@{ Limit = $KeepWeekly; KeyFn = { param($d) $d.Date.AddDays( - (([int]$d.DayOfWeek + 6) % 7)).ToString('yyyy-MM-dd') } },
    [pscustomobject]@{ Limit = $KeepMonthly; KeyFn = { param($d) $d.ToString('yyyy-MM') } }
  )
  foreach ($rule in $rules) {
    if ($rule.Limit -le 0) { continue }
    $buckets = @{}
    foreach ($f in $Files) {
      $k = & $rule.KeyFn $f.LastWriteTime
      if (-not $buckets.ContainsKey($k)) {
        if ($buckets.Count -ge $rule.Limit) { break }
        $buckets[$k] = $true
        [void]$keep.Add($f.FullName)
      }
    }
  }
  return , $keep
}

# ------------------------------------------------------------------ Bitwarden CLI

function ConvertTo-ArgString([string]$Arg) {
  # Quotes one argument using the Windows (CommandLineToArgvW) rules.
  if ($null -eq $Arg -or $Arg -eq '') { return '""' }
  if ($Arg -notmatch '[\s"]') { return $Arg }
  $e = [regex]::Replace($Arg, '(\\*)"', '$1$1\"')
  $e = [regex]::Replace($e, '(\\+)$', '$1$1')
  return '"' + $e + '"'
}

function Invoke-Bw {
  param(
    [Parameter(Mandatory = $true)][string[]]$ArgumentList,
    [string]$DataDir,
    [hashtable]$Environment = @{},
    [int]$TimeoutSec = 60
  )
  if (-not (Test-Path -LiteralPath $script:BwPath)) {
    return [pscustomobject]@{ Code = 127; Out = ''; Err = "bw.exe not found at $script:BwPath"; TimedOut = $false }
  }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $script:BwPath
  $psi.Arguments = (@($ArgumentList) + '--nointeraction' | ForEach-Object { ConvertTo-ArgString $_ }) -join ' '
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
  foreach ($k in 'BW_SESSION', 'BW_PASSWORD', 'BW_CLIENTID', 'BW_CLIENTSECRET') {
    if ($psi.EnvironmentVariables.ContainsKey($k)) { $psi.EnvironmentVariables.Remove($k) }
  }
  $psi.EnvironmentVariables['BW_NOINTERACTION'] = 'true'
  if ($DataDir) { $psi.EnvironmentVariables['BITWARDENCLI_APPDATA_DIR'] = $DataDir }
  foreach ($k in $Environment.Keys) { $psi.EnvironmentVariables[$k] = [string]$Environment[$k] }

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  try { [void]$p.Start() }
  catch { return [pscustomobject]@{ Code = 126; Out = ''; Err = "Failed to start bw.exe: $($_.Exception.Message)"; TimedOut = $false } }

  try { $p.StandardInput.Close() } catch { }
  # Read both streams asynchronously so a chatty command can never fill the pipe and hang.
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()

  $timedOut = -not $p.WaitForExit($TimeoutSec * 1000)
  if ($timedOut) {
    try { $p.Kill() } catch { }
    [void]$p.WaitForExit(5000)
  } else {
    $p.WaitForExit()
  }
  $out = ''; $err = ''
  try { if ($outTask.Wait(5000)) { $out = [string]$outTask.Result } } catch { }
  try { if ($errTask.Wait(5000)) { $err = [string]$errTask.Result } } catch { }
  $code = if ($timedOut) { 124 } else { $p.ExitCode }
  $p.Dispose()
  if ($timedOut) { $err = ("Timed out after {0}s: bw {1}. {2}" -f $TimeoutSec, $ArgumentList[0], $err).Trim() }
  return [pscustomobject]@{ Code = $code; Out = $out.Trim(); Err = $err.Trim(); TimedOut = $timedOut }
}

function Get-BwMessage($Result) {
  $parts = @($Result.Err, $Result.Out) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  $msg = ($parts -join ' | ') -replace '\s+', ' '
  if ($msg.Length -gt 400) { $msg = $msg.Substring(0, 400) + '...' }
  $msg = $msg.Trim().TrimEnd('.')
  if (-not $msg) { $msg = "exit code $($Result.Code)" }
  return $msg
}

function Get-LastLine([string]$Text) {
  $lines = @($Text -split "`r?`n" | Where-Object { $_.Trim() })
  if ($lines.Count -eq 0) { return '' }
  return $lines[-1].Trim()
}

function ConvertFrom-BwJson([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
  $i = $Text.IndexOfAny([char[]]'[{')
  if ($i -lt 0) { return $null }
  try { return ($Text.Substring($i) | ConvertFrom-Json) } catch { return $null }
}

function Get-BwStatus([string]$DataDir, [string]$Session, [int]$TimeoutSec = 60) {
  $envs = @{}
  if ($Session) { $envs['BW_SESSION'] = $Session }
  $r = Invoke-Bw -ArgumentList @('status') -DataDir $DataDir -Environment $envs -TimeoutSec $TimeoutSec
  if ($r.Code -ne 0) { return $null }
  return (ConvertFrom-BwJson $r.Out)
}

function Open-BwSession {
  # Signs in (or unlocks) one account in its own isolated CLI data folder and syncs the vault.
  param($Account, $Timeouts)
  $dir = Get-AccountDataDir $Account
  $server = Normalize-Url (Get-Prop $Account 'serverUrl' 'https://vault.bitwarden.com')
  if (-not $server) { $server = 'https://vault.bitwarden.com' }
  $email = [string](Get-Prop $Account 'email' '')
  $auth = [string](Get-Prop $Account 'authMethod' 'password')
  $master = Unprotect-Secret ([string](Get-Prop $Account 'encMaster' ''))
  if (-not $master) { throw 'No master password is stored for this account.' }

  $status = Get-BwStatus -DataDir $dir -TimeoutSec $Timeouts.other
  $state = [string](Get-Prop $status 'status' 'unauthenticated')
  if ($state -ne 'unauthenticated') {
    $curServer = Normalize-Url ([string](Get-Prop $status 'serverUrl' ''))
    $curEmail = [string](Get-Prop $status 'userEmail' '')
    if (($curServer -and $curServer -ne $server) -or ($email -and $curEmail -and $curEmail -ne $email)) {
      Write-Log "Stored CLI login is for a different server/email; signing out first."
      [void](Invoke-Bw -ArgumentList @('logout') -DataDir $dir -TimeoutSec $Timeouts.other)
      $state = 'unauthenticated'
    }
  }

  $session = $null
  if ($state -eq 'unauthenticated') {
    $r = Invoke-Bw -ArgumentList @('config', 'server', $server) -DataDir $dir -TimeoutSec $Timeouts.other
    if ($r.Code -ne 0) { throw "bw config server '$server' failed: $(Get-BwMessage $r)" }

    if ($auth -eq 'apikey') {
      $cid = Unprotect-Secret ([string](Get-Prop $Account 'encClientId' ''))
      $csec = Unprotect-Secret ([string](Get-Prop $Account 'encClientSecret' ''))
      if (-not $cid -or -not $csec) { throw 'API key sign-in is selected but client_id/client_secret are not stored.' }
      Write-Log 'Logging in (API key)...'
      $r = Invoke-Bw -ArgumentList @('login', '--apikey') -DataDir $dir -Environment @{ BW_CLIENTID = $cid; BW_CLIENTSECRET = $csec } -TimeoutSec $Timeouts.login
      if ($r.Code -ne 0) { throw "API key login failed: $(Get-BwMessage $r)" }
    } else {
      Write-Log 'Logging in (master password)...'
      $r = Invoke-Bw -ArgumentList @('login', $email, '--passwordenv', 'BW_PASSWORD', '--raw') -DataDir $dir -Environment @{ BW_PASSWORD = $master } -TimeoutSec $Timeouts.login
      $session = Get-LastLine $r.Out
      if ($r.Code -ne 0 -or -not $session) {
        throw "Login failed: $(Get-BwMessage $r). If this account uses two-step login, switch it to API key sign-in in the setup menu."
      }
    }
  }

  if (-not $session) {
    Write-Log 'Unlocking...'
    $r = Invoke-Bw -ArgumentList @('unlock', '--passwordenv', 'BW_PASSWORD', '--raw') -DataDir $dir -Environment @{ BW_PASSWORD = $master } -TimeoutSec $Timeouts.unlock
    $session = Get-LastLine $r.Out
    if ($r.Code -ne 0 -or -not $session) { throw "Unlock failed: $(Get-BwMessage $r)" }
  }

  Write-Log 'Syncing vault...'
  $r = Invoke-Bw -ArgumentList @('sync') -DataDir $dir -Environment @{ BW_SESSION = $session } -TimeoutSec $Timeouts.sync
  if ($r.Code -ne 0) { throw "Sync failed (refusing to export possibly stale data): $(Get-BwMessage $r)" }

  return [pscustomobject]@{ DataDir = $dir; Session = $session }
}

function Close-BwSession {
  param([string]$DataDir, [string]$Mode = 'logout', $Timeouts)
  if (-not $DataDir) { return }
  $verb = if ($Mode -eq 'lock') { 'lock' } else { 'logout' }
  $r = Invoke-Bw -ArgumentList @($verb) -DataDir $DataDir -TimeoutSec $Timeouts.other
  if ($r.Code -eq 0) { Write-Log "CLI $verb OK." }
  else { Write-Log "CLI $verb returned $($r.Code) (usually harmless): $(Get-BwMessage $r)" }
}

# ------------------------------------------------------------------ cross-process lock

function Enter-BwLock([int]$TimeoutMs = 0) {
  $sha = [Security.Cryptography.SHA256]::Create()
  $hash = ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($script:Root.ToLowerInvariant())) | ForEach-Object { $_.ToString('x2') }) -join ''
  $m = New-Object System.Threading.Mutex($false, ('Local\VaultwardenBackup-' + $hash.Substring(0, 16)))
  $ok = $false
  try { $ok = $m.WaitOne($TimeoutMs) }
  catch [System.Threading.AbandonedMutexException] { $ok = $true }
  if (-not $ok) { $m.Dispose(); return $null }
  return $m
}

function Exit-BwLock($Mutex) {
  if ($null -eq $Mutex) { return }
  try { $Mutex.ReleaseMutex() } catch { }
  $Mutex.Dispose()
}
#END_SCRIPT

#BEGIN_SCRIPT BACKUP
# bitwarden_backup_all.ps1 - exports every active account (and its organizations) to every destination.
# Generated by run.bat. Edit run.bat instead: this file is rewritten when it differs.
#
# Exit codes: 0 = everything succeeded (or another run was already in progress)
#             1 = at least one export or required destination failed
#             2 = configuration / fatal error
param(
  [string[]]$Account,      # only back up these nicknames
  [switch]$SelectAccount,  # pick one account interactively
  [switch]$ShowLastRun     # print the summary of the previous run and exit
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bw_common.ps1')
$script:LogFile = Join-Path $script:LogsDir 'backup.log'
Initialize-Dirs

function Show-LastRun {
  if (-not (Test-Path -LiteralPath $script:StatusPath)) { Write-Host 'No backup has been run yet.'; return 0 }
  $s = Read-JsonFile $script:StatusPath
  Write-Host ''
  Write-Host ('Last run started : {0}' -f $s.startedAt)
  Write-Host ('Finished         : {0}' -f $s.finishedAt)
  $color = if ($s.exitCode -eq 0) { 'Green' } else { 'Red' }
  Write-Host ('Result           : {0} (exit code {1})' -f $s.summary, $s.exitCode) -ForegroundColor $color
  Write-Host ''
  foreach ($r in @($s.results)) {
    $c = switch ($r.status) { 'ok' { 'Green' } 'skipped' { 'DarkGray' } 'warning' { 'Yellow' } default { 'Red' } }
    Write-Host ('  [{0,-7}] {1} / {2}  {3}' -f $r.status.ToUpper(), $r.account, $r.scope, $r.message) -ForegroundColor $c
  }
  Write-Host ''
  return 0
}

$script:Results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$AccountName, [string]$Scope, [string]$Status, [string]$Message) {
  $script:Results.Add([pscustomobject]@{ account = $AccountName; scope = $Scope; status = $Status; message = $Message })
}

function Test-ExportFile {
  param([string]$Path, [string]$Format)
  if (-not (Test-Path -LiteralPath $Path)) { throw 'bw reported success but no export file was written.' }
  $len = (Get-Item -LiteralPath $Path).Length
  if ($len -lt 20) { throw "Export file is suspiciously small ($len bytes)." }
  try { $json = Read-JsonFile $Path } catch { throw "Export file is not valid JSON: $($_.Exception.Message)" }
  if ((Get-Prop $json 'encrypted' $false) -ne $true) { throw 'Export is not marked as encrypted; refusing to store it.' }
  if ($Format -eq 'password' -and (Get-Prop $json 'passwordProtected' $false) -ne $true) {
    Write-Log 'Export is encrypted but not marked password-protected (older server/CLI?).' WARN
  }
  return $len
}

function Copy-Atomic([string]$Source, [string]$Target) {
  $dir = Split-Path $Target -Parent
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $tmp = "$Target.partial"
  Copy-Item -LiteralPath $Source -Destination $tmp -Force
  if ((Get-Item -LiteralPath $tmp).Length -ne (Get-Item -LiteralPath $Source).Length) {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    throw "Copy to '$Target' is incomplete."
  }
  Move-Item -LiteralPath $tmp -Destination $Target -Force
}

function Write-ToDestination {
  # Returns 'written' or 'skipped'; throws on failure.
  param($Dest, [string]$Staging, [hashtable]$Tokens, $Settings)
  $root = Resolve-DestinationRoot ([string]$Dest.path)
  $optional = [bool](Get-Prop $Dest 'optional' $false)
  if (-not (Test-Path -LiteralPath $root)) {
    if ($optional) { return 'skipped' }
    New-Item -ItemType Directory -Force -Path $root | Out-Null
  }

  $target = Join-Path $root (Expand-FileTemplate $Settings.fileNameTemplate $Tokens)
  Copy-Atomic $Staging $target
  Write-Log ("  -> [{0}] {1}" -f $Dest.name, $target) OK

  $latest = $null
  if ((Get-Prop $Dest 'writeLatest' $false) -and $Settings.latestFileNameTemplate) {
    $latest = Join-Path $root (Expand-FileTemplate $Settings.latestFileNameTemplate $Tokens)
    if ($latest -ne $target) { Copy-Atomic $Staging $latest }
  }

  $matcher = Get-RetentionMatcher -Template $Settings.fileNameTemplate -Tokens $Tokens -TimestampFormat $Settings.timestampFormat
  if ($matcher) {
    $dir = if ($matcher.RelDir) { Join-Path $root $matcher.RelDir } else { $root }
    $files = @(Get-ChildItem -LiteralPath $dir -File -Filter $matcher.Wildcard -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $matcher.Regex -and $_.FullName -ne $latest } |
        Sort-Object LastWriteTimeUtc -Descending)
    $keep = Select-FilesToKeep -Files $files `
      -KeepLast ([int](Get-Prop $Dest 'keepLast' 0)) -KeepDaily ([int](Get-Prop $Dest 'keepDaily' 0)) `
      -KeepWeekly ([int](Get-Prop $Dest 'keepWeekly' 0)) -KeepMonthly ([int](Get-Prop $Dest 'keepMonthly' 0))
    [void]$keep.Add($target)
    $removed = 0
    foreach ($f in $files) {
      if (-not $keep.Contains($f.FullName)) {
        try { Remove-Item -LiteralPath $f.FullName -Force; $removed++ }
        catch { Write-Log "  Could not delete old backup '$($f.FullName)': $($_.Exception.Message)" WARN }
      }
    }
    if ($removed -gt 0) { Write-Log ("  [{0}] retention removed {1} old file(s), {2} kept." -f $Dest.name, $removed, ($files.Count - $removed)) }
  }
  return 'written'
}

function Get-HostToken([string]$Url) {
  $u = Normalize-Url $Url
  if (-not $u) { $u = 'https://vault.bitwarden.com' }
  if ($u -notmatch '^[a-z][a-z0-9+.-]*://') { $u = 'https://' + $u }
  try { return ConvertTo-SafeName ([uri]$u).Host 'server' } catch { return 'server' }
}

function Export-Scope {
  param($Ctx, $Acct, [string]$Scope, [string]$Label, [string]$OrgId, [string]$Format, [string]$ExportPassword, [object[]]$Destinations, $Settings, [string]$Stamp)
  $nick = [string]$Acct.nickname
  Write-Log "Exporting $Label..."
  $staging = Join-Path $script:WorkDir ([guid]::NewGuid().ToString('N') + '.json')
  try {
    $bwArgs = @('export', '--format', 'encrypted_json', '--output', $staging)
    if ($Format -eq 'password') { $bwArgs += "--password=$ExportPassword" }
    if ($OrgId) { $bwArgs += @('--organizationid', $OrgId) }
    $r = Invoke-Bw -ArgumentList $bwArgs -DataDir $Ctx.DataDir -Environment @{ BW_SESSION = $Ctx.Session } -TimeoutSec $Settings.timeouts.export
    if ($r.Code -ne 0) { throw "bw export failed: $(Get-BwMessage $r)" }
    $size = Test-ExportFile -Path $staging -Format $Format

    $now = Get-Date
    $tokens = @{
      account   = ConvertTo-SafeName $nick 'account'
      scope     = $Scope
      timestamp = $Stamp
      date      = $now.ToString('yyyy-MM-dd')
      host      = Get-HostToken ([string](Get-Prop $Acct 'serverUrl' ''))
    }

    $written = 0; $failed = @(); $skipped = @()
    foreach ($d in $Destinations) {
      try {
        $res = Write-ToDestination -Dest $d -Staging $staging -Tokens $tokens -Settings $Settings
        if ($res -eq 'skipped') { $skipped += $d.name; Write-Log "  [$($d.name)] optional destination not available, skipped." WARN }
        else { $written++ }
      } catch {
        if (Get-Prop $d 'optional' $false) {
          $skipped += $d.name
          Write-Log "  [$($d.name)] optional destination failed: $($_.Exception.Message)" WARN
        } else {
          $failed += $d.name
          Write-Log "  [$($d.name)] FAILED: $($_.Exception.Message)" ERROR
        }
      }
    }

    $kb = [Math]::Round($size / 1KB, 1)
    if ($written -eq 0) {
      Add-Result $nick $Scope 'failed' 'export was not written to any destination'
    } elseif ($failed.Count -gt 0) {
      Add-Result $nick $Scope 'failed' ("{0} KB written to {1} destination(s); failed: {2}" -f $kb, $written, ($failed -join ', '))
    } elseif ($skipped.Count -gt 0) {
      Add-Result $nick $Scope 'warning' ("{0} KB written to {1} destination(s); skipped: {2}" -f $kb, $written, ($skipped -join ', '))
    } else {
      Add-Result $nick $Scope 'ok' ("{0} KB written to {1} destination(s)" -f $kb, $written)
    }
  } catch {
    Write-Log "$Label FAILED: $($_.Exception.Message)" ERROR
    Add-Result $nick $Scope 'failed' $_.Exception.Message
  } finally {
    Remove-Item -LiteralPath $staging -Force -ErrorAction SilentlyContinue
  }
}

function Backup-Account {
  param($Acct, $Settings, [string]$Stamp)
  $nick = [string]$Acct.nickname
  Write-Log "=== Account: $nick ($(Get-Prop $Acct 'email' '')) on $(Get-Prop $Acct 'serverUrl' '') ==="

  $format = [string](Get-Prop $Acct 'exportFormat' $Settings.exportFormat)
  $exportPassword = ''
  if ($format -eq 'password') {
    $exportPassword = Unprotect-Secret ([string](Get-Prop $Acct 'encExport' ''))
    if (-not $exportPassword) { Add-Result $nick '*' 'failed' 'no export password stored (required for password-protected exports)'; Write-Log 'No export password stored; skipping.' ERROR; return }
  }

  $dests = @(Get-AccountDestinations -Settings $Settings -Account $Acct)
  if ($dests.Count -eq 0) { Add-Result $nick '*' 'failed' 'no enabled destinations for this account'; Write-Log 'No enabled destinations; skipping.' ERROR; return }

  $includePersonal = [bool](Get-Prop $Acct 'includePersonal' $true)
  $orgs = @(Get-OrgScopes $Acct)
  if (-not $includePersonal -and $orgs.Count -eq 0) { Add-Result $nick '*' 'skipped' 'nothing selected to export'; return }

  $dataDir = Get-AccountDataDir $Acct
  try {
    $ctx = Open-BwSession -Account $Acct -Timeouts $Settings.timeouts
    if ($includePersonal) {
      Export-Scope -Ctx $ctx -Acct $Acct -Scope 'personal' -Label 'personal vault' -OrgId $null -Format $format -ExportPassword $exportPassword -Destinations $dests -Settings $Settings -Stamp $Stamp
    }
    foreach ($o in $orgs) {
      Export-Scope -Ctx $ctx -Acct $Acct -Scope $o.Scope -Label "organization '$($o.Name)'" -OrgId $o.Id -Format $format -ExportPassword $exportPassword -Destinations $dests -Settings $Settings -Stamp $Stamp
    }
  } catch {
    Write-Log "Account '$nick' FAILED: $($_.Exception.Message)" ERROR
    Add-Result $nick '*' 'failed' $_.Exception.Message
  } finally {
    Close-BwSession -DataDir $dataDir -Mode $Settings.sessionMode -Timeouts $Settings.timeouts
    $exportPassword = $null
  }
}

function Main {
  $settings = Load-Settings
  Invoke-LogRotation -Path $script:LogFile -MaxMB $settings.log.maxSizeMB -Keep $settings.log.keepFiles
  $store = Load-AccountStore
  $accounts = @($store.accounts)

  if ($SelectAccount) {
    if ($accounts.Count -eq 0) { Write-Host 'No accounts configured.'; return 0 }
    for ($i = 0; $i -lt $accounts.Count; $i++) { Write-Host ('  {0}) {1}' -f ($i + 1), $accounts[$i].nickname) }
    $n = Read-Host 'Back up which account [number]'
    $idx = ($n -as [int]) - 1
    if ($idx -lt 0 -or $idx -ge $accounts.Count) { Write-Host 'Cancelled.'; return 0 }
    $Account = @($accounts[$idx].nickname)
  }

  Write-Log '===== Backup run started ====='
  if ($accounts.Count -eq 0) { Write-Log 'No accounts configured. Run setup first.' WARN; return 0 }
  $stamp = (Get-Date).ToString($settings.timestampFormat, [Globalization.CultureInfo]::InvariantCulture)

  foreach ($acct in $accounts) {
    $nick = [string]$acct.nickname
    if ($Account -and -not ($Account | Where-Object { $_ -eq $nick })) { continue }
    if (Get-Prop $acct 'frozen' $false) {
      if ($Account) { Write-Log "Account '$nick' is frozen but was requested explicitly; backing it up anyway." WARN }
      else { Write-Log "Skipping frozen account: $nick"; Add-Result $nick '*' 'skipped' 'account is frozen'; continue }
    }
    Backup-Account -Acct $acct -Settings $settings -Stamp $stamp
    Write-Log ''
  }

  if ($Account -and $script:Results.Count -eq 0) { Write-Log "No account named '$($Account -join ', ')' was found." ERROR; return 2 }
  $bad = @($script:Results | Where-Object { $_.status -eq 'failed' }).Count
  $good = @($script:Results | Where-Object { $_.status -eq 'ok' -or $_.status -eq 'warning' }).Count
  if ($bad -gt 0) { Write-Log ("Finished with errors: {0} succeeded, {1} failed." -f $good, $bad) ERROR; return 1 }
  Write-Log ("Finished: {0} export(s) succeeded." -f $good) OK
  return 0
}

if ($ShowLastRun) { exit (Show-LastRun) }

$started = Get-Date
$lock = Enter-BwLock 0
if ($null -eq $lock) {
  Write-Log 'Another backup (or a setup sign-in) is already running; skipping this run.' WARN
  exit 0
}

$code = 2
try {
  $code = [int](Main | Select-Object -Last 1)
} catch {
  Write-Log "FATAL: $($_.Exception.Message)" ERROR
  $code = 2
} finally {
  Exit-BwLock $lock
  try {
    $bad = @($script:Results | Where-Object { $_.status -eq 'failed' }).Count
    $summary = switch ($code) { 0 { 'Success' } 1 { "$bad export(s) failed" } default { 'Fatal error - see backup.log' } }
    $status = [pscustomobject]@{
      startedAt  = $started.ToString('yyyy-MM-dd HH:mm:ss')
      finishedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
      exitCode   = $code
      summary    = $summary
      results    = $script:Results.ToArray()
    }
    Save-JsonFile $script:StatusPath $status
  } catch { }
}
exit $code
#END_SCRIPT

#BEGIN_SCRIPT SETUP
# bitwarden_backup_setup.ps1 - interactive configuration of accounts, organizations, destinations and settings.
# Generated by run.bat. Edit run.bat instead: this file is rewritten when it differs.
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bw_common.ps1')
$script:LogFile = Join-Path $script:LogsDir 'setup.log'
Initialize-Dirs

# ------------------------------------------------------------------ prompt helpers

function Show-Header([string]$Title) {
  Clear-Host
  Write-Host '=========================================='
  Write-Host "  $Title"
  Write-Host '=========================================='
  Write-Host ''
}

function Wait-Enter { [void](Read-Host 'Press Enter to continue') }

function Read-Text([string]$Label, [string]$Default = '') {
  $suffix = if ($Default -ne '') { " [$Default]" } else { '' }
  $v = Read-Host ($Label + $suffix)
  if ($null -eq $v) { $v = '' }
  $v = $v.Trim()
  if ($v -eq '') { return $Default }
  return $v
}

function Read-YesNo([string]$Label, [bool]$Default = $false) {
  $hint = if ($Default) { 'Y/n' } else { 'y/N' }
  while ($true) {
    $v = Read-Host "$Label ($hint)"
    if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
    if ($v -match '^\s*[Yy]') { return $true }
    if ($v -match '^\s*[Nn]') { return $false }
  }
}

function Read-Int([string]$Label, [int]$Default, [int]$Min = 0, [int]$Max = 100000) {
  while ($true) {
    $v = Read-Host "$Label [$Default]"
    if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
    $n = 0
    if ([int]::TryParse($v.Trim(), [ref]$n) -and $n -ge $Min -and $n -le $Max) { return $n }
    Write-Host "  Please enter a whole number between $Min and $Max." -ForegroundColor Yellow
  }
}

function Read-Choice([string]$Label, [int]$Max) {
  $v = Read-Host $Label
  $n = 0
  if ([int]::TryParse(([string]$v).Trim(), [ref]$n) -and $n -ge 1 -and $n -le $Max) { return $n }
  return 0
}

function Read-SecretBlob([string]$Label, [switch]$Confirm) {
  # Returns a DPAPI-protected blob, or $null if the input was empty or did not match.
  $s1 = Read-Host -AsSecureString $Label
  if ($null -eq $s1 -or $s1.Length -eq 0) { return $null }
  $blob = ConvertFrom-SecureString $s1
  if ($Confirm) {
    $s2 = Read-Host -AsSecureString '  Type it again to confirm'
    if ($null -eq $s2) { return $null }
    if ((Unprotect-Secret $blob) -cne (Unprotect-Secret (ConvertFrom-SecureString $s2))) {
      Write-Host '  The two entries did not match.' -ForegroundColor Yellow
      return $null
    }
  }
  return $blob
}

function Confirm-Typed([string]$Question) {
  Write-Host ''
  return ((Read-Host "$Question  Type YES to confirm") -ceq 'YES')
}

function Say([string]$Text, [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color }

# ------------------------------------------------------------------ accounts

function Show-Accounts($Store) {
  $accounts = @($Store.accounts)
  Write-Host 'Accounts:'
  if ($accounts.Count -eq 0) { Write-Host '  (none yet)'; return }
  for ($i = 0; $i -lt $accounts.Count; $i++) {
    $a = $accounts[$i]
    $state = if (Get-Prop $a 'frozen' $false) { 'FROZEN' } else { 'ACTIVE' }
    $orgs = @(Get-Prop $a 'organizations' @())
    $enabled = @($orgs | Where-Object { Get-Prop $_ 'enabled' $true }).Count
    $personal = if (Get-Prop $a 'includePersonal' $true) { 'personal+' } else { '' }
    Write-Host ('  {0}) {1,-14} [{2}] {3}{4}/{5} orgs  {6}  {7}  ({8})' -f ($i + 1), $a.nickname, $state, $personal, $enabled, $orgs.Count,
      (Get-Prop $a 'authMethod' 'password'), (Get-Prop $a 'serverUrl' ''), (Get-Prop $a 'email' ''))
  }
}

function Select-Account($Store) {
  $accounts = @($Store.accounts)
  if ($accounts.Count -eq 0) { Say 'No accounts configured yet.' Yellow; Start-Sleep -Milliseconds 900; return -1 }
  Show-Accounts $Store
  Write-Host ''
  $n = Read-Choice 'Select account [number] (blank to cancel)' $accounts.Count
  return ($n - 1)
}

function Read-ServerUrl([string]$Current) {
  Write-Host ''
  Write-Host 'Server:'
  Write-Host '  1) Bitwarden Cloud US  (https://vault.bitwarden.com)'
  Write-Host '  2) Bitwarden Cloud EU  (https://vault.bitwarden.eu)'
  Write-Host '  3) Self-hosted Vaultwarden / Bitwarden'
  $default = if ($Current -eq 'https://vault.bitwarden.eu') { 2 } elseif ($Current -and $Current -ne 'https://vault.bitwarden.com') { 3 } else { 1 }
  $c = Read-Int 'Choose' $default 1 3
  switch ($c) {
    1 { return 'https://vault.bitwarden.com' }
    2 { return 'https://vault.bitwarden.eu' }
    default {
      $def = if ($default -eq 3) { $Current } else { '' }
      $u = Normalize-Url (Read-Text 'Full server URL (e.g. https://vault.example.com)' $def)
      if ($u -and $u -notmatch '^https?://') { $u = 'https://' + $u }
      if ($u -like 'http://*') { Say '  Warning: http:// sends your credentials unencrypted.' Yellow }
      return $u
    }
  }
}

function Read-AuthSettings($Acct) {
  # Asks for the sign-in method and credentials; updates $Acct. Returns $false if cancelled.
  Write-Host ''
  Write-Host 'Sign-in method:'
  Write-Host '  1) Email + master password (accounts WITHOUT two-step login)'
  Write-Host '  2) Personal API key + master password (works with two-step login; recommended)'
  Say '     Find the API key in the web vault: Settings > Security > Keys > View API key.' DarkGray
  $default = if ((Get-Prop $Acct 'authMethod' 'password') -eq 'apikey') { 2 } else { 1 }
  $c = Read-Int 'Choose' $default 1 2
  if ($c -eq 2) {
    $cid = Read-SecretBlob 'client_id (input hidden)'
    if (-not $cid) { return $false }
    $csec = Read-SecretBlob 'client_secret (input hidden)'
    if (-not $csec) { return $false }
    Set-Prop $Acct 'authMethod' 'apikey'
    Set-Prop $Acct 'encClientId' $cid
    Set-Prop $Acct 'encClientSecret' $csec
  } else {
    Set-Prop $Acct 'authMethod' 'password'
    Set-Prop $Acct 'encClientId' $null
    Set-Prop $Acct 'encClientSecret' $null
  }
  $m = Read-SecretBlob 'Master password (input hidden; needed to unlock the vault)'
  if (-not $m) { return $false }
  Set-Prop $Acct 'encMaster' $m
  return $true
}

function Read-ExportSettings($Acct, $Settings) {
  Write-Host ''
  Write-Host 'Export encryption:'
  Write-Host '  1) Password-protected - can be imported into ANY Bitwarden/Vaultwarden account (recommended)'
  Write-Host '  2) Account-restricted - only importable into this same account; no extra password'
  Write-Host '  3) Use the global default'
  $cur = Get-Prop $Acct 'exportFormat'
  $default = if ($cur -eq 'password') { 1 } elseif ($cur -eq 'account') { 2 } else { 3 }
  $c = Read-Int 'Choose' $default 1 3
  $fmt = switch ($c) { 1 { 'password' } 2 { 'account' } default { $null } }
  $effective = if ($fmt) { $fmt } else { $Settings.exportFormat }
  if ($effective -eq 'password') {
    $hasPw = [bool](Get-Prop $Acct 'encExport')
    if (-not $hasPw -or (Read-YesNo 'Set a new export password?' $false)) {
      Say '  Write this password down somewhere safe - without it the backups cannot be restored.' Yellow
      $e = Read-SecretBlob 'Export password (input hidden)' -Confirm
      if (-not $e) { return $false }
      Set-Prop $Acct 'encExport' $e
    }
  }
  Set-Prop $Acct 'exportFormat' $fmt
  return $true
}

function Add-Account($Store, $Settings) {
  Show-Header 'Add account'
  $nick = Read-Text 'Nickname for this account (e.g. personal, work)'
  if (-not $nick) { return }
  if (@($Store.accounts | Where-Object { $_.nickname -eq $nick }).Count -gt 0) { Say "An account named '$nick' already exists." Yellow; Wait-Enter; return }
  $server = Read-ServerUrl ''
  if (-not $server) { return }
  $email = Read-Text 'Account email'
  if (-not $email) { return }

  $acct = [pscustomobject]@{
    id = [guid]::NewGuid().ToString('N'); nickname = $nick; serverUrl = $server; email = $email
    authMethod = 'password'; encMaster = $null; encClientId = $null; encClientSecret = $null
    exportFormat = $null; encExport = $null; includePersonal = $true; frozen = $false
    destinations = @(); organizations = @()
  }
  if (-not (Read-AuthSettings $acct)) { Say 'Cancelled.' Yellow; Wait-Enter; return }
  if (-not (Read-ExportSettings $acct $Settings)) { Say 'Cancelled.' Yellow; Wait-Enter; return }

  $Store.accounts = @(@($Store.accounts) + $acct)
  Save-AccountStore $Store
  Write-Log "Added account '$nick' ($server)."

  if (Read-YesNo 'Sign in now to verify the credentials and find organizations?' $true) {
    Update-Organizations $Store $acct $Settings
  }
}

function Invoke-WithSession {
  # Runs $Action with an open CLI session for $Acct, holding the shared lock.
  param($Acct, $Settings, [scriptblock]$Action)
  $lock = Enter-BwLock 0
  if ($null -eq $lock) { Say 'A backup is running right now; try again in a moment.' Yellow; return $false }
  $dir = Get-AccountDataDir $Acct
  try {
    $ctx = Open-BwSession -Account $Acct -Timeouts $Settings.timeouts
    & $Action $ctx | Out-Null
    return $true
  } catch {
    Say "Failed: $($_.Exception.Message)" Red
    Write-Log "Session for '$($Acct.nickname)' failed: $($_.Exception.Message)" ERROR
    return $false
  } finally {
    Close-BwSession -DataDir $dir -Mode $Settings.sessionMode -Timeouts $Settings.timeouts
    Exit-BwLock $lock
  }
}

function Update-Organizations($Store, $Acct, $Settings) {
  Write-Host ''
  Say "Signing in as '$($Acct.nickname)' to look for organizations..." Cyan
  $found = @{}
  $ok = Invoke-WithSession -Acct $Acct -Settings $Settings -Action {
    param($ctx)
    $r = Invoke-Bw -ArgumentList @('list', 'organizations') -DataDir $ctx.DataDir -Environment @{ BW_SESSION = $ctx.Session } -TimeoutSec $Settings.timeouts.other
    foreach ($o in @(ConvertFrom-BwJson $r.Out)) { if ($o -and $o.id) { $found[[string]$o.id] = [string]$o.name } }
    if ($found.Count -eq 0) {
      # Fallback for servers where 'list organizations' comes back empty: look at item ownership.
      $r = Invoke-Bw -ArgumentList @('list', 'items') -DataDir $ctx.DataDir -Environment @{ BW_SESSION = $ctx.Session } -TimeoutSec $Settings.timeouts.sync
      foreach ($it in @(ConvertFrom-BwJson $r.Out)) {
        $oid = [string](Get-Prop $it 'organizationId' '')
        if ($oid -and -not $found.ContainsKey($oid)) { $found[$oid] = '' }
      }
    }
  }
  if (-not $ok) { Wait-Enter; return }

  $existing = @(Get-Prop $Acct 'organizations' @())
  $merged = @()
  foreach ($id in $found.Keys) {
    $prev = $existing | Where-Object { $_.id -eq $id } | Select-Object -First 1
    $name = $found[$id]
    if (-not $name -and $prev) { $name = [string](Get-Prop $prev 'name' '') }
    if (-not $name) { $name = 'org-' + (Get-ShortId $id) }
    $enabled = if ($prev) { [bool](Get-Prop $prev 'enabled' $true) } else { $true }
    $merged += [pscustomobject]@{ id = $id; name = $name; enabled = $enabled }
    $tag = if ($prev) { '' } else { '  (new)' }
    Say ("  - {0}  id={1}  {2}{3}" -f $name, $id, $(if ($enabled) { 'ENABLED' } else { 'DISABLED' }), $tag)
  }
  foreach ($prev in $existing) {
    if (-not $found.ContainsKey([string]$prev.id)) {
      Say ("  - {0} is no longer visible to this account; removed from the list." -f $prev.name) Yellow
    }
  }
  if ($found.Count -eq 0) { Say 'Signed in OK. No organizations found.' Green }
  else { Say "Signed in OK. $($found.Count) organization(s) found." Green }
  Set-Prop $Acct 'organizations' @($merged)
  Save-AccountStore $Store
  Wait-Enter
}

function Select-AccountDestinations($Store, $Acct, $Settings) {
  $all = @($Settings.destinations)
  if ($all.Count -eq 0) { Say 'No destinations defined yet (see Backup destinations).' Yellow; Wait-Enter; return }
  $current = @(Get-Prop $Acct 'destinations' @() | ForEach-Object { ([string]$_).ToLower() })
  Write-Host ''
  Write-Host 'Destinations:'
  for ($i = 0; $i -lt $all.Count; $i++) {
    $d = $all[$i]
    $mark = if ($current.Count -eq 0 -or $current -contains $d.name.ToLower()) { 'x' } else { ' ' }
    $en = if (Get-Prop $d 'enabled' $true) { '' } else { ' (globally disabled)' }
    Write-Host ('  [{0}] {1}) {2}  {3}{4}' -f $mark, ($i + 1), $d.name, $d.path, $en)
  }
  Write-Host ''
  $v = Read-Host 'Numbers to use for this account, comma-separated (blank = all enabled destinations)'
  if ([string]::IsNullOrWhiteSpace($v)) { Set-Prop $Acct 'destinations' @(); Save-AccountStore $Store; return }
  $names = @()
  foreach ($part in $v.Split(',')) {
    $n = 0
    if ([int]::TryParse($part.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $all.Count) { $names += $all[$n - 1].name }
  }
  if ($names.Count -eq 0) { Say 'Nothing valid selected; unchanged.' Yellow; Wait-Enter; return }
  Set-Prop $Acct 'destinations' @($names | Select-Object -Unique)
  Save-AccountStore $Store
}

function Edit-Account($Store, $Settings) {
  Show-Header 'Edit account'
  $idx = Select-Account $Store
  if ($idx -lt 0) { return }
  $acct = @($Store.accounts)[$idx]

  while ($true) {
    Show-Header "Edit account: $($acct.nickname)"
    $fmt = Get-Prop $acct 'exportFormat'
    $fmtText = if ($fmt) { $fmt } else { "default ($($Settings.exportFormat))" }
    $dests = @(Get-Prop $acct 'destinations' @())
    $destText = if ($dests.Count -eq 0) { 'all enabled' } else { $dests -join ', ' }
    Write-Host ("  Server         : {0}" -f (Get-Prop $acct 'serverUrl' ''))
    Write-Host ("  Email          : {0}" -f (Get-Prop $acct 'email' ''))
    Write-Host ("  Sign-in        : {0}" -f (Get-Prop $acct 'authMethod' 'password'))
    Write-Host ("  Export format  : {0}" -f $fmtText)
    Write-Host ("  Personal vault : {0}" -f $(if (Get-Prop $acct 'includePersonal' $true) { 'included' } else { 'excluded' }))
    Write-Host ("  Destinations   : {0}" -f $destText)
    Write-Host ''
    Write-Host '  1) Change server / email'
    Write-Host '  2) Change sign-in method and passwords'
    Write-Host '  3) Change export format / export password'
    Write-Host '  4) Include/exclude personal vault'
    Write-Host '  5) Choose destinations for this account'
    Write-Host '  6) Rename'
    Write-Host '  7) Test sign-in now'
    Write-Host '  8) Back'
    Write-Host ''
    switch (Read-Choice 'Choose [1-8]' 8) {
      1 {
        $s = Read-ServerUrl ([string](Get-Prop $acct 'serverUrl' ''))
        if ($s) { $acct.serverUrl = $s }
        $acct.email = Read-Text 'Email' ([string](Get-Prop $acct 'email' ''))
        Save-AccountStore $Store; Write-Log "Updated server/email for '$($acct.nickname)'."
      }
      2 {
        if (Read-AuthSettings $acct) { Save-AccountStore $Store; Write-Log "Updated sign-in for '$($acct.nickname)'." }
        else { Say 'Cancelled; nothing changed.' Yellow; $Store = Load-AccountStore; $acct = @($Store.accounts)[$idx]; Wait-Enter }
      }
      3 {
        if (Read-ExportSettings $acct $Settings) { Save-AccountStore $Store; Write-Log "Updated export settings for '$($acct.nickname)'." }
        else { Say 'Cancelled; nothing changed.' Yellow; $Store = Load-AccountStore; $acct = @($Store.accounts)[$idx]; Wait-Enter }
      }
      4 {
        Set-Prop $acct 'includePersonal' (-not [bool](Get-Prop $acct 'includePersonal' $true))
        Save-AccountStore $Store
      }
      5 { Select-AccountDestinations $Store $acct $Settings }
      6 {
        $new = Read-Text 'New nickname' $acct.nickname
        if ($new -ne $acct.nickname) {
          if (@($Store.accounts | Where-Object { $_.nickname -eq $new }).Count -gt 0) { Say 'That name is taken.' Yellow; Wait-Enter }
          else {
            Say 'Note: existing backup files keep the old name and are no longer cleaned up by retention.' Yellow
            Write-Log "Renamed account '$($acct.nickname)' to '$new'."
            $acct.nickname = $new; Save-AccountStore $Store; Wait-Enter
          }
        }
      }
      7 {
        $ok = Invoke-WithSession -Acct $acct -Settings $Settings -Action { param($ctx) }
        if ($ok) { Say 'Sign-in, unlock and sync all worked.' Green }
        Wait-Enter
      }
      8 { return }
    }
  }
}

function Remove-AccountOrInstance($Store, $Settings) {
  Show-Header 'Remove account or instance'
  Show-Accounts $Store
  if (@($Store.accounts).Count -eq 0) { Wait-Enter; return }
  Write-Host ''
  Write-Host '  1) Remove ONE account'
  Write-Host '  2) Remove ALL accounts on a server URL'
  Write-Host '  3) Cancel'
  $mode = Read-Choice 'Choose [1-3]' 3
  $targets = @()
  if ($mode -eq 1) {
    $n = Read-Choice 'Remove which account [number]' @($Store.accounts).Count
    if ($n -lt 1) { return }
    $targets = @(@($Store.accounts)[$n - 1])
    if (-not (Confirm-Typed ("DELETE account '{0}' on {1}? Existing backup files are kept." -f $targets[0].nickname, $targets[0].serverUrl))) { return }
  } elseif ($mode -eq 2) {
    $url = Normalize-Url (Read-Text 'Server URL')
    if (-not $url) { return }
    $targets = @($Store.accounts | Where-Object { (Normalize-Url $_.serverUrl) -eq $url })
    if ($targets.Count -eq 0) { Say 'No accounts use that server.' Yellow; Wait-Enter; return }
    if (-not (Confirm-Typed ("DELETE {0} account(s) on '{1}'? Existing backup files are kept." -f $targets.Count, $url))) { return }
  } else { return }

  foreach ($t in $targets) {
    $dir = Join-Path $script:DataDir ('bw\' + $t.id)
    if (Test-Path -LiteralPath $dir) {
      [void](Invoke-Bw -ArgumentList @('logout') -DataDir $dir -TimeoutSec $Settings.timeouts.other)
      Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Log "Deleted account '$($t.nickname)'."
  }
  $ids = $targets | ForEach-Object { $_.id }
  $Store.accounts = @($Store.accounts | Where-Object { $ids -notcontains $_.id })
  Save-AccountStore $Store
  Wait-Enter
}

function Switch-Freeze($Store) {
  Show-Header 'Freeze / unfreeze account'
  $idx = Select-Account $Store
  if ($idx -lt 0) { return }
  $a = @($Store.accounts)[$idx]
  Set-Prop $a 'frozen' (-not [bool](Get-Prop $a 'frozen' $false))
  Save-AccountStore $Store
  Write-Log ("Account '{0}' is now {1}." -f $a.nickname, $(if ($a.frozen) { 'FROZEN' } else { 'ACTIVE' }))
  Start-Sleep -Milliseconds 700
}

function Manage-Organizations($Store, $Settings) {
  Show-Header 'Organizations'
  $idx = Select-Account $Store
  if ($idx -lt 0) { return }
  while ($true) {
    $acct = @($Store.accounts)[$idx]
    Show-Header "Organizations: $($acct.nickname)"
    $orgs = @(Get-Prop $acct 'organizations' @())
    if ($orgs.Count -eq 0) { Write-Host '  (none - use option 1 to discover)' }
    for ($i = 0; $i -lt $orgs.Count; $i++) {
      $o = $orgs[$i]
      $state = if (Get-Prop $o 'enabled' $true) { 'ENABLED ' } else { 'DISABLED' }
      Write-Host ('  {0}) [{1}] {2}  id={3}' -f ($i + 1), $state, $o.name, $o.id)
    }
    Write-Host ''
    Write-Host '  1) Discover organizations (sign in)'
    Write-Host '  2) Enable / disable an organization'
    Write-Host '  3) Rename an organization (changes its backup file names)'
    Write-Host '  4) Remove an organization from the list'
    Write-Host '  5) Back'
    Write-Host ''
    switch (Read-Choice 'Choose [1-5]' 5) {
      1 { Update-Organizations $Store $acct $Settings }
      2 {
        $n = Read-Choice 'Which organization [number]' $orgs.Count
        if ($n -ge 1) { $o = $orgs[$n - 1]; Set-Prop $o 'enabled' (-not [bool](Get-Prop $o 'enabled' $true)); Save-AccountStore $Store }
      }
      3 {
        $n = Read-Choice 'Which organization [number]' $orgs.Count
        if ($n -ge 1) { $o = $orgs[$n - 1]; $o.name = Read-Text 'Name' $o.name; Save-AccountStore $Store }
      }
      4 {
        $n = Read-Choice 'Which organization [number]' $orgs.Count
        if ($n -ge 1) {
          $o = $orgs[$n - 1]
          if (Confirm-Typed "Remove '$($o.name)' from the backup list? (Re-discovering adds it back; disabling is usually better.)") {
            Set-Prop $acct 'organizations' @($orgs | Where-Object { $_.id -ne $o.id })
            Save-AccountStore $Store
          }
        }
      }
      5 { return }
    }
  }
}

# ------------------------------------------------------------------ destinations

function Show-Destinations($Settings) {
  $dests = @($Settings.destinations)
  if ($dests.Count -eq 0) { Write-Host '  (none - backups have nowhere to go!)' -ForegroundColor Yellow; return }
  for ($i = 0; $i -lt $dests.Count; $i++) {
    $d = $dests[$i]
    $flags = @()
    $flags += $(if (Get-Prop $d 'enabled' $true) { 'ENABLED' } else { 'DISABLED' })
    if (Get-Prop $d 'optional' $false) { $flags += 'optional' }
    if (Get-Prop $d 'writeLatest' $false) { $flags += 'latest-copy' }
    Write-Host ('  {0}) {1}  [{2}]' -f ($i + 1), $d.name, ($flags -join ', '))
    Write-Host ('       path: {0}' -f $d.path)
    $resolved = Resolve-DestinationRoot $d.path
    if ($resolved -ne $d.path) { Write-Host ('       -> {0}' -f $resolved) -ForegroundColor DarkGray }
    Write-Host ('       keep: last {0}, daily {1}, weekly {2}, monthly {3}' -f (Get-Prop $d 'keepLast' 0), (Get-Prop $d 'keepDaily' 0), (Get-Prop $d 'keepWeekly' 0), (Get-Prop $d 'keepMonthly' 0)) -ForegroundColor DarkGray
  }
}

function Edit-DestinationFields($Settings, $Dest) {
  while ($true) {
    $name = Read-Text 'Name (short label, e.g. local, nas, onedrive, usb)' ([string](Get-Prop $Dest 'name' ''))
    if (-not $name) { return $false }
    $clash = @($Settings.destinations | Where-Object { $_ -ne $Dest -and $_.name -eq $name }).Count -gt 0
    if (-not $clash) { break }
    Say "  '$name' is already used." Yellow
  }
  Say '  Path examples: exports   D:\Backups\Vault   \\nas\backup\vault   %OneDrive%\Backups\Vault' DarkGray
  $path = Read-Text 'Folder path (relative paths are inside this tool''s folder)' ([string](Get-Prop $Dest 'path' ''))
  if (-not $path) { return $false }
  Say ('  Resolves to: {0}' -f (Resolve-DestinationRoot $path)) DarkGray
  $optional = Read-YesNo 'Optional? (skip quietly when the folder is missing, e.g. USB drive / offline NAS)' ([bool](Get-Prop $Dest 'optional' $false))
  $latest = Read-YesNo 'Also keep an always-current "latest" copy?' ([bool](Get-Prop $Dest 'writeLatest' $true))
  Write-Host ''
  Say '  Retention (0 = no limit for that rule; if all four are 0 nothing is ever deleted).' DarkGray
  Say '  A backup is kept if ANY rule selects it; the newest backup is always kept.' DarkGray
  $kl = Read-Int '  Keep the most recent N backups' ([int](Get-Prop $Dest 'keepLast' 24))
  $kd = Read-Int '  Keep one per day for N days' ([int](Get-Prop $Dest 'keepDaily' 14))
  $kw = Read-Int '  Keep one per week for N weeks' ([int](Get-Prop $Dest 'keepWeekly' 8))
  $km = Read-Int '  Keep one per month for N months' ([int](Get-Prop $Dest 'keepMonthly' 12))
  Set-Prop $Dest 'name' $name; Set-Prop $Dest 'path' $path; Set-Prop $Dest 'optional' $optional; Set-Prop $Dest 'writeLatest' $latest
  Set-Prop $Dest 'keepLast' $kl; Set-Prop $Dest 'keepDaily' $kd; Set-Prop $Dest 'keepWeekly' $kw; Set-Prop $Dest 'keepMonthly' $km
  if ($null -eq (Get-Prop $Dest 'enabled')) { Set-Prop $Dest 'enabled' $true }
  return $true
}

function Test-DestinationWrite($Dest) {
  $root = Resolve-DestinationRoot $Dest.path
  try {
    if (-not (Test-Path -LiteralPath $root)) {
      if (Get-Prop $Dest 'optional' $false) { Say "  Folder does not exist (optional destination would be skipped): $root" Yellow; return }
      New-Item -ItemType Directory -Force -Path $root | Out-Null
    }
    $f = Join-Path $root ('.write-test-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($f, 'test')
    Remove-Item -LiteralPath $f -Force
    $free = $null
    try { $free = [Math]::Round((New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($root))).AvailableFreeSpace / 1GB, 1) } catch { }
    $freeText = if ($null -ne $free) { " ($free GB free)" } else { '' }
    Say "  OK: $root is writable$freeText." Green
  } catch {
    Say "  FAILED: $root - $($_.Exception.Message)" Red
  }
}

function Manage-Destinations($Settings) {
  while ($true) {
    Show-Header 'Backup destinations & retention'
    Show-Destinations $Settings
    $dests = @($Settings.destinations)
    Write-Host ''
    Write-Host '  1) Add destination'
    Write-Host '  2) Edit destination'
    Write-Host '  3) Enable / disable destination'
    Write-Host '  4) Remove destination (files already there are kept)'
    Write-Host '  5) Test that all destinations are writable'
    Write-Host '  6) Back'
    Write-Host ''
    switch (Read-Choice 'Choose [1-6]' 6) {
      1 {
        $d = [pscustomobject]@{ name = ''; path = ''; enabled = $true; optional = $false; writeLatest = $true; keepLast = 24; keepDaily = 14; keepWeekly = 8; keepMonthly = 12 }
        if (Edit-DestinationFields $Settings $d) { $Settings.destinations = @($dests + $d); Save-Settings $Settings; Write-Log "Added destination '$($d.name)' -> $($d.path)" }
      }
      2 {
        $n = Read-Choice 'Edit which destination [number]' $dests.Count
        if ($n -ge 1) {
          $d = $dests[$n - 1]
          if (Edit-DestinationFields $Settings $d) { Save-Settings $Settings; Write-Log "Updated destination '$($d.name)'." }
        }
      }
      3 {
        $n = Read-Choice 'Toggle which destination [number]' $dests.Count
        if ($n -ge 1) { $d = $dests[$n - 1]; Set-Prop $d 'enabled' (-not [bool](Get-Prop $d 'enabled' $true)); Save-Settings $Settings }
      }
      4 {
        $n = Read-Choice 'Remove which destination [number]' $dests.Count
        if ($n -ge 1 -and (Confirm-Typed "Remove destination '$($dests[$n - 1].name)'?")) {
          $gone = $dests[$n - 1]
          $Settings.destinations = @($dests | Where-Object { $_ -ne $gone })
          Save-Settings $Settings
          Write-Log "Removed destination '$($gone.name)'."
        }
      }
      5 { foreach ($d in $dests) { Write-Host $d.name; Test-DestinationWrite $d }; Wait-Enter }
      6 { return }
    }
  }
}

# ------------------------------------------------------------------ general settings

function Edit-Template($Settings, [string]$Key, [switch]$AllowTime) {
  Write-Host ''
  Say '  Tokens: {account} {scope} {timestamp} {date} {host}' DarkGray
  Say '  {scope} is "personal" or "org-<name>". Use \ for sub-folders, e.g. {account}\{scope}\{timestamp}.json' DarkGray
  if ($AllowTime) { Say '  Without {timestamp} or {date}, each run overwrites the previous file (no history, no retention).' DarkGray }
  $v = Read-Text 'Template' ([string]$Settings.$Key)
  $problem = Test-FileTemplate $v -AllowTimeTokens:$AllowTime
  if ($problem) { Say "  Not saved: $problem" Yellow; Wait-Enter; return }
  $Settings.$Key = $v
  Save-Settings $Settings
}

function Edit-SettingsInNotepad {
  $before = [IO.File]::ReadAllText($script:SettingsPath)
  Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $script:SettingsPath) -Wait
  try {
    $s = Load-Settings
    Say 'settings.json is valid.' Green
    Start-Sleep -Milliseconds 800
    return $s
  } catch {
    Say $_.Exception.Message Red
    if (Read-YesNo 'Undo your changes?' $true) {
      [IO.File]::WriteAllText($script:SettingsPath, $before, (New-Object Text.UTF8Encoding($false)))
      Say 'Restored.' Green
    } else { Say 'Left as is. Backups will refuse to run until it is fixed.' Yellow }
    Wait-Enter
    return (Load-SettingsOrDefault)
  }
}

function Load-SettingsOrDefault {
  try { return Load-Settings } catch { return $null }
}

function Manage-General($Settings) {
  while ($true) {
    Show-Header 'General settings'
    $t = $Settings.timeouts
    Write-Host ("  1) File name template        : {0}" -f $Settings.fileNameTemplate)
    Write-Host ("  2) Latest-copy file template : {0}" -f $Settings.latestFileNameTemplate)
    Write-Host ("  3) Timestamp format          : {0}   (e.g. {1})" -f $Settings.timestampFormat, (Get-Date).ToString($Settings.timestampFormat))
    Write-Host ("  4) Default export format     : {0}" -f $Settings.exportFormat)
    Write-Host ("  5) After each run            : {0}" -f $(if ($Settings.sessionMode -eq 'lock') { 'lock (stay signed in; fewer logins)' } else { 'log out (nothing left signed in)' }))
    Write-Host ("  6) Advanced: edit settings.json in Notepad (timeouts {0}/{1}/{2}/{3}s, log size, task options)" -f $t.login, $t.unlock, $t.sync, $t.export)
    Write-Host  '  7) Back'
    Write-Host ''
    switch (Read-Choice 'Choose [1-7]' 7) {
      1 { Edit-Template $Settings 'fileNameTemplate' -AllowTime }
      2 { Edit-Template $Settings 'latestFileNameTemplate' }
      3 {
        Say '  .NET date format, e.g. yyyy-MM-dd_HHmmss or yyyyMMdd-HHmm. No colons or slashes.' DarkGray
        $old = $Settings.timestampFormat
        $Settings.timestampFormat = Read-Text 'Timestamp format' $old
        $allErrs = Test-Settings $Settings
        $errs = @($allErrs | Where-Object { $_ -like 'timestampFormat*' })
        if ($errs.Count -gt 0) { $Settings.timestampFormat = $old; Say "  Not saved: $($errs[0])" Yellow; Wait-Enter }
        else {
          if ($old -ne $Settings.timestampFormat) { Say '  Note: retention only recognises files that use the current format.' Yellow; Wait-Enter }
          Save-Settings $Settings
        }
      }
      4 {
        Write-Host '  1) password - password-protected, importable anywhere'
        Write-Host '  2) account  - account-restricted, importable only into the same account'
        $Settings.exportFormat = if ((Read-Int 'Choose' $(if ($Settings.exportFormat -eq 'account') { 2 } else { 1 }) 1 2) -eq 2) { 'account' } else { 'password' }
        Save-Settings $Settings
        if ($Settings.exportFormat -eq 'password') { Say '  Accounts without a stored export password will fail until you set one (Edit account > 3).' Yellow; Wait-Enter }
      }
      5 {
        Write-Host '  1) Log out after each run (most private; signs in every run)'
        Write-Host '  2) Lock after each run (keeps an encrypted local cache; avoids repeated logins / rate limits)'
        $Settings.sessionMode = if ((Read-Int 'Choose' $(if ($Settings.sessionMode -eq 'lock') { 2 } else { 1 }) 1 2) -eq 2) { 'lock' } else { 'logout' }
        Save-Settings $Settings
      }
      6 { $s = Edit-SettingsInNotepad; if ($s) { $Settings = $s } else { return } }
      7 { return }
    }
  }
}

# ------------------------------------------------------------------ main

function Main {
  Write-Log '===== Setup started ====='
  try { $settings = Load-Settings }
  catch {
    Say $_.Exception.Message Red
    if (Read-YesNo 'Open settings.json in Notepad to fix it?' $true) { $settings = Edit-SettingsInNotepad }
    if (-not $settings) { return 2 }
  }
  $store = Load-AccountStore

  while ($true) {
    Show-Header 'Bitwarden / Vaultwarden Backup Setup'
    Show-Accounts $store
    Write-Host ''
    Write-Host ('Destinations: {0}' -f ((@($settings.destinations) | ForEach-Object { if (Get-Prop $_ 'enabled' $true) { $_.name } else { "$($_.name) (off)" } }) -join ', '))
    Write-Host ''
    Write-Host '  1) Add account'
    Write-Host '  2) Edit account'
    Write-Host '  3) Remove account or instance'
    Write-Host '  4) Freeze / unfreeze account'
    Write-Host '  5) Organizations'
    Write-Host '  6) Backup destinations & retention'
    Write-Host '  7) General settings'
    Write-Host '  8) Back'
    Write-Host ''
    try {
      switch (Read-Choice 'Choose [1-8]' 8) {
        1 { Add-Account $store $settings }
        2 { Edit-Account $store $settings }
        3 { Remove-AccountOrInstance $store $settings }
        4 { Switch-Freeze $store }
        5 { Manage-Organizations $store $settings }
        6 { Manage-Destinations $settings }
        7 { Manage-General $settings }
        8 { Write-Log 'Leaving setup.'; return 0 }
      }
    } catch {
      Say "Error: $($_.Exception.Message)" Red
      Write-Log "Setup error: $($_.Exception.Message)" ERROR
      Wait-Enter
    }
    $store = Load-AccountStore
    $reloaded = Load-SettingsOrDefault
    if ($reloaded) { $settings = $reloaded }
  }
}

exit ([int](Main | Select-Object -Last 1))
#END_SCRIPT

#BEGIN_SCRIPT TASKS
# bitwarden_tasks.ps1 - creates, inspects, runs and removes the scheduled backup task.
# Generated by run.bat. Edit run.bat instead: this file is rewritten when it differs.
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('Create', 'Remove', 'View', 'Run')]
  [string]$Action,

  [ValidateSet('Interval', 'Daily')]
  [string]$Schedule = 'Interval',

  [int]$Minutes = 60,   # Interval: 0 = ask
  [string]$At = ''      # Daily: HH:mm, blank = ask
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bw_common.ps1')
$script:LogFile = Join-Path $script:LogsDir 'tasks.log'
Initialize-Dirs

$PsBackup = Join-Path $script:ScriptsDir 'bitwarden_backup_all.ps1'
$VbsPath = Join-Path $script:ScriptsDir 'run_bitwarden_backup_all.vbs'
$PsExe = '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe'
$PsExeResolved = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Inv = [Globalization.CultureInfo]::InvariantCulture
$PsArgs = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $PsBackup

try { $settings = Load-Settings } catch { $settings = Get-DefaultSettings; Write-Log "Using default task options: $($_.Exception.Message)" WARN }
$TaskName = [string]$settings.task.name

function Get-TaskFolder {
  $svc = New-Object -ComObject 'Schedule.Service'
  $svc.Connect()
  return @{ Service = $svc; Folder = $svc.GetFolder('\') }
}

function Get-Task {
  try { return (Get-TaskFolder).Folder.GetTask($TaskName) } catch { return $null }
}

function Resolve-Runner([string]$Mode) {
  $vbsAvailable = Test-Path (Join-Path $env:WINDIR 'System32\vbscript.dll')
  $build = [Environment]::OSVersion.Version.Build
  if ($Mode -eq 'auto') {
    if ($vbsAvailable) { return 'vbs' }
    if ($build -ge 19041) { return 'conhost' }
    return 'powershell'
  }
  if ($Mode -eq 'vbs' -and -not $vbsAvailable) {
    Write-Log 'VBScript is not installed on this PC; using conhost --headless instead.' WARN
    return 'conhost'
  }
  return $Mode
}

function Write-VbsRunner {
  # VBScript strings escape quotes by doubling them; backslashes are literal.
  $cmd = ('{0} {1}' -f $PsExe, $PsArgs).Replace('"', '""')
  $vbs = @(
    "' run_bitwarden_backup_all.vbs - generated by bitwarden_tasks.ps1",
    "' Runs the backup without a visible window and passes its exit code to Task Scheduler.",
    'Option Explicit',
    'Dim shell',
    'Set shell = CreateObject("WScript.Shell")',
    ('WScript.Quit shell.Run("{0}", 0, True)' -f $cmd)
  ) -join "`r`n"
  # UTF-16 LE keeps non-ASCII folder names (e.g. C:\Users\Jose) working; wscript reads it natively.
  [IO.File]::WriteAllText($VbsPath, $vbs + "`r`n", [Text.Encoding]::Unicode)
  Write-Log "Wrote VBS runner: $VbsPath"
}

function Get-ActionSpec([string]$Runner) {
  switch ($Runner) {
    'vbs' { Write-VbsRunner; return @{ Path = '%SystemRoot%\System32\wscript.exe'; Args = ('//B //NoLogo "{0}"' -f $VbsPath) } }
    'conhost' { return @{ Path = '%SystemRoot%\System32\conhost.exe'; Args = ('--headless "{0}" -WindowStyle Hidden {1}' -f $PsExeResolved, $PsArgs) } }
    default { return @{ Path = $PsExe; Args = ('-WindowStyle Hidden {0}' -f $PsArgs) } }
  }
}

function New-BackupTask {
  if (-not (Test-Path -LiteralPath $PsBackup)) { Write-Log "Backup script missing: $PsBackup" ERROR; return 1 }

  if ($Schedule -eq 'Interval' -and $Minutes -le 0) {
    $v = Read-Host 'Run every how many minutes? (5 - 1440)'
    if (-not [int]::TryParse($v, [ref]$Minutes) -or $Minutes -lt 1 -or $Minutes -gt 1440) { Write-Log 'Invalid interval; nothing changed.' WARN; return 1 }
  }
  $atTime = $null
  if ($Schedule -eq 'Daily') {
    if (-not $At) { $At = Read-Host 'Run daily at what time? (24h, HH:mm, e.g. 02:30)' }
    try { $atTime = [datetime]::ParseExact($At.Trim(), 'H:mm', [Globalization.CultureInfo]::InvariantCulture) }
    catch { Write-Log "Invalid time '$At'; nothing changed." WARN; return 1 }
  }

  $runner = Resolve-Runner ([string]$settings.task.runner)
  $spec = Get-ActionSpec $runner

  $tf = Get-TaskFolder
  $def = $tf.Service.NewTask(0)
  $def.RegistrationInfo.Description = "Bitwarden/Vaultwarden encrypted backup ($($script:Root))"
  $s = $def.Settings
  $s.Enabled = $true
  $s.Hidden = $false
  $s.StartWhenAvailable = $true                  # catch up on runs missed while the PC was off/asleep
  $s.MultipleInstances = 2                       # TASK_INSTANCES_IGNORE_NEW: never overlap runs
  $s.DisallowStartIfOnBatteries = $false
  $s.StopIfGoingOnBatteries = $false
  $s.RunOnlyIfNetworkAvailable = [bool]$settings.task.requireNetwork
  $s.ExecutionTimeLimit = ('PT{0}M' -f [Math]::Max(5, [int]$settings.task.executionLimitMinutes))

  # Interactive token: runs as you, only while you are signed in. Required because the stored
  # passwords are encrypted with your Windows account (DPAPI) and a stored-password-less
  # "run whether logged on or not" task cannot decrypt them.
  $def.Principal.LogonType = 3
  $def.Principal.RunLevel = 0

  if ($Schedule -eq 'Daily') {
    $trigger = $def.Triggers.Create(2)          # TASK_TRIGGER_DAILY
    $trigger.DaysInterval = 1
    $trigger.StartBoundary = (Get-Date).Date.Add($atTime.TimeOfDay).ToString("yyyy-MM-dd'T'HH:mm:ss", $Inv)
    $desc = "daily at $($atTime.ToString('HH:mm'))"
  } else {
    $trigger = $def.Triggers.Create(1)          # TASK_TRIGGER_TIME + indefinite repetition
    $trigger.StartBoundary = (Get-Date).AddMinutes(1).ToString("yyyy-MM-dd'T'HH:mm:00", $Inv)
    $trigger.Repetition.Interval = ('PT{0}M' -f $Minutes)
    $desc = "every $Minutes minute(s)"
  }
  $trigger.Enabled = $true

  $act = $def.Actions.Create(0)
  $act.Path = $spec.Path
  $act.Arguments = $spec.Args
  $act.WorkingDirectory = $script:Root

  # 6 = TASK_CREATE_OR_UPDATE, 3 = TASK_LOGON_INTERACTIVE_TOKEN
  $tf.Folder.RegisterTaskDefinition($TaskName, $def, 6, $null, $null, 3) | Out-Null
  Write-Log "Task '$TaskName' created/updated: $desc, runner=$runner." OK
  Write-Log "  Action: $($spec.Path) $($spec.Args)"
  return 0
}

function Remove-BackupTask {
  $tf = Get-TaskFolder
  try { $tf.Folder.DeleteTask($TaskName, 0); Write-Log "Removed task '$TaskName'." OK }
  catch { Write-Log "Task '$TaskName' does not exist." }
  if (Test-Path -LiteralPath $VbsPath) { Remove-Item -LiteralPath $VbsPath -Force -ErrorAction SilentlyContinue }
  return 0
}

function Format-TaskResult([int]$Code) {
  switch ($Code) {
    0 { return '0 (success)' }
    1 { return '1 (some exports failed - see backup.log)' }
    2 { return '2 (configuration/fatal error - see backup.log)' }
    0x41300 { return '0x41300 (ready)' }
    0x41301 { return '0x41301 (running now)' }
    0x41303 { return '0x41303 (has not run yet)' }
    0x41306 { return '0x41306 (terminated - hit the execution time limit?)' }
    default { return ('0x{0:X} ' -f $Code) }
  }
}

function Show-BackupTask {
  $task = Get-Task
  if (-not $task) { Write-Host "Task '$TaskName' does not exist. Create it from the scheduler menu."; return 0 }
  $states = @{ 0 = 'Unknown'; 1 = 'Disabled'; 2 = 'Queued'; 3 = 'Ready'; 4 = 'Running' }
  $def = $task.Definition
  Write-Host ''
  Write-Host "Task      : $TaskName"
  Write-Host "State     : $($states[[int]$task.State])"
  Write-Host "Last run  : $(if ($task.LastRunTime.Year -lt 2000) { 'never' } else { $task.LastRunTime })"
  Write-Host "Result    : $(Format-TaskResult $task.LastTaskResult)"
  Write-Host "Next run  : $(if ($task.NextRunTime.Year -lt 2000) { 'not scheduled' } else { $task.NextRunTime })"
  foreach ($t in $def.Triggers) {
    $what = switch ($t.Type) { 1 { "once from $($t.StartBoundary)" } 2 { "daily, starting $($t.StartBoundary)" } default { "type $($t.Type)" } }
    if ($t.Repetition.Interval) { $what += ", repeating every $($t.Repetition.Interval)" }
    Write-Host "Trigger   : $what"
  }
  foreach ($a in $def.Actions) { Write-Host "Action    : $($a.Path) $($a.Arguments)" }
  Write-Host "No overlap: $($def.Settings.MultipleInstances -eq 2)   Time limit: $($def.Settings.ExecutionTimeLimit)   Needs network: $($def.Settings.RunOnlyIfNetworkAvailable)"
  if ($def.Actions.Count -gt 0) {
    $a = @($def.Actions)[0]
    if ($a.Path -like '*wscript.exe' -and (Test-Path -LiteralPath $VbsPath)) {
      $txt = [IO.File]::ReadAllText($VbsPath)
      if ($txt -notmatch 'shell\.Run') { Write-Host 'WARNING: the VBS runner is a stub and does nothing. Re-create the task to fix it.' -ForegroundColor Red }
    }
  }
  Write-Host ''
  return 0
}

function Start-BackupTask {
  $task = Get-Task
  if (-not $task) { Write-Log "Task '$TaskName' does not exist." WARN; return 1 }
  [void]$task.Run($null)
  Write-Log "Started task '$TaskName'. Check 'View last backup result' in a minute." OK
  return 0
}

Write-Log "=== Action: $Action ==="
$code = 1
try {
  $code = switch ($Action) {
    'Create' { New-BackupTask }
    'Remove' { Remove-BackupTask }
    'View' { Show-BackupTask }
    'Run' { Start-BackupTask }
  }
} catch {
  Write-Log "ERROR: $($_.Exception.Message)" ERROR
  $code = 1
}
exit ([int]($code | Select-Object -Last 1))
#END_SCRIPT

#BEGIN_SCRIPT INSTALL
# install_bw.ps1 - installs or updates the Bitwarden CLI (bw.exe) into .\bin
# Generated by run.bat. Edit run.bat instead: this file is rewritten when it differs.
param([switch]$Update)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads ~10x slower in Windows PowerShell
. (Join-Path $PSScriptRoot 'bw_common.ps1')
$script:LogFile = Join-Path $script:LogsDir 'setup.log'
Initialize-Dirs
New-Item -ItemType Directory -Force -Path $script:BinDir | Out-Null
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

function Get-InstalledVersion {
  if (-not (Test-Path -LiteralPath $script:BwPath)) { return $null }
  $r = Invoke-Bw -ArgumentList @('--version') -TimeoutSec 60
  if ($r.Code -ne 0) { return $null }
  return (Get-LastLine $r.Out)
}

function Get-LatestRelease {
  # Latest stable CLI release from GitHub, including the SHA-256 digest GitHub publishes per asset.
  $headers = @{ 'User-Agent' = 'vaultwarden-backup-script'; 'Accept' = 'application/vnd.github+json' }
  $releases = Invoke-RestMethod -Uri 'https://api.github.com/repos/bitwarden/clients/releases?per_page=60' -Headers $headers -TimeoutSec 30
  $rel = $releases | Where-Object { $_.tag_name -like 'cli-v*' -and -not $_.prerelease -and -not $_.draft } | Select-Object -First 1
  if (-not $rel) { throw 'No CLI release found on GitHub.' }
  $ver = $rel.tag_name -replace '^cli-v', ''
  $asset = $rel.assets | Where-Object { $_.name -eq "bw-windows-$ver.zip" } | Select-Object -First 1
  if (-not $asset) { throw "Release $ver has no bw-windows-$ver.zip asset." }
  $digest = [string](Get-Prop $asset 'digest' '')
  return [pscustomobject]@{ Version = $ver; Url = $asset.browser_download_url; Sha256 = ($digest -replace '^sha256:', '') }
}

$current = Get-InstalledVersion
if ($current -and -not $Update) { Write-Log "Bitwarden CLI $current already installed."; exit 0 }

$release = $null
try { $release = Get-LatestRelease }
catch { Write-Log "GitHub lookup failed ($($_.Exception.Message)); falling back to bitwarden.com download." WARN }
if (-not $release) {
  $release = [pscustomobject]@{ Version = $null; Url = 'https://bitwarden.com/download/?app=cli&platform=windows'; Sha256 = '' }
}

if ($current -and $release.Version -and $current -eq $release.Version) {
  Write-Log "Bitwarden CLI $current is already the latest version." OK
  exit 0
}

$tmp = Join-Path $env:TEMP ('bwcli-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
  $zip = Join-Path $tmp 'bw.zip'
  $label = if ($release.Version) { $release.Version } else { 'latest' }
  Write-Log "Downloading Bitwarden CLI $label..."
  Invoke-WebRequest -Uri $release.Url -OutFile $zip -UseBasicParsing -TimeoutSec 300

  if ($release.Sha256) {
    $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    if ($actual -ne $release.Sha256) { throw "SHA-256 mismatch! expected $($release.Sha256), got $actual. Download discarded." }
    Write-Log 'SHA-256 checksum verified.' OK
  } else {
    Write-Log 'No published checksum available for this download; relying on the code signature check.' WARN
  }

  Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
  $exe = Get-ChildItem -LiteralPath $tmp -Recurse -Filter 'bw.exe' | Select-Object -First 1
  if (-not $exe) { throw 'bw.exe not found in the downloaded archive.' }

  $sig = Get-AuthenticodeSignature -LiteralPath $exe.FullName
  if ($sig.Status -eq 'Valid') {
    Write-Log "Code signature valid: $($sig.SignerCertificate.Subject)" OK
  } elseif ($sig.Status -eq 'NotSigned') {
    Write-Log 'bw.exe is not code-signed.' WARN
    if (-not $release.Sha256) { throw 'Refusing to install an unsigned bw.exe without a verified checksum.' }
  } else {
    throw "bw.exe has an INVALID code signature ($($sig.Status)). Not installing."
  }

  $lock = Enter-BwLock 120000
  if ($null -eq $lock) { throw 'A backup has been running for over 2 minutes; try the update again later.' }
  try { Copy-Item -LiteralPath $exe.FullName -Destination $script:BwPath -Force }
  finally { Exit-BwLock $lock }
  $new = Get-InstalledVersion
  Write-Log "Bitwarden CLI ready: $new ($script:BwPath)" OK
  exit 0
} catch {
  Write-Log "Install failed: $($_.Exception.Message)" ERROR
  exit 1
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
#END_SCRIPT
