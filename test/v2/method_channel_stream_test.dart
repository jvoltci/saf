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

  test('readFileStream pulls chunks until EOF, then closes the session',
      () async {
    final calls = <String>[];
    final chunks = [
      Uint8List.fromList([1]),
      Uint8List.fromList([2, 3]),
    ];
    var i = 0;
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'openReadSession':
          expect(call.arguments['bufferSize'], 4194304);
          return 'rs1';
        case 'readSessionChunk':
          expect(call.arguments['session'], 'rs1');
          return i < chunks.length ? chunks[i++] : null; // null => EOF
        case 'closeReadSession':
          return null;
      }
      throw StateError('unexpected ${call.method}');
    });
    final out = await (await platform.readFileStream('u')).toList();
    expect(out, [
      [1],
      [2, 3]
    ]);
    expect(calls, [
      'openReadSession',
      'readSessionChunk',
      'readSessionChunk',
      'readSessionChunk',
      'closeReadSession',
    ]);
  });

  test('readFileStream maps chunk errors to SafException and still closes',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'openReadSession':
          return 'rs2';
        case 'readSessionChunk':
          throw PlatformException(
              code: 'permission', message: 'no', details: {'uri': 'u'});
        case 'closeReadSession':
          return null;
      }
      return null;
    });
    final stream = await platform.readFileStream('u');
    await expectLater(stream.toList(), throwsA(isA<SafPermissionException>()));
    expect(calls, contains('closeReadSession')); // finally-block cleanup ran
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
