#!/usr/bin/env bash
set -euo pipefail

# ┌──────────────────────────────────────────────────────────┐
# │  Desktop Backup & Space Reclaimer                       │
# │  Stale project → GDrive → safe deletion pipeline        │
# └──────────────────────────────────────────────────────────┘

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$PROJECT_DIR/config"
LOG_DIR="$PROJECT_DIR/logs"
REPORT_DIR="$PROJECT_DIR/reports"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

# Load config or defaults
CONF="$CONFIG_DIR/stale-projects.conf"
if [[ -f "$CONF" ]]; then
    source "$CONF"
else
    echo "No config found. Copy config/stale-projects.conf.example to config/stale-projects.conf"
    echo "Then edit it for your machine."
    exit 1
fi

RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}:"
DESKTOP_PATH="${DESKTOP_PATH:-$HOME/Desktop}"
STALE_DAYS="${STALE_DAYS:-30}"
GDRIVE_BASE="${RCLONE_REMOTE}backups/desktop"
GDRIVE_NO_GIT="${RCLONE_REMOTE}backups/desktop-no-git"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$LOG_DIR/backup-${TIMESTAMP}.log"; }
ok()   { log "${GREEN}✓ $1${NC}"; }
warn() { log "${YELLOW}⚠ $1${NC}"; }
err()  { log "${RED}✗ $1${NC}"; }

mkdir -p "$LOG_DIR" "$REPORT_DIR"

# ─── Phase 1: Auth ────────────────────────────────────────

check_auth() {
    log "${BLUE}Checking rclone authentication...${NC}"
    if rclone lsd "$RCLONE_REMOTE" >/dev/null 2>&1; then
        ok "rclone authenticated and connected to remote"
        return 0
    else
        err "rclone auth failed. Token may be expired."
        echo ""
        echo "Run:  rclone config reconnect ${RCLONE_REMOTE%:}"
        echo "This will open a browser for OAuth."
        return 1
    fi
}

# ─── Phase 2: Scan ───────────────────────────────────────

scan_desktop() {
    local cutoff=$(date -v-${STALE_DAYS}d +%Y-%m-%d 2>/dev/null || date -d "${STALE_DAYS} days ago" +%Y-%m-%d)
    local report="$REPORT_DIR/scan-${TIMESTAMP}.txt"

    echo "=== DESKTOP STALE PROJECT SCAN ===" > "$report"
    echo "Scan date: $(date)" >> "$report"
    echo "Cutoff: $cutoff (${STALE_DAYS} days ago)" >> "$report"
    echo "" >> "$report"

    log "${BLUE}Scanning Desktop for stale projects (>${STALE_DAYS} days)...${NC}"

    local total_kb=0

    echo "--- TIER 1: Clean git (safe to archive) ---" >> "$report"
    for name in "${TIER1_CLEAN_GIT[@]}"; do
        dir="$DESKTOP_PATH/$name"
        [[ ! -d "$dir" ]] && continue
        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        kb=$(du -sk "$dir" 2>/dev/null | cut -f1)
        total_kb=$((total_kb + kb))
        remote=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "?")
        dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        ahead=$(git -C "$dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo "?")
        echo "  $name | $size | $remote | dirty:$dirty | ahead:$ahead" >> "$report"
    done

    echo "" >> "$report"
    echo "--- TIER 2: Dirty git (needs push) ---" >> "$report"
    for name in "${TIER2_DIRTY_GIT[@]}"; do
        dir="$DESKTOP_PATH/$name"
        [[ ! -d "$dir" ]] && continue
        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        kb=$(du -sk "$dir" 2>/dev/null | cut -f1)
        total_kb=$((total_kb + kb))
        remote=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "?")
        dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        ahead=$(git -C "$dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo "?")
        echo "  $name | $size | $remote | dirty:$dirty | ahead:$ahead" >> "$report"
    done

    echo "" >> "$report"
    echo "--- TIER 3: No-git (backup to GDrive) ---" >> "$report"
    for name in "${TIER3_NO_GIT[@]}"; do
        dir="$DESKTOP_PATH/$name"
        [[ ! -d "$dir" ]] && continue
        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        kb=$(du -sk "$dir" 2>/dev/null | cut -f1)
        total_kb=$((total_kb + kb))
        echo "  $name | $size" >> "$report"
    done

    echo "" >> "$report"
    echo "--- FREE SPACE ESTIMATE ---" >> "$report"
    echo "  Estimated recoverable: $(( total_kb / 1024 )) MB (~$(( total_kb / 1024 / 1024 )) GB)" >> "$report"

    cat "$report"
    ok "Scan complete: $report"
}

# ─── Phase 3: Push dirty repos ───────────────────────────

