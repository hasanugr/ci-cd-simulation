# =================================================================
# Dummy Project - Versioned Release Deployment Script
# =================================================================
# "Versioned Release" approach: Each deploy creates a new folder,
# IIS points to the new folder, old folders are cleaned up.
#
#   Build (workspace)  -->  Create new folder  -->  IIS path swap  -->  Cleanup
#   [No IIS impact]        [No locked files]       [< 1s downtime]     [Delete old]
#
# Benefits:
#   - NO DLL lock issues (new folder = no locked files)
#   - Minimal downtime (only during IIS path switch)
#   - Quick rollback capability (old folders still available)
#   - ZERO impact on other apps (no process kill)
#
# Usage    : .\scripts\deploy.ps1 -environment "qa"
# Required : FULL_VERSION env var (e.g., qa-v0.1.0.1)
# =================================================================

param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("qa", "prod")]
  [string]$environment
)

$ErrorActionPreference = "Stop"

# =================================================================
# ENVIRONMENT CONFIGURATION
# =================================================================
$envConfig = @{
  "qa" = @{
    ReleasesFolder = "C:\inetpub\wwwroot\site-name\qa-releases"
    SiteName       = "qa.site.com"
  }
  "prod" = @{
    ReleasesFolder = "C:\inetpub\wwwroot\site-name\prod-releases"
    SiteName       = "site.com"
  }
}

$releasesFolder = $envConfig[$environment].ReleasesFolder
$siteName       = $envConfig[$environment].SiteName
$appcmd         = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
$version        = $env:FULL_VERSION
$keepReleases   = 3  # Number of releases to keep

# --- Version validation ---
if ([string]::IsNullOrWhiteSpace($version)) {
  Write-Host "[FAIL] FULL_VERSION environment variable is not set!" -ForegroundColor Red
  exit 1
}

# Add timestamp to folder name (prevents conflicts and locked file issues)
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$uniqueVersionName = "$version-$timestamp"
$versionFolder = Join-Path $releasesFolder $uniqueVersionName

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY: Dummy Project" -ForegroundColor Cyan
Write-Host "  Strategy    : Versioned Release" -ForegroundColor White
Write-Host "  Environment : $($environment.ToUpper())" -ForegroundColor White
Write-Host "  Version     : $version" -ForegroundColor White
Write-Host "  Release Dir : $versionFolder" -ForegroundColor White
Write-Host "  IIS Site    : $siteName" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

# =================================================================
# PHASE 0: PRE-BUILD SETUP (Prepare env file before build)
# Next.js embeds NEXT_PUBLIC_ variables during build time.
# So .env file must be in workspace BEFORE the build.
# =================================================================
Write-Host "`n>> [PHASE 0/4] Setting up environment files..." -ForegroundColor Yellow

# Central Config Path (Create this folder on server and put .env file inside!)
# You can use different folders for QA and PROD or separate by filename (.env.qa, .env.prod)
$centralConfigPath = Join-Path $releasesFolder "config"
$envFileName = ".env" # Or environment-specific: ".env.$environment"

$srcEnv = Join-Path $centralConfigPath $envFileName
$destEnvWorkspace = ".\.env" # Workspace root

if (Test-Path $srcEnv) {
    Copy-Item -Path $srcEnv -Destination $destEnvWorkspace -Force
    Write-Host "[OK] Copied .env from central config to workspace for BUILD." -ForegroundColor Green
} else {
    Write-Host "[FAIL] Central .env file not found at: $srcEnv" -ForegroundColor Red
    Write-Host "       Please create this folder and put your .env file there." -ForegroundColor Red
    exit 1
}

# =================================================================
# PHASE 1: BUILD (In workspace - IIS not affected)
# Current site continues running while build happens
# =================================================================
Write-Host "`n>> [PHASE 1/4] Building in workspace..." -ForegroundColor Yellow

# npm warnings go to stderr, don't let PowerShell treat them as errors
$previousErrorPref = $ErrorActionPreference
$ErrorActionPreference = "Continue"

Write-Host ">> Installing dependencies..." -ForegroundColor Gray
npm install
$npmExitCode = $LASTEXITCODE
if ($npmExitCode -ne 0) {
  Write-Host "[FAIL] npm install failed with exit code $npmExitCode" -ForegroundColor Red
  $ErrorActionPreference = $previousErrorPref
  exit 1
}

Write-Host ">> Running build..." -ForegroundColor Gray
npm run build
$buildExitCode = $LASTEXITCODE

$ErrorActionPreference = $previousErrorPref

