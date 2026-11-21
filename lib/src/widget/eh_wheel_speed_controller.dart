import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../setting/mouse_setting.dart';

/// Smooths mouse-wheel scrolling while preserving responsive input.
///
/// Rapid wheel notches accumulate onto a shared target offset using a short
/// ease-out curve (instead of cancelling the previous animation and dropping
/// its remaining distance), while fine precision/trackpad deltas pass straight
/// through with zero animation latency.
class EHWheelSpeedController extends StatefulWidget {
  final ScrollController? controller;
  final Widget child;

  const EHWheelSpeedController({Key? key, required this.controller, required this.child}) : super(key: key);

  @override
  State<EHWheelSpeedController> createState() => _EHWheelSpeedControllerState();
}

class _EHWheelSpeedControllerState extends State<EHWheelSpeedController> {
  static const Duration _scrollDuration = Duration(milliseconds: 110);
  static const double _trackpadDeltaThreshold = 20.0;

  double? _targetOffset;
  int _lastWheelTimestampMs = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: widget.child,
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final ScrollController? controller = widget.controller;
    if (controller == null || !controller.hasClients) {
      return;
    }

    final double rawDy = event.scrollDelta.dy;
    final double delta = rawDy * mouseSetting.wheelScrollSpeed.value;
    if (delta == 0) {
      return;
    }

    GestureBinding.instance.pointerSignalResolver.resolve(event);

    final ScrollPosition position = controller.position;
    if (position.pixels < position.minScrollExtent || position.pixels > position.maxScrollExtent) {
      _targetOffset = null;
      return;
    }

    /// Precision trackpads emit small, high-frequency deltas; apply them
    /// directly without animation so scrolling feels 1:1 with finger motion.
    if (rawDy.abs() < _trackpadDeltaThreshold) {
      _targetOffset = null;
      position.pointerScroll(delta);
      return;
    }

    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final bool continuousWheel = _targetOffset != null && (nowMs - _lastWheelTimestampMs) <= 220;
    _lastWheelTimestampMs = nowMs;

    /// If scrolling reversed direction or the list moved externally (scrollbar
    /// drag / scroll-to-top), anchor from the current scroll offset.
    double baseOffset = position.pixels;
    if (continuousWheel) {
      final double prevTarget = _targetOffset!;
      final bool sameDirection = (prevTarget - position.pixels) * delta >= 0;
      if (sameDirection && (prevTarget - position.pixels).abs() < 2400) {
        baseOffset = prevTarget;
      }
    }

    final double nextTarget = (baseOffset + delta).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((nextTarget - position.pixels).abs() < 0.5) {
      _targetOffset = nextTarget;
      return;
    }

    _targetOffset = nextTarget;
    position.animateTo(
      nextTarget,
      duration: _scrollDuration,
      curve: Curves.easeOutCubic,
    );
  }
}
