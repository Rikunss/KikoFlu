import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A waveform-styled seekbar with floating time label during drag.
///
/// Uses simulated waveform data (seeded random) — no real-time audio analysis.
/// The waveform is visually smooth and consistent per widget lifecycle.
///
/// Animations:
/// - Progress value smoothly lerps toward the target (no jumps).
/// - Thumb glow ring pulses gently when [isPlaying] is true.
/// - Waveform bars near the thumb oscillate subtly while playing.
class WaveformSeeker extends StatefulWidget {
  /// Current progress (0.0–1.0).
  final double value;

  /// Called while the user drags the seekbar.
  final ValueChanged<double> onChanged;

  /// Called when the user finishes dragging.
  final ValueChanged<double> onChangeEnd;

  /// Total duration (for floating time label).
  final Duration duration;

  /// Whether audio is currently playing (enables pulse + wave animations).
  final bool isPlaying;

  /// Waveform bar count.
  final int barCount;

  /// Height of the waveform area.
  final double height;

  /// Optional gradient colours extracted from the album artwork.
  /// When null, a built-in rainbow gradient is used as fallback.
  final List<Color>? gradientColors;

  /// Called on long-press — used to trigger gradient colour refresh.
  final VoidCallback? onLongPress;

  const WaveformSeeker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    required this.duration,
    this.isPlaying = false,
    this.barCount = 80,
    this.height = 40,
    this.gradientColors,
    this.onLongPress,
  });

  @override
  State<WaveformSeeker> createState() => _WaveformSeekerState();
}

