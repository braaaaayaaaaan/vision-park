import 'dart:async';

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
  bool _ready = false;
  Completer<void>? _utterance;
  Future<void>? _stopping;
  Future<bool>? _initialization;
  VoidCallback? _onError;

  @override
  set onError(VoidCallback? callback) => _onError = callback;

  @override
  Future<bool> initialize() {
    if (_disposed) return Future.value(false);
    if (_ready) return Future.value(true);
    return _initialization ??= _initialize().whenComplete(() {
      _initialization = null;
    });
  }

  Future<bool> _initialize() async {
    if (_disposed ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    final tts = _tts = FlutterTts();
    tts.setErrorHandler((_) {
      _ready = false;
      final utterance = _utterance;
      if (utterance != null && !utterance.isCompleted) {
        utterance.completeError(StateError('Speech engine playback failed.'));
      }
      _onError?.call();
    });
    final engines = await tts.getEngines;
    if (engines is! List || engines.isEmpty || _disposed) return false;
    final installed = engines.whereType<String>().where((e) => e.isNotEmpty);
    if (installed.isEmpty) return false;
    final preferred = await tts.getDefaultEngine;
    if (_disposed) return false;
    // A Dart wrapper shares the plugin's native instance. Rebind explicitly:
    // its previous engine may have died or been replaced by an Android update.
    // setEngine completes after native onInit; its Dart return value is null.
    await tts.setEngine(
      installed.contains(preferred) ? preferred as String : installed.first,
    );
    if (_disposed) return false;
    String? english;
    for (final locale in ['en-US', 'en-GB', 'en']) {
      if (_disposed) return false;
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
    await tts.setVolume(.8);
    await tts.setAudioAttributesForNavigation();
    await tts.setQueueMode(0); // QUEUE_FLUSH: never build a speech backlog.
    await tts.awaitSpeakCompletion(true);
    return _ready = !_disposed;
  }

  @override
  Future<void> speak(String text) async {
    if (_disposed || _tts == null) return;
    if (!_ready) throw StateError('Speech engine is not ready.');
    // Native stop is asynchronous. Do not start the next line while Android
    // is still cancelling the previous audio track.
    await _stopping;
    if (_disposed) return;
    if (_utterance != null) throw StateError('Speech is already playing.');
    final utterance = _utterance = Completer<void>();
    try {
      await Future.any<void>([
        _tts!.speak(text, focus: true).then<void>((result) {
          if (result != 1) {
            throw StateError('Speech engine rejected the preview instruction.');
          }
        }),
        // flutter_tts 4.2.5 does not finish its pending speak result on Android
        // onStop. Release our caller explicitly when an utterance is cancelled.
        utterance.future,
      ]);
    } finally {
      if (identical(_utterance, utterance)) _utterance = null;
    }
  }

  @override
  Future<void> stop() {
    // Idle/uninitialized engines have no utterance to cancel. Calling native
    // stop here can hit a disconnected service and cannot restore its binding.
    final pending = _stopping;
    if (pending != null) return pending;
    final utterance = _utterance;
    if (utterance == null) return Future.value();
    _utterance = null;
    if (!utterance.isCompleted) utterance.complete();
    return _stopping = _tts!.stop().then<void>((_) {}).whenComplete(() {
      _stopping = null;
    });
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
