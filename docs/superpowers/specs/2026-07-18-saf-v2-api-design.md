# saf 2.0.0 — Single-Class SAF API (Design)

**Date:** 2026-07-18
**Status:** Approved by owner (jvoltci) — pending implementation plan
**Branch:** `saf-v2`

## 1. Goal

Make `saf` the single package a Flutter app needs for Android Storage Access
Framework work, replacing the combination of `saf_stream` (read/write) and
`saf_util` (pickers + file management) with one class — and beat both on
ergonomics, error handling, recursive operations, progress reporting, and SDK
reach.

### Success criteria

- One `Saf` class covers the evidence-backed core of both competitor packages
  (21 methods; see §4).
- Migration from `saf_stream` + `saf_util` is near find-and-replace
  (compatible method names and semantics where kept).
- Legacy 1.x API keeps working, renamed `LegacySaf`, `@Deprecated`.
- `flutter analyze` 0 issues, `dart doc` 0 warnings, `dart format` clean,
  pana 150/150, example APK builds.
- Unit tests cover the full Dart layer against a mocked platform interface.

### Non-goals (deliberate cuts, with evidence)

GitHub code-search hits for competitor method names (Dart, public repos,
2026-07-18) drove the cuts:

| Cut | Hits | Reason |
| --- | --- | --- |
| `startReadCustomFileStream` / `readCustomFileStreamChunk` / `skipCustomFileStreamChunk` / `endReadCustomFileStream` | 4 | ~zero users; `readFileStream(start:)` covers seeking |
| `writeFileUriBytes` | 4 | ~zero users; `writeFileBytes` covers it |
| `readFileSync` / `writeFileSync` | n/a | misleading names (not sync); pure duplicates |
| `openDirectory` / `openFile` / `openFiles` | n/a | URI-only duplicates of the `pick*` family |
| `pickMedia` | n/a | `image_picker` / `photo_manager` own this use case |
| `getFileDescriptor` / `closeFileDescriptor` | n/a | native-codec niche; defer until requested |
| `saveThumbnailToFile` | n/a | file-manager niche; legacy thumbnail API remains |
| Public 3-call write sessions (`startWriteStream`/`writeChunk`/`endWriteStream`) | 37 | capability kept, exposed as one `writeFileStream` call instead |

