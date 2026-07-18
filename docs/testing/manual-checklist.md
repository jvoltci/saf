# Manual on-device checklist (saf 2.x)

Run the example app (`cd example && flutter run`) on a physical device or
emulator before each release. Check every box.

## Pickers & permissions
- [ ] Pick dir → picker opens, returns directory name in header
- [ ] Cancel picker → "picker cancelled", no crash
- [ ] Kill and relaunch app → Restore permission → directory restored WITHOUT
      a new prompt (regression: 1.x re-prompted every launch)
- [ ] Pick an SD-card/USB volume if available → list works (regression: 1.x
      RangeError, issue #41)

## Files
- [ ] Write → both demo files appear in the list with sizes
- [ ] Read → contents echo back; stream chunk count > 1
- [ ] Walk → descendants stream with relative paths
- [ ] Copy+progress → progress bar animates; file lands in saf-backups/
- [ ] Clean up → demo files disappear
- [ ] Write twice without cleanup (overwrite: true path) → no duplicate
      "(1)" files

## Big-file sanity (manual, via a file manager)
- [ ] Put a >100 MB file in the granted directory; Read (stream) completes
      without OOM
- [ ] Copy+progress on that file shows steadily increasing progress

## Legacy
- [ ] A 1.x consumer app (or quick snippet using LegacySaf) still resolves
      and runs against 2.0.0
