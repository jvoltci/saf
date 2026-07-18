# saf 2.0.0 Single-Class API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `saf` 2.0.0 — one `Saf` class with 21 evidence-backed methods replacing `saf_stream` + `saf_util`, with typed exceptions, recursive walk, progress reporting, and the legacy API preserved as deprecated `LegacySaf`.

**Architecture:** Dart facade → `SafPlatform` (plugin_platform_interface) → `MethodChannelSaf` on a NEW channel `com.ivehement.plugins/saf/v2` → new Kotlin `SafV2Api` (coroutines, single-cursor DocumentsContract queries, per-session EventChannels for streams/progress). Legacy channels and Kotlin code untouched.

**Tech Stack:** Dart ≥3.0 (sealed classes), Flutter ≥3.10, `plugin_platform_interface ^2.1.8`, Kotlin 2.1 + kotlinx-coroutines, minSdk 21.

**Spec:** `docs/superpowers/specs/2026-07-18-saf-v2-api-design.md` (approved). Work happens on branch `saf-v2`.

**Verification limits:** Dart layer is fully unit-testable. Kotlin compiles via `flutter build apk --debug` in `example/` but SAF behavior needs the manual on-device checklist (Task 17) — do not claim device behavior verified.

---

## Channel protocol (reference for all tasks)

Method channel: `com.ivehement.plugins/saf/v2`. Event channels: `com.ivehement.plugins/saf/v2/events/<session>`.

| Method | Args | Returns |
| --- | --- | --- |
| `pickDirectory` | `initialUri?`, `writePermission`, `persistablePermission` | doc map or null (cancel) |
| `pickFile` | `initialUri?`, `mimeTypes?`, `persistablePermission` | doc map or null |
| `pickFiles` | same as pickFile | `List<doc map>` (empty = cancel) |
| `persistedPermissions` | – | `List<{uri,read,write,persistedTime}>` |
| `releasePersistedPermission` | `uri` | null |
| `list` | `dirUri` | `List<doc map>` |
| `stat` | `uri` | doc map or null |
| `child` | `dirUri`, `names: List<String>` | doc map or null |
| `mkdirp` | `dirUri`, `names` | doc map |
| `delete` | `uri` | null |
| `rename` | `uri`, `newName` | doc map |
| `copyTo` / `moveTo` | `uri`, `destDirUri`, `withProgress` | doc map, or session-id string when `withProgress` |
| `copyToLocalFile` | `srcUri`, `destPath`, `withProgress` | null or session-id |
| `pasteLocalFile` | `srcPath`, `destDirUri`, `name`, `mime`, `overwrite`, `withProgress` | doc map or session-id |
| `readFileBytes` | `uri`, `start?`, `count?` | `Uint8List` |
| `readFileStream` | `uri`, `start?`, `bufferSize` | session-id string |
| `startWalk` | `dirUri` | session-id string |
| `writeFileBytes` | `dirUri`,`name`,`mime`,`data`,`overwrite`,`append` | doc map |
| `startWriteStream` | `dirUri`,`name`,`mime`,`overwrite`,`append` | session-id string |
| `writeChunk` | `session`, `data` | null |
| `endWriteStream` | `session` | doc map |
| `abortWriteStream` | `session` | null |

doc map = `{uri: String, name: String, isDir: bool, length: int, lastModified: int, mimeType: String?}`.

Event payloads: read stream → `Uint8List` chunks then endOfStream. walk → `{file: docMap, relativePath: String}`. progress ops → `{type:'progress', bytesDone: int, totalBytes: int?, currentName: String}` then `{type:'done', file: docMap?}` then endOfStream. Errors: `sink.error(code, message, {uri})` with codes `permission|not_found|already_exists|io`.

---

### Task 1: v2 models

**Files:**
- Create: `lib/src/v2/models.dart`
- Test: `test/v2/models_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/v2/models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/models.dart';

void main() {
  const doc = SafDocumentFile(
    uri: 'content://x/tree/p/document/p%3Aa.txt',
    name: 'a.txt',
    isDir: false,
    length: 12,
    lastModified: 1700000000000,
    mimeType: 'text/plain',
  );

  group('SafDocumentFile', () {
    test('round-trips through map', () {
      expect(SafDocumentFile.fromMap(doc.toMap()), doc);
    });

    test('fromMap tolerates dynamic maps and missing mimeType', () {
      final m = <dynamic, dynamic>{
        'uri': 'u', 'name': 'n', 'isDir': true,
        'length': 0, 'lastModified': 0, 'mimeType': null,
      };
      final d = SafDocumentFile.fromMap(m);
      expect(d.isDir, isTrue);
      expect(d.mimeType, isNull);
    });

    test('equality and hashCode', () {
      expect(doc, SafDocumentFile.fromMap(doc.toMap()));
      expect(doc.hashCode, SafDocumentFile.fromMap(doc.toMap()).hashCode);
    });
  });

  test('SafPersistedPermission round-trips', () {
    const p = SafPersistedPermission(
        uri: 'u', read: true, write: false, persistedTime: 5);
    expect(SafPersistedPermission.fromMap(p.toMap()), p);
  });

  test('SafProgress holds values, totalBytes nullable', () {
    const pr = SafProgress(bytesDone: 3, totalBytes: null, currentName: 'f');
    expect(pr.bytesDone, 3);
    expect(pr.totalBytes, isNull);
  });

  test('SafWalkEntry holds file and relativePath', () {
    const e = SafWalkEntry(file: doc, relativePath: 'sub/a.txt');
    expect(e.file.name, 'a.txt');
    expect(e.relativePath, 'sub/a.txt');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/v2/models_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'saf/src/v2/models.dart'` (file missing)

- [ ] **Step 3: Write the models**

