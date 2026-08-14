@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ==========================================================
rem  run.bat - Vaultwarden Backup
rem ==========================================================

rem ---- Relaunch guard (keeps the window open) ----
if /I "%~1" NEQ "__STAY__" (
  echo Launching in a persistent Command Prompt window...
  start "Vaultwarden Backup" "%ComSpec%" /k ""%~f0" __STAY__"
  exit /b 0
)

rem ---- Dynamically get current directory and strip trailing backslash ----
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "BIN=%ROOT%\bin"
set "SCRIPTS=%ROOT%\scripts"
set "CONFIG=%ROOT%\config"
set "ORGCONFIG=%CONFIG%\organizations"
set "EXPORTS=%ROOT%\exports"
set "LOGS=%ROOT%\logs"

set "LOGFILE=%LOGS%\setup.log"
set "POLICY_SENTINEL=%CONFIG%\executionpolicy.done"

call :EnsureDirs
call :EnsureScripts
call :Log "===== setup.bat started ====="

rem ---- Ensure the Bitwarden CLI exists ----
if not exist "%BIN%\bw.exe" (
  call :Log "Bitwarden CLI not found. Downloading and extracting..."
  call :InstallBw
  set "rc=!errorlevel!"
  if not "!rc!"=="0" (
    call :Log "ERROR: Bitwarden CLI install failed (exit !rc!)."
    echo.
    echo [ERROR] Failed to install Bitwarden CLI. Check:
    echo   "%LOGFILE%"
    echo.
    pause
    goto MAINMENU
  )
) else (
  call :Log "Bitwarden CLI already present at '%BIN%\bw.exe'."
)

rem ---- One-time execution policy prompt ----
if not exist "%POLICY_SENTINEL%" (
  echo.
  echo [Setup] Optional: set PowerShell execution policy for this user.
  echo This lets your own scripts run without being blocked.
  echo.
  set "ans="
  set /p "ans=Set execution policy to RemoteSigned for current user? (Y/N) : "
  if /I "!ans!"=="Y" (
    call :Log "User approved RemoteSigned execution policy."
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force" >nul 2>&1
    if not "!errorlevel!"=="0" (
      call :Log "WARNING: Failed to set execution policy (continuing)."
    ) else (
      call :Log "Execution policy set to RemoteSigned."
    )
  ) else (
    call :Log "User declined execution policy change."
  )
  >"%POLICY_SENTINEL%" echo done
)

:MAINMENU
cls
echo ==========================================
echo   Bitwarden / Vaultwarden Backup Helper
echo ==========================================
echo.
echo   1^) Configure accounts, instances, and organizations
echo   2^) Run backup now ^(all accounts^)
echo   3^) Scheduler menu ^(create/update tasks^)
echo   4^) Remove scheduled task
echo   5^) View scheduled task status
echo   6^) Exit
echo.

set "choice="
set /p "choice=Choose an option [1-6]: "

if "!choice!"=="1" goto DO_SETUP
if "!choice!"=="2" goto DO_RUN
if "!choice!"=="3" goto DO_SCHEDMENU
if "!choice!"=="4" goto DO_REMOVE
if "!choice!"=="5" goto DO_VIEW
if "!choice!"=="6" goto END

call :Log "Invalid menu choice: !choice!"
timeout /t 1 >nul
goto MAINMENU

:DO_SETUP
call :Log "User selected menu option '1'."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\bitwarden_backup_setup.ps1"
set "rc=%errorlevel%"

if not "!rc!"=="0" (
  call :Log "bitwarden_backup_setup.ps1 exited with errorlevel !rc!."
  echo.
  echo [Info] Setup finished with a warning/error. See:
  echo   "%LOGFILE%"
  echo.
  pause
) else (
  call :Log "bitwarden_backup_setup.ps1 completed OK."
  timeout /t 1 >nul
)
goto MAINMENU

:DO_RUN
call :Log "User selected menu option '2'."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\bitwarden_backup_all.ps1"
set "rc=%errorlevel%"

if not "!rc!"=="0" (
  call :Log "bitwarden_backup_all.ps1 exited with errorlevel !rc!."
  echo.
  echo [Info] Backup completed with a warning/error. Check:
  echo   "%ROOT%\logs\backup.log"
  echo   "%LOGFILE%"
  echo.
  pause
) else (
  call :Log "bitwarden_backup_all.ps1 completed OK."
  timeout /t 1 >nul
)
goto MAINMENU

:DO_SCHEDMENU
call :Log "User opened scheduler submenu."
:SUBMENU
cls
echo ==========================================
echo   Scheduler Menu
echo ==========================================
echo.
echo   1^) Create/update task: HOURLY
echo   2^) Create/update task: every 30 minutes
echo   3^) Create/update task: every 1 minute ^(testing^)
echo   4^) Back
echo.

set "sub="
set /p "sub=Choose an option [1-4]: "

if "!sub!"=="1" (
  call :Log "Scheduler: Create 60"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\bitwarden_tasks.ps1" -Action Create -Minutes 60
  set "rc=!errorlevel!"
  if not "!rc!"=="0" (
    call :Log "Task create failed (60 min) rc=!rc!."
    echo.
    echo Task creation failed. See:
    echo   "%ROOT%\logs\tasks.log"
    echo.
    pause
  ) else (
    call :Log "Task create OK (60 min)."
    timeout /t 1 >nul
  )
  goto SUBMENU
)

if "!sub!"=="2" (
  call :Log "Scheduler: Create 30"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\bitwarden_tasks.ps1" -Action Create -Minutes 30
  set "rc=%errorlevel%"
  if not "!rc!"=="0" (
    call :Log "Task create failed (30 min) rc=!rc!."
    echo.
    echo Task creation failed. See:
    echo   "%ROOT%\logs\tasks.log"
    echo.
    pause
  ) else (
    call :Log "Task create OK (30 min)."
    timeout /t 1 >nul
  )
  goto SUBMENU
)

if "!sub!"=="3" (
  call :Log "Scheduler: Create 1"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\bitwarden_tasks.ps1" -Action Create -Minutes 1
  set "rc=%errorlevel%"
  if not "!rc!"=="0" (
    call :Log "Task create failed (1 min) rc=!rc!."
    echo.
    echo Task creation failed. See:
    echo   "%ROOT%\logs\tasks.log"
    echo.
    pause
  ) else (
    call :Log "Task create OK (1 min)."
    timeout /t 1 >nul
  )
  goto SUBMENU
)

