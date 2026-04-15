# Deletion Checklist Example

This is what a generated checklist looks like after running `bash scripts/backup.sh checklist`.

```markdown
# Deletion Checklist - Wed Apr 15 02:53:34 CEST 2026

## ⚠️ REVIEW EACH ITEM BEFORE DELETING
These projects have been backed up to Google Drive.

### Tier 1: Clean git (pushed to GitHub, backed up to GDrive)
- [ ] `_tmp_blender` (36M) → GitHub: https://github.com/stussysenik/blender.git → GDrive: backups/desktop/_tmp_blender/
- [ ] `cmux` (323M) → GitHub: https://github.com/stussysenik/cmux.git → GDrive: backups/desktop/cmux/
- [ ] `tesseract.js` (129M) → GitHub: https://github.com/stussysenik/tesseract.js.git → GDrive: backups/desktop/tesseract.js/

### Tier 2: Dirty git (committed & pushed, backed up to GDrive)
- [ ] `daily` (96M) → GitHub: https://github.com/stussysenik/daily.git → GDrive: backups/desktop/daily/
- [ ] `fulala-live-menu` (345M) → GitHub: https://github.com/stussysenik/fulala-live-menu.git → GDrive: backups/desktop/fulala-live-menu/

### Tier 3: No-git (backed up to GDrive only)
- [ ] `symphony-setup` (8.4G) → GDrive: backups/desktop-no-git/symphony-setup/
- [ ] `cc-config-backup` (6.0M) → GDrive: backups/desktop-no-git/cc-config-backup/

### Estimated space recovery
**~13 GB** recoverable
```

When you're satisfied that backups are verified, manually delete projects you've checked off.