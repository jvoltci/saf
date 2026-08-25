## 2.1.2

- Fix: build failure on AGP 9 with `android.builtInKotlin=false` (#45). 2.1.1
  inferred built-in Kotlin from the AGP major version alone, so projects using
  Flutter's documented opt-out got neither built-in Kotlin nor KGP and failed
  with `Could not find method kotlin()`. The guard now mirrors Flutter's own
  `isBuiltInKotlinEnabled` rule and reads the property.
- Fix: no more spurious "plugins that apply Kotlin Gradle Plugin (KGP): saf"
  warning on AGP 9. Flutter's check regex-scans the build script and cannot see
  the conditional, so KGP is now applied via `pluginManager.apply` instead.

## 2.1.1

- Android: compatible with AGP 9's built-in Kotlin (#45). The Kotlin Gradle
  Plugin is now applied only when building with AGP < 9, so the plugin builds
  on both current Flutter versions and the upcoming built-in-Kotlin default.
  No Dart API changes.
- Fix: `rename` no longer reports success when the provider rejected the rename
  (a null `renameDocument` result means failure, not "unchanged").
- Fix: `releasePersistedPermission` is idempotent again — releasing an already
  released or never-persisted URI no longer throws (regression in 2.1.0).
- Fix: `thumbnail` returns `null` instead of empty bytes when JPEG encoding
  fails, and rejects non-positive sizes or out-of-range quality.
- Docs: `closeFileDescriptor` is only safe for descriptors this plugin still
  owns (fd numbers are reused); an aborted `overwrite`/`append` write can leave
  the pre-existing document with partial content.
- Legacy `LegacySaf` fixes: `DocumentFile.canRead` no longer returns write
  status; `getFilesUri` sent the wrong argument key and always returned null;
  `createFileAsString` now writes UTF-8 instead of truncated UTF-16;
  `singleCache` never ran at all; `copy` and `getDocumentThumbnail` never
  completed their futures (thumbnail also crashed on an Int/double mismatch);
  cache/sync results are posted on the main thread as MethodChannel requires;
  `listFiles` no longer walks the whole subtree when `mimeType` is requested and
  now closes its stream; the picker works again after a configuration change.

## 2.1.0

- New: `openFileDescriptor` / `closeFileDescriptor` open a live file descriptor
  for a SAF document and expose its `/proc/self/fd/<fd>` path for native or
  path-based APIs; `withFileDescriptor` opens, runs your action, and always
  closes in a `finally`.
- New: `thumbnail(uri, width, height, quality)` returns provider-generated JPEG
  bytes (`Uint8List?`), or `null` when the provider has none.
- New: `SafOpenFd` model (`fd`, `path`).
- Example: a mini file-manager showcasing the new descriptor and thumbnail APIs.
- Fix: an aborted `writeFileStream` no longer deletes a pre-existing target
  file (`overwrite`/`append`) — only documents created by that write are
  cleaned up.
- Fix: `copyTo`/`moveTo` now reject copying a directory into itself or its own
  subtree instead of recursing until storage fills.
- Fix: `releasePersistedPermission` now releases directory grants taken by
  `pickDirectory` (URI-form mismatch made it a silent no-op).
- Fix: picker failures (e.g. no SAF handler on some Android TV/Go builds) no
  longer leave the plugin stuck rejecting all future picks.
- Fix: `openReadSession` no longer leaks the stream when seeking fails.
- Deprecated `FileTypes` (legacy 1.x, removed in 3.0.0); internal
  `mapPlatformException` is no longer exported.

## 2.0.1

* Documentation and presentation polish. No API or behavior changes.

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

