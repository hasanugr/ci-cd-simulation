param(
  [string]$environment
)

# Stop script immediately if any error occurs
$ErrorActionPreference = "Stop"

Write-Host "ROCKET Starting deployment... Target: $environment" -ForegroundColor Green

# Define Target Folder (IIS Directory)
$targetFolder = "C:\inetpub\wwwroot\Simulation_$environment"
Write-Host "FOLDER Target Folder: $targetFolder"

# 1. Install Dependencies
Write-Host "PACKAGE Installing dependencies..."
cmd /c "corepack enable"
cmd /c "pnpm install --no-frozen-lockfile"
if ($LASTEXITCODE -ne 0) { Write-Error "Install Failed"; exit 1 }

# 2. Build Project (Critical Check Added)
Write-Host "BUILD Building project..."
cmd /c "pnpm build"
if ($LASTEXITCODE -ne 0) { 
    Write-Error "ERROR Build failed. Deployment aborted."
    exit 1 
}

# 3. Copy Files (Using Robocopy)
Write-Host "COPY Copying files to server..."

# Create directory if it does not exist
if (!(Test-Path -Path $targetFolder)) {
  New-Item -ItemType Directory -Force -Path $targetFolder
  Write-Host "NEW Created new directory: $targetFolder"
}

# Mirror copy: Syncs out folder to target (Deleted extra files in target)
# Flags: /MIR (Mirror) /NFL (No File List) /NDL (No Dir List) /NJH (No Job Header) /NJS (No Job Summary) /nc (No Class) /ns (No Size) /np (No Progress) /R:0 (No Retries) /W:0 (No Wait)
robocopy .\out $targetFolder /MIR /NFL /NDL /NJH /NJS /nc /ns /np /R:0 /W:0

# Robocopy exit codes: 0-7 = Success, >8 = Fail
if ($LASTEXITCODE -gt 7) {
  Write-Error "ERROR Copy failed. Robocopy Exit Code: $LASTEXITCODE"
  exit 1
}

Write-Host "SUCCESS Deployment completed successfully!" -ForegroundColor Cyan

# Force success exit code (Override Robocopy's exit code 1)
exit 0