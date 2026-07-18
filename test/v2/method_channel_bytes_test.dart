// test/v2/method_channel_bytes_test.dart

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

  tearDown(
      () => messenger.setMockMethodCallHandler(platform.methodChannel, null));

  test('readFileBytes returns bytes and forwards range', () async {
    mock((_) => Uint8List.fromList([1, 2, 3]));
    final b = await platform.readFileBytes('u', start: 5, count: 3);
    expect(b, [1, 2, 3]);
    expect(lastCall!.arguments, {'uri': 'u', 'start': 5, 'count': 3});
  });

  test('writeFileBytes sends data and decodes result', () async {
    mock((_) => docMap);
    final d = await platform.writeFileBytes('content://dir', 'a.bin',
        'application/octet-stream', Uint8List.fromList([9, 9, 9, 9]));
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
