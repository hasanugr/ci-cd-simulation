param(
    [string]$environment
)

# Stop script immediately if any error occurs
$ErrorActionPreference = "Stop"

Write-Host "🚀 Starting deployment... Target: $environment" -ForegroundColor Green

# Define Target Folder (IIS Directory)
$targetFolder = "C:\inetpub\wwwroot\Simulation_$environment"
Write-Host "📂 Target Folder: $targetFolder"

# 1. Install Dependencies
Write-Host "📦 Installing dependencies..."
cmd /c "corepack enable"
cmd /c "pnpm install --no-frozen-lockfile"

# 2. Build Project
Write-Host "🔨 Building project..."
cmd /c "pnpm build"

# 3. Copy Files (Using Robocopy for speed)
Write-Host "🚚 Copying files to server..."

# Create directory if it does not exist
if (!(Test-Path -Path $targetFolder)) {
    New-Item -ItemType Directory -Force -Path $targetFolder
    Write-Host "✨ Created new directory: $targetFolder"
}

# Mirror copy: Syncs 'out' folder to target (Deletes extra files in target)
# Flags: /MIR (Mirror) /NFL (No File List) /NDL (No Dir List) /np (No Progress)
robocopy .\out $targetFolder /MIR /NFL /NDL /NJH /NJS /nc /ns /np

# Check Robocopy Exit Code (0-7 indicates success)
if ($LASTEXITCODE -gt 7) {
    Write-Error "❌ Copy failed. Robocopy Exit Code: $LASTEXITCODE"
    exit 1
}

Write-Host "✅ Deployment completed successfully!" -ForegroundColor Cyan