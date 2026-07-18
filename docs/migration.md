# Migrate

## From saf 1.x

The old path-based class still ships as `LegacySaf` (deprecated, removed in
3.0.0). Migrate at your own pace:

```dart
// before
final saf = Saf('/storage/emulated/0/MyApp');
// after — unchanged 1.x behavior
final saf = LegacySaf('/storage/emulated/0/MyApp');
```

The new API is **URI-based**, not path-based. Start from `pickDirectory()` and
store the returned URIs (not filesystem paths):

```dart
final saf = Saf();
final dir = await saf.pickDirectory();
if (dir != null) {
  final files = await saf.list(dir.uri);
}
```

### What's better in 2.x

- **No `isDir` parameters** — document type is resolved from the URI.
- **Typed exceptions** instead of raw `PlatformException`.
- **One-call `writeFileStream`** for large writes.
- **Recursive `walk()`** and **progress callbacks** on copy/move — new
  capabilities.

## Coming from another SAF package?

`saf` 2.x covers the full Storage Access Framework surface in one package —
pickers, permissions, file management, streaming read/write, recursive walk,
and progress. The API is URI-based and uses conventional method names
(`readFileBytes`, `writeFileBytes`, `list`, `stat`, `mkdirp`, `copyTo`, …), so
moving over is largely mechanical. See the [Recipes](guide.md) for the
equivalent of any operation.
