## 2.0.0

**One class for everything SAF.** The new `Saf` class covers pickers,
persisted permissions, file management, recursive `walk()`, byte/stream
read-write with progress callbacks, and local-file bridging — one focused
API, typed exceptions, no `isDir` parameters.

**BREAKING:** the legacy path-based class is renamed `LegacySaf`
(deprecated, removal in 3.0.0). Its behavior is unchanged — existing code
only needs `Saf(` → `LegacySaf(`.

- New: `pickDirectory`/`pickFile`/`pickFiles` with initial URI and
  persistable permissions; `persistedPermissions()` listing.
- New: `list` (single-cursor, fast), `stat`, `exists`, `child`, `mkdirp`,
  `delete`, `rename`, recursive `copyTo`/`moveTo` with progress, `walk()`.
- New: `readFileBytes`/`readFileStream`, `writeFileBytes`, one-call
  `writeFileStream`, `copyToLocalFile`/`pasteLocalFile`, and `copyDirToLocal`
  (bulk-copy a granted folder into your app dir — e.g. WhatsApp `.Statuses`).
- New: sealed `SafException` hierarchy (`permission` / `not_found` /
  `already_exists` / `io`).
- Broad support: Dart >=3.0, Flutter >=3.10, Android minSdk 21.