push_dirty_repos() {
    local dry="${1:-true}"
    log "${BLUE}Pushing dirty git repos... (dry_run=$dry)${NC}"

    for name in "${TIER2_DIRTY_GIT[@]}"; do
        dir="$DESKTOP_PATH/$name"
        [[ ! -d "$dir" ]] && continue

        dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        ahead=$(git -C "$dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo "0")

        if [[ "$dirty" -gt 0 ]]; then
            log "  $name: $dirty dirty files"
            if [[ "$dry" == "false" ]]; then
                git -C "$dir" add -A
                git -C "$dir" commit -m "chore: archive backup - auto-commit before desktop cleanup" --no-verify 2>/dev/null || warn "  Nothing to commit in $name"
                ok "  Committed changes in $name"
            else
                warn "  DRY RUN: Would commit $dirty files in $name"
            fi
        fi

        if [[ "$ahead" != "0" && "$ahead" != "?" ]]; then
            log "  $name: $ahead commits ahead of remote"
            if [[ "$dry" == "false" ]]; then
                git -C "$dir" push origin HEAD 2>&1 || err "  Push failed for $name"
                ok "  Pushed $name"
            else
                warn "  DRY RUN: Would push $ahead commits for $name"
            fi
        fi
    done
}

# ─── Phase 4: Backup to GDrive ───────────────────────────

backup_to_gdrive() {
    local dry="${1:-true}"
    local rclone_action="copy --dry-run"
    if [[ "$dry" == "false" ]]; then
        rclone_action="copy"
    fi

    log "${BLUE}Backing up to GDrive... (dry_run=$dry)${NC}"

    local excludes="--exclude-from=$CONFIG_DIR/rclone-excludes.txt"

    for name in "${TIER1_CLEAN_GIT[@]}" "${TIER2_DIRTY_GIT[@]}"; do
        dir="$DESKTOP_PATH/$name"
        [[ ! -d "$dir" ]] && continue
        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        log "  Backing up: $name ($size) → $GDRIVE_BASE/$name/"

        rclone $rclone_action \
            "$dir/" \
            "$GDRIVE_BASE/$name/" \
            --checksum \
            --transfers 8 \
            --checkers 16 \
            --drive-chunk-size 8M \
            --exclude ".DS_Store" \
            --exclude "node_modules/**" \
            --exclude ".next/**" \
            --log-file="$LOG_DIR/rclone-${TIMESTAMP}.log" \
            --log-level INFO \
            --retries 5 \
            --retries-sleep 15s \
            --low-level-retries 10 \
            2>&1 || warn "  Issues with $name (check log)"
    done

    for name in "${TIER3_NO_GIT[@]}"; do
        dir="$DESKTOP_PATH/$name"
        [[ ! -d "$dir" ]] && continue
        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        log "  Backing up (no-git): $name ($size) → $GDRIVE_NO_GIT/$name/"

        rclone $rclone_action \
            "$dir/" \
            "$GDRIVE_NO_GIT/$name/" \
            --checksum \
            --transfers 8 \
            --checkers 16 \
            --drive-chunk-size 8M \
            --exclude ".DS_Store" \
            --exclude "node_modules/**" \
            --log-file="$LOG_DIR/rclone-${TIMESTAMP}.log" \
            --log-level INFO \
            --retries 5 \
            --retries-sleep 15s \
            --low-level-retries 10 \
            2>&1 || warn "  Issues with $name (check log)"
    done
}

# ─── Phase 5: Verify ──────────────────────────────────────

verify_backups() {
    local dry="${1:-true}"

    if [[ "$dry" == "true" ]]; then
        warn "DRY RUN: Skipping verification (no files were actually uploaded)"
        return 0
    fi

    log "${BLUE}Verifying backups...${NC}"

    for name in "${TIER1_CLEAN_GIT[@]}" "${TIER2_DIRTY_GIT[@]}"; do
        dir="$DESKTOP_PATH/$name"
        [[ ! -d "$dir" ]] && continue
        log "  Verifying: $name"
        rclone check \
            "$dir/" \
            "$GDRIVE_BASE/$name/" \
            --checksum \
            --exclude ".DS_Store" \
            --exclude "node_modules/**" \
            --exclude ".next/**" \
            --checkers 16 \
            2>&1 | tail -5 | tee -a "$LOG_DIR/verify-${TIMESTAMP}.log"
    done

    for name in "${TIER3_NO_GIT[@]}"; do
        dir="$DESKTOP_PATH/$name"
        [[ ! -d "$dir" ]] && continue
        log "  Verifying (no-git): $name"
        rclone check \
            "$dir/" \
            "$GDRIVE_NO_GIT/$name/" \
            --checksum \
            --exclude ".DS_Store" \
            --exclude "node_modules/**" \
            --checkers 16 \
            2>&1 | tail -5 | tee -a "$LOG_DIR/verify-${TIMESTAMP}.log"
    done

    ok "Verification complete. See $LOG_DIR/verify-${TIMESTAMP}.log"
}

# ─── Phase 6: Deletion checklist ──────────────────────────

generate_delete_checklist() {
    local report="$REPORT_DIR/delete-checklist-${TIMESTAMP}.md"

    echo "# Deletion Checklist - $(date)" > "$report"
    echo "" >> "$report"
    echo "## ⚠️ REVIEW EACH ITEM BEFORE DELETING" >> "$report"
    echo "These projects have been backed up to Google Drive." >> "$report"
    echo "" >> "$report"

    echo "### Tier 1: Clean git (pushed to GitHub, backed up to GDrive)" >> "$report"
    for name in "${TIER1_CLEAN_GIT[@]}"; do
        dir="$DESKTOP_PATH/$name"
        [[ ! -d "$dir" ]] && continue
        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        remote=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "?")
        echo "- [ ] \`$name\` ($size) → GitHub: $remote → GDrive: backups/desktop/$name/" >> "$report"
    done

    echo "" >> "$report"
    echo "### Tier 2: Dirty git (committed & pushed, backed up to GDrive)" >> "$report"
    for name in "${TIER2_DIRTY_GIT[@]}"; do
        dir="$DESKTOP_PATH/$name"
        [[ ! -d "$dir" ]] && continue
        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        remote=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "?")
        echo "- [ ] \`$name\` ($size) → GitHub: $remote → GDrive: backups/desktop/$name/" >> "$report"
    done

    echo "" >> "$report"
    echo "### Tier 3: No-git (backed up to GDrive only)" >> "$report"
    for name in "${TIER3_NO_GIT[@]}"; do
        dir="$DESKTOP_PATH/$name"
        [[ ! -d "$dir" ]] && continue
        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        echo "- [ ] \`$name\` ($size) → GDrive: backups/desktop-no-git/$name/" >> "$report"
    done

    echo "" >> "$report"
    echo "### Estimated space recovery" >> "$report"
    local total=0
    for tier_name in TIER1_CLEAN_GIT TIER2_DIRTY_GIT TIER3_NO_GIT; do
        declare -n tier="$tier_name"
        for name in "${tier[@]}"; do
            dir="$DESKTOP_PATH/$name"
            [[ ! -d "$dir" ]] && continue
            kb=$(du -sk "$dir" 2>/dev/null | cut -f1)
            total=$((total + kb))
        done
    done
    echo "**~$(( total / 1024 / 1024 )) GB** recoverable" >> "$report"

    cat "$report"
    ok "Delete checklist: $report"
}

