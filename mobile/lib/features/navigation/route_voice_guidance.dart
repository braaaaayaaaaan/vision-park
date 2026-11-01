import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'navigation_speech_service.dart';
import 'route_instructions.dart';

enum _VoiceCue { upcoming, approach, arrival }

/// Event policy only. Uses published metres and the preview's existing clock.
/// The screen owns this object so mute preference survives session/map rebuilds.
class RouteVoiceGuidance extends ChangeNotifier {
  RouteVoiceGuidance({NavigationSpeechService? speech})
    : _speech = speech ?? AndroidNavigationSpeechService() {
    _speech.onError = _unavailable;
  }

  final NavigationSpeechService _speech;
  RouteInstructionPlan? _plan;
  RouteInstructionProgress? _progress;
  bool _enabled = false, _playing = false, _complete = false;
  bool _introduced = false;
  bool _disposed = false, _failed = false, _engineUsed = false;
  Future<bool>? _initialization;
  int? _target;
  final _approached = <int>{};
  int _epoch = 0;
  (int, _VoiceCue)? _pending;
  bool _draining = false;
  (int, _VoiceCue)? _lastCompleted;
  static const _sentenceGap = Duration(milliseconds: 350);

  bool get enabled => _enabled;
  bool get canEnable =>
      !_disposed && !_failed && (_plan?.canSynchronizePreview ?? false);
  bool get canRetry =>
      !_disposed && _failed && (_plan?.canSynchronizePreview ?? false);
  String? get unavailableReason => _failed
      ? 'Voice Guidance Unavailable. Check Android Speech Settings.'
      : !canEnable
      ? 'Voice Requires Detailed Directions And A Playable Route.'
      : null;

  void setPlan(RouteInstructionPlan plan) {
    if (_disposed || identical(_plan, plan)) return;
    restart();
    _plan = plan;
    // Called while attaching a map, before that map builds its voice control.
  }

  void releasePlan(RouteInstructionPlan plan) {
    if (!identical(_plan, plan)) return;
    restart();
    _plan = null;
  }

  void setEnabled(bool enabled) {
    if (enabled && canRetry) {
      _failed = false;
      _initialization = null;
    }
    if (_disposed || (enabled && !canEnable) || enabled == _enabled) return;
    _enabled = enabled;
    _cancelSpeech();
    notifyListeners();
    if (enabled) {
      unawaited(_ready());
      if (_playing) _announceUpcoming(force: true);
    }
  }

  void update({
    required RouteInstructionProgress? progress,
    required bool playing,
    required bool complete,
  }) {
    if (_disposed) return;
    _progress = progress;
    if (complete) {
      final firstCompletion = !_complete;
      _complete = true;
      _playing = false;
      if (firstCompletion && _enabled && canEnable) {
        _requestSpeech(_VoiceCue.arrival);
      }
      return;
    }
    if (!playing) {
      if (_playing) pause();
      return;
    }
    final starting = !_playing;
    _playing = true;
    if (_enabled && canEnable) _announceUpcoming(force: starting);
  }

  void pause() {
    if (_disposed) return;
    _playing = false;
    _cancelSpeech();
  }

  void restart() {
    if (_disposed) return;
    pause();
    _progress = null;
    _complete = false;
    _introduced = false;
    _target = null;
    _lastCompleted = null;
    _approached.clear();
  }

  (int, double)? _upcoming() {
    final progress = _progress, plan = _plan;
    if (progress == null || plan == null) return null;
    final active = plan.instructions[progress.instructionIndex];
    // Keep the ramp cue active throughout its interval. The continuation belongs
    // to the destination image, after the floor transition has completed.
    if (active.maneuver == RouteManeuver.ramp) {
      return (progress.instructionIndex, 0);
    }
    final atBoundary =
        active.maneuver != RouteManeuver.departure &&
        (progress.travelledMetres - active.distanceFromStartMetres).abs() <
            1e-6;
    final index = atBoundary
        ? progress.instructionIndex
        : math.min(progress.instructionIndex + 1, plan.instructions.length - 1);
    final instruction = plan.instructions[index];
    final remaining = math.max(
      0.0,
      instruction.distanceFromStartMetres - progress.travelledMetres,
    );
    return (index, remaining);
  }