if "!sub!"=="4" goto MAINMENU
goto SUBMENU

:DO_REMOVE
call :Log "User selected menu option '4' (Remove task)."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\bitwarden_tasks.ps1" -Action Remove
set "rc=%errorlevel%"

if not "!rc!"=="0" (
  call :Log "Task remove failed rc=!rc!."
  echo.
  echo Remove failed. See:
  echo   "%ROOT%\logs\tasks.log"
  echo.
  pause
) else (
  call :Log "Task removed OK."
  timeout /t 1 >nul
)
goto MAINMENU

:DO_VIEW
call :Log "User selected menu option '5' (View task)."
cls
echo ==========================================
echo   View Scheduled Task
echo ==========================================
echo.
echo Task name: BitwardenVaultBackup
echo.

echo [CMD view]
schtasks /Query /TN "BitwardenVaultBackup" /V /FO LIST 2>nul
echo.

echo [PowerShell view]
powershell.exe -NoProfile -Command "Get-ScheduledTask -TaskName 'BitwardenVaultBackup' -ErrorAction SilentlyContinue | Get-ScheduledTaskInfo | Format-List"
echo.
pause
goto MAINMENU

:END
call :Log "Exiting."
endlocal
exit /b 0

rem --------------------------
rem Helpers
rem --------------------------
:EnsureDirs
if not exist "%ROOT%"     md "%ROOT%"    >nul 2>&1
if not exist "%BIN%"     md "%BIN%"     >nul 2>&1
if not exist "%SCRIPTS%" md "%SCRIPTS%" >nul 2>&1
if not exist "%CONFIG%"  md "%CONFIG%"  >nul 2>&1
if not exist "%ORGCONFIG%" md "%ORGCONFIG%" >nul 2>&1
if not exist "%EXPORTS%" md "%EXPORTS%" >nul 2>&1
if not exist "%LOGS%"    md "%LOGS%"    >nul 2>&1
exit /b 0

:EnsureScripts
call :EnsureOneScript "#BEGIN_VBS" "#END_VBS" "%SCRIPTS%\run_bitwarden_backup_all.vbs"
call :EnsureOneScript "#BEGIN_PS1" "#END_PS1" "%SCRIPTS%\bitwarden_backup_all.ps1"
call :EnsureOneScript "#BEGIN_PS2" "#END_PS2" "%SCRIPTS%\bitwarden_backup_setup.ps1"
call :EnsureOneScript "#BEGIN_PS3" "#END_PS3" "%SCRIPTS%\bitwarden_tasks.ps1"
call :EnsureOneScript "#BEGIN_INSTALL_BW" "#END_INSTALL_BW" "%SCRIPTS%\install_bw.ps1"
exit /b 0

:EnsureOneScript <begin> <end> <outfile>
setlocal DisableDelayedExpansion
echo Recreating %~nx3 ...
call :ExtractScript "%~1" "%~2" "%~3"
endlocal
exit /b 0

:ExtractScript <begin_marker> <end_marker> <outfile>
setlocal DisableDelayedExpansion
rem -- Clean, loop-based inline array mapping without fragile string indexing or pipe operations --
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$o=@(); $g=$false; foreach($l in Get-Content -LiteralPath '%~f0'){ if($l.Trim() -eq '%~2'){$g=$false}; if($g){$o+=$l}; if($l.Trim() -eq '%~1'){$g=$true} }; Set-Content -LiteralPath '%~3' -Value $o -Encoding UTF8"
endlocal
exit /b 0

:InstallBw
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\install_bw.ps1"
exit /b %errorlevel%

:Log
set "msg=%~1"
for /f "tokens=1-2 delims=." %%a in ("%time%") do set "t=%%a.%%b"
set "stamp=[%date% %t%]"
echo %stamp% %msg%
>>"%LOGFILE%" echo %stamp% %msg%
exit /b 0

rem =============================================================
rem  Embedded helper scripts (extracted by :EnsureScripts)
rem =============================================================
goto :EOF

#BEGIN_VBS
' run_bitwarden_backup_all.vbs
' This block is dynamically managed via the Task Manager engine setup.
#END_VBS

#BEGIN_PS1
# bitwarden_backup_all.ps1
$ErrorActionPreference = "Stop"

$Root       = Split-Path $PSScriptRoot -Parent
$BwPath     = Join-Path $Root "bin\bw.exe"
$ConfigPath = Join-Path $Root "config\vault_accounts.json"
$ExportsDir = Join-Path $Root "exports"
$LogsDir    = Join-Path $Root "logs"
$LogFile    = Join-Path $LogsDir "backup.log"

New-Item -ItemType Directory -Force -Path $ExportsDir, $LogsDir | Out-Null

