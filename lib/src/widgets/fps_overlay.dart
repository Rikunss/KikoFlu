import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A lightweight, real-time FPS overlay for debugging performance.
///
/// Displays current FPS, worst build time, and worst raster time for the
/// last 60 frames. Also tracks jank (frames exceeding ~60Hz budget).
///
/// Only intended for debug builds — wrap usage in `kDebugMode`.
class FpsOverlay extends StatefulWidget {
  const FpsOverlay({super.key});

  @override
  State<FpsOverlay> createState() => _FpsOverlayState();
}

class _FpsOverlayState extends State<FpsOverlay> {
  double _fps = 0;
  double _worstBuildMs = 0;
  double _worstRasterMs = 0;
  int _jankCount = 0;
  double _periodFps = 0;
  int _periodJank = 0;

  bool _disposed = false;
  int _frameCount = 0;
  DateTime _lastMeasure = DateTime.now();
  Timer? _logTimer;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);

    // Log performance stats every 10 seconds for before/after comparison.
    _logTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      debugPrint(
        '[FPS] ${_periodFps.toStringAsFixed(1)} avg FPS | '
        'worst build: ${_worstBuildMs.toStringAsFixed(1)}ms | '
        'worst raster: ${_worstRasterMs.toStringAsFixed(1)}ms | '
        '$_periodJank janks in 10s',
      );
      // Reset worst values and jank for the next measurement window
      _worstBuildMs = 0;
      _worstRasterMs = 0;
      _periodJank = 0;
      _periodFps = 0;
    });
  }

  void _onFrame(Duration _) {
    if (_disposed) return;
    _frameCount++;
    final now = DateTime.now();
    final elapsed = now.difference(_lastMeasure);

    if (elapsed.inMilliseconds >= 1000) {
      final measuredFps =
          _frameCount / (elapsed.inMilliseconds / 1000.0);
      _periodFps = measuredFps;
      if (mounted) {
        setState(() {
          _fps = measuredFps;
          _frameCount = 0;
          _lastMeasure = now;
        });
      }
    }

    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final buildMs = timing.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000.0;

      // Track worst values with simple max comparison (no allocations)
      if (buildMs > _worstBuildMs) _worstBuildMs = buildMs;
      if (rasterMs > _worstRasterMs) _worstRasterMs = rasterMs;

      // Jank = frame exceeds 16.7ms (60Hz) budget
      if (buildMs > 16.7 || rasterMs > 16.7) {
        _jankCount++;
        _periodJank++;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _logTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  Color _fpsColor() {
    if (_fps >= 55) return const Color(0xFF4CAF50);
    if (_fps >= 30) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  Color _jankColor() {
    if (_jankCount <= 5) return const Color(0xFF4CAF50);
    if (_jankCount <= 20) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // FPS line
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _fpsColor(),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${_fps.toStringAsFixed(0)} FPS',
                style: TextStyle(
                  color: _fpsColor(),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Build time
          Text(
            'Build: ${_worstBuildMs.toStringAsFixed(1)}ms',
            style: const TextStyle(
              color: Color(0xFF90CAF9),
              fontSize: 9,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          // Raster time
          Text(
            'Raster: ${_worstRasterMs.toStringAsFixed(1)}ms',
            style: const TextStyle(
              color: Color(0xFFA5D6A7),
              fontSize: 9,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          // Jank count
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: _jankColor(),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '$_jankCount jank',
                style: TextStyle(
                  color: _jankColor(),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