```dart
// lib/src/v2/models.dart

/// Metadata for a SAF document (file or directory).
class SafDocumentFile {
  /// The document URI (`content://...`).
  final String uri;

  /// Display name.
  final String name;

  /// Whether this document is a directory.
  final bool isDir;

  /// Size in bytes. `0` for directories.
  final int length;

  /// Last-modified time in milliseconds since epoch.
  final int lastModified;

  /// MIME type, if the provider reports one. `null` for directories.
  final String? mimeType;

  const SafDocumentFile({
    required this.uri,
    required this.name,
    required this.isDir,
    required this.length,
    required this.lastModified,
    this.mimeType,
  });

  factory SafDocumentFile.fromMap(Map<dynamic, dynamic> map) {
    return SafDocumentFile(
      uri: map['uri'] as String,
      name: map['name'] as String,
      isDir: map['isDir'] as bool,
      length: (map['length'] as num).toInt(),
      lastModified: (map['lastModified'] as num).toInt(),
      mimeType: map['mimeType'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'uri': uri,
        'name': name,
        'isDir': isDir,
        'length': length,
        'lastModified': lastModified,
        'mimeType': mimeType,
      };

  @override
  bool operator ==(Object other) =>
      other is SafDocumentFile &&
      other.uri == uri &&
      other.name == name &&
      other.isDir == isDir &&
      other.length == length &&
      other.lastModified == lastModified &&
      other.mimeType == mimeType;

  @override
  int get hashCode =>
      Object.hash(uri, name, isDir, length, lastModified, mimeType);

  @override
  String toString() =>
      'SafDocumentFile(uri: $uri, name: $name, isDir: $isDir, '
      'length: $length, lastModified: $lastModified, mimeType: $mimeType)';
}

/// A persisted URI permission grant held by the app.
class SafPersistedPermission {
  final String uri;
  final bool read;
  final bool write;

  /// When the permission was persisted, in milliseconds since epoch.
  final int persistedTime;

  const SafPersistedPermission({
    required this.uri,
    required this.read,
    required this.write,
    required this.persistedTime,
  });

  factory SafPersistedPermission.fromMap(Map<dynamic, dynamic> map) {
    return SafPersistedPermission(
      uri: map['uri'] as String,
      read: map['read'] as bool,
      write: map['write'] as bool,
      persistedTime: (map['persistedTime'] as num).toInt(),
    );
  }

  Map<String, dynamic> toMap() =>
      {'uri': uri, 'read': read, 'write': write, 'persistedTime': persistedTime};

  @override
  bool operator ==(Object other) =>
      other is SafPersistedPermission &&
      other.uri == uri &&
      other.read == read &&
      other.write == write &&
      other.persistedTime == persistedTime;

  @override
  int get hashCode => Object.hash(uri, read, write, persistedTime);

  @override
  String toString() =>
      'SafPersistedPermission(uri: $uri, read: $read, write: $write)';
}

/// Progress of a long-running copy/move/paste operation.
class SafProgress {
  /// Bytes processed so far.
  final int bytesDone;

  /// Total bytes, or `null` when unknown (e.g. recursive directory copy).
  final int? totalBytes;

  /// Name of the file currently being processed.
  final String currentName;

  const SafProgress({
    required this.bytesDone,
    required this.totalBytes,
    required this.currentName,
  });

  @override
  String toString() =>
      'SafProgress($bytesDone/${totalBytes ?? '?'} bytes, $currentName)';
}

/// Callback for [SafProgress] updates.
typedef SafProgressCallback = void Function(SafProgress progress);

/// One entry emitted by `Saf.walk`.
class SafWalkEntry {
  final SafDocumentFile file;

  /// POSIX-style path relative to the walk root, e.g. `sub/dir/file.txt`.
  final String relativePath;

  const SafWalkEntry({required this.file, required this.relativePath});

  @override
  String toString() => 'SafWalkEntry($relativePath)';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/v2/models_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/src/v2/models.dart test/v2/models_test.dart
git commit -m "feat(v2): document, permission, progress, walk models"
```

---

### Task 2: v2 exceptions + PlatformException mapping

**Files:**
- Create: `lib/src/v2/exceptions.dart`
- Test: `test/v2/exceptions_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/v2/exceptions_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/exceptions.dart';

void main() {
  PlatformException pe(String code) => PlatformException(
      code: code, message: 'boom', details: {'uri': 'content://x'});

  test('maps stable codes to typed exceptions', () {
    expect(mapPlatformException(pe('permission')),
        isA<SafPermissionException>());
    expect(mapPlatformException(pe('not_found')),
        isA<SafNotFoundException>());
    expect(mapPlatformException(pe('already_exists')),
        isA<SafAlreadyExistsException>());
    expect(mapPlatformException(pe('io')), isA<SafIoException>());
  });

  test('unknown codes map to SafIoException', () {
    expect(mapPlatformException(pe('weird_code')), isA<SafIoException>());
  });

  test('carries uri and message', () {
    final e = mapPlatformException(pe('not_found'));
    expect(e.uri, 'content://x');
    expect(e.message, 'boom');
    expect(e.toString(), contains('content://x'));
  });

  test('tolerates missing details', () {
    final e = mapPlatformException(
        PlatformException(code: 'io', message: null, details: null));
    expect(e.uri, '');
    expect(e.message, 'io');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/v2/exceptions_test.dart`
Expected: FAIL — package path unresolvable

- [ ] **Step 3: Write the exceptions**

```dart
// lib/src/v2/exceptions.dart
import 'package:flutter/services.dart';

/// Base class for all failures thrown by the v2 `Saf` API.
sealed class SafException implements Exception {
  /// URI of the document involved, when known ('' otherwise).
  final String uri;

  /// Human-readable failure description.
  final String message;

  const SafException(this.uri, this.message);

  @override
  String toString() => '$runtimeType($uri): $message';
}

/// The app lacks (persisted) permission for the target URI.
class SafPermissionException extends SafException {
  const SafPermissionException(super.uri, super.message);
}

/// The target document does not exist.
class SafNotFoundException extends SafException {
  const SafNotFoundException(super.uri, super.message);
}

/// A document with the same name already exists.
class SafAlreadyExistsException extends SafException {
  const SafAlreadyExistsException(super.uri, super.message);
}

/// Any other I/O failure.
class SafIoException extends SafException {
  const SafIoException(super.uri, super.message);
}

/// Converts a [PlatformException] raised by the native side into the
/// typed [SafException] hierarchy.
SafException mapPlatformException(PlatformException e) {
  final details = e.details;
  final uri =
      (details is Map ? details['uri'] : null)?.toString() ?? '';
  final message = e.message ?? e.code;
  return switch (e.code) {
    'permission' => SafPermissionException(uri, message),
    'not_found' => SafNotFoundException(uri, message),
    'already_exists' => SafAlreadyExistsException(uri, message),
    _ => SafIoException(uri, message),
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/v2/exceptions_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/src/v2/exceptions.dart test/v2/exceptions_test.dart
git commit -m "feat(v2): typed SafException hierarchy with code mapping"
```

---

### Task 3: platform interface + method-channel scaffold + pubspec deps

**Files:**
- Create: `lib/src/v2/saf_platform_interface.dart`
- Create: `lib/src/v2/saf_method_channel.dart` (scaffold: channel + `_invoke` only; methods filled in Tasks 4–9)
- Modify: `pubspec.yaml` (add `plugin_platform_interface`)
- Test: `test/v2/platform_interface_test.dart`

- [ ] **Step 1: Add dependency to `pubspec.yaml`**

In the `dependencies:` block add:

```yaml
dependencies:
  flutter:
    sdk: flutter
  plugin_platform_interface: ^2.1.8
```

Run: `flutter pub get` — Expected: `Got dependencies!`

- [ ] **Step 2: Write the failing test**

```dart
// test/v2/platform_interface_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/saf_method_channel.dart';
import 'package:saf/src/v2/saf_platform_interface.dart';

void main() {
  test('default instance is MethodChannelSaf', () {
    expect(SafPlatform.instance, isA<MethodChannelSaf>());
  });

  test('method channel name is the v2 channel', () {
    final p = SafPlatform.instance as MethodChannelSaf;
    expect(p.methodChannel.name, 'com.ivehement.plugins/saf/v2');
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/v2/platform_interface_test.dart`
Expected: FAIL — files missing

- [ ] **Step 4: Write the platform interface**

```dart
// lib/src/v2/saf_platform_interface.dart
import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models.dart';
import 'saf_method_channel.dart';

/// The interface that platform implementations of `saf` v2 must implement.
abstract class SafPlatform extends PlatformInterface {
  SafPlatform() : super(token: _token);

  static final Object _token = Object();

  static SafPlatform _instance = MethodChannelSaf();

  /// The default instance of [SafPlatform] to use.
  static SafPlatform get instance => _instance;

  static set instance(SafPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // Pick & permissions ------------------------------------------------------

  Future<SafDocumentFile?> pickDirectory({
    String? initialUri,
    bool writePermission = true,
    bool persistablePermission = true,
  }) =>
      throw UnimplementedError('pickDirectory() has not been implemented.');

  Future<SafDocumentFile?> pickFile({
    String? initialUri,
    List<String>? mimeTypes,
    bool persistablePermission = false,
  }) =>
      throw UnimplementedError('pickFile() has not been implemented.');

  Future<List<SafDocumentFile>> pickFiles({
    String? initialUri,
    List<String>? mimeTypes,
    bool persistablePermission = false,
  }) =>
      throw UnimplementedError('pickFiles() has not been implemented.');

  Future<List<SafPersistedPermission>> persistedPermissions() =>
      throw UnimplementedError(
          'persistedPermissions() has not been implemented.');

  Future<void> releasePersistedPermission(String uri) =>
      throw UnimplementedError(
          'releasePersistedPermission() has not been implemented.');

  // Manage ------------------------------------------------------------------

  Future<List<SafDocumentFile>> list(String dirUri) =>
      throw UnimplementedError('list() has not been implemented.');

  Future<SafDocumentFile?> stat(String uri) =>
      throw UnimplementedError('stat() has not been implemented.');

  /// Whether a document exists at [uri]. Default implementation is sugar
  /// over [stat].
  Future<bool> exists(String uri) async => (await stat(uri)) != null;

  Future<SafDocumentFile?> child(String dirUri, List<String> names) =>
      throw UnimplementedError('child() has not been implemented.');

  Future<SafDocumentFile> mkdirp(String dirUri, List<String> names) =>
      throw UnimplementedError('mkdirp() has not been implemented.');

  Future<void> delete(String uri) =>
      throw UnimplementedError('delete() has not been implemented.');

  Future<SafDocumentFile> rename(String uri, String newName) =>
      throw UnimplementedError('rename() has not been implemented.');

  Future<SafDocumentFile> copyTo(String uri, String destDirUri,
          {SafProgressCallback? onProgress}) =>
      throw UnimplementedError('copyTo() has not been implemented.');

  Future<SafDocumentFile> moveTo(String uri, String destDirUri,
          {SafProgressCallback? onProgress}) =>
      throw UnimplementedError('moveTo() has not been implemented.');

  Stream<SafWalkEntry> walk(String dirUri) =>
      throw UnimplementedError('walk() has not been implemented.');

  // Read & write ------------------------------------------------------------

  Future<Uint8List> readFileBytes(String uri, {int? start, int? count}) =>
      throw UnimplementedError('readFileBytes() has not been implemented.');

  Future<Stream<Uint8List>> readFileStream(String uri,
          {int? start, int bufferSize = 4194304}) =>
      throw UnimplementedError('readFileStream() has not been implemented.');

  Future<SafDocumentFile> writeFileBytes(
          String dirUri, String name, String mime, Uint8List data,
          {bool overwrite = false, bool append = false}) =>
      throw UnimplementedError('writeFileBytes() has not been implemented.');

  Future<SafDocumentFile> writeFileStream(
          String dirUri, String name, String mime, Stream<List<int>> source,
          {bool overwrite = false, bool append = false}) =>
      throw UnimplementedError('writeFileStream() has not been implemented.');

  // Local-file bridge -------------------------------------------------------

  Future<void> copyToLocalFile(String srcUri, String destPath,
          {SafProgressCallback? onProgress}) =>
      throw UnimplementedError('copyToLocalFile() has not been implemented.');

  Future<SafDocumentFile> pasteLocalFile(
          String srcPath, String destDirUri, String name, String mime,
          {bool overwrite = false, SafProgressCallback? onProgress}) =>
      throw UnimplementedError('pasteLocalFile() has not been implemented.');
}
```

- [ ] **Step 5: Write the method-channel scaffold**

```dart
// lib/src/v2/saf_method_channel.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'exceptions.dart';
import 'models.dart';
import 'saf_platform_interface.dart';

/// The default [SafPlatform] implementation backed by method channels.
class MethodChannelSaf extends SafPlatform {
  /// The v2 method channel.
  @visibleForTesting
  final methodChannel = const MethodChannel('com.ivehement.plugins/saf/v2');

  static const String eventsPrefix = 'com.ivehement.plugins/saf/v2/events/';

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await methodChannel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  SafDocumentFile _doc(Object map) =>
      SafDocumentFile.fromMap(Map<String, dynamic>.from(map as Map));

  // Methods are implemented in subsequent tasks.
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/v2/platform_interface_test.dart`
Expected: PASS (2 tests). (`_doc` is unused for now — if the analyzer flags
`unused_element`, that clears in Task 4; ignore for this run.)

- [ ] **Step 7: Commit**

```bash
git add lib/src/v2/saf_platform_interface.dart lib/src/v2/saf_method_channel.dart pubspec.yaml test/v2/platform_interface_test.dart
git commit -m "feat(v2): SafPlatform interface and method-channel scaffold"
```

---

### Task 4: MethodChannelSaf — pickers & permissions (5 methods)

**Files:**
- Modify: `lib/src/v2/saf_method_channel.dart`
- Test: `test/v2/method_channel_pick_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/v2/method_channel_pick_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/models.dart';
import 'package:saf/src/v2/saf_method_channel.dart';

const docMap = {
  'uri': 'content://tree/1',
  'name': 'Pictures',
  'isDir': true,
  'length': 0,
  'lastModified': 1,
  'mimeType': null,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = MethodChannelSaf();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  MethodCall? lastCall;
  void mock(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      lastCall = call;
      return handler(call);
    });
  }

  tearDown(() =>
      messenger.setMockMethodCallHandler(platform.methodChannel, null));

  test('pickDirectory sends args and decodes doc', () async {
    mock((_) => docMap);
    final d = await platform.pickDirectory(
        initialUri: 'content://init', writePermission: false);
    expect(lastCall!.method, 'pickDirectory');
    expect(lastCall!.arguments, {
      'initialUri': 'content://init',
      'writePermission': false,
      'persistablePermission': true,
    });
    expect(d, SafDocumentFile.fromMap(docMap));
  });

  test('pickDirectory returns null on cancel', () async {
    mock((_) => null);
    expect(await platform.pickDirectory(), isNull);
  });

  test('pickFile passes mimeTypes', () async {
    mock((_) => docMap);
    await platform.pickFile(mimeTypes: ['text/plain']);
    expect(lastCall!.method, 'pickFile');
    expect(lastCall!.arguments['mimeTypes'], ['text/plain']);
    expect(lastCall!.arguments['persistablePermission'], false);
  });

  test('pickFiles decodes list; empty means cancel', () async {
    mock((_) => [docMap, docMap]);
    expect((await platform.pickFiles()).length, 2);
    mock((_) => <Object>[]);
    expect(await platform.pickFiles(), isEmpty);
  });

  test('persistedPermissions decodes grants', () async {
    mock((_) => [
          {'uri': 'u', 'read': true, 'write': false, 'persistedTime': 9}
        ]);
    final grants = await platform.persistedPermissions();
    expect(grants.single,
        const SafPersistedPermission(uri: 'u', read: true, write: false, persistedTime: 9));
  });

  test('releasePersistedPermission sends uri', () async {
    mock((_) => null);
    await platform.releasePersistedPermission('content://u');
    expect(lastCall!.method, 'releasePersistedPermission');
    expect(lastCall!.arguments, {'uri': 'content://u'});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/v2/method_channel_pick_test.dart`
Expected: FAIL with `UnimplementedError: pickDirectory() has not been implemented.`

- [ ] **Step 3: Implement in `MethodChannelSaf`** (replace the
`// Methods are implemented in subsequent tasks.` comment; keep `_doc`)

```dart
  // Pick & permissions ------------------------------------------------------

  @override
  Future<SafDocumentFile?> pickDirectory({
    String? initialUri,
    bool writePermission = true,
    bool persistablePermission = true,
  }) async {
    final m = await _invoke<Map>('pickDirectory', {
      'initialUri': initialUri,
      'writePermission': writePermission,
      'persistablePermission': persistablePermission,
    });
    return m == null ? null : _doc(m);
  }

  @override
  Future<SafDocumentFile?> pickFile({
    String? initialUri,
    List<String>? mimeTypes,
    bool persistablePermission = false,
  }) async {
    final m = await _invoke<Map>('pickFile', {
      'initialUri': initialUri,
      'mimeTypes': mimeTypes,
      'persistablePermission': persistablePermission,
    });
    return m == null ? null : _doc(m);
  }

  @override
  Future<List<SafDocumentFile>> pickFiles({
    String? initialUri,
    List<String>? mimeTypes,
    bool persistablePermission = false,
  }) async {
    final l = await _invoke<List>('pickFiles', {
      'initialUri': initialUri,
      'mimeTypes': mimeTypes,
      'persistablePermission': persistablePermission,
    });
    return (l ?? const []).map(_doc).toList();
  }

  @override
  Future<List<SafPersistedPermission>> persistedPermissions() async {
    final l = await _invoke<List>('persistedPermissions');
    return (l ?? const [])
        .map((e) =>
            SafPersistedPermission.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<void> releasePersistedPermission(String uri) =>
      _invoke<void>('releasePersistedPermission', {'uri': uri});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/v2/method_channel_pick_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/src/v2/saf_method_channel.dart test/v2/method_channel_pick_test.dart
git commit -m "feat(v2): pickers and permission methods over the channel"
```

---

### Task 5: MethodChannelSaf — manage methods (list/stat/exists/child/mkdirp/delete/rename)

**Files:**
- Modify: `lib/src/v2/saf_method_channel.dart`
- Test: `test/v2/method_channel_manage_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/v2/method_channel_manage_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/exceptions.dart';
import 'package:saf/src/v2/models.dart';
import 'package:saf/src/v2/saf_method_channel.dart';

const docMap = {
  'uri': 'content://doc/1',
  'name': 'a.txt',
  'isDir': false,
  'length': 3,
  'lastModified': 2,
  'mimeType': 'text/plain',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = MethodChannelSaf();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  MethodCall? lastCall;
  void mock(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      lastCall = call;
      return handler(call);
    });
  }

  tearDown(() =>
      messenger.setMockMethodCallHandler(platform.methodChannel, null));

  test('list decodes children', () async {
    mock((_) => [docMap]);
    final kids = await platform.list('content://dir');
    expect(lastCall!.arguments, {'dirUri': 'content://dir'});
    expect(kids.single.name, 'a.txt');
  });

  test('stat returns null for missing; exists mirrors stat', () async {
    mock((_) => null);
    expect(await platform.stat('u'), isNull);
    expect(await platform.exists('u'), isFalse);
    mock((_) => docMap);
    expect(await platform.exists('u'), isTrue);
  });

  test('child passes multi-segment names', () async {
    mock((_) => docMap);
    await platform.child('content://dir', ['a', 'b']);
    expect(lastCall!.arguments, {
      'dirUri': 'content://dir',
      'names': ['a', 'b']
    });
  });

  test('mkdirp returns created dir', () async {
    mock((_) => {...docMap, 'isDir': true});
    final d = await platform.mkdirp('content://dir', ['x']);
    expect(d.isDir, isTrue);
  });

  test('delete sends uri', () async {
    mock((_) => null);
    await platform.delete('content://doc/1');
    expect(lastCall!.method, 'delete');
  });

  test('rename returns renamed doc', () async {
    mock((_) => {...docMap, 'name': 'b.txt'});
    final d = await platform.rename('content://doc/1', 'b.txt');
    expect(lastCall!.arguments, {'uri': 'content://doc/1', 'newName': 'b.txt'});
    expect(d.name, 'b.txt');
  });

  test('PlatformException becomes typed SafException', () async {
    mock((_) => throw PlatformException(
        code: 'not_found', message: 'gone', details: {'uri': 'u'}));
    expect(() => platform.list('u'), throwsA(isA<SafNotFoundException>()));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/v2/method_channel_manage_test.dart`
Expected: FAIL with `UnimplementedError: list() has not been implemented.`

- [ ] **Step 3: Implement** (append inside `MethodChannelSaf`)

```dart
  // Manage ------------------------------------------------------------------

  @override
  Future<List<SafDocumentFile>> list(String dirUri) async {
    final l = await _invoke<List>('list', {'dirUri': dirUri});
    return (l ?? const []).map(_doc).toList();
  }

  @override
  Future<SafDocumentFile?> stat(String uri) async {
    final m = await _invoke<Map>('stat', {'uri': uri});
    return m == null ? null : _doc(m);
  }

  @override
  Future<SafDocumentFile?> child(String dirUri, List<String> names) async {
    final m = await _invoke<Map>('child', {'dirUri': dirUri, 'names': names});
    return m == null ? null : _doc(m);
  }

  @override
  Future<SafDocumentFile> mkdirp(String dirUri, List<String> names) async {
    final m = await _invoke<Map>('mkdirp', {'dirUri': dirUri, 'names': names});
    return _doc(m!);
  }

  @override
  Future<void> delete(String uri) => _invoke<void>('delete', {'uri': uri});

  @override
  Future<SafDocumentFile> rename(String uri, String newName) async {
    final m = await _invoke<Map>('rename', {'uri': uri, 'newName': newName});
    return _doc(m!);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/v2/method_channel_manage_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/src/v2/saf_method_channel.dart test/v2/method_channel_manage_test.dart
git commit -m "feat(v2): manage methods (list/stat/child/mkdirp/delete/rename)"
```

---

### Task 6: MethodChannelSaf — progress ops (copyTo/moveTo/copyToLocalFile/pasteLocalFile)

**Files:**
- Modify: `lib/src/v2/saf_method_channel.dart`
- Test: `test/v2/method_channel_progress_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/v2/method_channel_progress_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/models.dart';
import 'package:saf/src/v2/saf_method_channel.dart';

const docMap = {
  'uri': 'content://doc/copied',
  'name': 'a.txt',
  'isDir': false,
  'length': 3,
  'lastModified': 2,
  'mimeType': 'text/plain',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = MethodChannelSaf();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() =>
      messenger.setMockMethodCallHandler(platform.methodChannel, null));

  test('copyTo without progress is a plain call', () async {
    late MethodCall seen;
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      seen = call;
      return docMap;
    });
    final d = await platform.copyTo('content://src', 'content://dest');
    expect(seen.method, 'copyTo');
    expect(seen.arguments['withProgress'], false);
    expect(d, SafDocumentFile.fromMap(docMap));
  });

  test('copyTo with progress consumes the event session', () async {
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      expect(call.arguments['withProgress'], true);
      return 's1';
    });
    messenger.setMockStreamHandler(
      EventChannel('${MethodChannelSaf.eventsPrefix}s1'),
      MockStreamHandler.inline(onListen: (args, events) {
        events.success({
          'type': 'progress',
          'bytesDone': 5,
          'totalBytes': 10,
          'currentName': 'a.txt'
        });
        events.success({'type': 'done', 'file': docMap});
        events.endOfStream();
      }),
    );
    final seen = <SafProgress>[];
    final d = await platform.copyTo('content://src', 'content://dest',
        onProgress: seen.add);
    expect(seen.single.bytesDone, 5);
    expect(seen.single.totalBytes, 10);
    expect(d.uri, 'content://doc/copied');
  });

  test('copyToLocalFile with progress completes on done with null file',
      () async {
    messenger.setMockMethodCallHandler(
        platform.methodChannel, (call) async => 's2');
    messenger.setMockStreamHandler(
      EventChannel('${MethodChannelSaf.eventsPrefix}s2'),
      MockStreamHandler.inline(onListen: (args, events) {
        events.success({'type': 'done', 'file': null});
        events.endOfStream();
      }),
    );
    await platform.copyToLocalFile('content://src', '/tmp/x',
        onProgress: (_) {});
  });

  test('pasteLocalFile plain call sends all args', () async {
    late MethodCall seen;
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      seen = call;
      return docMap;
    });
    await platform.pasteLocalFile('/tmp/src', 'content://dir', 'a.txt',
        'text/plain');
    expect(seen.method, 'pasteLocalFile');
    expect(seen.arguments['name'], 'a.txt');
    expect(seen.arguments['overwrite'], false);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/v2/method_channel_progress_test.dart`
Expected: FAIL with `UnimplementedError: copyTo() has not been implemented.`

- [ ] **Step 3: Implement** (append inside `MethodChannelSaf`)

```dart
  // Progress ops -------------------------------------------------------------

  Future<Map<String, dynamic>?> _progressOp(
    String method,
    Map<String, dynamic> args,
    SafProgressCallback? onProgress,
  ) async {
    if (onProgress == null) {
      final m = await _invoke<Object>(method, {...args, 'withProgress': false});
      return m == null ? null : Map<String, dynamic>.from(m as Map);
    }
    final session =
        await _invoke<String>(method, {...args, 'withProgress': true});
    final events = EventChannel('$eventsPrefix$session');
    final completer = Completer<Map<String, dynamic>?>();
    late final StreamSubscription<dynamic> sub;
    sub = events.receiveBroadcastStream().listen(
      (event) {
        final m = Map<String, dynamic>.from(event as Map);
        switch (m['type']) {
          case 'progress':
            onProgress(SafProgress(
              bytesDone: (m['bytesDone'] as num).toInt(),
              totalBytes: (m['totalBytes'] as num?)?.toInt(),
              currentName: m['currentName'] as String? ?? '',
            ));
          case 'done':
            if (!completer.isCompleted) {
              final file = m['file'];
              completer.complete(
                  file == null ? null : Map<String, dynamic>.from(file as Map));
            }
            sub.cancel();
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) {
          completer.completeError(
              e is PlatformException ? mapPlatformException(e) : e);
        }
        sub.cancel();
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
              const SafIoException('', 'stream ended without a result'));
        }
      },
    );
    return completer.future;
  }

  @override
  Future<SafDocumentFile> copyTo(String uri, String destDirUri,
      {SafProgressCallback? onProgress}) async {
    final m = await _progressOp(
        'copyTo', {'uri': uri, 'destDirUri': destDirUri}, onProgress);
    return _doc(m!);
  }

  @override
  Future<SafDocumentFile> moveTo(String uri, String destDirUri,
      {SafProgressCallback? onProgress}) async {
    final m = await _progressOp(
        'moveTo', {'uri': uri, 'destDirUri': destDirUri}, onProgress);
    return _doc(m!);
  }

  @override
  Future<void> copyToLocalFile(String srcUri, String destPath,
      {SafProgressCallback? onProgress}) async {
    await _progressOp('copyToLocalFile',
        {'srcUri': srcUri, 'destPath': destPath}, onProgress);
  }

  @override
  Future<SafDocumentFile> pasteLocalFile(
      String srcPath, String destDirUri, String name, String mime,
      {bool overwrite = false, SafProgressCallback? onProgress}) async {
    final m = await _progressOp(
        'pasteLocalFile',
        {
          'srcPath': srcPath,
          'destDirUri': destDirUri,
          'name': name,
          'mime': mime,
          'overwrite': overwrite,
        },
        onProgress);
    return _doc(m!);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/v2/method_channel_progress_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/src/v2/saf_method_channel.dart test/v2/method_channel_progress_test.dart
git commit -m "feat(v2): copy/move/paste with optional progress sessions"
```

---

### Task 7: MethodChannelSaf — readFileBytes / writeFileBytes

**Files:**
- Modify: `lib/src/v2/saf_method_channel.dart`
- Test: `test/v2/method_channel_bytes_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/v2/method_channel_bytes_test.dart
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/saf_method_channel.dart';

const docMap = {
  'uri': 'content://doc/new',
  'name': 'a.bin',
  'isDir': false,
  'length': 4,
  'lastModified': 2,
  'mimeType': 'application/octet-stream',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = MethodChannelSaf();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  MethodCall? lastCall;
  void mock(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      lastCall = call;
      return handler(call);
    });
  }

  tearDown(() =>
      messenger.setMockMethodCallHandler(platform.methodChannel, null));

  test('readFileBytes returns bytes and forwards range', () async {
    mock((_) => Uint8List.fromList([1, 2, 3]));
    final b = await platform.readFileBytes('u', start: 5, count: 3);
    expect(b, [1, 2, 3]);
    expect(lastCall!.arguments, {'uri': 'u', 'start': 5, 'count': 3});
  });

  test('writeFileBytes sends data and decodes result', () async {
    mock((_) => docMap);
    final d = await platform.writeFileBytes(
        'content://dir', 'a.bin', 'application/octet-stream',
        Uint8List.fromList([9, 9, 9, 9]));
    expect(lastCall!.method, 'writeFileBytes');
    expect(lastCall!.arguments['data'], [9, 9, 9, 9]);
    expect(lastCall!.arguments['overwrite'], false);
    expect(lastCall!.arguments['append'], false);
    expect(d.name, 'a.bin');
  });

  test('writeFileBytes rejects overwrite+append', () async {
    mock((_) => docMap);
    expect(
      () => platform.writeFileBytes('d', 'n', 'm', Uint8List(0),
          overwrite: true, append: true),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/v2/method_channel_bytes_test.dart`
Expected: FAIL with `UnimplementedError: readFileBytes() has not been implemented.`

- [ ] **Step 3: Implement** (append inside `MethodChannelSaf`)

```dart
  // Read & write (bytes) -----------------------------------------------------

  @override
  Future<Uint8List> readFileBytes(String uri, {int? start, int? count}) async {
    final b = await _invoke<Uint8List>(
        'readFileBytes', {'uri': uri, 'start': start, 'count': count});
    return b ?? Uint8List(0);
  }

  @override
  Future<SafDocumentFile> writeFileBytes(
      String dirUri, String name, String mime, Uint8List data,
      {bool overwrite = false, bool append = false}) async {
    if (overwrite && append) {
      throw ArgumentError('overwrite and append are mutually exclusive');
    }
    final m = await _invoke<Map>('writeFileBytes', {
      'dirUri': dirUri,
      'name': name,
      'mime': mime,
      'data': data,
      'overwrite': overwrite,
      'append': append,
    });
    return _doc(m!);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/v2/method_channel_bytes_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/src/v2/saf_method_channel.dart test/v2/method_channel_bytes_test.dart
git commit -m "feat(v2): byte-level read and write"
```

---

### Task 8: MethodChannelSaf — readFileStream + walk (event channels)

**Files:**
- Modify: `lib/src/v2/saf_method_channel.dart`
- Test: `test/v2/method_channel_stream_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/v2/method_channel_stream_test.dart
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/exceptions.dart';
import 'package:saf/src/v2/saf_method_channel.dart';

const docMap = {
  'uri': 'content://doc/1',
  'name': 'a.txt',
  'isDir': false,
  'length': 3,
  'lastModified': 2,
  'mimeType': 'text/plain',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = MethodChannelSaf();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() =>
      messenger.setMockMethodCallHandler(platform.methodChannel, null));

  test('readFileStream yields chunks until endOfStream', () async {
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      expect(call.method, 'readFileStream');
      expect(call.arguments['bufferSize'], 4194304);
      return 'rs1';
    });
    messenger.setMockStreamHandler(
      EventChannel('${MethodChannelSaf.eventsPrefix}rs1'),
      MockStreamHandler.inline(onListen: (args, events) {
        events.success(Uint8List.fromList([1]));
        events.success(Uint8List.fromList([2, 3]));
        events.endOfStream();
      }),
    );
    final chunks = await (await platform.readFileStream('u')).toList();
    expect(chunks, [
      [1],
      [2, 3]
    ]);
  });

  test('readFileStream maps errors to SafException', () async {
    messenger.setMockMethodCallHandler(
        platform.methodChannel, (call) async => 'rs2');
    messenger.setMockStreamHandler(
      EventChannel('${MethodChannelSaf.eventsPrefix}rs2'),
      MockStreamHandler.inline(onListen: (args, events) {
        events.error(code: 'permission', message: 'no', details: {'uri': 'u'});
        events.endOfStream();
      }),
    );
    final stream = await platform.readFileStream('u');
    expect(stream.toList(), throwsA(isA<SafPermissionException>()));
  });

  test('walk yields entries with relative paths', () async {
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      expect(call.method, 'startWalk');
      return 'w1';
    });
    messenger.setMockStreamHandler(
      EventChannel('${MethodChannelSaf.eventsPrefix}w1'),
      MockStreamHandler.inline(onListen: (args, events) {
        events.success({'file': docMap, 'relativePath': 'sub/a.txt'});
        events.endOfStream();
      }),
    );
    final entries = await platform.walk('content://dir').toList();
    expect(entries.single.relativePath, 'sub/a.txt');
    expect(entries.single.file.name, 'a.txt');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/v2/method_channel_stream_test.dart`
Expected: FAIL with `UnimplementedError: readFileStream() has not been implemented.`

- [ ] **Step 3: Implement** (append inside `MethodChannelSaf`)

```dart
  // Streams ------------------------------------------------------------------

  Stream<dynamic> _sessionEvents(String session) =>
      EventChannel('$eventsPrefix$session').receiveBroadcastStream().handleError(
        (Object e) => throw mapPlatformException(e as PlatformException),
        test: (e) => e is PlatformException,
      );

  @override
  Future<Stream<Uint8List>> readFileStream(String uri,
      {int? start, int bufferSize = 4194304}) async {
    final session = await _invoke<String>('readFileStream',
        {'uri': uri, 'start': start, 'bufferSize': bufferSize});
    return _sessionEvents(session!).map((e) => e as Uint8List);
  }

  @override
  Stream<SafWalkEntry> walk(String dirUri) async* {
    final session = await _invoke<String>('startWalk', {'dirUri': dirUri});
    yield* _sessionEvents(session!).map((event) {
      final m = Map<String, dynamic>.from(event as Map);
      return SafWalkEntry(
        file: _doc(m['file'] as Object),
        relativePath: m['relativePath'] as String,
      );
    });
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/v2/method_channel_stream_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/src/v2/saf_method_channel.dart test/v2/method_channel_stream_test.dart
git commit -m "feat(v2): read stream and recursive walk over event channels"
```

---

### Task 9: MethodChannelSaf — writeFileStream (session pumping)

**Files:**
- Modify: `lib/src/v2/saf_method_channel.dart`
- Test: `test/v2/method_channel_write_stream_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/v2/method_channel_write_stream_test.dart
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/exceptions.dart';
import 'package:saf/src/v2/saf_method_channel.dart';

const docMap = {
  'uri': 'content://doc/new',
  'name': 'big.bin',
  'isDir': false,
  'length': 6,
  'lastModified': 2,
  'mimeType': 'application/octet-stream',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = MethodChannelSaf();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() =>
      messenger.setMockMethodCallHandler(platform.methodChannel, null));

  test('pumps chunks in order then ends the session', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'startWriteStream' => 'ws1',
        'writeChunk' => null,
        'endWriteStream' => docMap,
        _ => throw StateError('unexpected ${call.method}'),
      };
    });
    final source = Stream.fromIterable([
      [1, 2, 3],
      [4, 5, 6],
    ]);
    final d = await platform.writeFileStream(
        'content://dir', 'big.bin', 'application/octet-stream', source);
    expect(calls.map((c) => c.method).toList(),
        ['startWriteStream', 'writeChunk', 'writeChunk', 'endWriteStream']);
    expect(calls[1].arguments['data'], [1, 2, 3]);
    expect(calls[2].arguments['data'], [4, 5, 6]);
    expect(calls[1].arguments['session'], 'ws1');
    expect(d.length, 6);
  });

  test('aborts the session when the source stream errors', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      calls.add(call.method);
      return call.method == 'startWriteStream' ? 'ws2' : null;
    });
    final source = () async* {
      yield <int>[1];
      throw StateError('source broke');
    }();
    await expectLater(
      platform.writeFileStream('d', 'n', 'm', source),
      throwsA(isA<StateError>()),
    );
    expect(calls, ['startWriteStream', 'writeChunk', 'abortWriteStream']);
  });

  test('rejects overwrite+append before any channel call', () async {
    messenger.setMockMethodCallHandler(platform.methodChannel,
        (call) async => throw StateError('must not be called'));
    expect(
      () => platform.writeFileStream('d', 'n', 'm', const Stream.empty(),
          overwrite: true, append: true),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/v2/method_channel_write_stream_test.dart`
Expected: FAIL with `UnimplementedError: writeFileStream() has not been implemented.`

- [ ] **Step 3: Implement** (append inside `MethodChannelSaf`)

```dart
  @override
  Future<SafDocumentFile> writeFileStream(
      String dirUri, String name, String mime, Stream<List<int>> source,
      {bool overwrite = false, bool append = false}) async {
    if (overwrite && append) {
      throw ArgumentError('overwrite and append are mutually exclusive');
    }
    final session = await _invoke<String>('startWriteStream', {
      'dirUri': dirUri,
      'name': name,
      'mime': mime,
      'overwrite': overwrite,
      'append': append,
    });
    try {
      await for (final chunk in source) {
        await _invoke<void>('writeChunk', {
          'session': session,
          'data': chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
        });
      }
      final m = await _invoke<Map>('endWriteStream', {'session': session});
      return _doc(m!);
    } catch (_) {
      try {
        await _invoke<void>('abortWriteStream', {'session': session});
      } on SafException {
        // Best-effort cleanup; surface the original error instead.
      }
      rethrow;
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/v2/method_channel_write_stream_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/src/v2/saf_method_channel.dart test/v2/method_channel_write_stream_test.dart
git commit -m "feat(v2): one-call writeFileStream over an internal session"
```

---

### Task 10: `Saf` facade + public exports

**Files:**
- Create: `lib/src/v2/saf.dart`
- Modify: `lib/saf.dart`
- Test: `test/v2/facade_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/v2/facade_test.dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:saf/saf.dart';
import 'package:saf/src/v2/saf_platform_interface.dart';

const doc = SafDocumentFile(
    uri: 'u', name: 'n', isDir: false, length: 1, lastModified: 2);

class FakePlatform extends SafPlatform with MockPlatformInterfaceMixin {
  final log = <String>[];

  @override
  Future<SafDocumentFile?> pickDirectory(
      {String? initialUri,
      bool writePermission = true,
      bool persistablePermission = true}) async {
    log.add('pickDirectory');
    return doc;
  }

  @override
  Future<SafDocumentFile?> stat(String uri) async {
    log.add('stat:$uri');
    return uri == 'exists' ? doc : null;
  }

  @override
  Future<List<SafDocumentFile>> list(String dirUri) async {
    log.add('list:$dirUri');
    return [doc];
  }

  @override
  Future<Uint8List> readFileBytes(String uri, {int? start, int? count}) async {
    log.add('read:$uri');
    return Uint8List.fromList([7]);
  }

  @override
  Stream<SafWalkEntry> walk(String dirUri) =>
      Stream.value(const SafWalkEntry(file: doc, relativePath: 'n'));
}

void main() {
  test('Saf delegates to the registered platform', () async {
    final fake = FakePlatform();
    SafPlatform.instance = fake;
    final saf = Saf();

    expect(await saf.pickDirectory(), doc);
    expect(await saf.list('d'), [doc]);
    expect(await saf.readFileBytes('u'), [7]);
    expect((await saf.walk('d').toList()).single.relativePath, 'n');
    expect(await saf.exists('exists'), isTrue);
    expect(await saf.exists('missing'), isFalse);
    expect(fake.log, contains('pickDirectory'));
  });

  test('legacy LegacySaf is still exported', () {
    // ignore: deprecated_member_use_from_same_package
    expect(LegacySaf('some/path'), isA<LegacySaf>());
  });
}
```

NOTE: the `LegacySaf` expectation fails until Task 11 — in this task run only
the first test (see Step 3); the second is pre-staged for Task 11.

- [ ] **Step 2: Write the facade**

```dart
// lib/src/v2/saf.dart
import 'dart:typed_data';

import 'models.dart';
import 'saf_platform_interface.dart';

/// Android Storage Access Framework client.
///
/// One class for everything SAF: directory/file pickers, persisted
/// permissions, file management (list, stat, mkdirp, rename, copy, move,
/// recursive walk), byte- and stream-based read/write, and bridging between
/// SAF documents and local files.
///
/// ```dart
/// final saf = Saf();
/// final dir = await saf.pickDirectory();
/// if (dir != null) {
///   for (final f in await saf.list(dir.uri)) {
///     print('${f.name} (${f.length} bytes)');
///   }
/// }
/// ```
class Saf {
  SafPlatform get _p => SafPlatform.instance;

  // Pick & permissions ------------------------------------------------------

  /// Opens the system directory picker (`ACTION_OPEN_DOCUMENT_TREE`).
  ///
  /// Returns the picked directory, or `null` if the user cancelled.
  /// With [persistablePermission] (default) the grant survives app restarts;
  /// check [persistedPermissions] on later launches instead of re-prompting.
  Future<SafDocumentFile?> pickDirectory({
    String? initialUri,
    bool writePermission = true,
    bool persistablePermission = true,
  }) =>
      _p.pickDirectory(
          initialUri: initialUri,
          writePermission: writePermission,
          persistablePermission: persistablePermission);

  /// Opens the system file picker (`ACTION_OPEN_DOCUMENT`) for one file.
  ///
  /// Returns `null` if the user cancelled.
  Future<SafDocumentFile?> pickFile({
    String? initialUri,
    List<String>? mimeTypes,
    bool persistablePermission = false,
  }) =>
      _p.pickFile(
          initialUri: initialUri,
          mimeTypes: mimeTypes,
          persistablePermission: persistablePermission);

  /// Opens the system file picker allowing multiple selection.
  ///
  /// Returns an empty list if the user cancelled.
  Future<List<SafDocumentFile>> pickFiles({
    String? initialUri,
    List<String>? mimeTypes,
    bool persistablePermission = false,
  }) =>
      _p.pickFiles(
          initialUri: initialUri,
          mimeTypes: mimeTypes,
          persistablePermission: persistablePermission);

  /// Lists all URI permissions the app currently persists.
  Future<List<SafPersistedPermission>> persistedPermissions() =>
      _p.persistedPermissions();

  /// Releases a persisted URI permission previously taken by a picker.
  Future<void> releasePersistedPermission(String uri) =>
      _p.releasePersistedPermission(uri);

  // Manage ------------------------------------------------------------------

  /// Lists the children of [dirUri] with full metadata in a single query.
  Future<List<SafDocumentFile>> list(String dirUri) => _p.list(dirUri);

  /// Returns metadata for [uri], or `null` if no document exists there.
  Future<SafDocumentFile?> stat(String uri) => _p.stat(uri);

  /// Whether a document exists at [uri].
  Future<bool> exists(String uri) => _p.exists(uri);

  /// Resolves a descendant by name segments, e.g.
  /// `child(dir.uri, ['backups', 'config.json'])`. Returns `null` if any
  /// segment is missing.
  Future<SafDocumentFile?> child(String dirUri, List<String> names) =>
      _p.child(dirUri, names);

  /// Creates the directory path [names] under [dirUri], creating
  /// intermediate directories as needed. Returns the deepest directory.
  Future<SafDocumentFile> mkdirp(String dirUri, List<String> names) =>
      _p.mkdirp(dirUri, names);

  /// Deletes the document at [uri]. Directories are deleted recursively.
  Future<void> delete(String uri) => _p.delete(uri);

  /// Renames the document at [uri] to [newName] and returns it.
  Future<SafDocumentFile> rename(String uri, String newName) =>
      _p.rename(uri, newName);

  /// Copies a file or directory (recursively) into [destDirUri].
  ///
  /// [onProgress] receives byte-level progress; `totalBytes` is `null` for
  /// directory copies.
  Future<SafDocumentFile> copyTo(String uri, String destDirUri,
          {SafProgressCallback? onProgress}) =>
      _p.copyTo(uri, destDirUri, onProgress: onProgress);

  /// Moves a file or directory (recursively) into [destDirUri].
  ///
  /// Implemented as copy-then-delete for provider compatibility.
  Future<SafDocumentFile> moveTo(String uri, String destDirUri,
          {SafProgressCallback? onProgress}) =>
      _p.moveTo(uri, destDirUri, onProgress: onProgress);

  /// Recursively walks [dirUri] depth-first, emitting every descendant.
  ///
  /// Directories are emitted before their contents. Cancel the subscription
  /// to stop the native traversal early.
  Stream<SafWalkEntry> walk(String dirUri) => _p.walk(dirUri);

  // Read & write ------------------------------------------------------------

  /// Reads a file's bytes. Use [start]/[count] to read a range.
  Future<Uint8List> readFileBytes(String uri, {int? start, int? count}) =>
      _p.readFileBytes(uri, start: start, count: count);

  /// Streams a file's bytes in chunks of [bufferSize] (default 4 MiB).
  Future<Stream<Uint8List>> readFileStream(String uri,
          {int? start, int bufferSize = 4194304}) =>
      _p.readFileStream(uri, start: start, bufferSize: bufferSize);

  /// Writes [data] as a file named [name] inside [dirUri].
  ///
  /// By default a name collision creates an auto-renamed file
  /// (SAF behavior, e.g. `file (1).txt`); pass `overwrite: true` to truncate
  /// the existing document, or `append: true` to append to it.
  Future<SafDocumentFile> writeFileBytes(
          String dirUri, String name, String mime, Uint8List data,
          {bool overwrite = false, bool append = false}) =>
      _p.writeFileBytes(dirUri, name, mime, data,
          overwrite: overwrite, append: append);

  /// Writes a whole [source] stream as a file in one call — no session
  /// bookkeeping required.
  Future<SafDocumentFile> writeFileStream(
          String dirUri, String name, String mime, Stream<List<int>> source,
          {bool overwrite = false, bool append = false}) =>
      _p.writeFileStream(dirUri, name, mime, source,
          overwrite: overwrite, append: append);

  // Local-file bridge -------------------------------------------------------

  /// Copies a SAF document to a local filesystem path (e.g. app cache), so
  /// the file can be handed to APIs that need a real path.
  Future<void> copyToLocalFile(String srcUri, String destPath,
          {SafProgressCallback? onProgress}) =>
      _p.copyToLocalFile(srcUri, destPath, onProgress: onProgress);

  /// Copies a local file into a SAF directory.
  Future<SafDocumentFile> pasteLocalFile(
          String srcPath, String destDirUri, String name, String mime,
          {bool overwrite = false, SafProgressCallback? onProgress}) =>
      _p.pasteLocalFile(srcPath, destDirUri, name, mime,
          overwrite: overwrite, onProgress: onProgress);
}
```

- [ ] **Step 3: Update `lib/saf.dart` exports**

Replace the whole file with:

```dart
/// Flutter plugin for the Android Storage Access Framework (SAF):
/// directory/file pickers, persisted permissions, file management with
/// recursive walk, streamed read/write with progress, and local-file
/// bridging — in a single [Saf] class.
///
/// See the [project page](https://jvoltci.github.io/saf/) for usage examples.
library saf;

export 'src/v2/exceptions.dart';
export 'src/v2/models.dart';
export 'src/v2/saf.dart';
export 'src/v2/saf_platform_interface.dart' show SafPlatform;

// Legacy 1.x API — deprecated, removed in 3.0.0.
export 'src/storage_access_framework/saf.dart';
export 'src/storage_access_framework/file_types.dart';
```

`export 'src/storage_access_framework/saf.dart'` still exports the legacy
class named `Saf` at this point — that clashes with the new `Saf`. That is
expected mid-task: run only the facade test with the legacy export line
TEMPORARILY commented out, confirm it passes, then leave the line commented
with `// TODO(Task 11): re-enable after LegacySaf rename` — Task 11
immediately renames the legacy class and re-enables it.

- [ ] **Step 4: Run the facade test**

Run: `flutter test test/v2/facade_test.dart --plain-name 'Saf delegates to the registered platform'`
Expected: PASS (1 test; the LegacySaf test is covered in Task 11)

- [ ] **Step 5: Commit**

```bash
git add lib/src/v2/saf.dart lib/saf.dart test/v2/facade_test.dart
git commit -m "feat(v2): Saf facade class and public exports"
```

---

### Task 11: rename legacy `Saf` → `LegacySaf` (+ deprecation)

**Files:**
- Modify: `lib/src/storage_access_framework/saf.dart` (class declaration only)
- Modify: `lib/saf.dart` (re-enable legacy export)
- Modify: `example/lib/main.dart` (4 static call sites)
- Test: `test/v2/facade_test.dart` (second test now passes)

- [ ] **Step 1: Rename the legacy class**

In `lib/src/storage_access_framework/saf.dart` change the class declaration
(currently `class Saf {`) to:

```dart
/// The legacy 1.x path-based API.
///
/// Superseded by the URI-based [not exported here] `Saf` class in 2.0.0,
/// which follows SAF semantics correctly. This class is unchanged from 1.x
/// and will be removed in 3.0.0.
@Deprecated('Use the new Saf class instead. LegacySaf will be removed in 3.0.0')
class LegacySaf {
```

and rename its constructor `Saf(this._directory)` → `LegacySaf(this._directory)`.
No other edits to this file.

- [ ] **Step 2: Re-enable the legacy export in `lib/saf.dart`**

Uncomment the line so the exports read exactly as in Task 10 Step 3.

- [ ] **Step 3: Update the example's legacy calls**

At the top of `example/lib/main.dart` (line 1) add:

```dart
// ignore_for_file: deprecated_member_use
```

Then replace the four legacy static call sites:
- line ~57: `await Saf.getDynamicDirectoryPermission()` → `await LegacySaf.getDynamicDirectoryPermission()`
- line ~62: `await Saf.getPersistedPermissionDirectories()` → `await LegacySaf.getPersistedPermissionDirectories()`
- line ~76: `await Saf.getFilesPathFor(` → `await LegacySaf.getFilesPathFor(`
- line ~118: `await Saf.releasePersistedPermissions()` → `await LegacySaf.releasePersistedPermissions()`

(The debug string on line ~74 mentioning `Saf.getFilesPathFor` may stay.)

- [ ] **Step 4: Run the full suite + analyzer**

Run: `flutter test && flutter analyze`
Expected: all tests PASS (including `legacy LegacySaf is still exported`);
analyze: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/src/storage_access_framework/saf.dart lib/saf.dart example/lib/main.dart test/v2/facade_test.dart
git commit -m "feat(v2)!: rename legacy Saf to LegacySaf (deprecated)"
```

---

### Task 12: Kotlin — errors + DocumentsContract helpers

**Files:**
- Create: `android/src/main/kotlin/com/ivehement/saf/v2/SafErrors.kt`
- Create: `android/src/main/kotlin/com/ivehement/saf/v2/SafDocs.kt`

No JVM unit tests exist in this plugin; verification is compilation
(Task 15 builds the example APK). Keep functions small and total.

- [ ] **Step 1: Write `SafErrors.kt`**

```kotlin
package com.ivehement.saf.v2

import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException

/** Thrown when a document that must not exist already does. */
class SafAlreadyExistsException(message: String) : Exception(message)

/** Thrown when a document that must exist does not. */
class SafNotFoundException(message: String) : Exception(message)

/** Maps a throwable to one of the four stable v2 error codes. */
fun errorCodeOf(e: Throwable): String = when (e) {
  is SafNotFoundException, is FileNotFoundException -> "not_found"
  is SafAlreadyExistsException -> "already_exists"
  is SecurityException -> "permission"
  else -> "io"
}

/** Completes a method-channel result with a typed v2 error. */
fun MethodChannel.Result.safError(e: Throwable, uri: String?) {
  error(errorCodeOf(e), e.message ?: e.toString(), mapOf("uri" to (uri ?: "")))
}
```

- [ ] **Step 2: Write `SafDocs.kt`**

```kotlin
package com.ivehement.saf.v2

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import java.io.FileNotFoundException

/**
 * Cursor-based DocumentsContract helpers. All listing/stat operations use a
 * single ContentResolver query with a full projection instead of
 * DocumentFile's one-query-per-property pattern.
 */
object SafDocs {
  private val PROJECTION = arrayOf(
    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
    DocumentsContract.Document.COLUMN_MIME_TYPE,
    DocumentsContract.Document.COLUMN_SIZE,
    DocumentsContract.Document.COLUMN_LAST_MODIFIED,
  )

  /**
   * Normalizes a URI to a *document* URI. A bare tree URI (as returned by
   * ACTION_OPEN_DOCUMENT_TREE, path `tree/<id>`) becomes its root document
   * URI; anything else is returned unchanged.
   */
  fun docUriOf(uri: Uri): Uri {
    val segments = uri.pathSegments
    return if (segments.size == 2 && segments[0] == "tree") {
      DocumentsContract.buildDocumentUriUsingTree(
        uri, DocumentsContract.getTreeDocumentId(uri)
      )
    } else uri
  }

  private fun rowToMap(c: Cursor, uriFor: (String) -> Uri): Map<String, Any?> {
    val docId = c.getString(0)
    val mime = c.getString(2)
    val isDir = mime == DocumentsContract.Document.MIME_TYPE_DIR
    return mapOf(
      "uri" to uriFor(docId).toString(),
      "name" to (c.getString(1) ?: ""),
      "isDir" to isDir,
      "length" to (if (c.isNull(3)) 0L else c.getLong(3)),
      "lastModified" to (if (c.isNull(4)) 0L else c.getLong(4)),
      "mimeType" to (if (isDir) null else mime),
    )
  }

  /** Metadata for [uri], or null when the document does not exist. */
  fun stat(context: Context, uri: Uri): Map<String, Any?>? {
    val doc = docUriOf(uri)
    return try {
      context.contentResolver.query(doc, PROJECTION, null, null, null)?.use { c ->
        if (c.moveToFirst()) rowToMap(c) { doc } else null
      }
    } catch (e: FileNotFoundException) {
      null
    } catch (e: IllegalArgumentException) {
      null
    } catch (e: UnsupportedOperationException) {
      null
    }
  }

  /** Children of [dirUri] with full metadata from one cursor. */
  fun listChildren(context: Context, dirUri: Uri): List<Map<String, Any?>> {
    val dirDoc = docUriOf(dirUri)
    val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
      dirDoc, DocumentsContract.getDocumentId(dirDoc)
    )
    val out = mutableListOf<Map<String, Any?>>()
    val cursor = context.contentResolver.query(childrenUri, PROJECTION, null, null, null)
      ?: throw SafNotFoundException("Cannot list $dirUri")
    cursor.use { c ->
      while (c.moveToNext()) {
        out.add(rowToMap(c) { id -> DocumentsContract.buildDocumentUriUsingTree(dirDoc, id) })
      }
    }
    return out
  }

  /** Resolves a descendant by name segments, or null if any segment is missing. */
  fun child(context: Context, dirUri: Uri, names: List<String>): Map<String, Any?>? {
    var current = stat(context, dirUri) ?: return null
    for (name in names) {
      val kids = listChildren(context, Uri.parse(current["uri"] as String))
      current = kids.firstOrNull { it["name"] == name } ?: return null
    }
    return current
  }

  /** Creates directory path [names] under [dirUri], returning the deepest dir. */
  fun mkdirp(context: Context, dirUri: Uri, names: List<String>): Map<String, Any?> {
    var currentUri = docUriOf(dirUri)
    for (name in names) {
      val existing = listChildren(context, currentUri).firstOrNull { it["name"] == name }
      currentUri = if (existing != null) {
        if (existing["isDir"] != true) {
          throw SafAlreadyExistsException("'$name' exists and is not a directory")
        }
        Uri.parse(existing["uri"] as String)
      } else {
        DocumentsContract.createDocument(
          context.contentResolver, currentUri,
          DocumentsContract.Document.MIME_TYPE_DIR, name
        ) ?: throw Exception("Failed to create directory '$name'")
      }
    }
    return stat(context, currentUri) ?: throw SafNotFoundException("mkdirp result missing")
  }

  /** Creates a new (possibly auto-renamed) document in [dirUri]. */
  fun createFile(context: Context, dirUri: Uri, mime: String, name: String): Uri =
    DocumentsContract.createDocument(context.contentResolver, docUriOf(dirUri), mime, name)
      ?: throw Exception("Failed to create '$name' in $dirUri")

  /** Deletes a document (recursively for directories, per provider). */
  fun delete(context: Context, uri: Uri) {
    val ok = DocumentsContract.deleteDocument(context.contentResolver, docUriOf(uri))
    if (!ok) throw Exception("Failed to delete $uri")
  }

  /** Renames a document, returning its (possibly new) URI. */
  fun rename(context: Context, uri: Uri, newName: String): Uri {
    val doc = docUriOf(uri)
    return DocumentsContract.renameDocument(context.contentResolver, doc, newName) ?: doc
  }

  /**
   * Copies raw contents from [src] into [dest], invoking [progress] with the
   * cumulative byte count.
   */
  fun copyContents(
    context: Context,
    src: Uri,
    dest: Uri,
    progress: ((Long) -> Unit)?,
  ) {
    val input = context.contentResolver.openInputStream(src)
      ?: throw SafNotFoundException("Cannot open input $src")
    input.use { ins ->
      val output = context.contentResolver.openOutputStream(dest, "wt")
        ?: throw Exception("Cannot open output $dest")
      output.use { outs ->
        val buf = ByteArray(1 shl 16)
        var total = 0L
        while (true) {
          val n = ins.read(buf)
          if (n < 0) break
          outs.write(buf, 0, n)
          total += n
          progress?.invoke(total)
        }
        outs.flush()
      }
    }
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add android/src/main/kotlin/com/ivehement/saf/v2/SafErrors.kt android/src/main/kotlin/com/ivehement/saf/v2/SafDocs.kt
git commit -m "feat(v2): Kotlin error mapping and single-cursor document helpers"
```

---

### Task 13: Kotlin — event-channel sessions (QueuingEventSink)

**Files:**
- Create: `android/src/main/kotlin/com/ivehement/saf/v2/SafV2Streams.kt`

- [ ] **Step 1: Write `SafV2Streams.kt`**

```kotlin
package com.ivehement.saf.v2

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * An EventSink that buffers events until a Dart listener attaches, then
 * replays them. Solves the subscribe-after-invoke race for session channels.
 * Also exposes [cancelled] so producers can stop early when Dart cancels.
 */
class QueuingEventSink : EventChannel.EventSink {
  private var delegate: EventChannel.EventSink? = null
  private val buffer = mutableListOf<Any>()
  private var done = false

  @Volatile
  var cancelled = false
    private set

  private class EndOfStream
  private class ErrorEvent(val code: String, val message: String?, val details: Any?)

  @Synchronized
  fun setDelegate(sink: EventChannel.EventSink?) {
    delegate = sink
    if (sink == null) {
      cancelled = true
      return
    }
    for (event in buffer) dispatch(event, sink)
    buffer.clear()
  }

  @Synchronized
  override fun success(event: Any?) = enqueue(event ?: Unit)

  @Synchronized
  override fun error(code: String, message: String?, details: Any?) =
    enqueue(ErrorEvent(code, message, details))

  @Synchronized
  override fun endOfStream() {
    enqueue(EndOfStream())
    done = true
  }

  private fun enqueue(event: Any) {
    if (done) return
    val sink = delegate
    if (sink != null) dispatch(event, sink) else buffer.add(event)
  }

  private fun dispatch(event: Any, sink: EventChannel.EventSink) {
    when (event) {
      is EndOfStream -> sink.endOfStream()
      is ErrorEvent -> sink.error(event.code, event.message, event.details)
      is Unit -> sink.success(null)
      else -> sink.success(event)
    }
  }
}

/** An EventSink wrapper that always delivers on the Android main thread. */
class MainThreadEventSink(private val inner: EventChannel.EventSink) :
  EventChannel.EventSink {
  private val handler = Handler(Looper.getMainLooper())

  override fun success(event: Any?) = runOnMain { inner.success(event) }
  override fun error(code: String, message: String?, details: Any?) =
    runOnMain { inner.error(code, message, details) }
  override fun endOfStream() = runOnMain { inner.endOfStream() }

  private fun runOnMain(block: () -> Unit) {
    if (Looper.myLooper() == Looper.getMainLooper()) block() else handler.post(block)
  }
}

/** Creates one EventChannel per streaming session. */
class SessionManager(private val messenger: BinaryMessenger) {
  private var counter = 0

  @Synchronized
  fun create(): Pair<String, QueuingEventSink> {
    val id = "saf_v2_${System.nanoTime()}_${counter++}"
    val sink = QueuingEventSink()
    EventChannel(messenger, "com.ivehement.plugins/saf/v2/events/$id")
      .setStreamHandler(object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
          sink.setDelegate(MainThreadEventSink(events))
        }

        override fun onCancel(arguments: Any?) {
          sink.setDelegate(null)
        }
      })
    return id to sink
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add android/src/main/kotlin/com/ivehement/saf/v2/SafV2Streams.kt
git commit -m "feat(v2): queuing event sinks and per-session event channels"
```

---

### Task 14: Kotlin — SafV2Api handler + plugin wiring

**Files:**
- Create: `android/src/main/kotlin/com/ivehement/saf/v2/SafV2Api.kt`
- Modify: `android/src/main/kotlin/com/ivehement/saf/SafPlugin.kt`
- Modify: `android/build.gradle` (coroutines dep already present — verify only)

- [ ] **Step 1: Write `SafV2Api.kt`**

```kotlin
package com.ivehement.saf.v2

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import com.ivehement.saf.SafPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.OutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

private const val CHANNEL = "com.ivehement.plugins/saf/v2"
private const val PICK_DIRECTORY_CODE = 7101
private const val PICK_FILE_CODE = 7102
private const val PICK_FILES_CODE = 7103
private const val PROGRESS_INTERVAL_MS = 100L

class SafV2Api(private val plugin: SafPlugin) :
  MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {

  private var channel: MethodChannel? = null
  private var sessions: SessionManager? = null
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
  private val main = Handler(Looper.getMainLooper())
  private val pendingPicks =
    mutableMapOf<Int, Pair<MethodCall, MethodChannel.Result>>()

  private class WriteSession(
    val stream: OutputStream,
    val uri: Uri,
    val executor: ExecutorService,
  )

  private val writeSessions = mutableMapOf<String, WriteSession>()
  private var writeCounter = 0

  fun startListening(messenger: BinaryMessenger) {
    channel = MethodChannel(messenger, CHANNEL)
    channel?.setMethodCallHandler(this)
    sessions = SessionManager(messenger)
  }

  fun stopListening() {
    channel?.setMethodCallHandler(null)
    channel = null
    scope.cancel()
    synchronized(writeSessions) {
      writeSessions.values.forEach {
        runCatching { it.stream.close() }
        it.executor.shutdown()
      }
      writeSessions.clear()
    }
  }

  private val context get() = plugin.context
  private val activity: Activity? get() = plugin.binding?.activity

  /** Runs [block] on IO, posting success/typed error back on main. */
  private fun run(result: MethodChannel.Result, uri: String?, block: () -> Any?) {
    scope.launch {
      try {
        val value = block()
        main.post { result.success(value) }
      } catch (e: Throwable) {
        main.post { result.safError(e, uri) }
      }
    }
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "pickDirectory" -> startPick(PICK_DIRECTORY_CODE, call, result)
      "pickFile" -> startPick(PICK_FILE_CODE, call, result)
      "pickFiles" -> startPick(PICK_FILES_CODE, call, result)

      "persistedPermissions" -> run(result, null) {
        context.contentResolver.persistedUriPermissions.map {
          mapOf(
            "uri" to it.uri.toString(),
            "read" to it.isReadPermission,
            "write" to it.isWritePermission,
            "persistedTime" to it.persistedTime,
          )
        }
      }

      "releasePersistedPermission" -> {
        val uri = call.argument<String>("uri")!!
        run(result, uri) {
          val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
          runCatching {
            context.contentResolver.releasePersistableUriPermission(Uri.parse(uri), flags)
          }
          null
        }
      }

      "list" -> {
        val dirUri = call.argument<String>("dirUri")!!
        run(result, dirUri) { SafDocs.listChildren(context, Uri.parse(dirUri)) }
      }

      "stat" -> {
        val uri = call.argument<String>("uri")!!
        run(result, uri) { SafDocs.stat(context, Uri.parse(uri)) }
      }

      "child" -> {
        val dirUri = call.argument<String>("dirUri")!!
        val names = call.argument<List<String>>("names")!!
        run(result, dirUri) { SafDocs.child(context, Uri.parse(dirUri), names) }
      }

      "mkdirp" -> {
        val dirUri = call.argument<String>("dirUri")!!
        val names = call.argument<List<String>>("names")!!
        run(result, dirUri) { SafDocs.mkdirp(context, Uri.parse(dirUri), names) }
      }

      "delete" -> {
        val uri = call.argument<String>("uri")!!
        run(result, uri) { SafDocs.delete(context, Uri.parse(uri)); null }
      }

      "rename" -> {
        val uri = call.argument<String>("uri")!!
        val newName = call.argument<String>("newName")!!
        run(result, uri) {
          val renamed = SafDocs.rename(context, Uri.parse(uri), newName)
          SafDocs.stat(context, renamed) ?: throw SafNotFoundException("Renamed doc missing")
        }
      }

      "copyTo" -> copyOrMove(call, result, move = false)
      "moveTo" -> copyOrMove(call, result, move = true)

      "readFileBytes" -> {
        val uri = call.argument<String>("uri")!!
        val start = call.argument<Number>("start")?.toLong() ?: 0L
        val count = call.argument<Number>("count")?.toInt()
        run(result, uri) {
          val input = context.contentResolver.openInputStream(Uri.parse(uri))
            ?: throw SafNotFoundException("Cannot open $uri")
          input.use { ins ->
            skipFully(ins, start)
            if (count == null) ins.readBytes()
            else {
              val buf = ByteArray(count)
              var off = 0
              while (off < count) {
                val n = ins.read(buf, off, count - off)
                if (n < 0) break
                off += n
              }
              buf.copyOf(off)
            }
          }
        }
      }

      "readFileStream" -> {
        val uri = call.argument<String>("uri")!!
        val start = call.argument<Number>("start")?.toLong() ?: 0L
        val bufferSize = call.argument<Number>("bufferSize")!!.toInt()
        val (session, sink) = sessions!!.create()
        result.success(session)
        scope.launch {
          try {
            val input = context.contentResolver.openInputStream(Uri.parse(uri))
              ?: throw SafNotFoundException("Cannot open $uri")
            input.use { ins ->
              skipFully(ins, start)
              val buf = ByteArray(bufferSize)
              while (!sink.cancelled) {
                val n = ins.read(buf)
                if (n < 0) break
                sink.success(buf.copyOf(n))
              }
            }
            sink.endOfStream()
          } catch (e: Throwable) {
            sink.error(errorCodeOf(e), e.message ?: e.toString(), mapOf("uri" to uri))
            sink.endOfStream()
          }
        }
      }

      "startWalk" -> {
        val dirUri = call.argument<String>("dirUri")!!
        val (session, sink) = sessions!!.create()
        result.success(session)
        scope.launch {
          try {
            val stack = ArrayDeque<Pair<Uri, String>>()
            stack.addLast(Uri.parse(dirUri) to "")
            while (stack.isNotEmpty() && !sink.cancelled) {
              val (dir, prefix) = stack.removeLast()
              for (kid in SafDocs.listChildren(context, dir)) {
                if (sink.cancelled) break
                val rel = if (prefix.isEmpty()) kid["name"] as String
                          else "$prefix/${kid["name"]}"
                sink.success(mapOf("file" to kid, "relativePath" to rel))
                if (kid["isDir"] == true) {
                  stack.addLast(Uri.parse(kid["uri"] as String) to rel)
                }
              }
            }
            sink.endOfStream()
          } catch (e: Throwable) {
            sink.error(errorCodeOf(e), e.message ?: e.toString(), mapOf("uri" to dirUri))
            sink.endOfStream()
          }
        }
      }

      "writeFileBytes" -> {
        val dirUri = call.argument<String>("dirUri")!!
        val name = call.argument<String>("name")!!
        val mime = call.argument<String>("mime")!!
        val data = call.argument<ByteArray>("data")!!
        val overwrite = call.argument<Boolean>("overwrite") ?: false
        val append = call.argument<Boolean>("append") ?: false
        run(result, dirUri) {
          val target = resolveWriteTarget(dirUri, name, mime, overwrite, append)
          val mode = if (append) "wa" else "wt"
          val out = context.contentResolver.openOutputStream(target, mode)
            ?: throw Exception("Cannot open output $target")
          out.use { it.write(data); it.flush() }
          SafDocs.stat(context, target) ?: throw SafNotFoundException("Written doc missing")
        }
      }

      "startWriteStream" -> {
        val dirUri = call.argument<String>("dirUri")!!
        val name = call.argument<String>("name")!!
        val mime = call.argument<String>("mime")!!
        val overwrite = call.argument<Boolean>("overwrite") ?: false
        val append = call.argument<Boolean>("append") ?: false
        run(result, dirUri) {
          val target = resolveWriteTarget(dirUri, name, mime, overwrite, append)
          val mode = if (append) "wa" else "wt"
          val out = context.contentResolver.openOutputStream(target, mode)
            ?: throw Exception("Cannot open output $target")
          val id = synchronized(writeSessions) {
            val id = "w${writeCounter++}"
            writeSessions[id] =
              WriteSession(out, target, Executors.newSingleThreadExecutor())
            id
          }
          id
        }
      }

      "writeChunk" -> {
        val id = call.argument<String>("session")!!
        val data = call.argument<ByteArray>("data")!!
        val session = synchronized(writeSessions) { writeSessions[id] }
        if (session == null) {
          result.safError(SafNotFoundException("No write session $id"), null)
        } else {
          session.executor.execute {
            try {
              session.stream.write(data)
              main.post { result.success(null) }
            } catch (e: Throwable) {
              main.post { result.safError(e, session.uri.toString()) }
            }
          }
        }
      }

      "endWriteStream" -> {
        val id = call.argument<String>("session")!!
        val session = synchronized(writeSessions) { writeSessions.remove(id) }
        if (session == null) {
          result.safError(SafNotFoundException("No write session $id"), null)
        } else {
          session.executor.execute {
            try {
              session.stream.flush()
              session.stream.close()
              val map = SafDocs.stat(context, session.uri)
              main.post {
                if (map == null) {
                  result.safError(SafNotFoundException("Written doc missing"), session.uri.toString())
                } else {
                  result.success(map)
                }
              }
            } catch (e: Throwable) {
              main.post { result.safError(e, session.uri.toString()) }
            } finally {
              session.executor.shutdown()
            }
          }
        }
      }

      "abortWriteStream" -> {
        val id = call.argument<String>("session")!!
        val session = synchronized(writeSessions) { writeSessions.remove(id) }
        if (session == null) {
          result.success(null)
        } else {
          session.executor.execute {
            runCatching { session.stream.close() }
            runCatching { SafDocs.delete(context, session.uri) }
            session.executor.shutdown()
            main.post { result.success(null) }
          }
        }
      }

      "copyToLocalFile" -> {
        val srcUri = call.argument<String>("srcUri")!!
        val destPath = call.argument<String>("destPath")!!
        val withProgress = call.argument<Boolean>("withProgress") ?: false
        progressOp(result, withProgress, srcUri) { emit ->
          val total = SafDocs.stat(context, Uri.parse(srcUri))?.get("length") as? Long
          val name = File(destPath).name
          val input = context.contentResolver.openInputStream(Uri.parse(srcUri))
            ?: throw SafNotFoundException("Cannot open $srcUri")
          input.use { ins ->
            FileOutputStream(destPath).use { outs ->
              val buf = ByteArray(1 shl 16)
              var done = 0L
              while (true) {
                val n = ins.read(buf)
                if (n < 0) break
                outs.write(buf, 0, n)
                done += n
                emit?.invoke(done, total, name)
              }
            }
          }
          null
        }
      }

      "pasteLocalFile" -> {
        val srcPath = call.argument<String>("srcPath")!!
        val destDirUri = call.argument<String>("destDirUri")!!
        val name = call.argument<String>("name")!!
        val mime = call.argument<String>("mime")!!
        val overwrite = call.argument<Boolean>("overwrite") ?: false
        val withProgress = call.argument<Boolean>("withProgress") ?: false
        progressOp(result, withProgress, destDirUri) { emit ->
          val src = File(srcPath)
          if (!src.exists()) throw SafNotFoundException("No local file $srcPath")
          val total = src.length()
          val target = resolveWriteTarget(destDirUri, name, mime, overwrite, append = false)
          FileInputStream(src).use { ins ->
            val out = context.contentResolver.openOutputStream(target, "wt")
              ?: throw Exception("Cannot open output $target")
            out.use { outs ->
              val buf = ByteArray(1 shl 16)
              var done = 0L
              while (true) {
                val n = ins.read(buf)
                if (n < 0) break
                outs.write(buf, 0, n)
                done += n
                emit?.invoke(done, total, name)
              }
              outs.flush()
            }
          }
          SafDocs.stat(context, target) ?: throw SafNotFoundException("Pasted doc missing")
        }
      }

      else -> result.notImplemented()
    }
  }

  /** Existing-child + overwrite/append/auto-rename resolution for writes. */
  private fun resolveWriteTarget(
    dirUri: String,
    name: String,
    mime: String,
    overwrite: Boolean,
    append: Boolean,
  ): Uri {
    val dir = Uri.parse(dirUri)
    val existing = SafDocs.child(context, dir, listOf(name))
    return when {
      existing != null && (overwrite || append) -> Uri.parse(existing["uri"] as String)
      else -> SafDocs.createFile(context, dir, mime, name)
    }
  }

  /**
   * Runs [block] either as a plain call (progress emitter null) or as a
   * progress session that returns the session id immediately and reports
   * {progress,done} events, throttled to [PROGRESS_INTERVAL_MS].
   */
  private fun progressOp(
    result: MethodChannel.Result,
    withProgress: Boolean,
    uri: String,
    block: (emit: ((Long, Long?, String) -> Unit)?) -> Any?,
  ) {
    if (!withProgress) {
      run(result, uri) { block(null) }
      return
    }
    val (session, sink) = sessions!!.create()
    result.success(session)
    scope.launch {
      try {
        var lastEmit = 0L
        val file = block { done, total, name ->
          val now = System.currentTimeMillis()
          if (now - lastEmit >= PROGRESS_INTERVAL_MS) {
            lastEmit = now
            sink.success(mapOf(
              "type" to "progress",
              "bytesDone" to done,
              "totalBytes" to total,
              "currentName" to name,
            ))
          }
        }
        sink.success(mapOf("type" to "done", "file" to file))
        sink.endOfStream()
      } catch (e: Throwable) {
        sink.error(errorCodeOf(e), e.message ?: e.toString(), mapOf("uri" to uri))
        sink.endOfStream()
      }
    }
  }

  private fun copyOrMove(call: MethodCall, result: MethodChannel.Result, move: Boolean) {
    val uriStr = call.argument<String>("uri")!!
    val destDirStr = call.argument<String>("destDirUri")!!
    val withProgress = call.argument<Boolean>("withProgress") ?: false
    progressOp(result, withProgress, uriStr) { emit ->
      val srcMap = SafDocs.stat(context, Uri.parse(uriStr))
        ?: throw SafNotFoundException("Source missing: $uriStr")
      var cumulative = 0L
      val copied = copyRecursive(srcMap, Uri.parse(destDirStr)) { fileDone, name, fileTotal ->
        emit?.invoke(cumulative + fileDone,
          if (srcMap["isDir"] == true) null else fileTotal, name)
      }.also { root ->
        // Track cumulative bytes across files for directory copies.
        cumulative = 0L
        root
      }
      if (move) SafDocs.delete(context, Uri.parse(uriStr))
      copied
    }
  }

  /**
   * Copies [srcMap] (file or directory) into [destDir]; returns the map of the
   * created root document. [onFileProgress] gets per-file byte counts.
   */
  private fun copyRecursive(
    srcMap: Map<String, Any?>,
    destDir: Uri,
    onFileProgress: (done: Long, name: String, total: Long?) -> Unit,
  ): Map<String, Any?> {
    val name = srcMap["name"] as String
    return if (srcMap["isDir"] == true) {
      val newDir = SafDocs.mkdirp(context, destDir, listOf(name))
      for (kid in SafDocs.listChildren(context, Uri.parse(srcMap["uri"] as String))) {
        copyRecursive(kid, Uri.parse(newDir["uri"] as String), onFileProgress)
      }
      newDir
    } else {
      val mime = srcMap["mimeType"] as? String ?: "application/octet-stream"
      val target = SafDocs.createFile(context, destDir, mime, name)
      val total = srcMap["length"] as? Long
      SafDocs.copyContents(context, Uri.parse(srcMap["uri"] as String), target) { done ->
        onFileProgress(done, name, total)
      }
      SafDocs.stat(context, target) ?: throw SafNotFoundException("Copied doc missing")
    }
  }

  // Pickers -------------------------------------------------------------------

  private fun startPick(code: Int, call: MethodCall, result: MethodChannel.Result) {
    val act = activity
    if (act == null) {
      result.safError(Exception("Plugin not attached to an Activity"), null)
      return
    }
    synchronized(pendingPicks) {
      if (pendingPicks.containsKey(code)) {
        result.safError(Exception("Another picker is already open"), null)
        return
      }
      pendingPicks[code] = call to result
    }
    val intent = when (code) {
      PICK_DIRECTORY_CODE -> Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
      else -> Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = "*/*"
        val mimeTypes = call.argument<List<String>>("mimeTypes")
        if (!mimeTypes.isNullOrEmpty()) {
          putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
        }
        if (code == PICK_FILES_CODE) putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
      }
    }
    val initialUri = call.argument<String>("initialUri")
    if (initialUri != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(initialUri))
    }
    act.startActivityForResult(intent, code)
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    val pending = synchronized(pendingPicks) { pendingPicks.remove(requestCode) } ?: return false
    val (call, result) = pending
    if (resultCode != Activity.RESULT_OK || data == null) {
      main.post {
        result.success(if (requestCode == PICK_FILES_CODE) emptyList<Any>() else null)
      }
      return true
    }
    val persistable = call.argument<Boolean>("persistablePermission") ?: false
    val write = call.argument<Boolean>("writePermission") ?: true
    scope.launch {
      try {
        val value: Any? = when (requestCode) {
          PICK_DIRECTORY_CODE -> {
            val tree = data.data!!
            if (persistable) takePersistable(tree, write)
            SafDocs.stat(context, tree)
          }
          PICK_FILE_CODE -> {
            val uri = data.data!!
            if (persistable) takePersistable(uri, write = true)
            SafDocs.stat(context, uri)
          }
          else -> {
            val uris = mutableListOf<Uri>()
            val clip = data.clipData
            if (clip != null) {
              for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
            } else {
              data.data?.let { uris.add(it) }
            }
            uris.mapNotNull { uri ->
              if (persistable) takePersistable(uri, write = true)
              SafDocs.stat(context, uri)
            }
          }
        }
        main.post { result.success(value) }
      } catch (e: Throwable) {
        main.post { result.safError(e, data.data?.toString()) }
      }
    }
    return true
  }

  private fun takePersistable(uri: Uri, write: Boolean) {
    var flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
    if (write) flags = flags or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    runCatching { context.contentResolver.takePersistableUriPermission(uri, flags) }
  }

  private fun skipFully(input: java.io.InputStream, count: Long) {
    var remaining = count
    while (remaining > 0) {
      val skipped = input.skip(remaining)
      if (skipped <= 0) break
      remaining -= skipped
    }
  }
}
```

- [ ] **Step 2: Wire into `SafPlugin.kt`**

Apply exactly these edits to `android/src/main/kotlin/com/ivehement/saf/SafPlugin.kt`:

Add import (after the existing imports):

```kotlin
import com.ivehement.saf.v2.SafV2Api
```

Add a field below `private val storageAccessFrameworkApi = StorageAccessFramework(this)`:

```kotlin
    /** v2 single-class API channel */
    private var safV2Api: SafV2Api? = null
```

In `onAttachedToEngine`, after `storageAccessFrameworkApi.startListening(...)`:

```kotlin
      safV2Api = SafV2Api(this)
      safV2Api?.startListening(flutterPluginBinding.binaryMessenger)
```

In `onAttachedToActivity`, after `storageAccessFrameworkApi.startListeningToActivity()`:

```kotlin
      safV2Api?.let { binding.addActivityResultListener(it) }
```

In `onDetachedFromEngine`, after `storageAccessFrameworkApi.stopListening()`:

```kotlin
      safV2Api?.stopListening()
      safV2Api = null
```

In `onReattachedToActivityForConfigChanges`, after `this.binding = binding`:

```kotlin
      safV2Api?.let { binding.addActivityResultListener(it) }
```

- [ ] **Step 3: Verify the coroutines dependency exists**

`android/build.gradle` already contains
`implementation "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0"` — no change needed.

- [ ] **Step 4: Commit**

```bash
git add android/src/main/kotlin/com/ivehement/saf/v2/SafV2Api.kt android/src/main/kotlin/com/ivehement/saf/SafPlugin.kt
git commit -m "feat(v2): Kotlin SafV2Api handler wired into the plugin"
```

---

### Task 15: version bump, constraints, full-suite + APK compile check

**Files:**
- Modify: `pubspec.yaml` (version + environment)

- [ ] **Step 1: Update `pubspec.yaml`**

Change:

```yaml
version: 2.0.0

environment:
  sdk: ">=3.0.0 <4.0.0"
  flutter: ">=3.10.0"
```

(keep everything else, including `plugin_platform_interface: ^2.1.8`).

- [ ] **Step 2: Full Dart verification**

Run: `flutter pub get && flutter analyze && flutter test && dart format --output=none --set-exit-if-changed .`
Expected: analyze `No issues found!`; all tests PASS; format clean.

- [ ] **Step 3: Compile the Kotlin side**

Run: `cd example && flutter build apk --debug && cd ..`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`. This is the
compile-level proof for Tasks 12–14. Fix any Kotlin compile errors now.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml
git commit -m "chore(v2): version 2.0.0, Dart >=3.0 / Flutter >=3.10"
```

---

### Task 16: example kitchen-sink app

**Files:**
- Rewrite: `example/lib/main.dart`

- [ ] **Step 1: Replace `example/lib/main.dart` entirely**

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:saf/saf.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'saf 2.0 demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _saf = Saf();
  SafDocumentFile? _dir;
  List<SafDocumentFile> _children = const [];
  final _log = <String>[];
  double? _progress;

  void _print(String line) => setState(() => _log.insert(0, line));

  Future<void> _guard(String label, Future<void> Function() op) async {
    try {
      await op();
    } on SafException catch (e) {
      _print('✗ $label: $e');
    } catch (e) {
      _print('✗ $label: $e');
    }
  }

  Future<void> _pickDirectory() => _guard('pick', () async {
        final dir = await _saf.pickDirectory();
        if (dir == null) {
          _print('picker cancelled');
          return;
        }
        setState(() => _dir = dir);
        _print('✓ picked ${dir.name}');
        await _refresh();
      });

  Future<void> _refresh() => _guard('list', () async {
        final kids = await _saf.list(_dir!.uri);
        setState(() => _children = kids);
        _print('✓ listed ${kids.length} entries');
      });

  Future<void> _restorePermission() => _guard('restore', () async {
        final grants = await _saf.persistedPermissions();
        if (grants.isEmpty) {
          _print('no persisted permissions');
          return;
        }
        final dir = await _saf.stat(grants.first.uri);
        if (dir == null) {
          _print('persisted grant points at a missing document');
          return;
        }
        setState(() => _dir = dir);
        _print('✓ restored ${dir.name} without prompting');
        await _refresh();
      });

  Future<void> _writeDemoFiles() => _guard('write', () async {
        final bytes = Uint8List.fromList(utf8.encode('Hello from saf 2.0!\n'));
        final f1 = await _saf.writeFileBytes(
            _dir!.uri, 'saf-demo.txt', 'text/plain', bytes,
            overwrite: true);
        _print('✓ wrote ${f1.name} (${f1.length} B)');
        final chunks =
            Stream.fromIterable(List.generate(50, (i) => utf8.encode('line $i\n')));
        final f2 = await _saf.writeFileStream(
            _dir!.uri, 'saf-demo-stream.txt', 'text/plain', chunks,
            overwrite: true);
        _print('✓ streamed ${f2.name} (${f2.length} B)');
        await _refresh();
      });

  Future<void> _readBack() => _guard('read', () async {
        final f = await _saf.child(_dir!.uri, ['saf-demo.txt']);
        if (f == null) {
          _print('saf-demo.txt not found — write first');
          return;
        }
        final bytes = await _saf.readFileBytes(f.uri);
        _print('✓ read ${bytes.length} B: '
            '"${utf8.decode(bytes).trim()}"');
        final stream = await _saf.readFileStream(f.uri, bufferSize: 8);
        final n = (await stream.toList()).length;
        _print('✓ read again as $n stream chunks');
      });

  Future<void> _walk() => _guard('walk', () async {
        var count = 0;
        await for (final entry in _saf.walk(_dir!.uri)) {
          count++;
          if (count <= 5) _print('  ${entry.relativePath}');
        }
        _print('✓ walked $count descendants (first 5 shown)');
      });

  Future<void> _copyWithProgress() => _guard('copy', () async {
        final f = await _saf.child(_dir!.uri, ['saf-demo.txt']);
        if (f == null) {
          _print('saf-demo.txt not found — write first');
          return;
        }
        final backups = await _saf.mkdirp(_dir!.uri, ['saf-backups']);
        final copied = await _saf.copyTo(f.uri, backups.uri, onProgress: (p) {
          setState(() => _progress =
              p.totalBytes == null ? null : p.bytesDone / p.totalBytes!);
        });
        setState(() => _progress = null);
        _print('✓ copied to saf-backups/${copied.name}');
        await _refresh();
      });

  Future<void> _cleanUp() => _guard('delete', () async {
        for (final name in ['saf-demo.txt', 'saf-demo-stream.txt', 'saf-backups']) {
          final f = await _saf.child(_dir!.uri, [name]);
          if (f != null) await _saf.delete(f.uri);
        }
        _print('✓ demo files deleted');
        await _refresh();
      });

  @override
  Widget build(BuildContext context) {
    final hasDir = _dir != null;
    return Scaffold(
      appBar: AppBar(title: const Text('saf 2.0 kitchen sink')),
      body: Column(
        children: [
          if (_progress != null) LinearProgressIndicator(value: _progress),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                    onPressed: _pickDirectory, child: const Text('Pick dir')),
                FilledButton.tonal(
                    onPressed: _restorePermission,
                    child: const Text('Restore permission')),
                FilledButton.tonal(
                    onPressed: hasDir ? _writeDemoFiles : null,
                    child: const Text('Write')),
                FilledButton.tonal(
                    onPressed: hasDir ? _readBack : null,
                    child: const Text('Read')),
                FilledButton.tonal(
                    onPressed: hasDir ? _walk : null, child: const Text('Walk')),
                FilledButton.tonal(
                    onPressed: hasDir ? _copyWithProgress : null,
                    child: const Text('Copy+progress')),
                FilledButton.tonal(
                    onPressed: hasDir ? _cleanUp : null,
                    child: const Text('Clean up')),
              ],
            ),
          ),
          if (hasDir)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('${_dir!.name} — ${_children.length} entries',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final f in _children)
                  ListTile(
                    dense: true,
                    leading: Icon(f.isDir ? Icons.folder : Icons.description),
                    title: Text(f.name),
                    subtitle: Text(f.isDir
                        ? 'directory'
                        : '${f.length} B · ${f.mimeType ?? 'unknown'}'),
                  ),
                const Divider(),
                for (final line in _log)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 2),
                    child: Text(line,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Remove the example's `permission_handler` dependency**

The v2 API needs no runtime permissions. In `example/pubspec.yaml` delete the
line `permission_handler: ^12.0.3`, then run `cd example && flutter pub get`.

- [ ] **Step 3: Verify**

Run: `flutter analyze && flutter test && cd example && flutter build apk --debug && cd ..`
Expected: analyze clean (the `ignore_for_file: deprecated_member_use` comment
is gone along with all `LegacySaf` usage), tests pass, APK builds.

- [ ] **Step 4: Commit**

```bash
git add example/lib/main.dart example/pubspec.yaml example/pubspec.lock
git commit -m "feat(v2): kitchen-sink example exercising the whole API"
```

---

### Task 17: docs — README, CHANGELOG, manual checklist

**Files:**
- Rewrite: `README.md` (Usage + Documentation sections; keep banner/badges header)
- Modify: `CHANGELOG.md` (prepend 2.0.0)
- Create: `docs/testing/manual-checklist.md`

- [ ] **Step 1: Rewrite `README.md` from the `# Saf` heading down**

Keep lines 1–13 (banner + badges `<p align="center">...</p>`) untouched.
Replace everything from `# Saf` to the end of the file with:

````markdown
# Saf

One package for the Android Storage Access Framework: pickers, persisted
permissions, file management with recursive walk, streamed read/write with
progress, and local-file bridging — a single `Saf` class that replaces the
`saf_stream` + `saf_util` combination.

## Why saf

| | saf 2.x | saf_stream + saf_util |
| --- | --- | --- |
| Packages needed | **1** | 2 |
| Typed exceptions (`SafNotFoundException`, …) | **yes** | no (raw `PlatformException`) |
| Recursive `walk()` stream | **yes** | no |
| Recursive copy/move with progress callbacks | **yes** | no |
| One-call `writeFileStream` | **yes** | 3-call session dance |
| `isDir` parameters you must supply | **none** | required on most calls |
| List persisted permissions | **yes** | no |
| Dart / Flutter minimum | **3.0 / 3.10** | 3.12 / 3.44 |
| Min Android SDK | 21 | 21 |

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

### From saf_stream / saf_util

Near find-and-replace — method names were kept where sensible:

| saf_stream / saf_util | saf 2.x |
| --- | --- |
| `SafStream().readFileBytes(uri)` | `Saf().readFileBytes(uri)` |
| `SafStream().readFileStream(uri)` | `Saf().readFileStream(uri)` |
| `SafStream().writeFileBytes(dir, name, mime, data)` | `Saf().writeFileBytes(dir, name, mime, data)` |
| `startWriteStream` / `writeChunk` / `endWriteStream` | one call: `Saf().writeFileStream(dir, name, mime, stream)` |
| `SafStream().copyToLocalFile(src, dest)` | `Saf().copyToLocalFile(src, dest)` |
| `SafStream().pasteLocalFile(src, dir, name, mime)` | `Saf().pasteLocalFile(src, dir, name, mime)` |
| `SafUtil().pickDirectory(persistablePermission: …)` | `Saf().pickDirectory(persistablePermission: …)` |
| `SafUtil().pickFile()` / `pickFiles()` | `Saf().pickFile()` / `pickFiles()` |
| `SafUtil().list(uri)` | `Saf().list(uri)` |
| `SafUtil().stat(uri, isDir)` | `Saf().stat(uri)` — no `isDir` needed |
| `SafUtil().exists(uri, isDir)` | `Saf().exists(uri)` |
| `SafUtil().mkdirp(uri, names)` | `Saf().mkdirp(uri, names)` |
| `SafUtil().child(uri, names)` | `Saf().child(uri, names)` |
| `SafUtil().rename(uri, isDir, newName)` | `Saf().rename(uri, newName)` |
| `SafUtil().copyTo(uri, isDir, dest)` | `Saf().copyTo(uri, dest)` — recursive + progress |
| `SafUtil().moveTo(uri, isDir, parent, dest)` | `Saf().moveTo(uri, dest)` |
| `SafUtil().hasPersistedPermission(uri)` | check `Saf().persistedPermissions()` |
| `SafUtil().releasePersistedPermission(uri)` | `Saf().releasePersistedPermission(uri)` |

## What we deliberately don't include (and why)

Public-GitHub usage analysis showed several competitor APIs have ~zero
real-world users, so `saf` keeps its surface small on purpose:

- **Custom read sessions** (`readCustomFileStreamChunk` etc.) — ~4 public
  usages; `readFileStream(start: …)` covers seeking.
- **`readFileSync` / `writeFileSync`** — not actually synchronous; duplicates.
- **`openDirectory` / `openFile` variants** — URI-only duplicates of `pick*`.
- **Media picker** — `image_picker` / `photo_manager` do this better.
- **File descriptors, thumbnails** — niche; file an issue if you need them
  and they'll ship in a 2.1+.

## Documentation

- **[Documentation site](https://jvoltci.github.io/saf/)** — full API reference.
- **[Saf class reference](https://jvoltci.github.io/saf/saf/Saf-class.html)** — all 21 methods.

## Getting Started with Flutter

For help getting started with Flutter, view the online
[documentation](https://docs.flutter.dev/).
````

- [ ] **Step 2: Prepend to `CHANGELOG.md`**

```markdown
## 2.0.0

**One class for everything SAF.** The new `Saf` class replaces the
`saf_stream` + `saf_util` combination: pickers, persisted permissions, file
management, recursive `walk()`, byte/stream read-write with progress
callbacks, and local-file bridging — 21 methods, typed exceptions, no `isDir`
parameters.

**BREAKING:** the legacy path-based class is renamed `LegacySaf`
(deprecated, removal in 3.0.0). Its behavior is unchanged — existing code
only needs `Saf(` → `LegacySaf(`.

- New: `pickDirectory`/`pickFile`/`pickFiles` with initial URI and
  persistable permissions; `persistedPermissions()` listing.
- New: `list` (single-cursor, fast), `stat`, `exists`, `child`, `mkdirp`,
  `delete`, `rename`, recursive `copyTo`/`moveTo` with progress, `walk()`.
- New: `readFileBytes`/`readFileStream`, `writeFileBytes`, one-call
  `writeFileStream`, `copyToLocalFile`/`pasteLocalFile`.
- New: sealed `SafException` hierarchy (`permission` / `not_found` /
  `already_exists` / `io`).
- Broad support: Dart >=3.0, Flutter >=3.10, Android minSdk 21.
```

- [ ] **Step 3: Create `docs/testing/manual-checklist.md`**

```markdown
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
```

- [ ] **Step 4: Full verification battery**

Run:
```bash
flutter analyze && flutter test && dart format --output=none --set-exit-if-changed . && rm -rf /tmp/safdoc && dart doc --output /tmp/safdoc 2>&1 | tail -2 && dart pub global run pana --no-dartdoc . 2>&1 | grep '^Points'
```
Expected: analyze clean; tests pass; format clean; `Found 0 warnings and 0 errors.`; `Points: 150/150.`

- [ ] **Step 5: Commit**

```bash
git add README.md CHANGELOG.md docs/testing/manual-checklist.md
git commit -m "docs: 2.0.0 README with migration tables, changelog, manual checklist"
```

---

### Task 18: push branch + open PR

- [ ] **Step 1: Push**

```bash
git push -u origin saf-v2
```

- [ ] **Step 2: Open the PR**

```bash
gh pr create --base master --head saf-v2 \
  --title "saf 2.0.0: single-class SAF API (parity with saf_stream+saf_util, and beyond)" \
  --body "Implements the approved spec (docs/superpowers/specs/2026-07-18-saf-v2-api-design.md).

One Saf class, 21 methods: pickers + persisted permissions, file management with recursive walk, byte/stream read-write with progress, local-file bridge. Typed SafException hierarchy. Legacy API preserved as deprecated LegacySaf.

Verification: analyze 0, full unit suite green, dart doc 0 warnings, pana 150/150, example APK builds. On-device behavior requires docs/testing/manual-checklist.md before publishing to pub.dev."
```

- [ ] **Step 3: Hand off to the owner**

Do NOT merge and do NOT publish. Report: PR URL, verification results, and
that `docs/testing/manual-checklist.md` gates the pub.dev release.

---

## Plan self-review (completed at authoring time)

- **Spec coverage:** all 21 spec methods appear in Tasks 4–9 (Dart) and 14
  (Kotlin); models §5 → Task 1; exceptions §7 → Task 2 + 12; architecture §3
  → Tasks 3, 12–14; example/testing §9 → Tasks 15–17; docs §10 → Task 17;
  versioning §2 → Tasks 11, 15. Spec's `moveDocument` fast path is simplified
  to copy+delete (documented in facade dartdoc), which the spec's risk
  section explicitly allows.
- **Placeholders:** none — every code step contains complete code.
- **Type consistency:** doc-map keys (`uri,name,isDir,length,lastModified,mimeType`)
  match `SafDocumentFile.fromMap`, `SafDocs.rowToMap`, and all tests; error
  codes (`permission,not_found,already_exists,io`) match `exceptions.dart`
  and `SafErrors.kt`; channel names/`eventsPrefix` match between
  `MethodChannelSaf` and `SessionManager`.
