# Recipes

Copy-paste snippets for every `Saf` operation. All methods live on one class:

```dart
final saf = Saf();
```

!!! warning "Don't use `dart:io` on a SAF folder"
    A SAF grant gives access **only through this API**, not the filesystem — a
    `File(path).writeAsString(...)` / `readAsBytes()` from `dart:io` will fail
    on a granted directory. This is the single most common SAF mistake. Use the
    `Saf` methods below for every create / read / write / delete.

## Pick & permissions

```dart
// Directory (persistable by default)
final dir = await saf.pickDirectory(initialUri: null, writePermission: true);

// A single file / multiple files
final file  = await saf.pickFile(mimeTypes: ['application/pdf']);
final files = await saf.pickFiles(mimeTypes: ['image/*']);

// List and release persisted grants
final grants = await saf.persistedPermissions(); // List<SafPersistedPermission>
await saf.releasePersistedPermission(grants.first.uri);
```

`pick*` return `null` / an empty list when the user cancels — they never throw
for cancellation.

## Browse a directory

```dart
final children = await saf.list(dir.uri);         // one fast cursor query
final info     = await saf.stat(fileUri);         // null if missing
final there    = await saf.exists(fileUri);
final nested   = await saf.child(dir.uri, ['reports', '2026', 'q1.csv']);

// Recursive, depth-first, streamed
await for (final entry in saf.walk(dir.uri)) {
  print(entry.relativePath); // e.g. reports/2026/q1.csv
}
```

## Create, rename, delete

```dart
final reports = await saf.mkdirp(dir.uri, ['reports', '2026']); // nested, idempotent
final renamed = await saf.rename(fileUri, 'q1-final.csv');
await saf.delete(dirUri); // recursive for directories
```

## Read

=== "Bytes"

    ```dart
    final all   = await saf.readFileBytes(uri);
    final range = await saf.readFileBytes(uri, start: 1024, count: 512);
    ```

=== "Stream (large files)"

    ```dart
    final stream = await saf.readFileStream(uri, bufferSize: 1 << 20);
    await for (final chunk in stream) {
      // handle each Uint8List chunk
    }
    ```

## Write

=== "Bytes"

    ```dart
    final doc = await saf.writeFileBytes(
      dir.uri, 'data.bin', 'application/octet-stream', bytes,
      overwrite: true, // or append: true
    );
    ```

=== "Stream (one call)"

    ```dart
    final doc = await saf.writeFileStream(
      dir.uri, 'big.log', 'text/plain', sourceStream,
    );
    ```

`overwrite` and `append` are mutually exclusive. With neither, a name clash
creates an auto-renamed file (SAF behavior).

## Copy & move with progress

```dart
final copied = await saf.copyTo(fileUri, destDir.uri, onProgress: (p) {
  final pct = p.totalBytes == null ? null : p.bytesDone / p.totalBytes!;
  print('${p.currentName}: ${pct == null ? '?' : (pct * 100).toStringAsFixed(0) + '%'}');
});

await saf.moveTo(fileUri, destDir.uri); // recursive for directories
```

`totalBytes` is `null` for directory copies (grand total unknown up front).

## Bridge to local files

Hand a SAF document to APIs that need a real filesystem path:

```dart
await saf.copyToLocalFile(srcUri, '${cacheDir.path}/video.mp4',
    onProgress: (p) => print('${p.bytesDone}/${p.totalBytes}'));

final doc = await saf.pasteLocalFile(
    '${cacheDir.path}/export.zip', dir.uri, 'export.zip', 'application/zip');
```

## Hidden folders & WhatsApp statuses

Unlike MediaStore, SAF **lists dotfiles**, so hidden folders like WhatsApp's
`Android/media/com.whatsapp/WhatsApp/Media/.Statuses` work. Grant the folder,
list it (hidden files included), and pull each file into your app's own
directory so it can be saved, shared, or opened with `dart:io`:

```dart
final dir = await saf.pickDirectory(); // navigate to .Statuses and grant
if (dir == null) return;

final appDir = await getExternalStorageDirectory(); // path_provider
// One call — copies every file in the granted folder into your app dir,
// where they can be opened/saved/shared with dart:io.
final saved = await saf.copyDirToLocal(dir.uri, appDir!.path);
print('pulled ${saved.length} files out of the hidden folder');
```

`copyDirToLocal` is built on `list` + `copyToLocalFile`; drop to those two if
you need per-file control or recursion. `Android/media/…` is grantable on
Android 11+ (unlike `Android/data` and `Android/obb`, which the picker blocks).
