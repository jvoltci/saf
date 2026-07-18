// test/v2/method_channel_stream_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/exceptions.dart';
import 'package:saf/src/v2/saf_method_channel.dart';

const docMap = {
  'uri': 'content://doc/1',
  'name': 'a.txt',
  'isDir': false,
  'length': 3,
  'lastModified': 2,
  'mimeType': 'text/plain',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = MethodChannelSaf();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(
      () => messenger.setMockMethodCallHandler(platform.methodChannel, null));

  test('readFileStream yields chunks until endOfStream', () async {
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      expect(call.method, 'readFileStream');
      expect(call.arguments['bufferSize'], 4194304);
      return 'rs1';
    });
    messenger.setMockStreamHandler(
      EventChannel('${MethodChannelSaf.eventsPrefix}rs1'),
      MockStreamHandler.inline(onListen: (args, events) {
        events.success(Uint8List.fromList([1]));
        events.success(Uint8List.fromList([2, 3]));
        events.endOfStream();
      }),
    );
    final chunks = await (await platform.readFileStream('u')).toList();
    expect(chunks, [
      [1],
      [2, 3]
    ]);
  });

  test('readFileStream maps errors to SafException', () async {
    messenger.setMockMethodCallHandler(
        platform.methodChannel, (call) async => 'rs2');
    messenger.setMockStreamHandler(
      EventChannel('${MethodChannelSaf.eventsPrefix}rs2'),
      MockStreamHandler.inline(onListen: (args, events) {
        events.error(code: 'permission', message: 'no', details: {'uri': 'u'});
        events.endOfStream();
      }),
    );
    final stream = await platform.readFileStream('u');
    expect(stream.toList(), throwsA(isA<SafPermissionException>()));
  });

  test('walk yields entries with relative paths', () async {
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      expect(call.method, 'startWalk');
      return 'w1';
    });
    messenger.setMockStreamHandler(
      EventChannel('${MethodChannelSaf.eventsPrefix}w1'),
      MockStreamHandler.inline(onListen: (args, events) {
        events.success({'file': docMap, 'relativePath': 'sub/a.txt'});
        events.endOfStream();
      }),
    );
    final entries = await platform.walk('content://dir').toList();
    expect(entries.single.relativePath, 'sub/a.txt');
    expect(entries.single.file.name, 'a.txt');
  });
}
