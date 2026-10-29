import 'dart:async';

import 'package:flutter/widgets.dart';

/// Screen-scoped reads. A slow refresh never overlaps the next tick.
class VisiblePoller with WidgetsBindingObserver {
  VisiblePoller({
    required this.refresh,
    required this.isVisible,
    this.interval = const Duration(seconds: 15),
  }) {
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  final Future<void> Function() refresh;
  final bool Function() isVisible;
  final Duration interval;
  Timer? _timer;
  bool _disposed = false, _busy = false;
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _schedule() {
    _timer?.cancel();
    if (!_disposed && _foreground) _timer = Timer(interval, _tick);
  }

  Future<void> _tick() async {
    if (_disposed || _busy) return;
    _busy = true;
    try {
      if (_foreground && isVisible()) await refresh();
    } finally {
      _busy = false;
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _timer?.cancel();
    if (state == AppLifecycleState.resumed) unawaited(_tick());
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
