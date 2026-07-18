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
}
