import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';

import 'settings/account_screen.dart';
import 'settings/playback_screen.dart';
import 'settings/usb_dac_settings_screen.dart';
import 'settings/appearance_screen.dart';
import 'settings/downloads_storage_screen.dart';
import 'settings/privacy_content_screen.dart';
import 'settings/translation_screen.dart';
import 'settings/advanced_screen.dart';
import 'listening_statistics_screen.dart';
import 'about_screen.dart';
import 'settings/widgets/settings_dashboard_card.dart';

/// MD3 Dashboard-style Settings screen.
///
/// Features:
/// - Large Top App Bar (SliverAppBar.large)
/// - Live search bar for settings lookup
/// - 8 section cards with tonal icons
/// - Max 2-level navigation depth
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _navigate(Widget screen) {
    // Unfocus search bar before navigating so it doesn't auto-focus on pop
    _searchFocusNode.unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = S.of(context);
    final isSearching = _searchQuery.isNotEmpty;

    // ── Card data with search keywords ──
    final allCards = <_SettingsCardData>[
      _SettingsCardData(
        icon: Icons.music_note_rounded,
        iconColor: colorScheme.primary,
        title: s.settingsPlayback,
        subtitle: s.settingsPlaybackSubtitle,
        screen: const PlaybackScreen(),
        keywords: ['equalizer', 'crossfade', 'gapless', 'audio format', 'eq'],
      ),
      _SettingsCardData(
        icon: Icons.palette_rounded,
        iconColor: const Color(0xFF9C27B0),
        title: s.settingsAppearance,
        subtitle: s.settingsAppearanceSubtitle,
        screen: const AppearanceScreen(),
        keywords: ['theme', 'language', 'color', 'dark', 'light', 'display', 'card size', 'page'],
      ),
      _SettingsCardData(
        icon: Icons.download_rounded,
        iconColor: const Color(0xFF00796B),
        title: s.settingsDownloadsStorage,
        subtitle: s.settingsDownloadsStorageSubtitle,
        screen: const DownloadsStorageScreen(),
        keywords: ['download path', 'cache', 'storage', 'clear', 'space'],
      ),
      _SettingsCardData(
        icon: Icons.shield_rounded,
        iconColor: const Color(0xFFC62828),
        title: s.settingsPrivacyContent,
        subtitle: s.settingsPrivacyContentSubtitle,
        screen: const PrivacyContentScreen(),
        keywords: ['privacy mode', 'block', 'tag', 'voice actor', 'circle', 'blur'],
      ),
      _SettingsCardData(
        icon: Icons.translate_rounded,
        iconColor: const Color(0xFF283593),
        title: s.settingsTranslation,
        subtitle: s.settingsTranslationSubtitle,
        screen: const TranslationScreen(),
        keywords: ['translate', 'llm', 'api', 'openai', 'google', 'prompt'],
      ),
      _SettingsCardData(
        icon: Icons.person_rounded,
        iconColor: const Color(0xFF37474F),
        title: s.settingsAccount,
        subtitle: s.settingsAccountSubtitle,
        screen: const AccountScreen(),
        keywords: ['floating lyric', 'login', 'logout', 'server', 'permission', 'notification'],
      ),
      const _SettingsCardData(
        icon: Icons.usb,
        iconColor: Color(0xFF00695C),
        title: 'USB DAC (Beta)',
        subtitle: 'USB DAC routing & AAudio exclusive mode',
        screen: UsbDacSettingsScreen(),
        keywords: ['usb', 'dac', 'aaudio', 'exclusive mode', 'bit-perfect', 'mixer bypass', 'volume lock'],
      ),
      _SettingsCardData(
        icon: Icons.bar_chart_rounded,
        iconColor: const Color(0xFFE65100),
        title: s.listeningStatsTitle,
        subtitle: s.listeningStatsSubtitle,
        screen: const ListeningStatisticsScreen(),
        keywords: ['statistics', 'stats', 'listening', 'history', 'top', 'va', 'voice actor', 'streak', 'chart'],
      ),
      _SettingsCardData(
        icon: Icons.tune_rounded,
        iconColor: const Color(0xFF546E7A),
        title: s.settingsAdvanced,
        subtitle: s.settingsAdvancedSubtitle,
        screen: const AdvancedScreen(),
        keywords: ['sort', 'default', 'subtitle library', 'priority', 'log', 'debug', 'device info', 'legacy'],
      ),
      _SettingsCardData(
        icon: Icons.info_outline_rounded,
        iconColor: const Color(0xFF616161),
        title: s.aboutTitle,
        subtitle: s.settingsAboutSubtitle,
        screen: const AboutScreen(),
        keywords: ['version', 'update', 'license', 'author', 'repo', 'github'],
      ),
    ];

    // ── Filter ──
    final filteredCards = isSearching
        ? allCards.where((c) => c.matches(_searchQuery)).toList()
        : allCards;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Large Top App Bar (MD3) ──
          SliverAppBar.large(
            title: Text(
              s.settingsTitle,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // ── Search Bar ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SearchBar(
                hintText: s.searchSettings,
                leading: const Icon(Icons.search),
                trailing: [
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
                ],
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 16),
                ),
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(
                  colorScheme.surfaceContainerHighest,
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                focusNode: _searchFocusNode,
                controller: _searchController,
                onChanged: (value) {
                  setState(() => _searchQuery = value.trim());
                },
              ),
            ),
          ),

          // ── Dashboard Cards or No Results ──
          if (isSearching && filteredCards.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer
                              .withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.search_off_rounded,
                          size: 40,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        s.noResults,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildListDelegate([
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      ...filteredCards.map((card) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SettingsDashboardCard(
                          icon: card.icon,
                          iconColor: card.iconColor,
                          title: card.title,
                          subtitle: card.subtitle,
                          onTap: () => _navigate(card.screen),
                        ),
                      )),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Internal data holder for a settings dashboard card.
class _SettingsCardData {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget screen;
  final List<String> keywords;

  const _SettingsCardData({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.screen,
    this.keywords = const [],
  });

  bool matches(String query) {
    final q = query.toLowerCase();
    if (title.toLowerCase().contains(q)) return true;
    if (subtitle.toLowerCase().contains(q)) return true;
    return keywords.any((k) => k.toLowerCase().contains(q));
  }
}
