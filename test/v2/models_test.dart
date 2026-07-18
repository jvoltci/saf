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
        'uri': 'u',
        'name': 'n',
        'isDir': true,
        'length': 0,
        'lastModified': 0,
        'mimeType': null,
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
