<p align="center">
  <a href="https://jvoltci.github.io/saf/"><img src="https://raw.githubusercontent.com/jvoltci/saf/master/doc/assets/saf-hero.svg" alt="saf — one class for the Android Storage Access Framework" width="100%"></a>
</p>

<p align="center">
 <a href="https://pub.dartlang.org/packages/saf">
    <img alt="Saf" src="https://img.shields.io/pub/v/saf.svg">
  </a>
  <a href="https://github.com/jvoltci/saf/issues"><img src="https://img.shields.io/github/issues/jvoltci/saf">
  </a>
  <img src="https://img.shields.io/github/license/jvoltci/saf">
  <a href="https://github.com/jvoltci/saf/actions/workflows/ci.yml">
    <img alt="CI pipeline status" src="https://github.com/jvoltci/saf/actions/workflows/ci.yml/badge.svg">
  </a>
</p>

# Saf

One package for the Android Storage Access Framework: pickers, persisted
permissions, file management with recursive walk, streamed read/write with
progress, and local-file bridging — all in a single `Saf` class.

## Highlights

- **One class, no ceremony** — pickers, permissions, file management, and I/O all on `Saf`; no `isDir` parameters anywhere.
- **Typed errors** — `SafPermissionException`, `SafNotFoundException`, `SafAlreadyExistsException`, `SafIoException`.
- **Recursive `walk()`** plus recursive `copyTo` / `moveTo` with progress callbacks.
- **Streaming I/O** — backpressured `readFileStream` and one-call `writeFileStream` for large files.
- **Persisted permissions** — grant once, reuse across restarts; list them with `persistedPermissions()`.
- **Hidden folders** — read dotfile folders (e.g. WhatsApp `.Statuses`) and pull them into your app dir with `copyDirToLocal`.
- **Broad support** — Dart ≥ 3.0, Flutter ≥ 3.10, Android minSdk 21.

## Quick start

```dart
import 'package:saf/saf.dart';

final saf = Saf();

// 1. Ask once — the grant persists across restarts.
final dir = await saf.pickDirectory();
if (dir == null) return; // user cancelled

// Later launches: reuse the grant instead of prompting again.
final grants = await saf.persistedPermissions();

// 2. Manage files.
final files = await saf.list(dir.uri);
final report = await saf.mkdirp(dir.uri, ['reports', '2026']);
await for (final entry in saf.walk(dir.uri)) {
  print(entry.relativePath);
}

// 3. Read and write.
final doc = await saf.writeFileBytes(
    report.uri, 'summary.txt', 'text/plain', utf8.encode('hi') as Uint8List);
final bytes = await saf.readFileBytes(doc.uri);
final stream = await saf.readFileStream(doc.uri); // large files

// 4. Bridge to real file paths when another API needs one.
await saf.copyToLocalFile(doc.uri, '${cacheDir.path}/summary.txt',
    onProgress: (p) => print('${p.bytesDone}/${p.totalBytes}'));
```

Errors are typed — catch what you care about:

```dart
try {
  await saf.delete(uri);
} on SafPermissionException {
  // re-pick the directory
} on SafNotFoundException {
  // already gone
}
```

## Migrating

### From saf 1.x

The old path-based class still works as `LegacySaf` (deprecated, removed in
3.0.0): rename `Saf(` → `LegacySaf(` and migrate at your own pace. The new API
is URI-based — start from `pickDirectory()` and store URIs, not paths.

## Scope

`saf` keeps a focused, purposeful API. Intentionally out of scope for now:

- **Media picking** — use `image_picker` / `photo_manager`, which specialize in it.
- **Raw file descriptors and thumbnails** — niche; open an issue if you need them and they can land in a 2.1+.

## Architecture

`saf` is a single package with a mockable platform-interface layer, a thin Dart
facade, and one coroutine-based Kotlin handler on a dedicated channel — the
legacy 1.x channels are left untouched.

```mermaid
flowchart LR
  A["Your Flutter app"] --> B["Saf<br/>(facade)"]
  B --> C["SafPlatform<br/>platform interface"]
  C --> D["MethodChannelSaf<br/>saf/v2 channel"]
  D <--> E["SafV2Api · Kotlin<br/>coroutines · off-main-thread"]
  E --> F["DocumentsContract<br/>ContentResolver"]
  F --> G["Android Storage<br/>Access Framework"]
```

A typical grant-then-read flow — one permission prompt, reused across restarts:

```mermaid
sequenceDiagram
  participant App
  participant Saf
  participant OS as Android SAF
  App->>Saf: pickDirectory()
  Saf->>OS: ACTION_OPEN_DOCUMENT_TREE
  OS-->>Saf: tree URI (+ persisted grant)
  Saf-->>App: SafDocumentFile
  App->>Saf: list(dir.uri)
  Saf-->>App: List&lt;SafDocumentFile&gt;
  App->>Saf: readFileStream(file.uri)
  Saf-->>App: Stream&lt;Uint8List&gt;
```

## Documentation

- **[Documentation site](https://jvoltci.github.io/saf/)** — full API reference.
- **[Saf class reference](https://jvoltci.github.io/saf/saf/Saf-class.html)** — every method.

## Getting Started with Flutter

For help getting started with Flutter, view the online
[documentation](https://docs.flutter.dev/).

---

<p align="center">
  <sub>Built &amp; maintained by <a href="https://github.com/jvoltci"><b>jvoltci</b></a> &nbsp;·&nbsp; <a href="https://jvoltci.github.io/saf/">Docs</a> &nbsp;·&nbsp; <a href="https://github.com/jvoltci/saf/issues">Issues</a> &nbsp;·&nbsp; <a href="https://pub.dev/packages/saf">pub.dev</a> &nbsp;·&nbsp; MIT License</sub>
</p>
<p align="center"><sub>⭐ If <code>saf</code> saves you time, star the repo — it helps other Flutter devs find it.</sub></p>