function Write-Log {
  param([string]$Message)
  $line = "[{0}] {1}" -f (Get-Date), $Message
  Write-Host $line
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function End-Script {
  param([int]$Code, [string]$Message = "")
  if ($Message) { Write-Log $Message }
  [Environment]::ExitCode = $Code
  return $Code
}

function Bw {
  param(
    [Parameter(Mandatory=$true)][string[]]$Args,
    [int]$TimeoutSec = 20
  )

  if (-not (Test-Path $BwPath)) {
    return [pscustomobject]@{ code = 127; out = "bw.exe not found at: $BwPath" }
  }

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $BwPath

  $psi.Arguments = ($Args | ForEach-Object {
    if ($_ -match '\s') { '"' + ($_ -replace '"','\"') + '"' } else { $_ }
  }) -join ' '

  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow  = $true

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi

  try { [void]$p.Start() }
  catch { return [pscustomobject]@{ code = 126; out = "Failed to start bw.exe: $($_.Exception.Message)" } }

  if (-not $p.WaitForExit($TimeoutSec * 1000)) {
    try { $p.Kill() } catch {}
    return [pscustomobject]@{ code = 124; out = "Timed out after ${TimeoutSec}s: bw $($Args -join ' ')" }
  }

  $stdout = ($p.StandardOutput.ReadToEnd() | Out-String).Trim()
  $stderr = ($p.StandardError.ReadToEnd()  | Out-String).Trim()

  $out = @()
  if ($stdout) { $out += $stdout }
  if ($stderr) { $out += $stderr }

  [pscustomobject]@{ code = $p.ExitCode; out = ($out -join "`n").Trim() }
}

function Decrypt-String {
  param([Parameter(Mandatory=$true)][string]$Enc)
  $ss   = ConvertTo-SecureString $Enc
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Preflight-Logout {
  param([string]$Tag)

  $r = Bw -Args @("logout") -TimeoutSec 10
  if ($r.code -eq 0) {
    Write-Log "${Tag}: logout OK."
  } elseif ($r.code -eq 1) {
    Write-Log "${Tag}: logout returned 1 (already logged out) - OK."
  } else {
    Write-Log "${Tag}: logout returned $($r.code) - continuing. Output: $($r.out)"
  }
}

function Ensure-Server {
  param([Parameter(Mandatory=$true)][string]$ServerUrl)

  $srv = $ServerUrl.Trim()
  if ([string]::IsNullOrWhiteSpace($srv)) { return $true }

  $r = Bw -Args @("config","server",$srv) -TimeoutSec 10
  if ($r.code -ne 0) {
    Write-Log "ERROR: bw config server failed for '$srv'. Output: $($r.out)"
    return $false
  }
  return $true
}

function Get-ConfiguredServer {
  $r = Bw -Args @("config","server") -TimeoutSec 10
  if ($r.code -ne 0) { return $null }
  if ([string]::IsNullOrWhiteSpace($r.out)) { return $null }
  return $r.out.Trim()
}

function Main {
  try {
    Write-Log "===== bitwarden_backup_all.ps1 started ====="

    if (-not (Test-Path $BwPath)) {
      Write-Log "ERROR: bw.exe not found at: $BwPath"
      return 2
    }

    if (-not (Test-Path $ConfigPath)) {
      Write-Log "ERROR: Config file not found: $ConfigPath"
      return 2
    }

    $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $cfg.accounts -or $cfg.accounts.Count -eq 0) {
      Write-Log "No accounts configured. Run setup first."
      return 0
    }

    Write-Log "Pre-run global logout (safety)..."
    Preflight-Logout "Pre-run"
    Write-Log ""

    foreach ($acct in $cfg.accounts) {
      try {
        if ($acct.frozen) {
          Write-Log "Skipping frozen account: $($acct.nickname)"
          Write-Log ""
          continue
        }

        Write-Log "=== Account: $($acct.nickname) ==="
        Write-Log "Server: $($acct.serverUrl)"
        Write-Log "Email:  $($acct.email)"

        if (-not (Ensure-Server -ServerUrl $acct.serverUrl)) {
          Write-Log "Skipping account due to server config failure."
          Write-Log ""
          continue
        }

        $current = Get-ConfiguredServer
        if ($current) { Write-Log "Configured server now: $current" }

        $master = Decrypt-String $acct.encMaster
        $export = Decrypt-String $acct.encExport

        Write-Log "Logging in..."
        $env:BW_PASSWORD = $master

        $login = Bw -Args @("login","--raw","--passwordenv","BW_PASSWORD",$acct.email) -TimeoutSec 30
        if ($login.code -ne 0 -or [string]::IsNullOrWhiteSpace($login.out)) {
          Write-Log "Login failed. Output: $($login.out)"
          Write-Log ""
          continue
        }
        $loginSession = $login.out.Trim()

        Write-Log "Unlocking..."
        $unlock = Bw -Args @("unlock","--raw","--passwordenv","BW_PASSWORD","--session",$loginSession) -TimeoutSec 30
        if ($unlock.code -ne 0 -or [string]::IsNullOrWhiteSpace($unlock.out)) {
          Write-Log "Unlock failed. Output: $($unlock.out)"
          Write-Log ""
          continue
        }
        $session = $unlock.out.Trim()

        $fileName = $acct.exportFileName
        if ([string]::IsNullOrWhiteSpace($fileName)) {
          $fileName = "{0}-vault-backup-encrypted.json" -f $acct.nickname
        }
        $exportPath = Join-Path $ExportsDir $fileName

        Write-Log "Exporting PERSONAL vault to $exportPath ..."
        $exp = Bw -Args @("export","--format","encrypted_json","--password",$export,"--session",$session,"--output",$exportPath) -TimeoutSec 60
        if ($exp.code -ne 0) {
          Write-Log "Export FAILED. Output: $($exp.out)"
          Write-Log ""
          continue
        }
        Write-Log "Personal export OK."

        if ($acct.organizations) {
          foreach ($org in $acct.organizations) {
            if ($null -eq $org) { continue }
            if ($org.enabled -eq $false) { continue }
            if ([string]::IsNullOrWhiteSpace($org.id)) { continue }

            $orgFile = $org.exportFileName
            if ([string]::IsNullOrWhiteSpace($orgFile)) {
              $safe = (($org.name -replace '\s+','_') -replace '[^a-zA-Z0-9_]', '').ToLower()
              $orgFile = ("{0}-{1}-org-encrypted.json" -f $acct.nickname, $safe)
            }

            $orgPath = Join-Path $ExportsDir $orgFile
            $orgName = if ($org.name) { $org.name } else { $org.id }

            Write-Log ("Exporting ORG '{0}' to {1} ..." -f $orgName, $orgPath)

            $orgExp = Bw -Args @(
              "export",
              "--organizationid", $org.id,
              "--format", "encrypted_json",
              "--password", $export,
              "--session", $session,
              "--output", $orgPath
            ) -TimeoutSec 60

            if ($orgExp.code -ne 0) {
              Write-Log ("ORG export FAILED ('{0}'). Output: {1}" -f $orgName, $orgExp.out)
              continue
            }

            Write-Log ("ORG export OK ('{0}')." -f $orgName)
          }
        }

        Write-Log "Logging out (session)..."
        $lo = Bw -Args @("logout","--session",$session) -TimeoutSec 20
        if ($lo.code -eq 0) {
          Write-Log "Logout OK."
        } elseif ($lo.code -eq 1) {
          Write-Log "Logout: already logged out (normal)."
        } else {
          Write-Log "Logout returned non-zero (usually harmless). Output: $($lo.out)"
        }

        Write-Log "Post-account global logout (safety)..."
        Preflight-Logout "Post-account"
        Write-Log ""
      }
      catch {
        Write-Log "Unexpected error for account $($acct.nickname): $($_.Exception.Message)"
        Write-Log ""
      }
      finally {
        Remove-Item Env:\BW_PASSWORD -ErrorAction SilentlyContinue
      }
    }

    Write-Log "Final logout (best-effort)..."
    Preflight-Logout "Final"
    Write-Log "All done."
    Write-Log "Returning to setup menu..."
    return 0
  }
  catch {
    Write-Log "FATAL: Unhandled error: $($_.Exception.Message)"
    return 1
  }
}

$code = Main
[void](End-Script -Code $code)
return
#END_PS1

#BEGIN_PS2
# bitwarden_backup_setup.ps1
param()

$ErrorActionPreference = "Stop"

$Root      = Split-Path $PSScriptRoot -Parent
$ConfigDir = Join-Path $Root "config"
$LogsDir   = Join-Path $Root "logs"
$LogFile   = Join-Path $LogsDir "setup.log"

$ConfigPath = Join-Path $ConfigDir "vault_accounts.json"
$BwPath     = Join-Path $Root "bin\bw.exe"

New-Item -ItemType Directory -Force -Path $ConfigDir, $LogsDir | Out-Null

function Log([string]$msg) {
  $line = "[{0}] {1}" -f (Get-Date), $msg
  Write-Host $line
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function End([int]$code) {
  [Environment]::ExitCode = $code
  return $code
}

function Prompt([string]$label) {
  $v = Read-Host $label
  if ($null -eq $v) { return "" }
  return $v.Trim()
}

function Prompt-Secret([string]$label) {
  $s = Read-Host -AsSecureString $label
  if ($null -eq $s) { return "" }
  return (ConvertFrom-SecureString $s)
}

function Decrypt-String {
  param([Parameter(Mandatory=$true)][string]$Enc)
  $ss   = ConvertTo-SecureString $Enc
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Load-Config {
  if (-not (Test-Path $ConfigPath)) {
    return [pscustomobject]@{ version = 1; accounts = @() }
  }
  try {
    $raw = Get-Content $ConfigPath -Raw -Encoding UTF8
    $cfg = $raw | ConvertFrom-Json
    if (-not $cfg.accounts) { $cfg | Add-Member -NotePropertyName accounts -NotePropertyValue @() -Force }
    return $cfg
  } catch {
    Log ("ERROR: Failed to parse config JSON at ${ConfigPath}: {0}" -f $_.Exception.Message)
    return [pscustomobject]@{ version = 1; accounts = @() }
  }
}

function Save-Config($cfg) {
  $json = $cfg | ConvertTo-Json -Depth 10
  Set-Content -Path $ConfigPath -Value $json -Encoding UTF8
  Log "Configuration saved to: $ConfigPath"
}

function List-Accounts($cfg) {
  Write-Host ""
  Write-Host "Current accounts:"
  if (-not $cfg.accounts -or $cfg.accounts.Count -eq 0) {
    Write-Host "  (none yet)"
    return
  }
  for ($i=0; $i -lt $cfg.accounts.Count; $i++) {
    $a = $cfg.accounts[$i]
    $state = if ($a.frozen) { "FROZEN" } else { "ACTIVE" }
    $orgCount = 0
    if ($a.PSObject.Properties.Name -contains "organizations" -and $a.organizations) {
      $orgCount = @($a.organizations).Count
    }
    Write-Host ("  {0}) {1}  [{2}]  orgs:{3}  on {4}  ({5})" -f ($i+1), $a.nickname, $state, $orgCount, $a.serverUrl, $a.email)
  }
}

function Confirm([string]$question) {
  Write-Host ""
  $ans = Prompt ($question + "  Type YES to confirm")
  return ($ans -eq "YES")
}

function Normalize-Url([string]$url) {
  $u = ($url.Trim())
  if ($u.EndsWith("/")) { $u = $u.TrimEnd("/") }
  return $u
}

function Get-BwOrganizations {
  param([Parameter(Mandatory=$true)][string]$Session)

  if (-not (Test-Path $BwPath)) { return @() }

  $out = & $BwPath list organizations --session $Session
  if (-not $out) { return @() }

  try { return ($out | ConvertFrom-Json) }
  catch { return @() }
}

function Get-OrgIdsFromItemsFallback {
  param([Parameter(Mandatory=$true)][string]$Session)

  try {
    $raw = & $BwPath list items --session $Session
    if (-not $raw) { return @() }

    $items = $raw | ConvertFrom-Json
    if (-not $items) { return @() }

    $ids = @()
    foreach ($it in $items) {
      if ($null -ne $it.organizationId -and -not [string]::IsNullOrWhiteSpace([string]$it.organizationId)) {
        $ids += [string]$it.organizationId
      }
    }
    return ($ids | Sort-Object -Unique)
  }
  catch {
    return @()
  }
}

function Try-ResolveOrgNameFromCollectionsOutput {
  param(
    [Parameter(Mandatory=$true)][string]$Session,
    [Parameter(Mandatory=$true)][string]$OrgId
  )

  try {
    $output = & $BwPath list collections --organizationid $OrgId --session $Session 2>&1
    if (-not $output) { return $null }

    $txt = ($output | Out-String).Trim()

    $first = $txt.TrimStart()
    if ($first.StartsWith("[") -or $first.StartsWith("{")) {
      return $null
    }

    $m = [regex]::Match($txt, "organization\s+'([^']+)'", "IgnoreCase")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }

    $m2 = [regex]::Match($txt, "organization\s+""([^""]+)""", "IgnoreCase")
    if ($m2.Success) { return $m2.Groups[1].Value.Trim() }

    return $null
  }
  catch {
    return $null
  }
}

function Pick-ExistingAccountIndex($cfg) {
  if (-not $cfg.accounts -or $cfg.accounts.Count -eq 0) { return -1 }

  Write-Host ""
  List-Accounts $cfg
  Write-Host ""

  $n = Prompt "Select account [number] (or blank to cancel)"
  if ([string]::IsNullOrWhiteSpace($n)) { return -1 }
  if (-not ($n -as [int])) { return -1 }

  $idx = ([int]$n) - 1
  if ($idx -lt 0 -or $idx -ge $cfg.accounts.Count) { return -1 }
  return $idx
}

function Discover-And-Store-Orgs {
  param(
    [Parameter(Mandatory=$true)]$cfg,
    [Parameter(Mandatory=$true)][int]$idx,
    [Parameter(Mandatory=$true)][string]$masterPlain
  )

  try {
    Write-Host ""
    Write-Host "Checking for organizations for this account..."

    if (-not (Test-Path $BwPath)) {
      Write-Host "bw.exe not found, skipping organization discovery."
      throw "bw.exe missing"
    }

    $acct = $cfg.accounts[$idx]
    $server = $acct.serverUrl
    $email  = $acct.email

    $env:BW_PASSWORD = $masterPlain

    & $BwPath config server $server | Out-Null

    $login = & $BwPath login --raw --passwordenv BW_PASSWORD $email
    if ([string]::IsNullOrWhiteSpace($login)) {
      Write-Host "Login failed during org discovery."
      throw "login failed"
    }

    $unlock = & $BwPath unlock --raw --passwordenv BW_PASSWORD --session $login
    if ([string]::IsNullOrWhiteSpace($unlock)) {
      Write-Host "Unlock failed during org discovery."
      try { & $BwPath logout | Out-Null } catch { }
      throw "unlock failed"
    }

    Write-Host "Syncing vault..."
    & $BwPath sync --session $unlock | Out-Null

    $idToName = @{}
    $orgs = Get-BwOrganizations -Session $unlock
    if ($orgs -and $orgs.Count -gt 0) {
      foreach ($o in $orgs) {
        if ($null -ne $o.id -and -not [string]::IsNullOrWhiteSpace([string]$o.id)) {
          $idToName[[string]$o.id] = [string]$o.name
        }
      }
    }

    $idsFromItems = Get-OrgIdsFromItemsFallback -Session $unlock

    $allIds = @()
    if ($idToName.Keys.Count -gt 0) { $allIds += $idToName.Keys }
    if ($idsFromItems -and $idsFromItems.Count -gt 0) { $allIds += $idsFromItems }
    $allIds = @($allIds | Sort-Object -Unique)

    if (-not $allIds -or $allIds.Count -eq 0) {
      Write-Host "No organizations detected."
      if ($cfg.accounts[$idx].PSObject.Properties.Name -contains "organizations") {
        $cfg.accounts[$idx].PSObject.Properties.Remove("organizations")
      }
      try { & $BwPath logout --session $unlock | Out-Null } catch { }
      try { & $BwPath logout | Out-Null } catch { }
      return
    }

    $orgConfigs = @()
    foreach ($id in $allIds) {
      $name = $null
      if ($idToName.ContainsKey($id)) { $name = $idToName[$id] }

      if ([string]::IsNullOrWhiteSpace($name)) {
        $name = Try-ResolveOrgNameFromCollectionsOutput -Session $unlock -OrgId $id
      }

      if ([string]::IsNullOrWhiteSpace($name)) {
        $short = $id
        if ($short.Length -gt 8) { $short = $short.Substring(0,8) }
        $name = ("org-{0}" -f $short)
      }

      $safe = (($name -replace '\s+','_') -replace '[^a-zA-Z0-9_]', '').ToLower()
      if ([string]::IsNullOrWhiteSpace($safe)) {
        $short2 = $id
        if ($short2.Length -gt 8) { $short2 = $short2.Substring(0,8) }
        $safe = ("org_{0}" -f $short2)
      }

      $orgConfigs += [pscustomobject]@{
        id = $id
        name = $name
        enabled = $true
        exportFileName = ("{0}-{1}-org-encrypted.json" -f $acct.nickname, $safe)
      }
    }

    $cfg.accounts[$idx] | Add-Member -NotePropertyName organizations -NotePropertyValue @($orgConfigs) -Force

    Write-Host ""
    Write-Host "Organizations auto-added for backup:"
    foreach ($o in $orgConfigs) {
      Write-Host ("  - {0} (id={1})" -f $o.name, $o.id)
    }

    try { & $BwPath logout --session $unlock | Out-Null } catch { }
    try { & $BwPath logout | Out-Null } catch { }
  }
  catch {
    Write-Host "Warning: Organization discovery failed or skipped (continuing)."
    Write-Host ("Details: {0}" -f $_.Exception.Message)
  }
  finally {
    Remove-Item Env:\BW_PASSWORD -ErrorAction SilentlyContinue
  }
}

function List-OrganizationsForAccount {
  param([Parameter(Mandatory=$true)]$acct)

  Write-Host ""
  Write-Host ("Organizations for '{0}':" -f $acct.nickname)

  if (-not ($acct.PSObject.Properties.Name -contains "organizations") -or -not $acct.organizations -or @($acct.organizations).Count -eq 0) {
    Write-Host "  (none)"
    return
  }

  $orgs = @($acct.organizations)
  for ($i=0; $i -lt $orgs.Count; $i++) {
    $o = $orgs[$i]
    $enabled = $true
    if ($o.PSObject.Properties.Name -contains "enabled") { $enabled = [bool]$o.enabled }
    $state = if ($enabled) { "ENABLED" } else { "DISABLED" }
    $name = if ($o.name) { $o.name } else { "(no name)" }
    $id = if ($o.id) { $o.id } else { "(no id)" }
    Write-Host ("  {0}) {1}  [{2}]  id={3}" -f ($i+1), $name, $state, $id)
  }
}

function Manage-Organizations($cfg) {
  cls
  Write-Host "=========================================="
  Write-Host "  Manage Organizations"
  Write-Host "=========================================="

  $idx = Pick-ExistingAccountIndex $cfg
  if ($idx -lt 0) { return }

  while ($true) {
    cls
    $acct = $cfg.accounts[$idx]

    Write-Host "=========================================="
    Write-Host ("  Organizations: {0}" -f $acct.nickname)
    Write-Host "=========================================="

    List-OrganizationsForAccount $acct

    Write-Host ""
    Write-Host "Menu:"
    Write-Host "  1) Disable/Enable an organization (exclude/include in backup)"
    Write-Host "  2) Remove an organization from backup list (delete entry)"
    Write-Host "  3) Re-discover organizations (auto-add all found)"
    Write-Host "  4) Back"
    Write-Host ""

    $c = Prompt "Choose [1-4]"
    if ($c -eq "4") { return }

    if ($c -eq "1") {
      if (-not ($acct.PSObject.Properties.Name -contains "organizations") -or -not $acct.organizations -or @($acct.organizations).Count -eq 0) {
        Write-Host ""
        Write-Host "No organizations to toggle."
        Start-Sleep -Milliseconds 800
        continue
      }

      $n = Prompt "Choose organization [number]"
      if (-not ($n -as [int])) { continue }
      $oi = ([int]$n) - 1
      $orgs = @($cfg.accounts[$idx].organizations)
      if ($oi -lt 0 -or $oi -ge $orgs.Count) { continue }

      $o = $orgs[$oi]
      $cur = $true
      if ($o.PSObject.Properties.Name -contains "enabled") { $cur = [bool]$o.enabled }
      $o.enabled = (-not $cur)

      $cfg.accounts[$idx].organizations = $orgs
      Save-Config $cfg

      $state = if ($o.enabled) { "ENABLED" } else { "DISABLED" }
      Log ("Org '{0}' for '{1}' is now {2}." -f $o.name, $acct.nickname, $state)
      Start-Sleep -Milliseconds 700
      continue
    }

    if ($c -eq "2") {
      if (-not ($acct.PSObject.Properties.Name -contains "organizations") -or -not $acct.organizations -or @($acct.organizations).Count -eq 0) {
        Write-Host ""
        Write-Host "No organizations to remove."
        Start-Sleep -Milliseconds 800
        continue
      }

      $n = Prompt "Remove which organization [number]"
      if (-not ($n -as [int])) { continue }
      $oi = ([int]$n) - 1
      $orgs = @($cfg.accounts[$idx].organizations)
      if ($oi -lt 0 -or $oi -ge $orgs.Count) { continue }

      $o = $orgs[$oi]
      $name = if ($o.name) { $o.name } else { $o.id }

      if (-not (Confirm ("REMOVE organization '{0}' from backups for '{1}'? (This will stop exporting it.)" -f $name, $acct.nickname))) {
        continue
      }

      $orgs = @($orgs | Where-Object { $_ -ne $o })

      if ($orgs.Count -eq 0) {
        if ($cfg.accounts[$idx].PSObject.Properties.Name -contains "organizations") {
          $cfg.accounts[$idx].PSObject.Properties.Remove("organizations")
        }
      } else {
        $cfg.accounts[$idx].organizations = $orgs
      }

      Save-Config $cfg
      Log ("Removed org '{0}' from '{1}' backup list." -f $name, $acct.nickname)
      Start-Sleep -Milliseconds 700
      continue
    }

    if ($c -eq "3") {
      if (-not ($acct.PSObject.Properties.Name -contains "encMaster") -or [string]::IsNullOrWhiteSpace($acct.encMaster)) {
        Write-Host ""
        Write-Host "This account has no stored master password blob. Update the account first."
        Start-Sleep -Milliseconds 1000
        continue
      }

      Write-Host ""
      if (-not (Confirm ("Re-discover organizations for '{0}' now?" -f $acct.nickname))) {
        continue
      }

      $masterPlain = Decrypt-String $acct.encMaster
      Discover-And-Store-Orgs -cfg $cfg -idx $idx -masterPlain $masterPlain
      Save-Config $cfg

      Start-Sleep -Milliseconds 700
      continue
    }
  }
}

function Add-Or-Update($cfg) {
  cls
  Write-Host "=========================================="
  Write-Host "  Add or Update Account"
  Write-Host "=========================================="

  $mode = "new"
  if ($cfg.accounts -and $cfg.accounts.Count -gt 0) {
    Write-Host ""
    Write-Host "Choose mode:"
    Write-Host "  1) Add NEW account"
    Write-Host "  2) Update EXISTING account"
    $m = Prompt "Choose 1 or 2 (default 2)"
    if ([string]::IsNullOrWhiteSpace($m)) { $m = "2" }
    if ($m -eq "1") { $mode = "new" } else { $mode = "update" }
  }

  if ($mode -eq "update") {
    $idx = Pick-ExistingAccountIndex $cfg
    if ($idx -lt 0) { return }

    $acct = $cfg.accounts[$idx]
    $nick = $acct.nickname
    $server = $acct.serverUrl
    $email = $acct.email
    $fileName = $acct.exportFileName

    Write-Host ""
    Write-Host ("Updating '{0}' (current server: {1}, email: {2})" -f $nick, $server, $email)
    if (-not (Confirm ("Update account '{0}'? You will be asked for passwords." -f $nick))) { return }

    $change = Prompt "Change server/email? (Y/N, default N)"
    if ($change -match '^[Yy]') {
      $serverIn = Prompt ("Server URL (blank keeps {0})" -f $server)
      if (-not [string]::IsNullOrWhiteSpace($serverIn)) { $server = Normalize-Url $serverIn }

      $emailIn = Prompt ("Email (blank keeps {0})" -f $email)
      if (-not [string]::IsNullOrWhiteSpace($emailIn)) { $email = $emailIn.Trim() }
    }

    $fileIn = Prompt ("Export file name (blank keeps {0})" -f $fileName)
    if (-not [string]::IsNullOrWhiteSpace($fileIn)) { $fileName = $fileIn.Trim() }

    Write-Host ""
    $encMaster = Prompt-Secret "Type the Bitwarden master password (input is hidden)"
    if ([string]::IsNullOrWhiteSpace($encMaster)) { Log "Update cancelled (empty master password)."; return }

    Write-Host ""
    $encExport = Prompt-Secret "Type the export password used to encrypt backups (input is hidden)"
    if ([string]::IsNullOrWhiteSpace($encExport)) { Log "Update cancelled (empty export password)."; return }

    $cfg.accounts[$idx].serverUrl = $server
    $cfg.accounts[$idx].email = $email
    $cfg.accounts[$idx].encMaster = $encMaster
    $cfg.accounts[$idx].encExport = $encExport
    $cfg.accounts[$idx].exportFileName = $fileName
    if ($null -eq $cfg.accounts[$idx].frozen) { $cfg.accounts[$idx] | Add-Member frozen $false -Force }

    $masterPlain = Decrypt-String $encMaster
    Discover-And-Store-Orgs -cfg $cfg -idx $idx -masterPlain $masterPlain

    Save-Config $cfg
    Write-Host ""
    Write-Host "Saved."
    Start-Sleep -Milliseconds 600
    return
  }

  Write-Host ""
  $nick = Prompt "Nickname for this account (no spaces is best, e.g. personal, work)"
  if ([string]::IsNullOrWhiteSpace($nick)) { Log "Add cancelled (empty nickname)."; return }

  Write-Host ""
  Write-Host "Server type:"
  Write-Host "  1) Bitwarden Cloud (https://vault.bitwarden.com)"
  Write-Host "  2) Custom Vaultwarden / Bitwarden server"
  $st = Prompt "Choose 1 or 2 (default 1)"
  if ([string]::IsNullOrWhiteSpace($st)) { $st = "1" }

  $server = ""
  if ($st -eq "2") {
    $server = Prompt "Full server URL (e.g. https://vault.example.com)"
    if ([string]::IsNullOrWhiteSpace($server)) { Log "Add cancelled (empty server url)."; return }
  } else {
    $server = "https://vault.bitwarden.com"
  }
  $server = Normalize-Url $server

  $email = Prompt "Email for this account"
  if ([string]::IsNullOrWhiteSpace($email)) { Log "Add cancelled (empty email)."; return }

  Write-Host ""
  $encMaster = Prompt-Secret "Type the Bitwarden master password (input is hidden)"
  if ([string]::IsNullOrWhiteSpace($encMaster)) { Log "Add cancelled (empty master password)."; return }

  Write-Host ""
  $encExport = Prompt-Secret "Type the export password used to encrypt backups (input is hidden)"
  if ([string]::IsNullOrWhiteSpace($encExport)) { Log "Add cancelled (empty export password)."; return }

  $defaultFile = ("{0}-vault-backup-encrypted.json" -f $nick)
  $fileName = Prompt ("Export file name (default: {0})" -f $defaultFile)
  if ([string]::IsNullOrWhiteSpace($fileName)) { $fileName = $defaultFile }

  $cfg.accounts += [pscustomobject]@{
    nickname       = $nick
    serverUrl      = $server
    email          = $email
    encMaster      = $encMaster
    encExport      = $encExport
    exportFileName = $fileName
    frozen         = $false
  }
  $idx = $cfg.accounts.Count - 1

  $masterPlain2 = Decrypt-String $encMaster
  Discover-And-Store-Orgs -cfg $cfg -idx $idx -masterPlain $masterPlain2

  Save-Config $cfg
  Write-Host ""
  Write-Host "Saved."
  Start-Sleep -Milliseconds 600
}

function Remove-AccountOrInstance($cfg) {
  cls
  Write-Host "=========================================="
  Write-Host "  Remove account or instance"
  Write-Host "=========================================="
  List-Accounts $cfg
  Write-Host ""

  if (-not $cfg.accounts -or $cfg.accounts.Count -eq 0) { Start-Sleep -Milliseconds 400; return }

  Write-Host "Remove options:"
  Write-Host "  1) Remove ONE account (by number)"
  Write-Host "  2) Remove ALL accounts for a server URL (instance)"
  $mode = Prompt "Choose 1 or 2"
  if ($mode -ne "1" -and $mode -ne "2") { return }

  if ($mode -eq "1") {
    $n = Prompt "Remove which account [number]"
    if (-not ($n -as [int])) { return }
    $idx = ([int]$n) - 1
    if ($idx -lt 0 -or $idx -ge $cfg.accounts.Count) { return }

    $a = $cfg.accounts[$idx]
    if (-not (Confirm ("DELETE account '{0}' on {1}? (irreversible)" -f $a.nickname, $a.serverUrl))) {
      Log "Delete cancelled."
      return
    }

    $cfg.accounts = @($cfg.accounts | Where-Object { $_ -ne $a })
    Save-Config $cfg
    Log ("Deleted account '{0}'." -f $a.nickname)
    Start-Sleep -Milliseconds 600
    return
  }

  $url = Prompt "Server URL to remove (exact match recommended)"
  if ([string]::IsNullOrWhiteSpace($url)) { return }
  $url = Normalize-Url $url

  if (-not (Confirm ("DELETE all accounts on server '{0}'? (irreversible)" -f $url))) {
    Log "Delete cancelled."
    return
  }

  $before = $cfg.accounts.Count
  $cfg.accounts = @($cfg.accounts | Where-Object { (Normalize-Url $_.serverUrl) -ne $url })
  $after = $cfg.accounts.Count

  Save-Config $cfg
  Log ("Deleted {0} account(s) for server '{1}'." -f ($before - $after), $url)
  Start-Sleep -Milliseconds 600
}

function FreezeOrUnfreeze($cfg) {
  cls
  Write-Host "=========================================="
  Write-Host "  Freeze / Unfreeze accounts"
  Write-Host "=========================================="
  List-Accounts $cfg
  Write-Host ""

  if (-not $cfg.accounts -or $cfg.accounts.Count -eq 0) { Start-Sleep -Milliseconds 400; return }

  $n = Prompt "Choose account [number]"
  if (-not ($n -as [int])) { return }
  $idx = ([int]$n) - 1
  if ($idx -lt 0 -or $idx -ge $cfg.accounts.Count) { return }

  $a = $cfg.accounts[$idx]
  $new = -not [bool]$a.frozen
  $cfg.accounts[$idx].frozen = $new
  Save-Config $cfg

  $state = if ($new) { "FROZEN" } else { "ACTIVE" }
  Log ("Account '{0}' is now {1}." -f $a.nickname, $state)
  Start-Sleep -Milliseconds 600
}

function Main {
  Log "===== bitwarden_backup_setup.ps1 started ====="
  $cfg = Load-Config

  while ($true) {
    cls
    Write-Host "=========================================="
    Write-Host "  Bitwarden / Vaultwarden Backup Setup"
    Write-Host "=========================================="
    List-Accounts $cfg
    Write-Host ""
    Write-Host "Menu:"
    Write-Host "  1) Add or update account"
    Write-Host "  2) Remove account or instance"
    Write-Host "  3) Freeze/unfreeze account"
    Write-Host "  4) Manage organizations (view/disable/remove)"
    Write-Host "  5) Back"
    Write-Host ""

    $c = Prompt "Choose [1-5]"
    switch ($c) {
      "1" { Add-Or-Update $cfg; $cfg = Load-Config }
      "2" { Remove-AccountOrInstance $cfg; $cfg = Load-Config }
      "3" { FreezeOrUnfreeze $cfg; $cfg = Load-Config }
      "4" { Manage-Organizations $cfg; $cfg = Load-Config }
      "5" { Log "Leaving setup menu."; return 0 }
      default { Start-Sleep -Milliseconds 250 }
    }
  }
}

$rc = Main
End $rc
return
#END_PS2

#BEGIN_PS3
# bitwarden_tasks.ps1
param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("Create","Remove","View")]
  [string]$Action,

  [int]$Minutes = 60
)

