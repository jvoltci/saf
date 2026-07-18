# FAQ

## Why is `saf` Android-only?

The Storage Access Framework is an Android API. There is no cross-platform
equivalent, so a faithful SAF binding is Android-only by nature. On other
platforms use `dart:io` / `path_provider` / `file_picker`.

## Do I still need `permission_handler`?

No. `saf` 2.x does not depend on it, and SAF itself needs no runtime storage
permission — access is granted through the system picker. Add `permission_handler`
directly only if the rest of your app uses it.

## How do I avoid re-prompting on every launch?

Grants are persisted by default. On startup, check `persistedPermissions()` and
reuse a grant instead of calling `pickDirectory()` again:

```dart
final grants = await saf.persistedPermissions();
if (grants.isNotEmpty) {
  final dir = await saf.stat(grants.first.uri);
}
```

## `isDynamic: false` used to break — is that fixed?

That was the old `LegacySaf` behavior. The new `Saf` API is URI-based and does
not have `isDynamic`; it adopts whatever directory the user grants and reuses it
across restarts.

## Can I read very large files?

Yes — use `readFileStream` and process chunks as they arrive.

!!! warning "Backpressure"
    `readFileStream` uses Flutter's `EventChannel`, which does not apply
    backpressure. If your consumer is much slower than disk, lower `bufferSize`
    to cap peak memory. (This limitation is shared with other SAF streaming
    packages.)

## Does overwrite always truncate?

`saf` opens overwrites in truncate mode (`"wt"`), which conforming providers
honor. A few third-party DocumentsProviders ignore the truncate flag; if you
overwrite with shorter content on such a provider, delete first to be safe.

## Where's the full API reference?

The generated dartdoc lives at
[jvoltci.github.io/saf/api](https://jvoltci.github.io/saf/api/).
