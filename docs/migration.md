# Migrate

## From saf 1.x

The old path-based class is still shipped as `LegacySaf` (deprecated, removed in
3.0.0). Rename and migrate at your own pace:

```dart
// before
final saf = Saf('/storage/emulated/0/MyApp');
// after (keeps 1.x behavior)
final saf = LegacySaf('/storage/emulated/0/MyApp');
```

The **new** API is URI-based, not path-based. Start from `pickDirectory()` and
store the returned URIs (not filesystem paths):

```dart
final saf = Saf();
final dir = await saf.pickDirectory();
final files = await saf.list(dir!.uri);
```

## From saf_stream / saf_util

`saf` 2.x replaces both packages. Method names were kept where sensible, so it's
close to find-and-replace:

| saf_stream / saf_util | saf 2.x |
| --- | --- |
| `SafStream().readFileBytes(uri)` | `Saf().readFileBytes(uri)` |
| `SafStream().readFileStream(uri)` | `Saf().readFileStream(uri)` |
| `SafStream().writeFileBytes(dir, name, mime, data)` | `Saf().writeFileBytes(dir, name, mime, data)` |
| `startWriteStream` / `writeChunk` / `endWriteStream` | one call: `Saf().writeFileStream(dir, name, mime, stream)` |
| `SafStream().copyToLocalFile(src, dest)` | `Saf().copyToLocalFile(src, dest)` |
| `SafStream().pasteLocalFile(src, dir, name, mime)` | `Saf().pasteLocalFile(src, dir, name, mime)` |
| `SafUtil().pickDirectory(...)` | `Saf().pickDirectory(...)` |
| `SafUtil().pickFile()` / `pickFiles()` | `Saf().pickFile()` / `pickFiles()` |
| `SafUtil().list(uri)` | `Saf().list(uri)` |
| `SafUtil().stat(uri, isDir)` | `Saf().stat(uri)` — no `isDir` |
| `SafUtil().exists(uri, isDir)` | `Saf().exists(uri)` |
| `SafUtil().mkdirp(uri, names)` | `Saf().mkdirp(uri, names)` |
| `SafUtil().child(uri, names)` | `Saf().child(uri, names)` |
| `SafUtil().rename(uri, isDir, newName)` | `Saf().rename(uri, newName)` |
| `SafUtil().copyTo(uri, isDir, dest)` | `Saf().copyTo(uri, dest)` — recursive + progress |
| `SafUtil().moveTo(uri, isDir, parent, dest)` | `Saf().moveTo(uri, dest)` |
| `SafUtil().hasPersistedPermission(uri)` | check `Saf().persistedPermissions()` |
| `SafUtil().releasePersistedPermission(uri)` | `Saf().releasePersistedPermission(uri)` |

### What changes for the better

- **No `isDir` parameters** — the native side resolves document type from the URI.
- **Typed exceptions** instead of raw `PlatformException`.
- **One-call `writeFileStream`** instead of the three-call session dance.
- **Recursive `walk()`** and **progress callbacks** on copy/move — new capabilities.
