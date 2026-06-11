import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/audio_provider.dart';
import '../providers/update_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/mini_player.dart';
import 'works_screen.dart';
import 'search_screen.dart';
import 'my_screen.dart';
import 'settings_screen.dart';
import '../providers/settings_provider.dart';

/// Extracted widget that watches [authProvider] via a narrow `select()` and
/// rebuilds only itself, not the surrounding IndexedStack.
class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOfflineMode = ref.watch(authProvider.select(
      (s) => s.currentUser != null && !s.isLoggedIn && s.error != null,
    ));

    if (!isOfflineMode) {
      return const SizedBox.shrink();
    }

    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(12, topPadding + 4, 12, 4),
        color: Colors.orange.shade800,
        child: Row(
          children: [
            const Icon(Icons.cloud_off, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                S.of(context).offlineModeMessage,
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ),
            TextButton(
              onPressed: () async {
                final notifier = ref.read(authProvider.notifier);
                await notifier.retryConnection();
              },
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                S.of(context).retry,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Extracted widget that provides top padding when offline mode is active.
/// Uses a narrow `select()` so it doesn't rebuild the IndexedStack.
class _OfflinePadding extends ConsumerWidget {
  final Widget child;

  const _OfflinePadding({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOfflineMode = ref.watch(authProvider.select(
      (s) => s.currentUser != null && !s.isLoggedIn && s.error != null,
    ));

    return Padding(
      padding: EdgeInsets.only(top: isOfflineMode ? 30 : 0),
      child: child,
    );
  }
}

/// Extracted MiniPlayer area that floats above bottom navigation.
///
/// Wrapped in horizontal padding + bottom spacing for the floating pill look.
/// Slides down (hidden) when fullscreen player is active, with a fade.
class _MiniPlayerArea extends ConsumerWidget {
  const _MiniPlayerArea();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTrack = ref.watch(currentTrackProvider);
    final isFullscreenActive = ref.watch(isFullscreenPlayerActiveProvider);

    final hasTrack = currentTrack.when(
      data: (track) => track != null,
      loading: () => false,
      error: (_, __) => false,
    );

    // Collapse to 0 height when fullscreen is active — smooth.
    return AnimatedCrossFade(
      firstChild: const MiniPlayer(),
      secondChild: const SizedBox.shrink(),
      crossFadeState: hasTrack && !isFullscreenActive
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
      duration: const Duration(milliseconds: 300),
      firstCurve: Curves.easeOutCubic,
      secondCurve: Curves.easeOutCubic,
      sizeCurve: Curves.easeOutCubic,
    );
  }
}

/// Simple nav item data used by the custom segmented navigation bar.
class _NavItem {
  final IconData outlined;
  final IconData filled;
  final String label;
  final bool showBadge;
  const _NavItem({
    required this.outlined,
    required this.filled,
    required this.label,
    this.showBadge = false,
  });
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentIndex = 0;
  int _previousIndex = 0;
  static const int _settingsTabIndex = 3;

  // 使用 PageStorageBucket 来保存页面状态
  final PageStorageBucket _bucket = PageStorageBucket();

  late final List<Widget> _screens;
  late final List<Widget> _heroWrappedScreens;

  bool _lastShowUpdateBadge = false;
  List<_NavItem>? _cachedNavItems;

  @override
  void initState() {
    super.initState();
    _screens = const [
      WorksScreen(key: PageStorageKey('works_screen')),
      SearchScreen(key: PageStorageKey('search_screen')),
      MyScreen(key: PageStorageKey('my_screen')),
      SettingsScreen(key: PageStorageKey('settings_screen')),
    ];
    // Cache per-screen RepaintBoundary + HeroMode wrappers.
    // Each tab gets its own compositing layer so repaints in one
    // tab don't affect the others (IndexedStack keeps all alive).
    _heroWrappedScreens = List.generate(_screens.length, (index) {
      return RepaintBoundary(
        child: HeroMode(
          enabled: index == 0,
          child: _screens[index],
        ),
      );
    });
  }

  List<_NavItem> _buildNavItems(BuildContext context, bool showUpdateBadge) {
    final s = S.of(context);
    return [
      _NavItem(
        outlined: Icons.home_outlined,
        filled: Icons.home,
        label: s.navHome,
      ),
      _NavItem(
        outlined: Icons.search_outlined,
        filled: Icons.search,
        label: s.navSearch,
      ),
      _NavItem(
        outlined: Icons.favorite_border,
        filled: Icons.favorite,
        label: s.navMy,
      ),
      _NavItem(
        outlined: Icons.settings_outlined,
        filled: Icons.settings,
        label: s.navSettings,
        showBadge: showUpdateBadge,
      ),
    ];
  }

  void _handleDestinationSelected(int index) {
    if (_currentIndex == index) {
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _previousIndex = _currentIndex;
      _currentIndex = index;
    });

    if (index == _settingsTabIndex) {
      ref.read(settingsCacheRefreshTriggerProvider.notifier).state++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final showUpdateBadge = ref.watch(showUpdateRedDotProvider);
    // Memoize nav items to avoid recreating on every build
    if (_cachedNavItems == null || _lastShowUpdateBadge != showUpdateBadge) {
      _cachedNavItems = _buildNavItems(context, showUpdateBadge);
      _lastShowUpdateBadge = showUpdateBadge;
    }
    final navItems = _cachedNavItems!;

    final isFullscreenActive = ref.watch(isFullscreenPlayerActiveProvider);

    if (isLandscape) {
      // 横屏布局：使用自定义 NavigationRail 风格
      final colorScheme = Theme.of(context).colorScheme;
      final mq = MediaQuery.of(context);

      Widget navRail = SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(navItems.length, (i) {
            final item = navItems[i];
            final isSel = i == _currentIndex;
            final col = isSel
                ? (isFullscreenActive
                    ? Colors.white
                    : colorScheme.primary)
                : colorScheme.onSurfaceVariant;

            // Crossfade icon: outlined → filled
            Widget iconWidget = SizedBox(
              width: 24,
              height: 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedOpacity(
                    opacity: isSel ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(item.outlined, size: 22, color: col),
                  ),
                  AnimatedOpacity(
                    opacity: isSel ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(item.filled, size: 22, color: col),
                  ),
                ],
              ),
            );

            if (item.showBadge) {
              iconWidget = Badge(
                isLabelVisible: true,
                child: iconWidget,
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: GestureDetector(
                onTap: () => _handleDestinationSelected(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    color: isSel
                        ? (isFullscreenActive
                            ? colorScheme.primary.withValues(alpha: 0.25)
                            : colorScheme.primaryContainer)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      iconWidget,
                      const SizedBox(height: 4),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              isSel ? FontWeight.w600 : FontWeight.w400,
                          color: col,
                        ),
                        child: Text(item.label),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      );

      if (isFullscreenActive) {
        navRail = ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                border: Border(
                  right: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: navRail,
            ),
          ),
        );
      }

      return PopScope(
        canPop: _currentIndex != _settingsTabIndex,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _currentIndex == _settingsTabIndex) {
            setState(() {
              _currentIndex = _previousIndex;
            });
          }
        },
        child: Scaffold(
        body: Stack(
          children: [
            Row(
              children: [
                SafeArea(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: mq.size.height -
                          mq.padding.top -
                          mq.padding.bottom,
                    ),
                      child: IntrinsicHeight(
                        child: navRail,
                      ),
                    ),
                  ),
                ),
                if (!isFullscreenActive)
                  const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: _OfflinePadding(
                    child: SafeArea(
                      top: false,
                      child: Column(
                        children: [
                          Expanded(
                            child: PageStorage(
                              bucket: _bucket,
                              child: IndexedStack(
                                index: _currentIndex,
                                children: _heroWrappedScreens,
                              ),
                            ),
                          ),
                          const _MiniPlayerArea(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const _OfflineBanner(),
          ],
        ),
      ),
    );
  }

    // 竖屏布局
    return PopScope(
      canPop: _currentIndex != _settingsTabIndex,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _currentIndex == _settingsTabIndex) {
          setState(() {
            _currentIndex = _previousIndex;
          });
        }
      },
      child: Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          _OfflinePadding(
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: PageStorage(
                      bucket: _bucket,
                      child: IndexedStack(
                        index: _currentIndex,
                        children: _heroWrappedScreens,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const _OfflineBanner(),
        ],
      ),
      bottomNavigationBar: Consumer(
            builder: (context, ref, child) {
              final isFullscreenActive = ref.watch(isFullscreenPlayerActiveProvider);
              final mediaQuery = MediaQuery.of(context);
              final bottomPadding = mediaQuery.padding.bottom;
              final isIOS = Platform.isIOS;

              final colorScheme = Theme.of(context).colorScheme;
              final isDark = colorScheme.brightness == Brightness.dark;
              const double navHeight = 56;
              const Duration animDur = Duration(milliseconds: 400);

              Widget navBar = LayoutBuilder(
                builder: (context, constraints) {
                  final count = navItems.length;
                  final itemWidth = constraints.maxWidth / count;
                  final maxPill = itemWidth * 0.6;
                  final pillWidth = (itemWidth * 0.48)
                      .clamp(28.0, maxPill < 28.0 ? 28.0 : maxPill);
                  final pillLeft = _currentIndex * itemWidth + (itemWidth - pillWidth) / 2;

                  return SizedBox(
                    height: navHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // Sliding pill indicator — centered on content
                        AnimatedPositioned(
                          duration: animDur,
                          curve: Curves.easeOutCubic,
                          left: pillLeft,
                          top: 6,
                          width: pillWidth,
                          height: 44,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isFullscreenActive
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        // Gradient top accent line
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Container(
                              height: 1.5,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    colorScheme.primary.withValues(alpha: 0.0),
                                    colorScheme.primary.withValues(alpha: isFullscreenActive ? 0.25 : 0.4),
                                    colorScheme.primary.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Items row
                        Row(
                          children: List.generate(count, (i) {
                            final item = navItems[i];
                            final isSel = i == _currentIndex;

                            final fgColor = isSel
                                ? (isFullscreenActive
                                    ? Colors.white
                                    : colorScheme.primary)
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.45)
                                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.7));

                            // Icon with crossfade between outlined & filled
                            Widget iconWidget = SizedBox(
                              width: 24,
                              height: 24,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  AnimatedOpacity(
                                    opacity: isSel ? 0.0 : 1.0,
                                    duration: animDur,
                                    child: Icon(item.outlined, size: 22, color: fgColor),
                                  ),
                                  AnimatedOpacity(
                                    opacity: isSel ? 1.0 : 0.0,
                                    duration: animDur,
                                    child: Icon(item.filled, size: 22, color: fgColor),
                                  ),
                                ],
                              ),
                            );

                            if (item.showBadge) {
                              iconWidget = Badge(
                                isLabelVisible: true,
                                child: iconWidget,
                              );
                            }

                            return Expanded(
                              child: GestureDetector(
                                onTap: () => _handleDestinationSelected(i),
                                behavior: HitTestBehavior.opaque,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    iconWidget,
                                    const SizedBox(height: 3),
                                    AnimatedDefaultTextStyle(
                                      duration: animDur,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                                        color: fgColor,
                                      ),
                                      child: Text(item.label),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  );
                },
              );

              // ── Wrap nav bar in floating pill container ──
              navBar = Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isFullscreenActive ? Colors.transparent : colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: isFullscreenActive
                      ? []
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                            spreadRadius: -2,
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: isFullscreenActive
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.15),
                            ),
                            child: navBar,
                          ),
                        ),
                      )
                    : navBar,
              );

              if (isIOS) {
                navBar = MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: navBar,
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _MiniPlayerArea(),
                  Padding(
                    padding:
                        EdgeInsets.only(bottom: isIOS && bottomPadding > 0 ? 6.0 : bottomPadding),
                    child: navBar,
                  ),
                ],
              );
            },
          ),
      ),
    );
  }
}