  void _announceUpcoming({required bool force}) {
    final upcoming = _upcoming();
    if (upcoming == null) return;
    final (index, remaining) = upcoming;
    final plan = _plan!;
    final instruction = plan.instructions[index];
    final legMetres = index == 0
        ? 0.0
        : instruction.distanceFromStartMetres -
              plan.instructions[index - 1].distanceFromStartMetres;
    final threshold = math.min(5.0, legMetres / 2);
    final isTurn = switch (instruction.maneuver) {
      RouteManeuver.left || RouteManeuver.right || RouteManeuver.ramp => true,
      _ => false,
    };
    // Short legs get one cue, not an immediate second approach reminder.
    final approaching = isTurn && legMetres >= 6 && remaining <= threshold;
    var cue = _VoiceCue.upcoming;
    if (force || index != _target) {
      _target = index;
      if (remaining <= threshold) _approached.add(index);
    } else if (approaching && _approached.add(index)) {
      // One approach event per instruction occurrence, including looped turns.
      // Optional reminders never interrupt or wait behind an existing cue.
      if (_draining) return;
      cue = _VoiceCue.approach;
    } else {
      return;
    }
    _requestSpeech(cue);
  }

  String? _cueText(_VoiceCue cue) {
    if (cue == _VoiceCue.arrival) {
      return _complete
          ? 'Route preview complete. ${_plan!.instructions.last.text}'
          : null;
    }
    if (!_playing || _complete) return null;
    final upcoming = _upcoming();
    if (upcoming == null) return null;
    final (index, remaining) = upcoming;
    final text = _plan!.instructions[index].text;
    return remaining <= 1
        ? text
        : 'In ${remaining.ceil()} metres, ${text[0].toLowerCase()}${text.substring(1)}';
  }

  Future<bool> _ready() => _initialization ??= () async {
    _engineUsed = true;
    try {
      final ready = await _speech.initialize().timeout(
        const Duration(seconds: 10),
      );
      if (!ready) _unavailable();
      return ready && !_disposed && !_failed;
    } catch (_) {
      _unavailable();
      return false;
    }
  }();

  bool _current(int epoch) =>
      !_disposed && _enabled && canEnable && epoch == _epoch;

  void _requestSpeech(_VoiceCue cue) {
    _pending = (_epoch, cue);
    unawaited(_drain());
  }

  /// Finish the current sentence, then speak only the latest relevant cue.
  /// Resolve its distance at dispatch so delayed countdowns cannot go stale.
  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending != null) {
        final (epoch, cue) = _pending!;
        _pending = null;
        try {
          if (!await _ready() || !_current(epoch)) continue;
          if (_pending != null) continue;
          await _speech.stop();
          if (!_current(epoch)) continue;
          if (_pending != null) continue;
          final text = _cueText(cue);
          if (text == null) continue;
          final index = cue == _VoiceCue.arrival
              ? _plan!.instructions.length - 1
              : _upcoming()!.$1;
          final occurrence = (index, cue);
          if (_lastCompleted == occurrence ||
              (cue == _VoiceCue.upcoming && _lastCompleted?.$1 == index)) {
            continue;
          }
          // Introduce the simulation once per run, at dispatch. Superseded
          // pending cues must not consume it or repeat it after an interruption.
          final introduce = cue == _VoiceCue.upcoming && !_introduced;
          if (introduce) _introduced = true;
          await _speech.speak(introduce ? 'Route preview. $text' : text);
          if (_current(epoch)) {
            _lastCompleted = occurrence;
          } else {
            await _speech.stop();
          }
          // Give adjacent lines and cancelled audio tracks a clean boundary.
          // New cues replace _pending during this gap rather than queueing up.
          await Future<void>.delayed(_sentenceGap);
        } catch (_) {
          if (_current(epoch)) _unavailable();
        }
      }
    } finally {
      _draining = false;
    }
  }

  void _cancelSpeech() {
    ++_epoch;
    _pending = null;
    _stopImmediately();
  }

  void _stopImmediately() {
    if (_engineUsed) {
      unawaited(_speech.stop().catchError((Object _) => _unavailable()));
    }
  }

  void _unavailable() {
    if (_disposed || _failed) return;
    _failed = true;
    _enabled = false;
    _cancelSpeech();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _cancelSpeech();
    _disposed = true;
    _speech.onError = null;
    unawaited(_speech.dispose().catchError((Object _) {}));
    super.dispose();
  }
}
