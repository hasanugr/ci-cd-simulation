# CI/CD Pipeline for IIS + Node.js

> Production-ready GitHub Actions CI/CD pipeline for Next.js applications running on Windows Server with IIS and iisnode

[![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=github-actions&logoColor=white)](https://github.com/features/actions)
[![IIS](https://img.shields.io/badge/Server-IIS-5E5E5E?logo=microsoft&logoColor=white)](https://www.iis.net/)
[![Node.js](https://img.shields.io/badge/Node.js-24.x-339933?logo=node.js&logoColor=white)](https://nodejs.org/)
[![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?logo=powershell&logoColor=white)](https://docs.microsoft.com/en-us/powershell/)

---

## The Problem

Deploying Node.js applications to Windows Server with IIS presents unique challenges:

- **DLL Locking Issues**: Native modules (sharp, better-sqlite3, etc.) get locked by iisnode, preventing updates
- **Deployment Downtime**: Traditional IIS deployments require stopping entire application pools
- **Manual Version Management**: Tracking versions, merges, and rollbacks becomes error-prone
- **Legacy Infrastructure**: Many organizations still run critical applications on Windows Server + IIS

Most CI/CD solutions target Linux/containerized environments, leaving Windows + IIS deployments as manual, risky processes.

---

## The Solution

This project provides a **complete, automated CI/CD pipeline** specifically designed for Windows Server + IIS + Node.js deployments. It solves DLL locking issues through a **versioned release strategy** while maintaining near-zero downtime.

### Key Features

#### Zero-Downtime Deployment

- **< 2 seconds** downtime during IIS path switch
- Build happens while current site is running
- Atomic swap to new release folder

#### DLL Lock Problem Solved

- Each deploy creates a **new versioned folder** with timestamp
- No locked files in fresh directories
- Old releases preserved for instant rollback

#### Automated Branch Management

- **dev → qa → main** branch flow
- Automatic merging with conflict detection
- Smart semantic versioning (app version + build number)
- Git tags for every deployment

#### Production Rollback

- **One-click rollback** to any previous version
- Automatic (revert to last working) or manual (select specific tag)
- Confirmation checkpoints prevent accidents

#### Built for Legacy Infrastructure

- Designed for **Windows Server** + **IIS** + **iisnode**
- PowerShell deployment scripts
- Self-hosted GitHub Actions runners
- Works with existing IIS configurations

---

## Quick Start

### Prerequisites

- Windows Server with IIS + iisnode
- Node.js 24.x or higher
- GitHub repository with fine-grained PAT token
- Self-hosted GitHub Actions runner on Windows

### Installation

1. **Clone and configure**

   ```bash
   git clone https://github.com/yourusername/iis-nodejs-deployment.git
   cd iis-nodejs-deployment
   ```

2. **Update deployment paths**

   Edit [`scripts/deploy.ps1`](scripts/deploy.ps1) with your server paths:

   ```powershell
   "qa" = @{
     ReleasesFolder = "C:\inetpub\wwwroot\your-site\qa-releases"
     SiteName       = "qa.yoursite.com"
   }
   ```

3. **Create branches**

   ```bash
   git checkout -b dev
   git checkout -b qa
   git push origin dev qa main
   ```

4. **Setup GitHub secrets**
   - Create fine-grained PAT token with `Contents: Write` permission
   - Add as repository secret named `BYPASS_TOKEN`

5. **Install runner on Windows Server**

   ```powershell
   # Create runner directory
   mkdir C:\actions-runner-yourproject; cd C:\actions-runner-yourproject

   # Download and configure runner (follow GitHub's instructions)
   # Label for QA server: qa-server
   # Label for PROD server: prod-server
   ```

6. **Deploy to QA**
   - Go to Actions → "Deploy to QA" → Run workflow
   - Monitor the automated build and deployment

**Full setup guide**: See [docs/ci-cd-guide-en.md](docs/ci-cd-guide-en.md)

---

## How It Works

### Architecture

```
Developer (Local)
    |
    | git push to dev
    v
GitHub Actions (Manual Trigger)
    |
    | 1. Merge dev → qa (automated)
    | 2. Calculate version (package.json + build number)
    | 3. Build on self-hosted runner
    | 4. Deploy to versioned folder (qa-v0.1.0.3-20260212-143022)
    | 5. IIS path swap (< 2 sec)
    | 6. Create git tag (qa-v0.1.0.3)
    v
QA Server (https://qa.yoursite.com)
    |
    | After QA approval
    v
GitHub Actions (Deploy to PROD)
    |
    | 1. Merge qa → main
    | 2. Use QA version
    | 3. Deploy to PROD (prod-v0.1.0.3-20260212-160000)
    v
PROD Server (https://yoursite.com)

Emergency Rollback:
    PROD → Select version → Deploy old tag → Live in < 2 min
```

### Version Format

```
{env}-v{major}.{minor}.{patch}.{build}-{timestamp}

Example:
- Git Tag:     qa-v0.1.7.2
- IIS Folder:  qa-v0.1.7.2-20260212-143022
```

The timestamp allows multiple deploys of the same version and prevents file conflicts.

### Deployment Strategy: Versioned Release

```
Phase 0: PRE-BUILD
  └─ Copy .env from central config to workspace (for NEXT_PUBLIC_ vars)

Phase 1: BUILD (No downtime - current site running)
  ├─ npm install
  └─ npm run build (.next folder created)

Phase 2: PREPARE (No downtime)
  ├─ Create new versioned folder (qa-v0.1.0.3-20260212-143022)
  ├─ Copy runtime files (server.js, .next, public, package files)
  ├─ Copy .env and web.config from central config
  └─ npm install --omit=dev --ignore-scripts (production dependencies)

Phase 3: IIS PATH SWAP (< 2 seconds downtime)
  ├─ Stop IIS site (only this site, not entire IIS)
  ├─ Change physical path to new folder
  └─ Start IIS site

Phase 4: CLEANUP
  └─ Keep last 3 releases, delete older folders
```

**Result**: New folder = no DLL locks + minimal downtime + instant rollback capability

---

## Workflows

### 1. Deploy to QA ([.github/workflows/deploy-qa.yml](.github/workflows/deploy-qa.yml))

- Merges `dev` → `qa`
- Auto-increments build number
- Deploys to QA server (runner: `qa-server`)
- Creates git tag (e.g., `qa-v0.1.7.2`)

### 2. Deploy to PROD ([.github/workflows/deploy.prod.yml](.github/workflows/deploy.prod.yml))

- Reads latest QA tag
- Merges `qa` → `main`
- Deploys to PROD server (runner: `prod-server`)
- Creates PROD tag (e.g., `prod-v0.1.7.2`)

### 3. Rollback PROD ([.github/workflows/rollback-prod.yml](.github/workflows/rollback-prod.yml))

- **Auto mode**: Reverts to previous working version
- **Manual mode**: Select specific tag to rollback
- Requires confirmation checkbox
- Re-deploys old version to new timestamped folder

---

## Project Structure

```
iis-nodejs-deployment/
├── .github/
│   └── workflows/
│       ├── deploy-qa.yml          # QA deployment workflow
│       ├── deploy.prod.yml        # PROD deployment workflow
│       └── rollback-prod.yml      # PROD rollback workflow
├── scripts/
│   └── deploy.ps1                 # PowerShell deployment script
├── docs/
│   ├── ci-cd-guide-en.md          # Complete setup guide (English)
│   └── ci-cd-guide-tr.md          # Complete setup guide (Turkish)
├── server.js                      # Custom Node.js server for iisnode
├── web.config                     # IIS + iisnode configuration
└── README.md                      # This file
```

---

## Requirements

### Server

- Windows Server 2016 or higher
- IIS with Static Content + WebSocket Protocol
- iisnode module installed
- Git for Windows
- Node.js 24.x or higher
- PowerShell 5.1 or higher

### GitHub

- Fine-grained Personal Access Token (PAT) with `Contents: Write`
- Self-hosted Windows runner with label `qa-server` / `prod-server`
- Workflow permissions: Read and write + Allow PR creation

### Project

- Next.js 14.x or higher (adaptable to other Node.js frameworks)
- `server.js` entry point for iisnode
- `web.config` for IIS configuration

---

## Use Cases

This pipeline is ideal for:

- **Enterprise Applications**: Organizations running Node.js apps on Windows Server
- **Legacy Infrastructure**: Modernizing CI/CD without infrastructure migration
- **Regulated Industries**: On-premise deployments with strict control requirements
- **Cost Optimization**: Leveraging existing Windows Server investments
- **SSR Applications**: Next.js or other frameworks requiring server-side rendering on IIS

---

## Configuration

### Branch Protection

**Main Branch**:

- Require pull request before merging (0 approvals)
- No force push
- Workflows bypass with `BYPASS_TOKEN`

**QA Branch** (Optional):

- Same as main branch

### Environment Variables

Create `C:\inetpub\wwwroot\your-site\{env}-releases\config\.env`:

```env
NODE_ENV=production
NEXT_PUBLIC_SITE_URL=https://qa.yoursite.com
NEXT_PUBLIC_API_URL=https://qa-api.yoursite.com
# Add your environment-specific variables
```

### IIS Configuration

The `web.config` file should be placed in `config` folder:

```xml
<handlers>
  <add name="iisnode" path="server.js" verb="*" modules="iisnode" />
</handlers>
```

---

## Documentation

- **Complete Setup Guide**: [docs/ci-cd-guide-en.md](docs/ci-cd-guide-en.md)
- **Turkish Guide**: [docs/ci-cd-guide-tr.md](docs/ci-cd-guide-tr.md)
- **Deployment Script**: [scripts/deploy.ps1](scripts/deploy.ps1)

---

## Troubleshooting

| Issue                       | Solution                                                 |
| --------------------------- | -------------------------------------------------------- |
| Running scripts is disabled | `Set-ExecutionPolicy RemoteSigned -Scope LocalMachine`   |
| Access Denied (IIS folder)  | Grant `Users` group Modify permission on releases folder |
| Access Denied (appcmd)      | Add runner service account to Administrators group       |
| DLL still locked            | Verify using versioned release (new folder each deploy)  |
| Merge conflicts             | Workflow stops, resolve manually and re-trigger          |

---

## Contributing

Contributions are welcome! This is a template/starter project designed to be forked and customized for your needs.

1. Fork the repository
2. Adapt paths and configurations for your environment
3. Test thoroughly in QA before PROD
4. Share improvements via pull requests

---

## License

MIT License - Feel free to use this in your projects, commercial or personal.

---

## Acknowledgments

Designed for organizations running Node.js applications on Windows Server + IIS, where containerization isn't an option and zero-downtime deployments are critical.

**Special thanks to** the teams maintaining GitHub Actions, PowerShell, iisnode, and IIS on Windows Server.

---

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/iis-nodejs-deployment/issues)
- **Documentation**: [Complete Setup Guide](docs/ci-cd-guide-en.md)
- **Discussions**: Share your use cases and improvements

---

**Made with automation for Windows Server deployments**
