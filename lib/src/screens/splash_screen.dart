import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers/theme_provider.dart';
import '../utils/theme.dart';

/// Splash screen shown immediately while background services initialize.
/// Uses its own minimal MaterialApp to avoid dependency on app services
/// (Riverpod, Hive, etc.) that haven't been initialized yet.
class SplashApp extends StatelessWidget {
  /// Seed color for the splash theme. If null, defaults to ocean blue.
  final Color? seedColor;

  const SplashApp({super.key, this.seedColor});

  /// Read saved [ColorSchemeType] from SharedPreferences and return the matching seed color.
  /// Returns `null` if prefs aren't available yet (cold start fallback uses default blue).
  static Future<Color?> loadSavedSeedColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(ThemeSettingsNotifier.colorSchemeTypeKey) ?? 0;
      return AppTheme.seedColorForType(ColorSchemeType.values[index]);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final seed = seedColor ?? const Color(0xFF146683);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KikoFlu Edge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const SplashBody(),
    );
  }
}

class SplashBody extends StatefulWidget {
  const SplashBody({super.key});

  @override
  State<SplashBody> createState() => _SplashBodyState();
}

class _SplashBodyState extends State<SplashBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _iconFade;
  late final Animation<double> _iconScale;
  late final Animation<double> _titleFade;
  late final Animation<double> _subtitleFade;
  late final Animation<double> _subtitleSlide;
  late final Animation<double> _subtitleLetterSpacing;
  late final Animation<double> _spinnerFade;
  late final Animation<double> _bottomFade;

  String _version = '';

  @override
  void initState() {
    super.initState();

    _loadVersion();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // ── Icon: fade-in (0→25%) + elastic scale (0→35%) ──
    _iconFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.25, curve: Curves.easeOut),
    );
    _iconScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOutBack),
      ),
    );

    // ── Title: fade-in (15→40%) ──
    _titleFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.15, 0.40, curve: Curves.easeOut),
    );

    // ── Subtitle: fade (25→50%) + slide-up + letter-spacing ──
    _subtitleFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.25, 0.50, curve: Curves.easeOut),
    );
    _subtitleSlide = Tween<double>(begin: 16.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.25, 0.50, curve: Curves.easeOutCubic),
      ),
    );
    _subtitleLetterSpacing = Tween<double>(begin: -2.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.25, 0.55, curve: Curves.easeOutCubic),
      ),
    );

    // ── Loader: fade-in (35→55%) ──
    _spinnerFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.55, curve: Curves.easeOut),
    );

    // ── Bottom info: fade-in (40→70%) ──
    _bottomFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.40, 0.70, curve: Curves.easeOut),
    );

    _controller.forward();

    // Start pulse loop after initial animation
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _controller.addStatusListener(_pulseListener);
      }
    });
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = 'v${info.version}');
    } catch (_) {
      if (mounted) setState(() => _version = 'v3.2.0'); // fallback
    }
  }

  void _pulseListener(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _controller.reverse();
    } else if (status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_pulseListener);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // Note: NOT using Scaffold here because SplashBody is rendered inside
    // the _SplashCrossFade overlay which has no MaterialApp ancestor.
    // Scaffold requires a Directionality widget ancestor (from MaterialApp).
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  colorScheme.surface,
                  colorScheme.surfaceContainerLow,
                  colorScheme.surface,
                ]
              : [
                  colorScheme.surface,
                  colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
                  colorScheme.surface,
                ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        alignment: Alignment.topLeft,
        children: [
            // Subtle decorative circles
            Positioned(
              top: -80,
              right: -60,
              child: _DecorativeCircle(
                size: 200,
                color: colorScheme.primary.withValues(alpha: 0.04),
              ),
            ),
            Positioned(
              bottom: -40,
              left: -40,
              child: _DecorativeCircle(
                size: 160,
                color: colorScheme.tertiary.withValues(alpha: 0.04),
              ),
            ),
            Positioned(
              top: isLandscape ? 10 : null,
              bottom: !isLandscape ? 40 : null,
              right: !isLandscape ? 20 : null,
              child: _DecorativeCircle(
                size: 80,
                color: colorScheme.secondary.withValues(alpha: 0.03),
              ),
            ),

            // Main content
            Center(
              child: isLandscape
                  ? _buildLandscapeLayout(theme, colorScheme)
                  : _buildPortraitLayout(theme, colorScheme),
            ),
          ],
        ),
      );
  }

  Widget _buildPortraitLayout(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        // ── Main content (icon, title, subtitle, loader) — truly centered ──
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── App icon with pulse ──
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final scaleValue = _controller.status == AnimationStatus.forward &&
                            _controller.value < 0.35
                        ? _iconScale.value
                        : _controller.status == AnimationStatus.completed ||
                                _controller.status == AnimationStatus.reverse
                            ? 1.0 + (_controller.value * 0.03)
                            : 1.0;
                    return FadeTransition(
                      opacity: _iconFade,
                      child: Transform.scale(
                        scale: scaleValue,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.primary.withValues(alpha: 0.25),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.asset(
                              'assets/icons/app_icon_opaque.png',
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Icon(
                                Icons.audiotrack,
                                size: 100,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // ── App name ──
                FadeTransition(
                  opacity: _titleFade,
                  child: Text(
                    'KikoFlu Edge',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // ── Tagline with slide-up + letter-spacing animation ──
                FadeTransition(
                  opacity: _subtitleFade,
                  child: Transform.translate(
                    offset: Offset(0, _subtitleSlide.value),
                    child: Text(
                      'Kikoeru Client',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                        letterSpacing: _subtitleLetterSpacing.value,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 48),

                // ── Animated loading indicator ──
                FadeTransition(
                  opacity: _spinnerFade,
                  child: _AnimatedDotsLoader(
                    primaryColor: colorScheme.primary,
                    tertiaryColor: colorScheme.tertiary,
                    secondaryColor: colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Version info at bottom ──
        Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: FadeTransition(
            opacity: _bottomFade,
            child: Text(
              _version,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Left: icon
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final scaleValue = _controller.status == AnimationStatus.forward &&
                    _controller.value < 0.35
                ? _iconScale.value
                : _controller.status == AnimationStatus.completed ||
                        _controller.status == AnimationStatus.reverse
                    ? 1.0 + (_controller.value * 0.03)
                    : 1.0;
            return FadeTransition(
              opacity: _iconFade,
              child: Transform.scale(
                scale: scaleValue,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/icons/app_icon_opaque.png',
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.audiotrack,
                        size: 80,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),

        const SizedBox(width: 32),

        // Right: text + spinner
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FadeTransition(
              opacity: _titleFade,
              child: Text(
                'KikoFlu Edge',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FadeTransition(
              opacity: _subtitleFade,
              child: Transform.translate(
                offset: Offset(0, _subtitleSlide.value),
                child: Text(
                  'Kikoeru Client',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: _subtitleLetterSpacing.value,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FadeTransition(
              opacity: _spinnerFade,
              child: _AnimatedDotsLoader(
                primaryColor: colorScheme.primary,
                tertiaryColor: colorScheme.tertiary,
                secondaryColor: colorScheme.secondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Subtle decorative circle used as background design element.
class _DecorativeCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _DecorativeCircle({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

/// Animated bouncing dots loading indicator with color cycling.
class _AnimatedDotsLoader extends StatefulWidget {
  final Color primaryColor;
  final Color tertiaryColor;
  final Color secondaryColor;

  const _AnimatedDotsLoader({
    required this.primaryColor,
    required this.tertiaryColor,
    required this.secondaryColor,
  });

  @override
  State<_AnimatedDotsLoader> createState() => _AnimatedDotsLoaderState();
}

class _AnimatedDotsLoaderState extends State<_AnimatedDotsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<Color> get _dotColors => [
        widget.primaryColor,
        widget.tertiaryColor,
        widget.secondaryColor,
      ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.15;
            final phase = (_ctrl.value + delay) % 1.0;
            final opacity = 0.3 + (phase * 0.7);
            final bouncePhase = (_ctrl.value * 2.0 + delay * 2.0) % 1.0;
            final translateY = -8.0 * (bouncePhase < 0.5
                ? 2.0 * bouncePhase * bouncePhase
                : 1.0 -
                    (-2.0 * bouncePhase * bouncePhase +
                        2.0 * bouncePhase));

            // Color cycle through primary → tertiary → secondary
            final colorCycle = (_ctrl.value * 2.0 + i * 0.33) % 1.0;
            final fromIdx = (i + (colorCycle * 3).floor()) % 3;
            final toIdx = (fromIdx + 1) % 3;
            final colorT = colorCycle * 3.0 - (colorCycle * 3).floor();
            final dotColor = Color.lerp(
                  _dotColors[fromIdx],
                  _dotColors[toIdx],
                  colorT,
                ) ??
                _dotColors[i];

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.translate(
                offset: Offset(0, translateY),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor.withValues(alpha: opacity),
                    boxShadow: [
                      BoxShadow(
                        color: dotColor.withValues(alpha: opacity * 0.3),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
