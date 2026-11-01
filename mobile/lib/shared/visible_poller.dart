import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

/// Screen-scoped reads. A slow refresh never overlaps the next tick.
class VisiblePoller with WidgetsBindingObserver {
  VisiblePoller({
    required this.refresh,
    required this.isVisible,
    this.interval = const Duration(seconds: 15),
    this.hasError,
  }) {
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  final Future<void> Function() refresh;
  final bool Function() isVisible;
  final Duration interval;
  final bool Function()? hasError;
  int _failures = 0;
  Timer? _timer;
  bool _disposed = false, _busy = false;
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _schedule() {
    _timer?.cancel();
    final delay = _failures == 0
        ? interval
        : Duration(
            milliseconds: min(
              90000,
              (interval.inMilliseconds *
                      (1 << min(_failures, 3)) *
                      (.85 + Random().nextDouble() * .3))
                  .round(),
            ),
          );
    if (!_disposed && _foreground) _timer = Timer(delay, _tick);
  }

  Future<void> _tick() async {
    if (_disposed || _busy) return;
    _busy = true;
    try {
      if (_foreground && isVisible()) {
        await refresh();
        _failures = hasError?.call() == true ? _failures + 1 : 0;
      }
    } catch (_) {
      _failures++;
    } finally {
      _busy = false;
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _timer?.cancel();
    if (state == AppLifecycleState.resumed) {
      _failures = 0;
      unawaited(_tick());
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
