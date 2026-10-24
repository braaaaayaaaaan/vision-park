import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speech completes when the utterance finishes. Stop must remain available
/// while speech is pending and release the in-flight utterance immediately.
abstract interface class NavigationSpeechService {
  set onError(VoidCallback? callback);
  Future<bool> initialize();
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> dispose();
}

class AndroidNavigationSpeechService implements NavigationSpeechService {
  FlutterTts? _tts;
  bool _disposed = false;
  VoidCallback? _onError;

  @override
  set onError(VoidCallback? callback) => _onError = callback;

  @override
  Future<bool> initialize() async {
    if (_disposed ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    final tts = _tts = FlutterTts();
    tts.setErrorHandler((_) => _onError?.call());
    final engines = await tts.getEngines;
    if (engines is! List || engines.isEmpty || _disposed) return false;
    String? english;
    for (final locale in ['en-US', 'en-GB', 'en']) {
      if (await tts.isLanguageAvailable(locale) == true &&
          await tts.isLanguageInstalled(locale) == true) {
        english = locale;
        break;
      }
    }
    if (english == null || _disposed) return false;
    if (await tts.setLanguage(english) != 1) return false;
    await tts.setSpeechRate(.45);
    await tts.setPitch(1);
    await tts.setVolume(1);
    await tts.setQueueMode(0); // QUEUE_FLUSH: never build a speech backlog.
    await tts.awaitSpeakCompletion(true);
    return !_disposed;
  }

  @override
  Future<void> speak(String text) async {
    if (_disposed || _tts == null) return;
    if (await _tts!.speak(text) != 1) {
      throw StateError('Speech engine rejected the preview instruction.');
    }
  }

  @override
  Future<void> stop() async {
    await _tts?.stop();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _onError = null;
    // flutter_tts has no Dart dispose API. Stop and release our callbacks;
    // the plugin releases the native engine when its Flutter engine detaches.
    _tts?.setErrorHandler((_) {});
    await stop();
  }
}
