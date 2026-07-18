// lib/src/v2/saf_method_channel.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'saf_platform_interface.dart';

/// The default [SafPlatform] implementation backed by method channels.
class MethodChannelSaf extends SafPlatform {
  /// The v2 method channel.
  @visibleForTesting
  final methodChannel = const MethodChannel('com.ivehement.plugins/saf/v2');

  static const String eventsPrefix = 'com.ivehement.plugins/saf/v2/events/';

  // Methods are implemented in subsequent tasks.
}
