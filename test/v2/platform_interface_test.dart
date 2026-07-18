// test/v2/platform_interface_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/saf_method_channel.dart';
import 'package:saf/src/v2/saf_platform_interface.dart';

void main() {
  test('default instance is MethodChannelSaf', () {
    expect(SafPlatform.instance, isA<MethodChannelSaf>());
  });

  test('method channel name is the v2 channel', () {
    final p = SafPlatform.instance as MethodChannelSaf;
    expect(p.methodChannel.name, 'com.ivehement.plugins/saf/v2');
  });
}