$ErrorActionPreference = "Stop"

$Root    = Split-Path $PSScriptRoot -Parent
$Scripts = Join-Path $Root "scripts"
$LogsDir = Join-Path $Root "logs"
$LogFile = Join-Path $LogsDir "tasks.log"

$TaskName = "BitwardenVaultBackup"
$PsBackup = Join-Path $Scripts "bitwarden_backup_all.ps1"
$VbsPath  = Join-Path $Scripts "run_bitwarden_backup_all.vbs"

New-Item -ItemType Directory -Force -Path $LogsDir, $Scripts | Out-Null

function Log([string]$msg) {
  $line = "[{0}] {1}" -f (Get-Date), $msg
  Write-Host $line
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function End([int]$code) {
  [Environment]::ExitCode = $code
  return
}

function Ensure-VbsRunner {
  if (-not (Test-Path $PsBackup)) {
    Log "ERROR: Backup script missing: $PsBackup"
    End 1
    return $false
  }

  $vbs = @"
' run_bitwarden_backup_all.vbs
' Runs the PowerShell backup script hidden (no popups)
Set shell = CreateObject("WScript.Shell")
ps1 = "$($PsBackup -replace '\\', '\\\\')"
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """"
shell.Run cmd, 0, True
"@

  Set-Content -Path $VbsPath -Value $vbs -Encoding ASCII -Force
  Log "Created/updated VBS runner: $VbsPath"
  return $true
}

function Get-WScriptPath {
  $sysnative = Join-Path $env:WINDIR "Sysnative\wscript.exe"
  $system32  = Join-Path $env:WINDIR "System32\wscript.exe"
  $wow64     = Join-Path $env:WINDIR "SysWOW64\wscript.exe"

  if (Test-Path $sysnative) { return $sysnative }
  if (Test-Path $system32)  { return $system32 }
  if (Test-Path $wow64)     { return $wow64 }
  return $null
}

function Remove-TaskCom {
  try {
    $svc = New-Object -ComObject "Schedule.Service"
    $svc.Connect()
    $rootFolder = $svc.GetFolder("\")
    try {
      $rootFolder.DeleteTask($TaskName, 0)
      Log "Removed task: $TaskName"
    } catch {
      Log "Remove: task may not exist (ignored)."
    }
    End 0
  } catch {
    Log "ERROR: Remove failed: $($_.Exception.Message)"
    End 1
  }
}

function View-TaskCom {
  try {
    $svc = New-Object -ComObject "Schedule.Service"
    $svc.Connect()
    $rootFolder = $svc.GetFolder("\")
    $task = $rootFolder.GetTask($TaskName)

    Log "Task found: $TaskName"
    $def = $task.Definition

    Write-Host ""
    Write-Host "=== Task: $TaskName ==="
    Write-Host "Path: \"
    Write-Host "Enabled: $($task.Enabled)"
    Write-Host "LastRunTime: $($task.LastRunTime)"
    Write-Host "NextRunTime: $($task.NextRunTime)"
    Write-Host "LastTaskResult: $($task.LastTaskResult)"
    Write-Host ""
    Write-Host "Action:"
    foreach($a in $def.Actions){
      Write-Host "  Exec: $($a.Path)"
      Write-Host "  Args: $($a.Arguments)"
    }
    Write-Host ""
    Write-Host "Triggers:"
    foreach($t in $def.Triggers){
      Write-Host "  Type: $($t.Type)"
      Write-Host "  StartBoundary: $($t.StartBoundary)"
      if($t.Repetition){
        Write-Host "  Repetition Interval: $($t.Repetition.Interval)"
        Write-Host "  Repetition Duration: $($t.Repetition.Duration)"
      }
    }

    End 0
  } catch {
    Log "ERROR: View failed: $($_.Exception.Message)"
    End 1
  }
}

function Create-TaskCom([int]$mins) {
  if ($mins -lt 1) { $mins = 1 }

  if (-not (Ensure-VbsRunner)) { return }

  $wscript = Get-WScriptPath
  if (-not $wscript) {
    Log "ERROR: Could not locate wscript.exe in System32/Sysnative/SysWOW64."
    End 1
    return
  }

  if (-not (Test-Path $VbsPath)) {
    Log "ERROR: VBS runner missing after creation: $VbsPath"
    End 1
    return
  }

  Log "Action exe: $wscript"
  Log "Action arg: $VbsPath"

  try { Remove-TaskCom } catch { }

  try {
    $svc = New-Object -ComObject "Schedule.Service"
    $svc.Connect()
    $rootFolder = $svc.GetFolder("\")

    $taskDef = $svc.NewTask(0)

    $taskDef.RegistrationInfo.Description = "Bitwarden/Vaultwarden encrypted backup runner"
    $taskDef.Settings.Enabled = $true
    $taskDef.Settings.Hidden = $true
    $taskDef.Settings.StartWhenAvailable = $true
    $taskDef.Settings.MultipleInstances = 0 
    $taskDef.Settings.DisallowStartIfOnBatteries = $false
    $taskDef.Settings.StopIfGoingOnBatteries = $false

    $taskDef.Principal.LogonType = 3  
    $taskDef.Principal.RunLevel  = 0  

    $trigger = $taskDef.Triggers.Create(2) 
    $start = (Get-Date).Date.AddMinutes(1) 
    $trigger.StartBoundary = $start.ToString("s")
    $trigger.DaysInterval = 1
    $trigger.Enabled = $true

    $trigger.Repetition.Interval = ("PT{0}M" -f $mins)
    $trigger.Repetition.Duration = "P1D"

    $action = $taskDef.Actions.Create(0) 
    $action.Path = $wscript
    $action.Arguments = ('"{0}"' -f $VbsPath)

    $TASK_LOGON_INTERACTIVE_TOKEN = 3

    $rootFolder.RegisterTaskDefinition($TaskName, $taskDef, 6, $null, $null, $TASK_LOGON_INTERACTIVE_TOKEN) | Out-Null

    Log "Task created/updated successfully: $TaskName"
    End 0
  } catch {
    Log "ERROR: Create failed: $($_.Exception.Message)"
    Log "Tip: if it still says 'cannot find the file specified', it is almost always the Action exe path."
    End 1
  }
}

Log "=== Action: $Action ==="

switch ($Action) {
  "Create" { Create-TaskCom -mins $Minutes }
  "Remove" { Remove-TaskCom }
  "View"   { View-TaskCom }
}

return
#END_PS3

#BEGIN_INSTALL_BW
# install_bw.ps1
$dir = Join-Path (Split-Path $PSScriptRoot -Parent) 'bin'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$zip = Join-Path $dir 'bitwarden-cli.zip'
$url = 'https://bitwarden.com/download/?app=cli&platform=windows'
Write-Host 'Downloading Bitwarden CLI ...'
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
Write-Host 'Extracting CLI ...'
Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
Remove-Item $zip -ErrorAction SilentlyContinue
$bw = Join-Path $dir 'bw.exe'
if ( -not (Test-Path $bw) ) { throw 'bw.exe not found after extract.' }
Write-Host ('Bitwarden CLI is ready at: ' + $bw)
& $bw --version
#END_INSTALL_BW
