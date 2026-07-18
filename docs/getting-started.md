# Install & first run

## 1. Add the dependency

```yaml
dependencies:
  saf: ^2.0.0
```

```bash
flutter pub get
```

`saf` is Android-only and needs no runtime permissions — SAF grants are handled
through the system picker.

!!! note "Minimum versions"
    Dart ≥ 3.0, Flutter ≥ 3.10, Android `minSdk 21`.

## 2. Grant a directory

```dart
import 'package:saf/saf.dart';

final saf = Saf();

Future<void> pick() async {
  final dir = await saf.pickDirectory();   // opens the system folder picker
  if (dir == null) {
    // user cancelled
    return;
  }
  print('granted: ${dir.uri}');
}
```

The grant is **persisted** by default. On later launches, reuse it instead of
prompting again:

```dart
final grants = await saf.persistedPermissions();
if (grants.isNotEmpty) {
  final dir = await saf.stat(grants.first.uri);
  // use dir without showing the picker
}
```

## 3. Read and write

```dart
// write
final doc = await saf.writeFileBytes(
  dir.uri, 'notes.txt', 'text/plain',
  utf8.encode('Hello from saf 2.0!') as Uint8List,
);

// read
final bytes = await saf.readFileBytes(doc.uri);
print(utf8.decode(bytes)); // Hello from saf 2.0!
```

## 4. Handle errors

Every operation throws a typed [`SafException`](https://jvoltci.github.io/saf/api/):

```dart
try {
  await saf.delete(uri);
} on SafPermissionException {
  // grant was revoked — re-pick the directory
} on SafNotFoundException {
  // already gone
}
```

Next: **[Recipes](guide.md)** for every operation, or the full
**[API reference](https://jvoltci.github.io/saf/api/)**.
