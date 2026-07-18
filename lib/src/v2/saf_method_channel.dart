// lib/src/v2/saf_method_channel.dart
import 'dart:async';

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

  SafDocumentFile _doc(dynamic map) =>
      SafDocumentFile.fromMap(Map<String, dynamic>.from(map as Map));

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

  // Streams ------------------------------------------------------------------

  Stream<dynamic> _sessionEvents(String session) =>
      EventChannel('$eventsPrefix$session')
          .receiveBroadcastStream()
          .handleError(
            (Object e) => throw mapPlatformException(e as PlatformException),
            test: (e) => e is PlatformException,
          );

  @override
  Future<Stream<Uint8List>> readFileStream(String uri,
      {int? start, int bufferSize = 4194304}) async {
    final session = await _invoke<String>('openReadSession',
        {'uri': uri, 'start': start, 'bufferSize': bufferSize});
    return _pullReadChunks(session!);
  }

  /// Pull-based read: request the next chunk only after the consumer is ready,
  /// so the native side never reads ahead (backpressure, no unbounded buffer).
  Stream<Uint8List> _pullReadChunks(String session) async* {
    try {
      while (true) {
        final chunk =
            await _invoke<Uint8List>('readSessionChunk', {'session': session});
        if (chunk == null) break; // null => end of stream
        yield chunk;
      }
    } finally {
      await _invoke<void>('closeReadSession', {'session': session});
    }
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

  // File descriptor & thumbnail ---------------------------------------------

  @override
  Future<SafOpenFd> openFileDescriptor(String uri, String mode) async {
    final m = await _invoke<Map>('openFileDescriptor', {'uri': uri, 'mode': mode});
    return SafOpenFd.fromMap(Map<String, dynamic>.from(m!));
  }

  @override
  Future<void> closeFileDescriptor(int fd) =>
      _invoke<void>('closeFileDescriptor', {'fd': fd});

  @override
  Future<Uint8List?> thumbnail(String uri, int width, int height, int quality) =>
      _invoke<Uint8List>('thumbnail', {
        'uri': uri,
        'width': width,
        'height': height,
        'quality': quality,
      });
}
