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

  /// Copies the files directly inside [dirUri] into the local directory
  /// [destDirPath] (which must already exist — e.g. your app's
  /// `getExternalStorageDirectory()`), returning the local paths written.
  ///
  /// Restores the classic "cache a granted folder into my app" workflow —
  /// e.g. pulling WhatsApp `.Statuses` out so they can be saved or shared.
  /// Only top-level files are copied (sub-directories are skipped). Built on
  /// [list] + [copyToLocalFile].
  Future<List<String>> copyDirToLocal(String dirUri, String destDirPath) async {
    final written = <String>[];
    for (final f in await list(dirUri)) {
      if (f.isDir) continue;
      final dest = '$destDirPath/${f.name}';
      await copyToLocalFile(f.uri, dest);
      written.add(dest);
    }
    return written;
  }

  // File descriptor & thumbnail ---------------------------------------------

  /// Opens a native file descriptor for [uri] in [mode] (one of `r`, `w`,
  /// `rw`, `wt`), returning its raw [SafOpenFd.fd] and `/proc/self/fd/<fd>`
  /// path for handing to path-based/native APIs.
  ///
  /// The descriptor stays open until you call [closeFileDescriptor]; prefer
  /// [withFileDescriptor] to guarantee it is closed.
  Future<SafOpenFd> openFileDescriptor(String uri, String mode) =>
      _p.openFileDescriptor(uri, mode);

  /// Closes a file descriptor previously opened by [openFileDescriptor].
  ///
  /// Idempotent: closing an unknown or already-closed [fd] is a no-op.
  Future<void> closeFileDescriptor(int fd) => _p.closeFileDescriptor(fd);

  /// Requests a provider-generated thumbnail for [uri], sized up to
  /// [width]x[height] and JPEG-encoded at [quality] (0-100).
  ///
  /// Returns the raw JPEG bytes, or `null` when the provider has no thumbnail.
  Future<Uint8List?> thumbnail(String uri, int width, int height, int quality) =>
      _p.thumbnail(uri, width, height, quality);

  /// Opens a file descriptor for [uri] in [mode], runs [action] with it, and
  /// always closes the descriptor afterwards — even if [action] throws.
  Future<T> withFileDescriptor<T>(
      String uri, String mode, Future<T> Function(SafOpenFd) action) async {
    final descriptor = await openFileDescriptor(uri, mode);
    try {
      return await action(descriptor);
    } finally {
      await closeFileDescriptor(descriptor.fd);
    }
  }
}
