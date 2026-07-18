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