These cuts are documented in the README ("what we deliberately don't include,
and why") so absence reads as intent, not neglect. Deferred items ship in a
2.1+ only when users file issues asking for them.

## 2. Versioning & compatibility

- **Version 2.0.0** (breaking: the class name `Saf` changes meaning).
- Old path-based class renamed `LegacySaf` with
  `@Deprecated('Use Saf instead. LegacySaf will be removed in 3.0.0')` on the
  class. Internals, method channels, and behavior untouched. 1.x users
  rename `Saf(` → `LegacySaf(` and are done.
- Environment: Dart `>=3.0.0 <4.0.0`, Flutter `>=3.10.0` — deliberately
  broader than competitors (Dart `^3.12`, Flutter `>=3.44`).
- Android `minSdk 21` (same as competitors).
- New dependency: `plugin_platform_interface` (^2.1.0). Nothing else.

## 3. Package layout

```
lib/
  saf.dart                        # exports v2 (Saf, models, exceptions) + deprecated legacy
  src/
    v2/
      saf.dart                    # Saf facade class
      saf_platform_interface.dart # abstract SafPlatform (plugin_platform_interface)
      saf_method_channel.dart     # MethodChannelSaf implementation
      models.dart                 # SafDocumentFile, SafWalkEntry, SafProgress, SafPersistedPermission
      exceptions.dart             # SafException hierarchy + code mapping
    storage_access_framework/     # legacy, untouched except Saf -> LegacySaf rename
android/src/main/kotlin/com/ivehement/saf/
  SafPlugin.kt                    # registers legacy + v2 handlers
  v2/
    SafV2Api.kt                   # MethodChannel handler (channel: com.ivehement.plugins/saf/v2)
    SafV2Streams.kt               # per-session EventChannel management (read/walk/progress)
    SafDocumentsContract.kt       # cursor-based list/stat/walk helpers
    SafErrors.kt                  # exception -> stable error-code mapping
```

The platform-interface pattern lives inside the single package (as
`saf_stream`/`saf_util` do): mockable in tests, federable later without
another breaking change.

## 4. Public API contract

Instance-based facade; all methods delegate to `SafPlatform.instance`.

```dart
final saf = Saf();
```

### Pick & permissions (5)

```dart
Future<SafDocumentFile?> pickDirectory({
  String? initialUri,
  bool writePermission = true,
  bool persistablePermission = true,
});
Future<SafDocumentFile?> pickFile({
  String? initialUri,
  List<String>? mimeTypes,
  bool persistablePermission = false,
});
Future<List<SafDocumentFile>> pickFiles({
  String? initialUri,
  List<String>? mimeTypes,
  bool persistablePermission = false,
});
Future<List<SafPersistedPermission>> persistedPermissions();
Future<void> releasePersistedPermission(String uri);
```

- `pick*` return `null` / empty list when the user cancels — never throw for
  cancellation.
- `persistablePermission: true` takes the persistable grant immediately after
  the pick (`takePersistableUriPermission`).
- `persistedPermissions()` lists all current grants (uri, read, write,
  persistedTime) — neither competitor offers listing.

### Manage (9 + walk)

```dart
Future<List<SafDocumentFile>> list(String dirUri);
Future<SafDocumentFile?> stat(String uri);
Future<bool> exists(String uri);
Future<SafDocumentFile?> child(String dirUri, List<String> names);
Future<SafDocumentFile> mkdirp(String dirUri, List<String> names);
Future<void> delete(String uri);
Future<SafDocumentFile> rename(String uri, String newName);
Future<SafDocumentFile> copyTo(String uri, String destDirUri, {SafProgressCallback? onProgress});
Future<SafDocumentFile> moveTo(String uri, String destDirUri, {SafProgressCallback? onProgress});
Stream<SafWalkEntry> walk(String dirUri);
```

- **No `isDir` parameters anywhere** (competitors require them). Native side
  resolves document type from the URI via `DocumentsContract`.
- `list` executes ONE `ContentResolver.query` over
  `buildChildDocumentsUriUsingTree` with a full projection (id, name, mime,
  size, lastModified) — one cursor per directory instead of
  `DocumentFile.listFiles()`'s N-queries-per-child.
- `stat` returns `null` for a missing document. `exists` is Dart sugar over
  `stat`.
- `child`/`mkdirp` accept multi-segment paths (`['a', 'b', 'c']`).
- `delete` is recursive for directories.
- `copyTo`/`moveTo` handle files and directories (recursive), reporting
  progress per §6. `moveTo` uses `DocumentsContract.moveDocument` when
  provider-supported, else copy+delete fallback.
- `walk` emits a depth-first `Stream<SafWalkEntry>` over an EventChannel;
  directories emitted before their children; cancellation stops native
  iteration.

### Read & write (4)

```dart
Future<Uint8List> readFileBytes(String uri, {int? start, int? count});
Future<Stream<Uint8List>> readFileStream(String uri, {int? start, int bufferSize = 4194304});
Future<SafDocumentFile> writeFileBytes(
  String dirUri, String name, String mime, Uint8List data,
  {bool overwrite = false, bool append = false});
Future<SafDocumentFile> writeFileStream(
  String dirUri, String name, String mime, Stream<List<int>> source,
  {bool overwrite = false, bool append = false});
```

Write APIs return the created/updated file as a `SafDocumentFile`.

- `overwrite: false` (default) matches `saf_stream`: name collisions create
  auto-renamed files ("file (1).txt") per SAF's `createFile` behavior.
  `overwrite: true` truncates the existing document. `append: true` opens in
  append mode ("wa"). `overwrite` and `append` are mutually exclusive
  (ArgumentError).
- `writeFileStream` consumes any Dart `Stream<List<int>>` in one call.
  Internally it drives the native chunked-write session (start/chunk/end over
  the method channel); the session API is **not** public.
- `readFileStream` streams native-read chunks over a per-session
  EventChannel.

### Local-file bridge (2)

```dart
Future<void> copyToLocalFile(String srcUri, String destPath, {SafProgressCallback? onProgress});
Future<SafDocumentFile> pasteLocalFile(
  String srcPath, String destDirUri, String name, String mime,
  {bool overwrite = false, SafProgressCallback? onProgress});
```

## 5. Models

```dart
class SafDocumentFile {
  final String uri;
  final String name;
  final bool isDir;
  final int length;          // bytes; 0 for dirs
  final int lastModified;    // epoch millis
  final String? mimeType;    // competitors don't expose this
}

class SafWalkEntry {
  final SafDocumentFile file;
  final String relativePath; // POSIX-style, relative to walk root, e.g. "sub/dir/file.txt"
}

class SafProgress {
  final int bytesDone;
  final int? totalBytes;     // null when unknown (e.g. recursive dir copy)
  final String currentName;  // name of the file currently being processed
}

typedef SafProgressCallback = void Function(SafProgress progress);

class SafPersistedPermission {
  final String uri;
  final bool read;
  final bool write;
  final int persistedTime;   // epoch millis
}
```

All models are immutable, `const`-constructible, with `==`/`hashCode`/`toString`
and `fromMap`/`toMap` for channel marshalling.

## 6. Progress reporting

`onProgress` callbacks are delivered via the operation's per-session
EventChannel, throttled natively to at most ~10 events/second (and always a
final event at completion). If `onProgress` is null, no event channel is
created (zero overhead).

## 7. Error model

```dart
sealed class SafException implements Exception {
  final String uri;
  final String message;
}
class SafPermissionException extends SafException {}   // code: "permission"
class SafNotFoundException extends SafException {}     // code: "not_found"
class SafAlreadyExistsException extends SafException {}// code: "already_exists"
class SafIoException extends SafException {}           // code: "io" (catch-all)
```

- Kotlin catches all failures and rethrows as `PlatformException` with one of
  the four stable codes + uri + message; the Dart method-channel layer maps
  codes to typed exceptions. Unknown codes map to `SafIoException`.
- Contract: v2 methods **throw** on failure. Only `pick*` (user cancel),
  `stat`, and `child` return `null` as a semantic "not there" result.
- `ArgumentError` for caller mistakes (e.g. `overwrite && append`) — thrown in
  Dart before hitting the channel.

## 8. Kotlin implementation notes

- New handler `SafV2Api.kt` on channel `com.ivehement.plugins/saf/v2`;
  registered alongside legacy handlers in `SafPlugin.kt`. Legacy channels are
  untouched — zero regression risk for `LegacySaf`.
- All I/O on `Dispatchers.IO` coroutines; results posted back on the main
  thread. No `Thread(...)` usage (unlike legacy).
- `list`/`stat`/`walk`/`child` use `ContentResolver.query` +
  `DocumentsContract` (single-cursor pattern). `walk` iterates iteratively
  (explicit stack) to avoid recursion depth issues, emitting batches to the
  event sink.
- Streams: each streaming call creates a unique session id; events flow over
  `com.ivehement.plugins/saf/v2/events/<sessionId>`; sessions are cleaned up
  on completion, error, and Dart-side cancellation.
- Gradle: migrate the plugin to Flutter's built-in Kotlin declaration (drop
  `kotlin-gradle-plugin` buildscript classpath) per current plugin template.

