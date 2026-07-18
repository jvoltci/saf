import 'dart:typed_data';

import 'package:saf/src/storage_access_framework/api.dart';
import 'package:saf/src/storage_access_framework/api.dart' as api;
import 'package:saf/src/channels.dart';

/// The legacy 1.x path-based API.
///
/// Superseded by the URI-based `Saf` class in 2.0.0,
/// which follows SAF semantics correctly. This class is unchanged from 1.x
/// and will be removed in 3.0.0.
@Deprecated('Use the new Saf class instead. LegacySaf will be removed in 3.0.0')
class LegacySaf {
  String? _uriString;
  String _directory;
  LegacySaf(this._directory) {
    _uriString = makeUriString(path: _directory, isTreeUri: true);
  }

  /// Request the user for access to `Directory Permission`, if access hasn't already
  /// been grant access before.
  ///
  /// When [isDynamic] is `false` the picker opens at the directory this instance
  /// was created for; when `true` it simply lets the user pick any directory.
  /// In both cases the permission the user actually grants is adopted, so a
  /// previously granted directory is reused on later launches instead of
  /// re-prompting every time.
  ///
  /// Returns [bool].
  Future<bool?> getDirectoryPermission(
      {bool grantWritePermission = true, bool isDynamic = false}) async {
    try {
      /// Reuse an existing persisted permission for this directory if present.
      /// Matching is done against the URIs the OS actually granted (not a
      /// reconstructed string), which is why access is now remembered across
      /// app restarts. (#27, #34)
      if (await _adoptPersistedPermission()) return true;

      const kOpenDocumentTree = 'openDocumentTree';
      const kGrantWritePermission = 'grantWritePermission';
      const kInitialUri = 'initialUri';

      /// Initial location of native file explorer
      /// when user is prompted to chose the directory
      String initialUri = makeUriString(path: _directory);

      final args = <String, dynamic>{
        kGrantWritePermission: grantWritePermission,
        kInitialUri: initialUri
      };

      /// Get the URI of user selected Directory path
      final selectedDirectoryUri = await kDocumentFileChannel
          .invokeMethod<String?>(kOpenDocumentTree, args);

      /// User dismissed the picker without choosing anything.
      if (selectedDirectoryUri == null) return false;

      /// Adopt the directory the user actually granted. Previously this only
      /// happened for `isDynamic: true`, so `isDynamic: false` always compared
      /// the granted URI against a reconstructed one that never matched, then
      /// released the grant and returned false. (#8)
      _uriString = selectedDirectoryUri;
      _directory = makeDirectoryPath(selectedDirectoryUri);

      return true;
    } catch (e) {
      return null;
    }
  }

  /// If the OS already holds a persisted permission whose directory matches
  /// [_directory], adopt its (real) URI and return `true`.
  Future<bool> _adoptPersistedPermission() async {
    final uriPermissions = await persistedUriPermissions();
    if (uriPermissions == null) return false;

    for (final uriPermission in uriPermissions) {
      final uriString = uriPermission.uri.toString();
      if (isSameDirectoryPath(makeDirectoryPath(uriString), _directory)) {
        _uriString = uriString;
        _directory = makeDirectoryPath(uriString);
        return true;
      }
    }
    return false;
  }

  /// Returns an `List<String>` with all persisted [Directory]
  ///
  /// To persist an [Directory] call `getDirectoryPermission`
  /// and to remove an persisted `URI` call `releasePersistedPermissions`
  static Future<List<String>?> getPersistedPermissionDirectories() async {
    var uriPermissions = await persistedUriPermissions();

    if (uriPermissions == null) return null;

    List<String> uriStrings = [];
    for (var uriPermission in uriPermissions) {
      uriStrings.add(makeDirectoryPath(uriPermission.uri.toString()));
    }
    return uriStrings;
  }

  /// Returns the content `URI`s of the files inside the granted directory.
  ///
  /// Pass one of these URIs to [getDocumentContentAsBytes] to read a file's
  /// bytes. This is the SAF-correct way to read non-media files on Android 11+,
  /// where reading the absolute paths from [getFilesPath] through `dart:io`
  /// fails with a permission error. (#24)
  Future<List<String>?> getFilesUri({String fileType = "any"}) async {
    if (_uriString == null) return null;
    return api.getFilesUri(_uriString!, fileType: fileType);
  }

