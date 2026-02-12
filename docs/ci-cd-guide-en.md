# CI/CD Pipeline Setup Guide

## DummyProject + IIS (iisnode) + GitHub Actions

**Last Updated:** MM.DD.YYYY

> **Important Note:** The deploy script adds a **timestamp** to each release (e.g., `qa-v0.1.0.1-20260212-143022`).
> This allows multiple deploys of the same version and prevents locked file issues.

---

## Roadmap and Progress Tracker

### Project Preparation (Local)

- [ ] Create branches (dev, qa, main)

### Server Preparation (Windows Server - RDP)

- [ ] Install Git (required for runner)
- [ ] Check IIS + iisnode (WebSocket, Static Content)
- [ ] QA folder permissions (`C:\inetpub\wwwroot\[site-name]\qa`)
- [ ] PowerShell execution policy configuration
- [ ] Verify `.env` file exists on server

### GitHub Setup

- [ ] Workflow permissions (Read and write + Allow PR creation)
- [ ] Create Fine-Grained Personal Access Token
- [ ] Add Repository Secret (`BYPASS_TOKEN`)
- [ ] Install self-hosted runner (as Windows Service)
- [ ] Configure `git config core.longPaths true` (after runner installation)
- [ ] Setup Branch Protection rules

### CI/CD Testing

- [ ] QA deploy test (first green checkmark)
- [ ] Version tagging verification
- [ ] Rollback test

### PROD (Future)

- [ ] PROD environment configuration
- [ ] PROD deploy test
- [ ] Rollback test

---

## Project Information

| Information             | Value                                                    |
| ----------------------- | -------------------------------------------------------- |
| **Framework**           | Next.js 14.2.33 (SSR - App Router)                       |
| **Node.js**             | >= 24.13.0                                               |
| **Package Manager**     | npm                                                      |
| **IIS Approach**        | iisnode + custom server.js                               |
| **QA Releases Path**    | `C:\inetpub\wwwroot\[site-name]\qa-releases\<version>`   |
| **QA IIS Site**         | `qa`                                                     |
| **QA URL**              | `https://qa.site.net`                                    |
| **PROD Releases Path**  | `C:\inetpub\wwwroot\[site-name]\prod-releases\<version>` |
| **PROD IIS Site**       | `site.com`                                               |
| **PROD URL**            | `https://site.com`                                       |
| **Deploy Strategy**     | Versioned Release (blue-green)                           |
| **Version Format**      | `{env}-v{major}.{minor}.{patch}.{build}-{timestamp}`     |
| **Timestamp Format**    | `yyyyMMdd-HHmmss`                                        |
| **Keep Releases**       | 3 (last 3 releases are kept)                             |
| **Branch Flow**         | dev -> qa -> main                                        |
| **QA Runner Label**     | `qa-server`                                              |
| **PROD Runner Label**   | `prod-server`                                            |
| **GitHub Environments** | `QA`, `PROD` (deployment history tracking)               |

**Note:** QA and PROD are on separate machines. Each machine has its own runner with its label. Workflows target the correct machine via labels.

**Version Example:**

- **Git Tag**: `qa-v0.1.7.2` (qa environment, version 0.1.7, build 2)
- **IIS Folder**: `qa-v0.1.7.2-20260212-143022` (February 12, 2026 at 14:30:22)
- **Difference**: Deploy script adds timestamp to git tag, allowing the same tag to be deployed multiple times

### Deploy Strategy: Versioned Release

Since the project runs in SSR mode, it runs `server.js` via iisnode on IIS.
The **Versioned Release** approach is used: each deploy creates a new version folder,
IIS's physical path is redirected to this new folder, and old folders are cleaned up.

This approach completely eliminates the issue of native DLL files (sharp, etc.) being locked by iisnode
— there are no locked files in the new folder.