## 9. Testing

- **Unit (Dart):** mock `SafPlatform` / mocked method channel via
  `TestDefaultBinaryMessenger`. Cover: argument marshalling for all 21
  methods; model round-trips; error-code → exception mapping; `writeFileStream`
  chunk pumping (order, backpressure, end-of-stream); `walk` event decoding
  and cancellation; `exists`/`child` sugar; ArgumentError guards; user-cancel
  null contracts. Keep the existing 12 URI-helper tests (legacy).
- **Example app:** kitchen-sink screen exercising pick → list → walk →
  read/write bytes+stream → copy/move with progress → delete, usable as the
  manual on-device test harness.
- **Manual on-device checklist** committed at `docs/testing/manual-checklist.md`
  (picker flows, persisted grants across restart, SD/USB volume, large-file
  stream, progress events). No emulator CI (owner decision).
- **Gates before merge:** analyze 0, test green, format clean, dart doc 0
  warnings, pana 150/150, example `flutter build apk --debug` succeeds.

## 10. Documentation & migration

- README rewritten around v2: quick start, feature table vs
  `saf_stream`+`saf_util`, three migration tables (from saf 1.x / from
  saf_stream / from saf_util), deliberate-cuts section, link to docs site.
- Dartdoc on every public member; docs site auto-deploys via existing Pages
  workflow.
- CHANGELOG 2.0.0 with explicit breaking-change callout and migration snippet.

## 11. Deferred (2.1+, issue-driven)

File descriptors, media picker, new thumbnail API, public low-level session
APIs, `Saf`-object OO layer (rich `SafDocument` instance methods) — each only
when a real issue requests it.

## 12. Risks

- **Recursive copy/move correctness** across providers → mitigated by
  copy+delete fallback and the manual checklist.
- **EventChannel session leaks** → sessions self-clean on error/cancel; unit
  tests assert cleanup calls.
- **Legacy rename fallout** (`Saf` → `LegacySaf`) → major-version signal +
  one-line migration; legacy semantics unchanged.
- **On-device behavior unverifiable in CI** → kitchen-sink example +
  checklist; publish only after owner runs it (same policy as 1.0.5).