  /// Read the full binary content of a file, given its content [uriString]
  /// (as returned by [getFilesUri]).
  ///
  /// Returns the raw bytes for any file type — including non-media files on
  /// Android 13+ that cannot be read via a `dart:io` `File`. (#24)
  static Future<Uint8List?> getDocumentContentAsBytes(String uriString) =>
      api.getDocumentContentAsBytes(Uri.parse(uriString));

  /// Equivalent to `DocumentsContract.buildDocumentUriUsingTree` and
  /// here it decode URI's to full Path
  ///
  /// [Refer to details](https://developer.android.com/reference/android/provider/DocumentsContract#buildDocumentUriUsingTree%28android.net.Uri,%20java.lang.String%29)
  Future<List<String>?> getFilesPath({String fileType = "any"}) async {
    try {
      const kGetFilesPath = "buildChildDocumentsPathUsingTree";
      const kFileType = "fileType";
      const kSourceTreeUriString = "sourceTreeUriString";
      var sourceTreeUriString = _uriString;

      final args = <String, dynamic>{
        kFileType: fileType,
        kSourceTreeUriString: sourceTreeUriString,
      };
      final paths = await kDocumentsContractChannel
          .invokeMethod<List<dynamic>?>(kGetFilesPath, args);
      if (paths == null) return null;
      return List<String>.from(paths);
    } catch (e) {
      return null;
    }
  }

  // Request to `cache` the Granted Directory into App's Package `files` folder
  Future<List<String>?> cache({String? fileType}) async {
    try {
      const kCacheToExternalFilesDirectory = "cacheToExternalFilesDirectory";
      const kSourceTreeUriString = "sourceTreeUriString";
      const kFileType = "fileType";
      const kCacheDirectoryName = "cacheDirectoryName";

      var cacheDirectoryName = makeDirectoryPathToName(_directory);
      fileType ??= "any";

      final args = <String, dynamic>{
        kSourceTreeUriString: _uriString,
        kFileType: fileType,
        kCacheDirectoryName: cacheDirectoryName,
      };
      final paths = await kDocumentFileChannel.invokeMethod<List<dynamic>?>(
          kCacheToExternalFilesDirectory, args);
      if (paths == null) return null;
      return List<String>.from(paths);
    } catch (e) {
      return null;
    }
  }

  /// Returns an `List<String>` with all cached files full path
  ///
  /// To cach an [Directory] call `cache`
  /// and to clear a cached [Directory] call `clearCache`
  Future<List<String>?> getCachedFilesPath() async {
    try {
      const kGetFilesPath = "getCachedFilesPath";
      const kCacheDirectoryName = "cacheDirectoryName";

      var cacheDirectoryName = makeDirectoryPathToName(_directory);

      final args = <String, dynamic>{
        kCacheDirectoryName: cacheDirectoryName,
      };
      final paths = await kDocumentFileChannel.invokeMethod<List<dynamic>?>(
          kGetFilesPath, args);
      if (paths == null) return null;
      return List<String>.from(paths);
    } catch (e) {
      return null;
    }
  }

  // Request to `cache` the single files from Granted Directory into App's Package `files` folder
  Future<String?> singleCache({
    required String? filePath,
    String? directory,
  }) async {
    try {
      const kSingleCacheToExternalFilesDirectory =
          "singleCacheToExternalFilesDirectory";
      const kSourceUriString = "sourceUriString";
      const kCacheDirectoryName = "cacheDirectoryName";

      var sourceUriString = makeUriString(path: filePath as String);
      var cacheDirectoryName = makeDirectoryPathToName(_directory);
      if (directory != null) {
        cacheDirectoryName = makeDirectoryPathToName(directory);
      }

      final args = <String, dynamic>{
        kSourceUriString: sourceUriString,
        kCacheDirectoryName: cacheDirectoryName,
      };
      final path = await kDocumentFileChannel.invokeMethod<String?>(
          kSingleCacheToExternalFilesDirectory, args);
      if (path == null) return null;
      return path;
    } catch (e) {
      return null;
    }
  }