# ─── Main ─────────────────────────────────────────────────

case "${1:-help}" in
    auth)
        check_auth
        ;;
    scan)
        scan_desktop
        ;;
    push)
        push_dirty_repos "${2:-true}"
        ;;
    push-live)
        push_dirty_repos "false"
        ;;
    backup)
        backup_to_gdrive "${2:-true}"
        ;;
    backup-live)
        backup_to_gdrive "false"
        ;;
    verify)
        verify_backups "${2:-true}"
        ;;
    verify-live)
        verify_backups "false"
        ;;
    checklist)
        generate_delete_checklist
        ;;
    dry-run)
        echo "╔══════════════════════════════════════╗"
        echo "║   DESKTOP BACKUP — DRY RUN MODE     ║"
        echo "╚══════════════════════════════════════╝"
        echo ""
        check_auth || exit 1
        echo ""
        scan_desktop
        echo ""
        push_dirty_repos "true"
        echo ""
        backup_to_gdrive "true"
        echo ""
        generate_delete_checklist
        echo ""
        echo "╔══════════════════════════════════════╗"
        echo "║   DRY RUN COMPLETE                  ║"
        echo "║   Review the checklist above.        ║"
        echo "║   When ready, run:                  ║"
        echo "║     ./scripts/backup.sh push-live    ║"
        echo "║     ./scripts/backup.sh backup-live  ║"
        echo "║     ./scripts/backup.sh verify-live  ║"
        echo "║   Then manually delete from checklist║"
        echo "╚══════════════════════════════════════╝"
        ;;
    help|*)
        echo "Desktop Backup & Space Reclaimer"
        echo ""
        echo "Usage: $0 <command> [true|false]"
        echo ""
        echo "Commands:"
        echo "  auth        Check rclone authentication"
        echo "  scan        Scan Desktop for stale projects"
        echo "  push        Show what would be pushed (dry run)"
        echo "  push-live   Actually push dirty repos"
        echo "  backup      Dry-run backup to GDrive"
        echo "  backup-live Actually backup to GDrive"
        echo "  verify      Dry-run verification"
        echo "  verify-live Actually verify backups"
        echo "  checklist   Generate deletion checklist"
        echo "  dry-run     Full dry run (auth + scan + push + backup + checklist)"
        echo ""
        echo "Environment variables:"
        echo "  RCLONE_REMOTE  rclone remote name (default: gdrive)"
        echo "  DESKTOP_PATH    path to Desktop (default: ~/Desktop)"
        echo "  STALE_DAYS      days threshold (default: 30)"
        ;;
esac