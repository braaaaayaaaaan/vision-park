import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Optional foreground feedback. Never blocks or changes allocation handling.
class AllocationSound {
  static const _channel = MethodChannel('visionpark/allocation_sound');

  static Future<void> play() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel
          .invokeMethod<bool>('play')
          .timeout(const Duration(seconds: 1));
    } catch (_) {
      // Muted devices, missing native support and audio errors stay silent.
      // The assignment banner and navigation must still work normally.
    }
  }
}
