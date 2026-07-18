import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:saf/saf.dart';
// ignore: unnecessary_import
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