```
PHASE 0: PRE-BUILD (Env Setup)
  - .env file from "qa-releases/config/.env" is copied to workspace
  - This allows NEXT_PUBLIC_ variables to be embedded in code during build

PHASE 1: BUILD (No downtime - current site running)
  - npm install (in runner workspace)
  - npm run build (.next folder created)

PHASE 2: PREPARE RELEASE FOLDER (No downtime - site still running)
  - New version folder created (e.g., qa-releases/qa-v0.1.0.3-20260212-143022)
  - Runtime files copied (server.js, .next, public, package files)
  - .env file taken from workspace (from Phase 0)
  - web.config taken from active site if exists, otherwise from central config
  - Production dependencies installed with npm install --omit=dev --ignore-scripts

PHASE 3: IIS PATH SWAP (Minimal downtime < 2 seconds)
  - IIS site stopped (only qa.site.net, not entire IIS)
  - IIS physical path redirected to new folder
  - IIS site started

PHASE 4: CLEANUP
  - Last 3 releases kept, old folders deleted
```

**Benefits:**

- DLL lock issue **ELIMINATED** (new folder = no locked files)
- Minimal downtime (only during IIS path switch, < 2 seconds)
- Quick rollback capability (old folders still available)
- **Zero impact** on other applications (no process kill)

### Config File Management

The `.env` and `web.config` files needed during Build and Runtime are kept in a fixed folder on the server.
The deploy script retrieves files from the **config folder under qa/prod-release** each time it runs.

| File         | Description                              | Source Priority                                                |
| ------------ | ---------------------------------------- | -------------------------------------------------------------- |
| `.env`       | Environment variables (API URL, secrets) | 1. `config/.env` (to workspace in Phase 0) → 2. Release folder |
| `web.config` | IIS + iisnode configuration              | 1. Active IIS path → 2. `config/web.config` → 3. Skip          |

**Config Files Flow:**

1. **Phase 0**: `.env` file copied from `{env}-releases/config/.env` to workspace root (needed for build)
2. **Phase 2**:
   - `.env` copied from workspace (from Phase 0) to new release folder
   - `web.config` first tried from active IIS physical path (to preserve current settings)
   - If no active site (first deploy), `config/web.config` is used
   - If both don't exist, skip (web.config may come from git if in project)

---

## 1. Prerequisites and Server Configuration

### A. Git Installation (Server)

Git must be installed on the server for the runner to work.

1. Download Git for Windows from https://git-scm.com/download/win
2. Complete installation with default settings
3. After installation, close and reopen PowerShell
4. Verify:

```powershell
git --version   # Should show git version 2.x.x
```

5. Prevent long path issues (Administrator PowerShell):

```powershell
git config --system core.longPaths true
```

### B. IIS Folder Permissions

The runner service account (or `Users` group) must have write permissions to release folders:

```
C:\inetpub\wwwroot\[site-name]\qa-releases  -> Grant Modify permission to Users group
C:\inetpub\wwwroot\[site-name]\prod-releases -> Grant Modify permission to Users group (for PROD setup)
```

> **Note:** These folders are automatically created by the script during first deploy.
> However, write permission must exist on the parent folder (`C:\inetpub\wwwroot\[site-name]`).

**Steps:**

1. Right-click `C:\inetpub\wwwroot\[site-name]` > Properties > Security tab
2. Edit > Add > Type `Users` > Check Names > OK
3. Check `Modify` box > Apply > OK
4. Automatically inherits to subfolders

### C. IIS Features and iisnode

Verify the following IIS features are active on the server:

- **Common HTTP Features > Static Content** (Required)
- **Application Development Features > WebSocket Protocol** (Recommended)
- **iisnode** module must be installed (to run Node.js on IIS)

**Verification:**

- IIS Manager > Sites > Verify `qa` site points to current QA folder
  (After first deploy, IIS automatically redirected to `qa-releases\qa-v0.1.0.X-YYYYMMDD-HHMMSS` folder)
- Check site bindings for correct hostname/port settings (e.g., qa.site.net)
- Verify `iisnode` handler is defined for `server.js` in Handler Mappings

**iisnode Check (Optional - Read-Only):**

These commands only **check** if iisnode is installed, don't change any settings, and don't affect running applications. Paste into Administrator PowerShell:

```powershell
# Method 1: Is iisnode handler defined?
Get-WebHandler -Name "iisnode" -ErrorAction SilentlyContinue
# If returns result, iisnode is active. If error or empty, not installed.

# Method 2: Does iisnode file exist?
Test-Path "$env:ProgramFiles\iisnode\iisnode.dll"
# True if installed, False if not.
```

