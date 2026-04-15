# macOS Desktop Backup & Space Reclaimer

Opinionated backup pipeline for stale projects → Google Drive (via rclone) → safe local deletion.

**Philosophy:** Nothing is deleted automatically. Every deletion requires human review and approval.

## Features

- **Tier classification** — clean git, dirty git, no-git projects
- **Auto-commit + push** dirty repos before backing up
- **Checksum verification** — `rclone check` after every backup
- **Dry-run mode** — see exactly what would happen
- **Deletion checklist** — generated report with checkboxes for human review
- **Disk analysis** — finds where your storage went
- **Quick wins** — immediate wins from caches, simulators, etc.

## Setup

### Prerequisites

```bash
brew install rclone dust ncdu
rclone config  # set up your Google Drive remote (named "gdrive" by default)
```

### Configure for your machine

Copy the example config and edit for your setup:

```bash
cp config/stale-projects.conf.example config/stale-projects.conf
```

Edit `config/stale-projects.conf` with your project names per tier.

## Usage

```bash
# Full dry run (auth + scan + push preview + backup preview + checklist)
bash scripts/backup.sh dry-run

# Step-by-step (recommended for first run)
bash scripts/backup.sh auth          # Verify rclone connection
bash scripts/backup.sh scan          # Find stale projects on your Desktop
bash scripts/backup.sh push          # Preview dirty git commits
bash scripts/backup.sh push-live     # Actually commit + push dirty repos
bash scripts/backup.sh backup        # Dry-run backup to GDrive
bash scripts/backup.sh backup-live   # Actually upload to GDrive
bash scripts/backup.sh verify-live   # Checksum verification
bash scripts/backup.sh checklist     # Generate deletion checklist

# Quick wins (caches, simulators, etc.)
bash scripts/quick-wins.sh scan      # Show what can be freed immediately

# Disk analysis
dust ~ --depth 1                     # Overview
ncdu ~/Library                       # Deep dive
```

## Project Structure

```
desktop-backup/
├── README.md
├── scripts/
│   ├── backup.sh              # Main pipeline (auth/scan/push/backup/verify/checklist)
│   ├── quick-wins.sh          # Disk space quick wins menu
│   └── disk-analysis.sh       # Where did your storage go?
├── config/
│   ├── stale-projects.conf.example  # Template config
│   ├── stale-projects.conf          # Your tier lists (gitignored)
│   └── rclone-excludes.txt          # Files to skip during backup
├── examples/
│   ├── delete-checklist.example.md  # What a checklist looks like
│   └── scan-example.txt             # What a scan looks like
├── logs/                      # Auto-generated (gitignored)
└── reports/                   # Auto-generated (gitignored)
```

## How It Works

1. **Scan** — finds projects on Desktop not touched in 30+ days
2. **Classify** — sorts into tiers:
   - Tier 1: Clean git (fully pushed to GitHub) → safe to archive
   - Tier 2: Dirty git (uncommitted/pushed changes) → commit + push first
   - Tier 3: No git → backup to GDrive only
3. **Backup** — `rclone copy` each project to `gdrive:backups/desktop/`
4. **Verify** — `rclone check` with MD5 checksums
5. **Checklist** — generates a markdown checklist for human review
6. **Delete** — you manually delete what you're comfortable removing

## Safety Guarantees

- **No automatic deletion** — ever. You review and delete manually.
- **Checksum verification** before any deletion is recommended.
- **Dry-run mode** on every destructive operation.
- **Git push first** — all dirty repos get committed and pushed before backup.
- **GDrive remote** — data exists in two places before you delete local copy.

## Configuration

### Remote name

Default is `gdrive`. Override with env var:

```bash
RCLONE_REMOTE=mydrive bash scripts/backup.sh backup-live
```

### Stale threshold

Default is 30 days. Override:

```bash
STALE_DAYS=60 bash scripts/backup.sh scan
```

### Desktop path

Default is `~/Desktop`. Override:

```bash
DESKTOP_PATH=~/Projects bash scripts/backup.sh scan
```

## License

MIT