  /// Returns `bool` after deleting files from App's Package `files` folder
  /// for respective Granted Directory
  /// To cache an [Directory] call `cache`
  Future<bool?> clearCache() async {
    try {
      const kClearCachedFiles = "clearCachedFiles";
      const kCacheDirectoryName = "cacheDirectoryName";

      var cacheDirectoryName = makeDirectoryPathToName(_directory);

      final args = <String, dynamic>{
        kCacheDirectoryName: cacheDirectoryName,
      };
      final cleared = await kDocumentFileChannel.invokeMethod<bool?>(
          kClearCachedFiles, args);
      if (cleared == null) return null;
      return cleared;
    } catch (e) {
      return null;
    }
  }

  /// Returns 'bool' on syncing the [Directory]'s files with Cached [Directory]
  Future<bool?> sync() async {
    try {
      const kSyncWithExternalFilesDirectory = "syncWithExternalFilesDirectory";
      const kSourceTreeUriString = "sourceTreeUriString";
      const kCacheDirectoryName = "cacheDirectoryName";

      var cacheDirectoryName = makeDirectoryPathToName(_directory);

      final args = <String, dynamic>{
        kSourceTreeUriString: _uriString,
        kCacheDirectoryName: cacheDirectoryName,
      };
      final isSync = await kDocumentFileChannel.invokeMethod<bool?>(
          kSyncWithExternalFilesDirectory, args);
      if (isSync == null) return null;
      return isSync;
    } catch (e) {
      return null;
    }
  }

  /// Will revoke an persistable URI
  ///
  /// Call this when your App no longer wants the permission of an `URI` returned
  /// by `getDirectoryPermission` method
  ///
  /// To get the current persisted `URI`s call `getPersistedPermissionDirectories`
  Future<void> releasePersistedPermission() async {
    await releasePersistableUriPermission(
        makeUriString(path: _directory, isTreeUri: true));
  }

  /// Request the user for access to `Directory Permission` of User choice
  ///
  /// Returns [bool].
  static Future<bool?> getDynamicDirectoryPermission(
      {bool grantWritePermission = true}) async {
    try {
      const kOpenDocumentTree = 'openDocumentTree';
      const kGrantWritePermission = 'grantWritePermission';
      const kInitialUri = 'initialUri';

      String initialUri = makeUriString();

      final args = <String, dynamic>{
        kGrantWritePermission: grantWritePermission,
        kInitialUri: initialUri
      };
      final selectedDirectoryUri = await kDocumentFileChannel
          .invokeMethod<String?>(kOpenDocumentTree, args);
      if (selectedDirectoryUri != null) return true;
      return false;
    } catch (e) {
      return null;
    }
  }

  /// Static method for Dynamic call
  /// Equivalent to `DocumentsContract.buildDocumentUriUsingTree` and
  /// here it decode URI's to full Path
  ///
  /// [Refer to details](https://developer.android.com/reference/android/provider/DocumentsContract#buildDocumentUriUsingTree%28android.net.Uri,%20java.lang.String%29)
  static Future<List<String>?> getFilesPathFor(String? directory,
      {String fileType = "any"}) async {
    if (directory == null) return null;
    try {
      const kGetFilesPath = "buildChildDocumentsPathUsingTree";
      const kFileType = "fileType";
      const kSourceTreeUriString = "sourceTreeUriString";
      var sourceTreeUriString = makeUriString(path: directory, isTreeUri: true);

      final args = <String, dynamic>{
        kFileType: fileType,
        kSourceTreeUriString: sourceTreeUriString,
      };
      final paths = await kDocumentsContractChannel
          .invokeMethod<List<dynamic>?>(kGetFilesPath, args);
      if (paths == null) return null;
      return List<String>.from(paths);
    } catch (e) {
      return null;
    }
  }

  /// Static method for Dynamic call
  // Request to `cache` the Granted Directory into App's Package `files` folder
  static Future<List<String>?> cacheFor(String? directory,
      {String fileType = "any"}) async {
    if (directory == null) return null;
    try {
      const kCacheToExternalFilesDirectory = "cacheToExternalFilesDirectory";
      const kSourceTreeUriString = "sourceTreeUriString";
      const kFileType = "fileType";
      const kCacheDirectoryName = "cacheDirectoryName";

      var cacheDirectoryName = makeDirectoryPathToName(directory);
      var uriString = makeUriString(path: directory, isTreeUri: true);

      final args = <String, dynamic>{
        kSourceTreeUriString: uriString,
        kFileType: fileType,
        kCacheDirectoryName: cacheDirectoryName,
      };
      final paths = await kDocumentFileChannel.invokeMethod<List<dynamic>?>(
          kCacheToExternalFilesDirectory, args);
      if (paths == null) return null;
      return List<String>.from(paths);
    } catch (e) {
      return null;
    }
  }