**Note:** The project is already running on IIS with iisnode, so both commands will likely return positive results. This step is for verification only and can be skipped.

### D. PowerShell Permissions

Windows blocks PowerShell script execution by default. We need to enable this for our deploy script to run.

Open **Administrator PowerShell** (right-click > Run as Administrator) and paste this command:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine
```

A confirmation prompt will appear:

```
Execution Policy Change
Do you want to change the execution policy?
[Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help
```

Type **`A` (Yes to All)** and press Enter.

**What it does:** Only blocks unsigned scripts downloaded from the internet. Locally created scripts (like our deploy.ps1) will run without issues.

### E. Node.js Check

Node.js 24.x must be installed on the server:

```powershell
node --version   # Should be v20.20.x (LTS) or higher (v24.13.0 (LTS) recommended)
npm --version    # npm version
```

**Important:** The `nodeProcessCommandLine` in `web.config` points to the Node.js path:

```xml
nodeProcessCommandLine="&quot;%programfiles%\nodejs\node.exe&quot;"
```

Verify this path is valid.

### F. GitHub Workflow Permissions

For GitHub Actions to create and merge PRs:

1. **Repo Settings** > **Actions** > **General**
2. Scroll to bottom of page: **"Workflow permissions"**
3. Select **Read and write permissions**
4. Check **Allow GitHub Actions to create and approve pull requests**
5. **Save**

### G. Create Fine-Grained Personal Access Token

An admin-level token is needed to bypass branch protection rules.

**Steps:**

1. **GitHub Profile** > **Settings** > **Developer settings** > **Personal access tokens** > **Fine-grained tokens**
2. **Generate new token**
3. **Settings:**
   - **Name:** `BYPASS_TOKEN_DUMMYPROJECT` (or your preferred name)
   - **Expiration:** `90 days` (regular renewal recommended)
   - **Repository access:** `Only select repositories` > Select your repo
4. **Repository Permissions:**
   - **Contents:** `Read and write` (For merge, push, tag)
   - **Metadata:** `Read-only` (Auto-included)
5. **Generate token** > Copy the token (won't be shown again!)
6. **Repo Settings** > **Secrets and variables** > **Actions** > **New repository secret**
   - **Name:** `BYPASS_TOKEN`
   - **Secret:** Paste the copied token
   - **Add secret**

**Note:** When the token expires, create a new one and update the secret.

### H. Create Config Folder (Central Structure)

You need to create a fixed `config` folder inside the releases folder for the deploy script to find the `.env` file.

**Steps for QA:**

1. Create folder:
   `C:\inetpub\wwwroot\[site-name]\qa-releases\config`

2. Copy your working `.env` file to this folder.

3. Copy your working `web.config` file to this folder.

**Folder Structure Should Look Like:**

```text
C:\inetpub\wwwroot\[site-name]\qa-releases\
    ├── config\
    │     ├── .env
    │     └── web.config
    ├── qa-v0.1.0.1-20260210-120000\ (old versions if exist)
    ├── qa-v0.1.0.2-20260211-150000\ (if exist)
    └── ...
```

> **Warning:** If this folder doesn't exist, the deploy process will fail at "Phase 0" stage.

### I. GitHub Self-Hosted Runner Installation (Service Mode)

The runner runs as a Windows Service on the IIS server. It starts automatically when the server reboots.

**A separate runner must be installed on each server (QA and PROD).**

> **Note:** The runner's working folder (`_work`) contains build files.
> The deploy script copies build output from this workspace to the new release folder.

Follow the steps on the GitHub page:
**Repo > Settings > Actions > Runners > New self-hosted runner > Windows / x64**

#### Download

The GitHub page asks you to create a folder with `mkdir actions-runner; cd actions-runner`.
Since we use project-based naming, skip this first step and create our own folder:

```powershell
# Create project-based folder (prevents conflicts if multiple project runners on same machine)
mkdir C:\actions-runner-site; cd C:\actions-runner-site
```

Copy and run the download and extract commands from the GitHub page as is:

```powershell
# Download runner package (copy version from GitHub page, below is example)
Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.331.0/actions-runner-win-x64-2.331.0.zip -OutFile actions-runner-win-x64-2.331.0.zip
```

```powershell
# Optional: Hash verification (compare with hash on GitHub page)
if((Get-FileHash -Path actions-runner-win-x64-2.331.0.zip -Algorithm SHA256).Hash.ToUpper() -ne 'HASH_FROM_GITHUB_PAGE'.ToUpper()){ throw 'Computed checksum did not match' }
```

```powershell
# Extract archive
Add-Type -AssemblyName System.IO.Compression.FileSystem ;
[System.IO.Compression.ZipFile]::ExtractToDirectory("$PWD/actions-runner-win-x64-2.331.0.zip", "$PWD")
```

> **Note:** Version numbers and hash values change over time. Always copy the current commands from the GitHub page.

#### Configure

```cmd
# Configure runner (copy --url and --token values from GitHub page)
.\config.cmd --url https://github.com/<ORG_NAME>/<REPO_NAME> --token TOKEN_FROM_GITHUB_PAGE
```

Interactive questions will be asked during configuration:

| Question          | QA Server               | PROD Server             |
| ----------------- | ----------------------- | ----------------------- |
| Runner group      | Enter (default)         | Enter (default)         |
| Runner name       | `QA-Deployer`           | `PROD-Deployer`         |
| Additional labels | `qa-server`             | `prod-server`           |
| Work folder       | Enter (default `_work`) | Enter (default `_work`) |
| Run as service?   | **Y** (Yes)             | **Y** (Yes)             |
| Service account   | Enter (default)         | Enter (default)         |

> **Critical:** Label values must exactly match `runs-on: [self-hosted, qa-server]` in workflow files!

> **Service question:** At the last step, it asks `Would you like to run the runner as service? (Y/N)` — answer **Y**. This automatically registers and starts the runner as a Windows Service. The runner will automatically start even if the server restarts. Don't use `run.cmd` — the runner stops when you close the terminal.

#### Verification

1. **On Server:** `services.msc` > Find "GitHub Actions Runner (...)"
   - Status: **Running**
   - Startup Type: **Automatic**
2. **On GitHub:** Repo > Settings > Actions > Runners — runner should show **Idle** status

#### Runner Service Account Permission Setup

The runner runs as a Windows Service under a specific user account (default: `Network Service`).
During deployment, the runner performs these operations:

- Copies files to target folder (needs folder write permission)
- Stops and starts IIS site with `appcmd` (needs IIS management permission)

The `appcmd` command requires being in the **Administrators** group to read IIS configuration files (`redirection.config`, etc.).
Folder permission alone is not enough — IIS site management also requires permission. So we add the service account to the Administrators group.

**Open Administrator PowerShell and run these commands:**

```powershell
# Add runner service account to Administrators group
net localgroup Administrators "NT AUTHORITY\NETWORK SERVICE" /add

# Restart runner service (for change to take effect)
Restart-Service *actions*
```

**Verification:**

```powershell
# Check if account is in group
net localgroup Administrators
# Should see "NT AUTHORITY\NETWORK SERVICE" in list
```

> **Note:** Service account may differ. Check from `services.msc` > "GitHub Actions Runner (...)" > **Log On** tab.
> If you see a different account, add that account instead.

---

## 2. Project Configuration

### A. server.js & web.config

**server.js** - Custom Node.js HTTP server:

```javascript
// iisnode runs this file
// PORT env variable is automatically set by iisnode (named pipe)
const port = process.env.PORT || 3000;
```

**web.config** - IIS + iisnode configuration:

- iisnode handler runs `server.js`
- URL rewrite rules redirect all requests to server.js
- Static content MIME type definitions included
- **This file is NOT CHANGED during deploy** (remains environment-specific on server)

### B. .env Files

The `.env` file on the server should contain these variables:

```dotenv
NODE_ENV=production
NEXT_PUBLIC_SITE_URL=https://qa.site.net
NEXT_PUBLIC_API_URL=https://qa-api.site.net   # QA API address
...
```

**Important:** The `.env` file is not overwritten during deployment. Must be created manually during initial setup.

---

## 3. Automation Files

All files have been created in the project:

```
DummyProject/
  scripts/
    deploy.ps1                    # PowerShell deploy script
  .github/
    workflows/
      deploy-qa.yml               # QA deploy workflow
      deploy-prod.yml             # PROD deploy workflow
      rollback-prod.yml           # PROD rollback workflow (no QA rollback)
```

### A. Deploy Script (`scripts/deploy.ps1`)

This script deploys using the **Versioned Release** approach.
Each deploy creates a new version folder and publishes with IIS path swap.

**Script Parameters and Settings:**

| Parameter/Setting     | Value                              | Description                                 |
| --------------------- | ---------------------------------- | ------------------------------------------- |
| `-environment`        | `qa` or `prod`                     | Deployment environment (required parameter) |
| `$env:FULL_VERSION`   | `{env}-v{X.Y.Z.B}`                 | Git tag (set by workflow)                   |
| `$timestamp`          | `yyyyMMdd-HHmmss`                  | Auto-generated by script                    |
| `$uniqueVersionName`  | `{FULL_VERSION}-{timestamp}`       | Final folder name                           |
| `$keepReleases`       | `3`                                | Number of old releases to keep              |
| `$appcmd`             | `C:\Windows\System32\...\...`      | IIS management tool                         |
| QA `ReleasesFolder`   | `C:\...\[site-name]\qa-releases`   | Folder where QA releases are kept           |
| QA `SiteName`         | `qa`                               | IIS site name (QA)                          |
| PROD `ReleasesFolder` | `C:\...\[site-name]\prod-releases` | Folder where PROD releases are kept         |
| PROD `SiteName`       | `site.com`                         | IIS site name (PROD)                        |

**Error Handling:**

- `ErrorActionPreference = "Stop"` — Any error stops deployment
- For npm commands `ErrorActionPreference = "Continue"` (stderr warning messages not treated as errors)
- Successful exit: `exit 0` — On error: `exit 1`

**Phases:**

0. **PHASE 0: PRE-BUILD** — Copy `.env` file from central config to workspace (needed before build)
1. **PHASE 1: BUILD** — `npm install` + `npm run build` (runner workspace, site running)
2. **PHASE 2: PREPARE** — Create new timestamped folder, copy runtime files, run `npm install --omit=dev --ignore-scripts`
3. **PHASE 3: SWAP** — IIS stop > change physicalPath > IIS start (< 2 seconds downtime)
4. **PHASE 4: CLEANUP** — Sort by CreationTime, keep last 3 releases, delete old folders (config folder excluded)

**Usage:**

```powershell
# Required: FULL_VERSION env var (set by workflow)
# NOTE: Timestamp automatically added by deploy script
$env:FULL_VERSION = "qa-v0.1.0.1"
.\scripts\deploy.ps1 -environment "qa"
# Result: C:\inetpub\wwwroot\[site-name]\qa-releases\qa-v0.1.0.1-20260212-143022\

.\scripts\deploy.ps1 -environment "prod"
```

**Folder Structure:**

```
C:\inetpub\wwwroot\[site-name]\
  qa-releases\              # QA releases
    config\                 # Central config folder (.env, web.config)
    qa-v0.1.0.1-20260210-120000\   # Old release (to be cleaned)
    qa-v0.1.0.2-20260211-150000\   # Previous release
    qa-v0.1.0.3-20260212-143022\   # <-- IIS currently points here
  prod-releases\            # PROD releases
    config\                 # Central config folder
    prod-v0.1.0.1-20260212-160000\ # <-- IIS currently points here
```

**Copied Runtime Files (workspace -> release folder):**

- `server.js` — iisnode entry point
- `package.json`, `package-lock.json` — for npm install
- `next.config.js` — Next.js runtime config
- `.next/` — compiled build output (**cache folder excluded - robocopy /XD cache**)
- `public/` — static files (images, icons, robots, etc.)
- `.env` — .env from workspace (from central config in Phase 0)

**Not Copied (build-time only, not needed at runtime):**

- `src/` — source code (already compiled in .next)
- `node_modules/` — reinstalled in release folder
- `tsconfig.json`, `tailwind.config.ts`, `postcss.config.js` — build tools

**NPM Install Flags:**

- `--omit=dev` — Only production dependencies installed (devDependencies skipped)
- `--ignore-scripts` — postinstall/prepare scripts skipped (git config, husky won't error)

**IIS Site Management:**

- `appcmd list site /site.name:"qa" /text:state` — Checks site state (Started/Stopped)
- `appcmd stop site /site.name:"qa"` — Only stops this site (if already Started)
- `appcmd set vdir /vdir.name:"qa/" /physicalPath:"new-path"` — Changes physical path
- `appcmd start site /site.name:"qa"` — Starts site
- General IIS service NOT AFFECTED, other sites continue running

**Important:** Runner service account must have IIS management permission (in `Administrators` group), otherwise appcmd commands will error.

### B. QA Workflow (`.github/workflows/deploy-qa.yml`)

**Trigger:** Manual (`workflow_dispatch`)
**Flow:** DEV -> QA branch merge + Build + Deploy + Tag

**Version Calculation Logic:**

1. App version read from `package.json` (e.g., `0.1.7`)
2. Count existing `qa-v0.1.7.*` tags
3. Find highest build number and increment by +1
4. Final tag: `qa-v{app_version}.{build_number}` (e.g., `qa-v0.1.7.3`)
5. Deploy script adds timestamp to this tag (folder: `qa-v0.1.7.3-20260212-143022`)

Steps:

1. Checkout QA branch (with BYPASS_TOKEN)
2. Merge DEV branch into QA (`--allow-unrelated-histories --no-edit`)
3. Calculate version (logic above)
4. Amend merge commit with version info and push
5. Setup Node.js 24
6. Run deploy script (timestamp auto-added)
7. Create and push git tag (e.g., `qa-v0.1.0.1`)
8. Summary report (GitHub Actions summary)

### C. PROD Workflow (`.github/workflows/deploy-prod.yml`)

**Trigger:** Manual (`workflow_dispatch`)
**Flow:** QA -> MAIN branch merge + Build + Deploy + Tag

**Version Derivation:**

1. All `qa-v*` tags sorted by semantic version
2. Latest QA tag selected (e.g., `qa-v0.1.7.2`)
3. PROD tag derived from QA tag: `qa-v0.1.7.2` → `prod-v0.1.7.2`
4. Deploy script adds timestamp to this tag (folder: `prod-v0.1.7.2-20260212-160000`)

Steps:

1. Checkout MAIN branch (with BYPASS_TOKEN)
2. Read version from latest QA tag (logic above)
3. Merge QA branch into MAIN (`--allow-unrelated-histories --no-edit`)
4. Push merge commit with version info
5. Setup Node.js 24
6. Run deploy script (timestamp auto-added)
7. Create and push PROD tag (e.g., `prod-v0.1.0.1`)
8. Summary report (GitHub Actions summary)

### D. Rollback Workflow (`.github/workflows/rollback-prod.yml`)

**Trigger:** Manual (`workflow_dispatch` + confirmation checkbox)

**Rollback Modes:**

1. **AUTO_PREVIOUS (Automatic)**
   - All `prod-v*` tags sorted by semantic version
   - At least 2 tags required (current + previous)
   - Second tag selected (previous version)

2. **MANUAL_TAG (Manual)**
   - User can enter specific tag (e.g., `prod-v0.1.0.1`)
   - Tag existence verified in repository

**Rollback Process:**

1. Target tag checked out (e.g., `prod-v0.1.0.1`)
2. Deploy script runs normally
3. New timestamped folder created (`prod-v0.1.0.1-20260212-173000`)
4. IIS redirected to this new folder
5. Git tag NOT ADDED (existing tag used, no new tag created)

**Security:** `confirm_action` checkbox required (workflow errors if false before starting)

---

## 4. Branch Protection Setup

> **Note:** "Rulesets" feature only works with GitHub Team (paid) plan on private repos.
> Below uses **Branch protection rules** which work on free plan.

### A. Main Branch Protection

1. **Repo Settings** > **Branches** > **Add branch protection rule**
2. **Branch name pattern:** `main`
3. Only check this option:
   - [x] **Require a pull request before merging**
     - Required approvals: **0**
4. Leave all other options as is (empty)
5. **Create**

> **Why is this enough?** When "Require PR" is active, direct push and force push are automatically blocked.
> Since approval count is 0, PR can be created but doesn't wait for approval — this way
> CI/CD workflow with admin-privileged `BYPASS_TOKEN` can merge without issues.

### B. QA Branch Protection (Optional)

1. **Repo Settings** > **Branches** > **Add branch protection rule**
2. **Branch name pattern:** `qa`
3. Only check this option:
   - [x] **Require a pull request before merging**
     - Required approvals: **0**
4. Leave all other options as is (empty)
5. **Create**

### C. Bypass Approach

Workflows use `BYPASS_TOKEN` (admin-privileged PAT) to bypass branch protection rules.
Tokens with admin privileges are exempt from protection rules, allowing CI/CD flow to work seamlessly.

---

## 5. Step-by-Step Initial Setup (QA)

Follow these steps in order:

### Step 1: Local Preparation

```bash
# 1. Build test
npm install
npm run build

# 2. Commit CI/CD files
git add scripts/ .github/
git commit -m "ci: add CI/CD pipeline (deploy, rollback workflows)"
```

### Step 2: Create Branches

```bash
# If you don't have dev branch
git checkout -b dev
git push origin dev

# Create qa branch
git checkout -b qa
git push origin qa

# Return to main branch
git checkout main
```

### Step 3: Push Changes

```bash
git push origin main

# Also push to dev and qa branches
git checkout dev && git merge main && git push origin dev
git checkout qa && git merge main && git push origin qa
```

### Step 4: GitHub Settings

Complete these steps from GitHub web interface **before accessing server**:

1. Configure workflow permissions (Section 1.F)
2. Create Fine-Grained PAT (Section 1.G)
3. Add `BYPASS_TOKEN` secret (Section 1.G, Step 6)
4. Create Branch Protection rules (Section 4)

### Step 5: Server Preparation (RDP)

Connect to QA server via RDP and do these in order:

1. **Install Git** (if not installed): https://git-scm.com/download/win (Section 1.A)
2. **Long paths fix**: `git config --system core.longPaths true`
3. **PowerShell**: `Set-ExecutionPolicy RemoteSigned -Scope LocalMachine`
4. **Folder permissions**: `C:\inetpub\wwwroot\[site-name]` grant Users > Modify (inherits to subfolders)
5. **IIS check**: Verify `qa` site points to current QA folder
6. **Config Folder Preparation**:
   - Create `C:\inetpub\wwwroot\[site-name]\qa-releases\config` folder.
   - Put your working `.env` and `web.config` files inside this folder.
   - **Note:** If this step is skipped, deploy will fail at Phase 0 stage.

### Step 6: Runner Installation (On Server)

After Git and PowerShell are ready, install runner **in same RDP session**:

1. Install self-hosted runner on QA server, label: `qa-server` (Section 1.H)
2. Verify runner service is **Running** and **Automatic** (`services.msc`)
3. Verify runner shows **Idle** on GitHub > Repo > Settings > Actions > Runners

### Step 7: First Deploy Test

1. GitHub > Actions > "Deploy to QA" > Run workflow
2. Follow workflow logs
3. After green checkmark, check `https://qa.site.net` address

---

## 6. Common Errors and Solutions

| Error                                  | Solution                                                                    |
| -------------------------------------- | --------------------------------------------------------------------------- |
| Running scripts is disabled            | `Set-ExecutionPolicy RemoteSigned -Scope LocalMachine`                      |
| Filename too long                      | `git config --system core.longPaths true`                                   |
| Access Denied (IIS folder)             | Grant Users > Modify permission on folder                                   |
| Access Denied (appcmd)                 | Add runner service account to Administrators group                          |
| Could not read IIS site state          | Runner account needs IIS management permission (Administrators group)       |
| Process exit code 1 (despite success)  | Script ends with `exit 0` (Robocopy exit code 1 = success)                  |
| PowerShell Encoding Error              | Don't use emoji in YAML/Script, use ASCII characters                        |
| Resource not accessible by integration | Workflow permissions > Read and write + Allow PR creation                   |
| Runner stops after closing CMD         | Install as Windows Service with `.\svc.cmd install`                         |
| Protected ref cannot update            | Add `token: ${{ secrets.BYPASS_TOKEN }}` to `actions/checkout`              |
| Merge conflict in workflow             | Workflow stops, resolve conflict manually and re-trigger                    |
| IIS site won't stop                    | Verify site name with `appcmd list site`                                    |
| Build fails but old site runs          | Build happens in workspace, IIS unaffected — site continues running         |
| FULL_VERSION env var not set           | Check FULL_VERSION is properly set in workflow                              |
| appcmd set vdir fails                  | Check vdir name format: `siteName/` (must end with slash)                   |
| [FAIL] Central .env file not found     | Create `{env}-releases\config` folder and put `.env` inside                 |
| [FAIL] .next copy failed               | Check build succeeded, .next folder should exist                            |
| npm install failed in release folder   | Verify package.json and package-lock.json are copied                        |
| Old release folder couldn't be deleted | Locked files possible (normal), script continues, will retry on next deploy |

---

## 7. PROD Setup (Future)

When setting up PROD environment, complete these steps:

1. **Create `C:\inetpub\wwwroot\[site-name]` folder on server** and grant Users > Modify permission
   (prod-releases subfolder auto-created on first deploy)

2. **Create PROD Config Folder:**
   - Create `C:\inetpub\wwwroot\[site-name]\prod-releases\config` folder.
   - Put valid production `.env` and `web.config` files here.

3. **Check PROD site in IIS**: `site.com` site should point to current folder

4. **Install runner on PROD server** - Label: `prod-server` (Section 1.H)

5. **Add Branch Protection rule** for PROD branch (optional, same as Section 4.B)

6. **Test first PROD deploy**: Actions > "Deploy to PROD" > Run workflow
   - Script automatically copies `.env` and `web.config` from current IIS path
   - IIS path redirected to new release folder
   - Old folder not deleted (last 3 releases kept)

---

## 8. Architecture Summary

```
Developer (Local)
    |
    | git push
    v
GitHub (dev branch)
    |
    | [Deploy to QA] workflow triggered (manual)
    | 1. dev -> qa merge (--allow-unrelated-histories)
    | 2. Version calculation (package.json + tag count)
    | 3. Build on QA Runner (workspace)
    | 4. Phase 0: .env from central config to workspace
    | 5. Phase 1: npm install + build
    | 6. Phase 2: New timestamped folder (qa-v0.1.0.X-20260212-143022)
    | 7. Phase 3: IIS path swap (< 2 sec)
    | 8. Phase 4: Cleanup (keep last 3 releases)
    | 9. Git tag push (qa-v0.1.0.X)
    v
QA Server (https://qa.site.net) [runner: qa-server]
    |
    | [Deploy to PROD] workflow triggered (manual)
    | 1. Find latest QA tag (semantic sort)
    | 2. qa -> main merge
    | 3. Build on PROD Runner (workspace)
    | 4. Phase 0-4 run same way
    | 5. New timestamped folder (prod-v0.1.0.X-20260212-160000)
    | 6. Git tag push (prod-v0.1.0.X)
    v
PROD Server (https://site.com) [runner: prod-server]

    Emergency:
    [Rollback PROD] -> Reverts to old release folder
```

**Runner Location:** Each IIS server runs its own runner (self-hosted). QA runner identified by `qa-server` label, PROD runner by `prod-server` label. Build and deploy happen on the same machine. File copying happens on local disk (no network transfer).

**Versioned Release Folder Structure:**

```
C:\inetpub\wwwroot\[site-name]\
  qa-releases\
    config\                         # Central config (.env, web.config)
    qa-v0.1.0.1-20260210-120000\   # old (cleaned if more than 3)
    qa-v0.1.0.2-20260211-150000\   # previous
    qa-v0.1.0.3-20260212-143022\   # <-- IIS points here (newest)
  prod-releases\
    config\                         # Central config
    prod-v0.1.0.1-20260212-160000\ # <-- IIS points here
```

**Note:** Each release folder name has timestamp added (`yyyyMMdd-HHmmss` format).
This allows multiple deploys of the same version and prevents file locking issues.
