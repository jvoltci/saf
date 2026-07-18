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
