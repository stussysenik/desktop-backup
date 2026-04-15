#!/usr/bin/env bash
set -euo pipefail

# ┌──────────────────────────────────────────────────────────┐
# │  Quick Wins — immediate disk space recovery              │
# └──────────────────────────────────────────────────────────┘

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF="$PROJECT_DIR/config/stale-projects.conf"

[[ -f "$CONF" ]] && source "$CONF"

RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}:"
DESKTOP_PATH="${DESKTOP_PATH:-$HOME/Desktop}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗"
echo -e "║        DISK SPACE RECOVERY — QUICK WINS          ║"
echo -e "╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Current disk:${NC}"
df -h / | tail -1
echo ""

case "${1:-menu}" in
    # ─── No-backup deletions (re-downloadable/caches) ──────

    simulators)
        echo -e "${YELLOW}Deleting unavailable iOS simulators...${NC}"
        xcrun simctl delete unavailable 2>/dev/null || true
        echo -e "${GREEN}✓ Done${NC}"
        echo ""
        echo -e "${YELLOW}Listing remaining simulators with sizes:${NC}"
        for uuid in $(xcrun simctl list devices -j 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); [print(v['UDID']) for runtime in d['devices'].values() for v in runtime]" 2>/dev/null); do
            root="$HOME/Library/Developer/CoreSimulator/Devices/$uuid"
            [[ -d "$root" ]] || continue
            size=$(du -sh "$root" 2>/dev/null | cut -f1)
            name=$(xcrun simctl list devices -j 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); [print(v['name']) for runtime in d['devices'].values() for v in runtime if v['UDID']=='$uuid']" 2>/dev/null)
            echo "  $name | $size | $uuid"
        done 2>/dev/null | sort -t'|' -k2 -rh
        ;;

    homebrew)
        echo -e "${YELLOW}Cleaning Homebrew cache...${NC}"
        brew cleanup --prune=all 2>&1 | tail -3
        echo -e "${GREEN}✓ Done${NC}"
        ;;

    caches)
        echo -e "${YELLOW}Clearing dev caches...${NC}"
        du -sh ~/Library/Caches/Cypress 2>/dev/null && rm -rf ~/Library/Caches/Cypress && echo "  ✓ Cypress cleared"
        du -sh ~/Library/Caches/ms-playwright 2>/dev/null && rm -rf ~/Library/Caches/ms-playwright && echo "  ✓ Playwright cleared"
        du -sh ~/Library/Caches/Homebrew 2>/dev/null && rm -rf ~/Library/Caches/Homebrew && echo "  ✓ Homebrew cache cleared"
        echo -e "${YELLOW}Running npm cache clean...${NC}"
        npm cache clean --force 2>&1 | tail -1
        echo -e "${GREEN}✓ Caches cleared${NC}"
        ;;

    simulators-delete)
        echo -e "${RED}⚠️  Deleting specific simulators by UUID${NC}"
        echo "Usage: $0 simulators-delete <uuid1> <uuid2> ..."
        for uuid in "${@:2}"; do
            echo "  Deleting $uuid..."
            xcrun simctl delete "$uuid" 2>/dev/null && echo "  ✓ Deleted" || echo "  ✗ Failed"
        done
        ;;

    # ─── Backup then delete ─────────────────────────────────

    screenrecordings-backup)
        echo -e "${YELLOW}Backing up ScreenRecordings to GDrive...${NC}"
        echo -e "  Source: ~/Library/ScreenRecordings/"
        echo -e "  Dest:   ${RCLONE_REMOTE}backups/desktop-cleanup/ScreenRecordings/"
        echo ""
        rclone copy \
            ~/Library/ScreenRecordings/ \
            "${RCLONE_REMOTE}backups/desktop-cleanup/ScreenRecordings/" \
            --checksum \
            --transfers 4 \
            --checkers 16 \
            --drive-chunk-size 8M \
            --exclude ".DS_Store" \
            --log-file="$PROJECT_DIR/logs/screenrecordings-rclone.log" \
            --log-level INFO \
            --retries 5 \
            --retries-sleep 15s \
            --progress
        echo -e "${GREEN}✓ ScreenRecordings backed up${NC}"
        echo ""
        echo -e "${YELLOW}Verify with:${NC}"
        echo "  rclone check ~/Library/ScreenRecordings/ \"${RCLONE_REMOTE}backups/desktop-cleanup/ScreenRecordings/\" --checksum"
        ;;

    screenrecordings-delete)
        echo -e "${RED}⚠️  Deleting ScreenRecordings (47GB)${NC}"
        echo -e "${RED}Make sure you verified the GDrive backup first!${NC}"
        echo ""
        read -p "Type 'YES' to confirm deletion: " confirm
        [[ "$confirm" != "YES" ]] && echo "Aborted." && exit 0
        rm -rf ~/Library/ScreenRecordings/*.mov
        echo -e "${GREEN}✓ ScreenRecordings deleted${NC}"
        ;;

    memoryvault-delete)
        echo -e "${RED}⚠️  Deleting MemoryVault data (40GB)${NC}"
        du -sh ~/Library/Application\ Support/com.memoryvault.MemoryVault/ 2>/dev/null
        echo ""
        read -p "Type 'YES' to confirm deletion: " confirm
        [[ "$confirm" != "YES" ]] && echo "Aborted." && exit 0
        rm -rf ~/Library/Application\ Support/com.memoryvault.MemoryVault/
        echo -e "${GREEN}✓ MemoryVault deleted${NC}"
        ;;

    # ─── Combined ───────────────────────────────────────────

    safe)
        echo -e "${BOLD}${GREEN}Running all safe (no-backup-needed) wins...${NC}"
        echo ""
        echo "1/4 iOS Simulators..."
        xcrun simctl delete unavailable 2>/dev/null || true
        echo "  ✓ Unavailable simulators deleted"
        echo ""
        echo "2/4 Homebrew..."
        brew cleanup --prune=all 2>&1 | tail -1
        echo "  ✓ Homebrew cleaned"
        echo ""
        echo "3/4 Caches..."
        rm -rf ~/Library/Caches/Cypress ~/Library/Caches/ms-playwright ~/Library/Caches/Homebrew 2>/dev/null
        npm cache clean --force 2>&1 | tail -1
        echo "  ✓ Caches cleared"
        echo ""
        echo "4/4 Disk status:"
        df -h / | tail -1
        ;;

    # ─── Info ────────────────────────────────────────────────

    scan)
        echo -e "${BOLD}Disk usage breakdown:${NC}"
        echo ""
        echo "=== Top directories ==="
        du -sh ~/*/ 2>/dev/null | sort -rh | head -10
        echo ""
        echo "=== Library breakdown ==="
        du -sh ~/Library/*/ 2>/dev/null | sort -rh | head -10
        echo ""
        echo "=== Top hidden dirs ==="
        du -sh ~/.[!.]* 2>/dev/null | sort -rh | head -10
        echo ""
        echo "Use 'dust ~ --depth 2' for interactive analysis"
        ;;

    menu|*)
        echo -e "${BOLD}Quick Wins Menu:${NC}"
        echo ""
        echo -e "${GREEN}No backup needed (safe to delete):${NC}"
        echo "  $0 simulators        Delete unavailable iOS simulators"
        echo "  $0 homebrew          Clean Homebrew cache"
        echo "  $0 caches            Clear Cypress/Playwright/npm caches"
        echo "  $0 safe              Run all safe wins"
        echo ""
        echo -e "${YELLOW}Backup first, then delete:${NC}"
        echo "  $0 screenrecordings-backup   Backup ScreenRecordings to GDrive"
        echo "  $0 screenrecordings-delete    Delete ScreenRecordings (after verify!)"
        echo "  $0 memoryvault-delete         Delete MemoryVault data (after verify!)"
        echo ""
        echo -e "${CYAN}Info:${NC}"
        echo "  $0 scan             Show disk usage breakdown"
        echo ""
        echo -e "${BOLD}Disk status:${NC}"
        df -h / | tail -1
        ;;
esac