class _WaveformSeekerState extends State<WaveformSeeker>
    with SingleTickerProviderStateMixin {
  bool _isDragging = false;
  double _dragValue = 0.0;
  double _smoothValue = 0.0;
  late List<double> _waveformData;
  late AnimationController _animCtrl;
  final GlobalKey _stackKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _smoothValue = widget.value;
    _waveformData = _generateWaveform(widget.barCount);
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (widget.isPlaying) _animCtrl.repeat();
  }

  @override
  void didUpdateWidget(WaveformSeeker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying == widget.isPlaying) return;
    if (widget.isPlaying) {
      _animCtrl.repeat();
    } else {
      _animCtrl.stop();
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  /// Generate smooth, natural-looking waveform amplitudes (0.0–1.0).
  static List<double> _generateWaveform(int count) {
    final random = math.Random(42);
    final raw = List.generate(count, (_) => 0.2 + random.nextDouble() * 0.8);

    final smoothed = List<double>.from(raw);
    for (int pass = 0; pass < 2; pass++) {
      for (int i = 1; i < smoothed.length - 1; i++) {
        smoothed[i] =
            (smoothed[i - 1] + smoothed[i] + smoothed[i + 1]) / 3;
      }
    }
    return smoothed;
  }

  /// Smoothly interpolate the progress value for butter-smooth animation.
  double _getAnimatedValue() {
    final raw = _isDragging ? _dragValue : widget.value;
    _smoothValue += (raw - _smoothValue) * 0.18;
    return _smoothValue.clamp(0.0, 1.0);
  }

  /// Pulse intensity (0.3–1.0) for the thumb glow ring — breathes while playing.
  double _pulseValue(double animTime) {
    if (!widget.isPlaying) return 0.0;
    return (math.sin(animTime * math.pi * 2) + 1.0) / 2.0;
  }

  /// Convert a local DX position to a clamped 0.0–1.0 value.
  double _dxToValue(double dx, double width) {
    return (dx / width).clamp(0.0, 1.0);
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');      final hours = d.inHours;
      final minutes = d.inMinutes.remainder(60);
      final seconds = d.inSeconds.remainder(60);
      if (hours > 0) {
        return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
      }
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  /// Build wave offsets for bars near the playhead.
  /// Called inside AnimatedBuilder each animation frame.
  List<double> _buildBarWave(double displayValue, double animTime) {
    return List.generate(widget.barCount, (i) {
      if (!widget.isPlaying) return 0.0;
      final barCenter = (i + 0.5) / widget.barCount;
      final dist = ((barCenter - displayValue).abs() * widget.barCount);
      if (dist > 8) return 0.0;
      final phase = animTime * math.pi * 4 + i * 0.6;
      final amplitude = (1.0 - dist / 8.0) * 0.15;
      return math.sin(phase) * amplitude;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          final labelText = _formatDuration(
            Duration(
              milliseconds: (_dragValue * widget.duration.inMilliseconds)
                  .round(),
            ),
          );
          final labelStyle = TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colorScheme.onInverseSurface,
            fontFeatures: const [
              FontFeature.tabularFigures(),
            ],
          );
          final textPainter = TextPainter(
            text: TextSpan(text: labelText, style: labelStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          const labelHozPadding = 10.0;
          final labelWidth = textPainter.width + labelHozPadding * 2;

          return Stack(
            key: _stackKey,
            clipBehavior: Clip.none,
            children: [
              AnimatedBuilder(
                animation: _animCtrl,
                builder: (context, child) {
                  final animTime = _animCtrl.value;
                  final displayValue = _getAnimatedValue();
                  final pulse = _pulseValue(animTime);
                  final barWave = _buildBarWave(displayValue, animTime);

                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: (_) {
                      setState(() => _isDragging = true);
                    },
                    onHorizontalDragUpdate: (details) {
                      final value = _dxToValue(
                        details.localPosition.dx,
                        width,
                      );
                      setState(() => _dragValue = value);
                      widget.onChanged(value);
                    },
                    onHorizontalDragEnd: (_) {
                      widget.onChangeEnd(_dragValue);
                      setState(() => _isDragging = false);
                    },
                    onTapUp: (details) {
                      final value = _dxToValue(
                        details.localPosition.dx,
                        width,
                      );
                      widget.onChanged(value);
                      widget.onChangeEnd(value);
                    },
                    onLongPress: widget.onLongPress,
                    child: CustomPaint(
                      size: Size(width, widget.height),
                      painter: WaveformPainter(
                        data: _waveformData,
                        progress: displayValue,
                        pulseValue: pulse,
                        barWave: barWave,
                        gradientColors: widget.gradientColors,
                        inactiveColor:
                            colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  );
                },
              ),

              if (_isDragging)
                _buildFloatingLabel(
                  displayValue: _getAnimatedValue(),
                  width: width,
                  labelWidth: labelWidth,
                  labelText: labelText,
                  labelStyle: labelStyle,
                  colorScheme: colorScheme,
                ),
            ],
          );
        },
      ),
    );
  }

  /// Floating time label shown during drag — extracted to keep build() readable.
  Widget _buildFloatingLabel({
    required double displayValue,
    required double width,
    required double labelWidth,
    required String labelText,
    required TextStyle labelStyle,
    required ColorScheme colorScheme,
  }) {
    final thumbX = displayValue * width;
    return Positioned(
      top: -28,
      left: (thumbX - labelWidth / 2).clamp(0.0, width - labelWidth),
      child: AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            labelText,
            style: labelStyle,
          ),
        ),
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> data;
  final double progress;
  final double pulseValue;
  final List<double> barWave;
  final Color inactiveColor;
  final List<Color>? gradientColors;

  /// Fallback rainbow gradient — used when no artwork colours are available.
  static const List<Color> _fallbackGradient = [
    Color(0xFFFF4D4D),
    Color(0xFFFF9F1C),
    Color(0xFFFFD726),
    Color(0xFF2ECC71),
    Color(0xFF00BCD4),
    Color(0xFF7C4DFF),
  ];

  WaveformPainter({
    required this.data,
    required this.progress,
    this.pulseValue = 0.0,
    this.barWave = const [],
    this.gradientColors,
    required this.inactiveColor,
  });

  /// The effective gradient — artwork colours if available, otherwise rainbow.
  List<Color> get _effectiveGradient => gradientColors ?? _fallbackGradient;

  /// Map [t] (0.0–1.0) to a gradient colour.
  Color _gradientColor(double t) {
    final colors = _effectiveGradient;
    final clamped = t.clamp(0.0, 1.0);
    final segment = clamped * (colors.length - 1);
    final index = segment.floor();
    final frac = segment - index;
    if (index >= colors.length - 1) return colors.last;
    return Color.lerp(colors[index], colors[index + 1], frac)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / data.length;
    final gap = barWidth * 0.25;
    final drawWidth = barWidth - gap;
    final midY = size.height / 2;
    final maxBarHeight = size.height * 0.85;
    final effectiveProgress = progress.clamp(0.0, 1.0);
    final cutoffX = effectiveProgress * size.width;

    for (int i = 0; i < data.length; i++) {
      final wave = i < barWave.length ? barWave[i] : 0.0;
      final barHeight =
          (data[i] + wave).clamp(0.05, 1.0) * maxBarHeight;
      final x = i * barWidth + gap / 2;
      final barCenterX = x + drawWidth / 2;

      final isActive = barCenterX <= cutoffX;
      final barColor = isActive
          ? _gradientColor(barCenterX / size.width)
          : inactiveColor;

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromCenter(
            center: Offset(barCenterX, midY),
            width: drawWidth,
            height: barHeight,
          ),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
          bottomLeft: const Radius.circular(2),
          bottomRight: const Radius.circular(2),
        ),
        Paint()
          ..color = barColor
          ..style = PaintingStyle.fill,
      );
    }

    if (effectiveProgress > 0.0 && effectiveProgress < 1.0) {
      final thumbX = effectiveProgress * size.width;
      final thumbColor = _gradientColor(effectiveProgress);

      canvas.drawCircle(
        Offset(thumbX, midY),
        6,
        Paint()
          ..color = thumbColor
          ..style = PaintingStyle.fill,
      );

      final glowRadius = 8.0 + pulseValue * 6.0;
      final glowAlpha = (0.15 + pulseValue * 0.25).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(thumbX, midY),
        glowRadius,
        Paint()
          ..color = thumbColor.withValues(alpha: glowAlpha)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.barWave != barWave ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.gradientColors != gradientColors;
  }
}