if ($buildExitCode -ne 0) {
  Write-Host "[FAIL] Build failed. Deployment aborted - site unaffected." -ForegroundColor Red
  exit 1
}
Write-Host "[OK] Build completed successfully." -ForegroundColor Green

# =================================================================
# PHASE 2: PREPARE NEW RELEASE FOLDER
# Create new versioned folder, copy files,
# install production dependencies
# =================================================================
Write-Host "`n>> [PHASE 2/4] Preparing release folder..." -ForegroundColor Yellow

# --- 2a: Create releases root folder (for first deploy) ---
if (!(Test-Path $releasesFolder)) {
  New-Item -ItemType Directory -Force -Path $releasesFolder | Out-Null
  Write-Host "[INFO] Created releases directory: $releasesFolder" -ForegroundColor Gray
}

# --- 2b: Clean existing version folder if exists (for rollback/re-deploy) ---
if (Test-Path $versionFolder) {
  Write-Host "[INFO] Version folder already exists, removing for clean deploy..." -ForegroundColor Gray
  Remove-Item -Path $versionFolder -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $versionFolder | Out-Null

# --- 2c: Copy runtime files ---
# Only copy files needed in production:
#   server.js       - iisnode entry point
#   package.json    - for npm install
#   package-lock.json - deterministic install
#   next.config.js  - Next.js runtime config
#   .next/          - compiled build output (excluding cache)
#   public/         - static files (images, icons, robots, etc.)
#
# NOT COPIED: src/, node_modules/, .git/, scripts/, docs/,
#             tsconfig, postcss, tailwind (all build-time only)

Write-Host ">> Copying runtime files..." -ForegroundColor Gray

# Copy root files
$runtimeFiles = @("server.js", "package.json", "package-lock.json", "next.config.js")
foreach ($file in $runtimeFiles) {
  if (Test-Path ".\$file") {
    Copy-Item ".\$file" -Destination $versionFolder -Force
    Write-Host "  + $file" -ForegroundColor Gray
  } else {
    Write-Host "  [WARN] $file not found in workspace" -ForegroundColor Yellow
  }
}

# Copy .next build output (excluding cache - build priority only)
Write-Host ">> Copying .next build output..." -ForegroundColor Gray
robocopy ".\.next" "$versionFolder\.next" /E /XD cache `
  /NFL /NDL /NJH /NJS /nc /ns /np /R:0 /W:0
if ($LASTEXITCODE -gt 7) {
  Write-Host "[FAIL] .next copy failed. Robocopy Exit Code: $LASTEXITCODE" -ForegroundColor Red
  exit 1
}

# Copy public folder
Write-Host ">> Copying public folder..." -ForegroundColor Gray
robocopy ".\public" "$versionFolder\public" /E `
  /NFL /NDL /NJH /NJS /nc /ns /np /R:0 /W:0
if ($LASTEXITCODE -gt 7) {
  Write-Host "[FAIL] public copy failed. Robocopy Exit Code: $LASTEXITCODE" -ForegroundColor Red
  exit 1
}

Write-Host "[OK] Runtime files copied." -ForegroundColor Green

# --- 2d: Copy .env from workspace (retrieved in Phase 0) ---
# =================================================================
Write-Host ">> Copying .env to release folder..." -ForegroundColor Gray

if (Test-Path ".\.env") {
    Copy-Item -Path ".\.env" -Destination $versionFolder -Force
    Write-Host "  + .env copied to release folder" -ForegroundColor Green
}

# web.config can still be copied from old deploy or from central config.
# Current logic for web.config is appropriate:
$currentPath = $null
try {
    $currentPath = (& $appcmd list vdir "$siteName/" /text:physicalPath 2>$null)
    if ($currentPath) { $currentPath = $currentPath.Trim() }
} catch {}

if ($currentPath -and (Test-Path (Join-Path $currentPath "web.config"))) {
    Copy-Item -Path (Join-Path $currentPath "web.config") -Destination $versionFolder -Force
    Write-Host "  + web.config (from active deployment)" -ForegroundColor Green
} else {
     # If no old deploy exists, get web.config from central config
     $centralWebConfig = Join-Path $centralConfigPath "web.config"
     if (Test-Path $centralWebConfig) {
         Copy-Item -Path $centralWebConfig -Destination $versionFolder -Force
         Write-Host "  + web.config (from central config)" -ForegroundColor Green
     }
}

# --- 2e: Install production dependencies (clean folder - NO DLL lock risk) ---
#   --omit=dev        : Only install production dependencies
#   --ignore-scripts  : DON'T run postinstall (git config) and prepare (husky)
#                       Release folder is not a git repo, these scripts will fail
#                       Sharp comes as prebuilt binary, no scripts needed
Write-Host ">> Installing production dependencies in release folder..." -ForegroundColor Gray

# npm warnings go to stderr, don't let PowerShell treat them as errors
$previousErrorPref = $ErrorActionPreference
$ErrorActionPreference = "Continue"

Push-Location $versionFolder
npm install --omit=dev --ignore-scripts 2>&1 | Out-Host
$npmExitCode = $LASTEXITCODE
Pop-Location

$ErrorActionPreference = $previousErrorPref

if ($npmExitCode -ne 0) {
  Write-Host "[FAIL] npm install in release folder failed with exit code $npmExitCode" -ForegroundColor Red
  exit 1
}
Write-Host "[OK] Production dependencies installed." -ForegroundColor Green

# =================================================================
# PHASE 3: IIS PATH SWAP (Minimal downtime — total < 2 seconds)
# Site is stopped, physical path changed, site is started
# =================================================================
Write-Host "`n>> [PHASE 3/4] Switching IIS to new release..." -ForegroundColor Yellow

# Check IIS site state
$siteState = & $appcmd list site /site.name:"$siteName" /text:state 2>$null

if (-not $siteState -or $siteState -match "ERROR") {
  Write-Host "[FAIL] Could not read IIS site state for '$siteName'." -ForegroundColor Red
  Write-Host "[HINT] Runner service account may lack IIS permissions." -ForegroundColor Yellow
  Write-Host "[HINT] Run: net localgroup Administrators `"NT AUTHORITY\NETWORK SERVICE`" /add" -ForegroundColor Yellow
  exit 1
}

# --- Stop site ---
if ($siteState -eq "Started") {
  Write-Host ">> Stopping IIS site..." -ForegroundColor Gray
  & $appcmd stop site /site.name:"$siteName"
  if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Could not stop IIS site '$siteName'" -ForegroundColor Red
    exit 1
  }
} elseif ($siteState -eq "Stopped") {
  Write-Host "[INFO] Site was already stopped." -ForegroundColor Gray
} else {
  Write-Host "[WARN] Unexpected site state: $siteState. Attempting to stop..." -ForegroundColor Yellow
  & $appcmd stop site /site.name:"$siteName" 2>$null
}

# --- Change physical path ---
Write-Host ">> Setting physical path: $versionFolder" -ForegroundColor Gray
& $appcmd set vdir /vdir.name:"$siteName/" /physicalPath:"$versionFolder"
if ($LASTEXITCODE -ne 0) {
  Write-Host "[FAIL] Could not change IIS physical path!" -ForegroundColor Red
  Write-Host "[HINT] Trying to start site with old path..." -ForegroundColor Yellow
  & $appcmd start site /site.name:"$siteName" 2>$null
  exit 1
}

# --- Start site ---
Write-Host ">> Starting IIS site..." -ForegroundColor Gray
& $appcmd start site /site.name:"$siteName"
if ($LASTEXITCODE -ne 0) {
  Write-Host "[FAIL] Could not start IIS site. Check IIS Manager." -ForegroundColor Red
  exit 1
}
Write-Host "[OK] IIS now serving from: $versionFolder" -ForegroundColor Green

# =================================================================
# PHASE 4: CLEANUP (Remove old release folders)
# Keep the last $keepReleases releases, delete the rest
# =================================================================
Write-Host "`n>> [PHASE 4/4] Cleaning up old releases..." -ForegroundColor Yellow

$releases = Get-ChildItem $releasesFolder -Directory |
            Where-Object { $_.Name -ne "config" } |
            Sort-Object CreationTime -Descending

if ($releases.Count -gt $keepReleases) {
  $toDelete = $releases | Select-Object -Skip $keepReleases
  foreach ($dir in $toDelete) {
    try {
      Remove-Item $dir.FullName -Recurse -Force
      Write-Host "  - Removed: $($dir.Name)" -ForegroundColor Gray
    } catch {
      Write-Host "  [WARN] Could not remove $($dir.Name): $($_.Exception.Message)" -ForegroundColor Yellow
    }
  }
  Write-Host "[OK] Cleaned $($toDelete.Count) old release(s)." -ForegroundColor Green
} else {
  Write-Host "[INFO] $($releases.Count) release(s) found, nothing to clean (keep=$keepReleases)." -ForegroundColor Gray
}

# =================================================================
# DONE
# =================================================================
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  [SUCCESS] Deployment completed!" -ForegroundColor Green
Write-Host "  Version : $version" -ForegroundColor White
Write-Host "  Site    : $siteName" -ForegroundColor White
Write-Host "  Path    : $versionFolder" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green

exit 0