  /// Static method for Dynamic call
  /// Returns an `List<String>` with all cached files full path
  ///
  /// To cach an [Directory] call `cache`
  /// and to clear a cached [Directory] call `clearCache`
  static Future<List<String>?> getCachedFilesPathFor(String? directory) async {
    if (directory == null) return null;
    try {
      const kGetFilesPath = "getCachedFilesPath";
      const kCacheDirectoryName = "cacheDirectoryName";

      var cacheDirectoryName = makeDirectoryPathToName(directory);

      final args = <String, dynamic>{
        kCacheDirectoryName: cacheDirectoryName,
      };
      final paths = await kDocumentFileChannel.invokeMethod<List<dynamic>?>(
          kGetFilesPath, args);
      if (paths == null) return null;
      return List<String>.from(paths);
    } catch (e) {
      return null;
    }
  }

  /// Static method for Dynamic call
  /// Returns `bool` after deleting files from App's Package `files` folder
  /// for respective Granted Directory
  /// To cache an [Directory] call `cache`
  static Future<bool?> clearCacheFor(String? directory) async {
    if (directory == null) return null;
    try {
      const kClearCachedFiles = "clearCachedFiles";
      const kCacheDirectoryName = "cacheDirectoryName";

      var cacheDirectoryName = makeDirectoryPathToName(directory);

      final args = <String, dynamic>{
        kCacheDirectoryName: cacheDirectoryName,
      };
      final cleared = await kDocumentFileChannel.invokeMethod<bool?>(
          kClearCachedFiles, args);
      if (cleared == null) return null;
      return cleared;
    } catch (e) {
      return null;
    }
  }

  /// Static method for Dynamic call
  /// Returns 'bool' on syncing the [Directory]'s files with Cached [Directory]
  static Future<bool?> syncWith(String? directory) async {
    if (directory == null) return null;
    try {
      const kDynamicSyncWithExternalFilesDirectory =
          "dynamicSyncWithExternalFilesDirectory";
      const kSourceTreeUriString = "sourceTreeUriString";
      const kCacheDirectoryName = "cacheDirectoryName";

      var sourceUriString = makeUriString(path: directory, isTreeUri: true);
      var cacheDirectoryName = makeDirectoryPathToName(directory);

      final args = <String, dynamic>{
        kSourceTreeUriString: sourceUriString,
        kCacheDirectoryName: cacheDirectoryName,
      };
      final isSync = await kDocumentFileChannel.invokeMethod<bool?>(
          kDynamicSyncWithExternalFilesDirectory, args);
      if (isSync == null) return null;
      return isSync;
    } catch (e) {
      return null;
    }
  }

  /// Will revoke an persistable URI
  ///
  /// Call this when your App no longer wants the permission of all the `URI`s
  ///
  /// To get the current persisted `URI`s call `getPersistedPermissionDirectories`
  static Future<void> releasePersistedPermissions() async {
    var persistedPermissionDirectories =
        await getPersistedPermissionDirectories();
    if (persistedPermissionDirectories != null) {
      for (var directory in persistedPermissionDirectories) {
        releasePersistableUriPermission(
            makeUriString(path: directory, isTreeUri: true));
      }
    }
  }

  /// Will revoke an persistable URI
  ///
  /// Call this when your App no longer wants the permission of an [Directory] returned
  /// by `getDirectoryPermission` method
  ///
  /// To get the current persisted [Directory]s call `getDirectoryPermission`
  static Future<void> releasePersistedPermissionFor(String? directory) async {
    if (directory != null) {
      await releasePersistableUriPermission(
          makeUriString(path: directory, isTreeUri: true));
    }
  }

  /// Convenient method to verify if a given [Directory]
  /// is allowed to be write or read from SAF API's
  ///
  /// This uses the `persistedUriPermissions` method to get the List
  /// of allowed `URI`s then will verify if the `uri` is included in
  static Future<bool?> isPersistedPermissionDirectoryFor(
      String? uriString) async {
    if (uriString == null) return null;

    var uriPermissions = await persistedUriPermissions();
    if (uriPermissions == null) return null;

    for (var uriPermission in uriPermissions) {
      if (uriString == uriPermission.uri.toString()) return true;
    }
    return false;
  }
}
