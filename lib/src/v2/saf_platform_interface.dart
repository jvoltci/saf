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
