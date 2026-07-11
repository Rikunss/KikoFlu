import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/log_service.dart';
import '../../l10n/app_localizations.dart';
import '../models/search_type.dart';
import '../providers/auth_provider.dart';
import '../services/kikoeru_api_service.dart';
import '../providers/search_history_provider.dart';
import '../utils/l10n_extensions.dart';
import '../utils/server_utils.dart';
import '../utils/snackbar_util.dart';
import '../utils/tag_localizer.dart';
import '../widgets/scrollable_appbar.dart';
import '../widgets/download_fab.dart';
import 'search_result_screen.dart';

class SearchCondition {
  final String id;
  final SearchType type;
  final String value;
  final bool isExclude;

  SearchCondition({
    required this.id,
    required this.type,
    required this.value,
    this.isExclude = false,
  });

  String toSearchString() {
    switch (type) {
      case SearchType.keyword:
        return value;
      case SearchType.rjNumber:
        return 'RJ$value';
      case SearchType.tag:
        return isExclude ? '\$-tag:$value\$' : '\$tag:$value\$';
      case SearchType.circle:
        return isExclude ? '\$-circle:$value\$' : '\$circle:$value\$';
      case SearchType.va:
        return isExclude ? '\$-va:$value\$' : '\$va:$value\$';
    }
  }
}

/// Pill data for the segmented search type selector.
class _SearchTypePill {
  final SearchType type;
  final IconData outlined;
  final IconData filled;

  const _SearchTypePill({
    required this.type,
    required this.outlined,
    required this.filled,
  });
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  final List<SearchCondition> _searchConditions = [];
  final FocusNode _searchFocusNode = FocusNode();

  SearchType _currentSearchType = SearchType.keyword;
  bool _isExcludeMode = false;
  double _minRate = 0;
  AgeRating _ageRating = AgeRating.all;
  SalesRange _salesRange = SalesRange.all;
  bool _showAdvancedFilters = false;

  List<Map<String, dynamic>> _allTags = [];
  List<Map<String, dynamic>> _allVas = [];
  List<Map<String, dynamic>> _allCircles = [];
  bool _isLoadingSuggestions = false;

  static const List<_SearchTypePill> _searchTypePills = [
    _SearchTypePill(type: SearchType.keyword, outlined: Icons.search_outlined, filled: Icons.search),
    _SearchTypePill(type: SearchType.tag, outlined: Icons.label_outline, filled: Icons.label),
    _SearchTypePill(type: SearchType.va, outlined: Icons.person_outline, filled: Icons.person),
    _SearchTypePill(type: SearchType.circle, outlined: Icons.group_outlined, filled: Icons.group),
    _SearchTypePill(type: SearchType.rjNumber, outlined: Icons.tag, filled: Icons.tag),
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _ensureSuggestionsLoaded() async {
    if (_currentSearchType == SearchType.keyword ||
        _currentSearchType == SearchType.rjNumber) {
      return;
    }
    final needsLoad = switch (_currentSearchType) {
      SearchType.tag => _allTags.isEmpty,
      SearchType.va => _allVas.isEmpty,
      SearchType.circle => _allCircles.isEmpty,
      _ => false,
    };
    if (needsLoad) {
      await _loadSuggestions();
    }
  }

  Future<void> _loadSuggestions() async {
    if (_currentSearchType == SearchType.keyword ||
        _currentSearchType == SearchType.rjNumber) {
      return;
    }

    setState(() => _isLoadingSuggestions = true);

    try {
      final api = ref.read(kikoeruApiServiceProvider);

      switch (_currentSearchType) {
        case SearchType.tag:
          if (_allTags.isEmpty) {
            final data = await api.getAllTags();
            _allTags = List<Map<String, dynamic>>.from(data);
            _allTags
                .sort((a, b) => (b['count'] ?? 0).compareTo(a['count'] ?? 0));
          }
          break;
        case SearchType.va:
          if (_allVas.isEmpty) {
            final data = await api.getAllVas();
            _allVas = List<Map<String, dynamic>>.from(data);
            _allVas
                .sort((a, b) => (b['count'] ?? 0).compareTo(a['count'] ?? 0));
          }
          break;
        case SearchType.circle:
          if (_allCircles.isEmpty) {
            final data = await api.getAllCircles();
            _allCircles = List<Map<String, dynamic>>.from(data);
            _allCircles
                .sort((a, b) => (b['count'] ?? 0).compareTo(a['count'] ?? 0));
          }
          break;
        default:
          break;
      }

      setState(() {});
    } catch (e) {
      LogService.instance.warning('加载建议列表失败: $e', tag: 'UI');
    } finally {
      setState(() => _isLoadingSuggestions = false);
    }
  }

  void _addSearchCondition() {
    final value = _searchController.text.trim();
    if (value.isEmpty) {
      SnackBarUtil.showWarning(context, S.of(context).enterSearchContent);
      return;
    }

    HapticFeedback.lightImpact();

    setState(() {
      _searchConditions.add(SearchCondition(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: _currentSearchType,
        value: value,
        isExclude: _isExcludeMode,
      ));
      _searchController.clear();
      _isExcludeMode = false;
    });

    FocusScope.of(context).unfocus();
  }

  void _removeSearchCondition(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      _searchConditions.removeWhere((condition) => condition.id == id);
    });
  }

  Future<void> _performSearch() async {
    if (_searchConditions.isEmpty) {
      SnackBarUtil.showWarning(
          context, S.of(context).addAtLeastOneSearchCondition);
      return;
    }

    List<String> searchParts = [];
    for (var condition in _searchConditions) {
      searchParts.add(condition.toSearchString());
    }

    if (_minRate > 0) {
      searchParts.add('\$rate:${_minRate.toInt()}\$');
    }
    if (_ageRating != AgeRating.all && _ageRating.value.isNotEmpty) {
      searchParts.add('\$age:${_ageRating.value}\$');
    }
    if (_salesRange != SalesRange.all && _salesRange.value > 0) {
      searchParts.add('\$sell:${_salesRange.value}\$');
    }

    final searchKeyword = searchParts.join(' ');

    final displayParts = _searchConditions.map((c) {
      final prefix = c.isExclude ? '${S.of(context).excludeMode} ' : '';
      final value = c.type == SearchType.rjNumber
          ? 'RJ${c.value}'
          : c.type == SearchType.tag
              ? TagLocalizer.localizeByName(
                  c.value, Localizations.localeOf(context))
              : c.value;
      return '$prefix${c.type.localizedLabel(context)}: $value';
    }).toList();
    final displayText = displayParts.join(', ');

    final searchParams = <String, dynamic>{
      'keyword': searchKeyword,
      'conditions': _searchConditions
          .map((c) => {
                'type': c.type.localizedLabel(context),
                'value': c.value,
                'isExclude': c.isExclude,
              })
          .toList(),
    };

    if (_minRate > 0) {
      searchParams['minRate'] = _minRate;
    }
    if (_ageRating != AgeRating.all) {
      searchParams['ageRating'] = _ageRating.localizedLabel(context);
    }
    if (_salesRange != SalesRange.all) {
      searchParams['salesRange'] = _salesRange.localizedLabel(context);
    }

    ref.read(searchHistoryProvider.notifier).addHistory(
          keyword: searchKeyword,
          displayText: displayText,
          searchParams: searchParams,
        );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SearchResultScreen(
            keyword: searchKeyword,
            searchTypeLabel: null,
            searchParams: searchParams,
          ),
        ),
      );
    }
  }

  void _searchFromHistory(SearchHistoryItem historyItem) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchResultScreen(
          keyword: historyItem.keyword,
          searchTypeLabel: null,
          searchParams: historyItem.searchParams,
        ),
      ),
    );
  }

  void _selectSearchType(SearchType type) {
    final supportsExclude = type == SearchType.tag ||
        type == SearchType.va ||
        type == SearchType.circle;

    final needLoad =
        type == SearchType.tag || type == SearchType.va || type == SearchType.circle;

    setState(() {
      if (_currentSearchType == type && supportsExclude) {
        _isExcludeMode = !_isExcludeMode;
      } else {
        _currentSearchType = type;
        _isExcludeMode = false;
        _searchController.clear();
        if (needLoad) {
          _ensureSuggestionsLoaded();
        }
      }
    });
  }

  bool get _isPillType =>
      _currentSearchType == SearchType.tag ||
      _currentSearchType == SearchType.va ||
      _currentSearchType == SearchType.circle;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        floatingActionButton: const DownloadFab(),
        appBar: ScrollableAppBar(
          title:
              Text(S.of(context).search, style: const TextStyle(fontSize: 18)),
          actions: [
            IconButton(
              icon: Icon(
                _showAdvancedFilters
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined,
                color: _showAdvancedFilters
                    ? theme.colorScheme.primary
                    : null,
              ),
              iconSize: 22,
              padding: const EdgeInsets.all(8),
              constraints:
                  const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () {
                setState(() {
                  _showAdvancedFilters = !_showAdvancedFilters;
                  if (!_showAdvancedFilters) {
                    _minRate = 0;
                    _ageRating = AgeRating.all;
                    _salesRange = SalesRange.all;
                  }
                });
              },
              tooltip: S.of(context).filter,
            ),
          ],
        ),
        resizeToAvoidBottomInset: true,
        body: isLandscape
            ? _buildLandscapeBody(theme)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildContentSections(),
                ),
              ),
      ),
    );
  }

  Widget _buildLandscapeBody(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showAdvancedFilters)
            Flexible(
              flex: 4,
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 16, 8, 16),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                S.of(context).advancedFilter,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: S.of(context).close,
                                onPressed: () {
                                  setState(() {
                                    _showAdvancedFilters = false;
                                    _minRate = 0;
                                    _ageRating = AgeRating.all;
                                    _salesRange = SalesRange.all;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ..._buildAdvancedFilterSections(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            flex: 8,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  _showAdvancedFilters ? 8 : 16, 16, 16, 16),
              child: Container(
                color: theme.colorScheme.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildContentSections(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the main content sections as a flat list.
  List<Widget> _buildContentSections() {
    final tt = Theme.of(context).textTheme;
    return [
      if (_searchConditions.isNotEmpty) ...[
        _buildConditionChipsCard(),
        const SizedBox(height: 16),
      ],

      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child:
            Text(S.of(context).search, style: tt.titleSmall),
      ),
      _buildSearchTypePills(),
      if (_currentSearchType == SearchType.tag ||
          _currentSearchType == SearchType.va ||
          _currentSearchType == SearchType.circle)
        _buildExcludeModeIndicator(),

      const SizedBox(height: 12),
      _buildPremiumSearchBar(),

      if (!(MediaQuery.orientationOf(context) == Orientation.landscape) &&
          _showAdvancedFilters) ...[
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        ..._buildAdvancedFilterSections(),
      ],

      const SizedBox(height: 16),
      _buildSearchButton(),

      ..._buildSearchHistory(),
    ];
  }

  Widget _buildConditionChipsCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.filter_list,
                    size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  S.of(context).filter,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _searchConditions.map(_buildConditionChip).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionChip(SearchCondition condition) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayValue = condition.type == SearchType.rjNumber
        ? 'RJ${condition.value}'
        : condition.type == SearchType.tag
            ? TagLocalizer.localizeByName(
                condition.value, Localizations.localeOf(context))
            : condition.value;
    final chipColor =
        condition.isExclude ? colorScheme.errorContainer : colorScheme.secondaryContainer;
    final textColor =
        condition.isExclude ? colorScheme.onErrorContainer : colorScheme.onSecondaryContainer;
    final icon = condition.isExclude
        ? Icons.remove_circle_outline
        : _searchTypePills
            .firstWhere((p) => p.type == condition.type, orElse: () => _searchTypePills.first)
            .filled;

    return Container(
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            '${condition.type.localizedLabel(context)}: $displayValue',
            style: TextStyle(fontSize: 12, color: textColor),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _removeSearchCondition(condition.id),
            child: Icon(Icons.close, size: 14,
                color: textColor.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTypePills() {
    final colorScheme = Theme.of(context).colorScheme;
    const Duration animDur = Duration(milliseconds: 300);

    return SizedBox(
      height: 44,
      child: Row(
        children: List.generate(_searchTypePills.length, (i) {
          final pill = _searchTypePills[i];
          final isActive = _currentSearchType == pill.type;
          final supportsExclude = pill.type == SearchType.tag ||
              pill.type == SearchType.va ||
              pill.type == SearchType.circle;
          final isExcludeActive = isActive && _isExcludeMode && supportsExclude;

          final bgColor = isExcludeActive
              ? colorScheme.errorContainer
              : isActive
                  ? colorScheme.primaryContainer
                  : Colors.transparent;
          final fgColor = isExcludeActive
              ? colorScheme.onErrorContainer
              : isActive
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant;

          return Expanded(
            child: Padding(
              padding:
                  EdgeInsets.only(right: i < _searchTypePills.length - 1 ? 6 : 0),
              child: GestureDetector(
                onTap: () => _selectSearchType(pill.type),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: animDur,
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: animDur,
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(
                              scale: anim,
                              child:
                                  FadeTransition(opacity: anim, child: child),
                            ),
                        child: Icon(
                          isExcludeActive
                              ? Icons.remove_circle_outline
                              : (isActive ? pill.filled : pill.outlined),
                          key: ValueKey(
                              '${pill.type.value}_${isActive}_$_isExcludeMode'),
                          size: 18,
                          color: fgColor,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Flexible(
                        child: Text(
                          pill.type.localizedLabel(context),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.w400,
                            color: fgColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildExcludeModeIndicator() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            _isExcludeMode
                ? Icons.remove_circle_outline
                : Icons.info_outline,
            size: 13,
            color: _isExcludeMode
                ? colorScheme.error
                : colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            _isExcludeMode
                ? '${S.of(context).excludeMode}: ${_currentSearchType.localizedLabel(context)}'
                : '${S.of(context).includeMode}: ${_currentSearchType.localizedLabel(context)}',
            style: TextStyle(
              fontSize: 11,
              color: _isExcludeMode
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isPillType) {
      return Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFilterTextField(),
            _buildFilterableChipsArea(),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: _buildPlainTextField(),
    );
  }

  Widget _buildFilterTextField() {
    final colorScheme = Theme.of(context).colorScheme;
    final s = S.of(context);

    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: '${s.search} ${_currentSearchType.localizedLabel(context).toLowerCase()}...',
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Icon(
            _isExcludeMode
                ? Icons.remove_circle_outline
                : Icons.search,
            size: 20,
            color: _isExcludeMode
                ? colorScheme.error
                : colorScheme.primary,
          ),
        ),
        suffixIcon: _searchController.text.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  tooltip: s.clear,
                ),
              )
            : _isLoadingSuggestions
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        filled: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _addSearchCondition(),
    );
  }

  List<Map<String, dynamic>> _getFilteredItems() {
    List<Map<String, dynamic>> sourceList;
    switch (_currentSearchType) {
      case SearchType.tag:
        sourceList = _allTags;
        break;
      case SearchType.va:
        sourceList = _allVas;
        break;
      case SearchType.circle:
        sourceList = _allCircles;
        break;
      default:
        return [];
    }

    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return sourceList.take(500).toList();
    }

    final locale = Localizations.localeOf(context);
    var filtered = sourceList.where((item) {
      final name = (item['name'] ?? item['title'] ?? '').toString().toLowerCase();
      if (name.startsWith(query) || name.contains(query)) return true;
      if (_currentSearchType == SearchType.tag) {
        final id = item['id'] as int?;
        if (id != null) {
          final locName =
              TagLocalizer.localize(id, item['name'] ?? '', locale).toLowerCase();
          if (locName.startsWith(query) || locName.contains(query)) return true;
        }
      }
      return false;
    }).toList();

    filtered.sort((a, b) {
      final aName = (a['name'] ?? a['title'] ?? '').toString().toLowerCase();
      final bName = (b['name'] ?? b['title'] ?? '').toString().toLowerCase();
      final aStarts = aName.startsWith(query) ? 0 : 1;
      final bStarts = bName.startsWith(query) ? 0 : 1;
      if (aStarts != bStarts) return aStarts.compareTo(bStarts);
      return (b['count'] ?? 0).compareTo(a['count'] ?? 0);
    });

    return filtered.take(300).toList();
  }

  Widget _buildFilterableChipsArea() {
    final hasData = _allTags.isNotEmpty ||
        _allVas.isNotEmpty ||
        _allCircles.isNotEmpty;

    if (!hasData) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final items = _getFilteredItems();
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Text(
          S.of(context).noMatchingTags,
          style: TextStyle(
            fontSize: 12,
            color: cs.outline,
          ),
        ),
      );
    }

    final locale = Localizations.localeOf(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items.map((item) {
              final name = (item['name'] ?? item['title'] ?? '').toString();
              final count = item['count'] ?? 0;
              final displayName =
                  _currentSearchType == SearchType.tag && item['id'] != null
                      ? TagLocalizer.localize(
                          item['id'] as int, name, locale)
                      : name;
              final isSelected = _isItemAlreadySelected(name);

              return _buildSuggestionChip(
                displayName: displayName,
                count: count,
                isSelected: isSelected,
                onTap: isSelected ? null : () => _onChipTapped(name),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionChip({
    required String displayName,
    required int count,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    Color bgColor;
    Color textColor;

    switch (_currentSearchType) {
      case SearchType.tag:
        bgColor = colorScheme.primaryContainer;
        textColor = colorScheme.onPrimaryContainer;
        break;
      case SearchType.va:
        bgColor = colorScheme.tertiaryContainer;
        textColor = colorScheme.onTertiaryContainer;
        break;
      case SearchType.circle:
        bgColor = colorScheme.secondaryContainer;
        textColor = colorScheme.onSecondaryContainer;
        break;
      default:
        bgColor = colorScheme.surfaceContainerHigh;
        textColor = colorScheme.onSurface;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? bgColor.withValues(alpha: 0.35) : bgColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Icon(Icons.check, size: 13, color: textColor.withValues(alpha: 0.45)),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                displayName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected
                      ? textColor.withValues(alpha: 0.45)
                      : textColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 3),
            Text(
              '($count)',
              style: TextStyle(
                fontSize: 10,
                color: isSelected
                    ? textColor.withValues(alpha: 0.35)
                    : textColor.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isItemAlreadySelected(String name) {
    return _searchConditions
        .any((c) => c.type == _currentSearchType &&
            c.value.toLowerCase() == name.toLowerCase());
  }

  void _onChipTapped(String name) {
    HapticFeedback.lightImpact();
    _searchController.text = name;
    _addSearchCondition();
  }

  Widget _buildPlainTextField() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: _currentSearchType.localizedHint(context),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Icon(
            _searchTypePills
                .firstWhere((p) => p.type == _currentSearchType, orElse: () => _searchTypePills.first)
                .filled,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        prefixText:
            _currentSearchType == SearchType.rjNumber ? 'RJ' : null,
        prefixStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.normal,
        ),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: IconButton(
            icon:
                Icon(Icons.add_circle, color: colorScheme.primary, fill: 1),
            onPressed: _addSearchCondition,
            tooltip: S.of(context).add,
          ),
        ),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        filled: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      keyboardType: _currentSearchType == SearchType.rjNumber
          ? TextInputType.number
          : TextInputType.text,
      inputFormatters: _currentSearchType == SearchType.rjNumber
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _addSearchCondition(),
    );
  }

  Widget _buildSearchButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _searchConditions.isEmpty ? null : _performSearch,
        icon: const Icon(Icons.search),
        label: Text(
          _searchConditions.isEmpty
              ? S.of(context).enterSearchContent
              : '${S.of(context).search} (${_searchConditions.length})',
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSearchHistory() {
    final historyState = ref.watch(searchHistoryProvider);
    if (historyState.isLoading || historyState.items.isEmpty) {
      return [];
    }

    final theme = Theme.of(context);
    final s = S.of(context);

    return [
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(s.searchHistory, style: theme.textTheme.titleSmall),
          TextButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(s.clearSearchHistory),
                  content: Text(s.clearSearchHistoryConfirm),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(s.cancel)),
                    FilledButton(
                      onPressed: () {
                        ref
                            .read(searchHistoryProvider.notifier)
                            .clearHistory();
                        Navigator.pop(ctx);
                      },
                      child: Text(s.confirm),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(s.clear),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: historyState.items.take(10).map((item) {
              return Dismissible(
                key: Key(item.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  color: theme.colorScheme.errorContainer,
                  child: Icon(Icons.delete,
                      color: theme.colorScheme.error),
                ),
                onDismissed: (_) => ref
                    .read(searchHistoryProvider.notifier)
                    .removeHistory(item.id),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        theme.colorScheme.primaryContainer,
                    child: Icon(Icons.history,
                        size: 16,
                        color: theme.colorScheme.primary),
                  ),
                  title: Text(item.displayText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    _formatTimestamp(item.timestamp),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => ref
                        .read(searchHistoryProvider.notifier)
                        .removeHistory(item.id),
                    tooltip: s.delete,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                  onTap: () => _searchFromHistory(item),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    ];
  }

  String _formatTimestamp(DateTime timestamp) {
    final s = S.of(context);
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return s.justNow;
    } else if (diff.inHours < 1) {
      return s.minutesAgo(diff.inMinutes);
    } else if (diff.inDays < 1) {
      return s.hoursAgo(diff.inHours);
    } else if (diff.inDays < 7) {
      return s.daysAgo(diff.inDays);
    } else {
      return '${timestamp.month}/${timestamp.day}';
    }
  }

  List<Widget> _buildAdvancedFilterSections() {
    final theme = Theme.of(context);
    final host = ref.watch(authProvider.select((s) => s.host ?? ''));
    final isOfficialServer = ServerUtils.isOfficialServer(host);
    final s = S.of(context);

    return [
      if (isOfficialServer) ...[
        Row(
          children: [
            const Icon(Icons.star, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${s.minRating}: ${s.minRatingStars(_minRate.toStringAsFixed(2))}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Slider(
                    value: _minRate,
                    min: 0,
                    max: 5,
                    divisions: 20,
                    label: _minRate.toStringAsFixed(2),
                    onChanged: (value) =>
                        setState(() => _minRate = value),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<AgeRating>(
              initialValue: _ageRating,
              decoration: InputDecoration(
                labelText: s.ageRatingLabel,
                prefixIcon: const Icon(Icons.shield),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                isDense: true,
              ),
              items: AgeRating.values
                  .where(
                      (rating) => isOfficialServer || rating != AgeRating.r15)
                  .map((rating) {
                return DropdownMenuItem(
                  value: rating,
                  child: Text(rating.localizedLabel(context)),
                );
              }).toList(),
              onChanged: (value) =>
                  setState(() => _ageRating = value ?? AgeRating.all),
            ),
          ),
          if (isOfficialServer) ...[
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<SalesRange>(
                initialValue: _salesRange,
                decoration: InputDecoration(
                  labelText: s.salesLabel,
                  prefixIcon: const Icon(Icons.trending_up),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  isDense: true,
                ),
                items: SalesRange.values.map((range) {
                  return DropdownMenuItem(
                    value: range,
                    child: Text(range == SalesRange.all
                        ? s.salesRangeAll
                        : range.label),
                  );
                }).toList(),
                onChanged: (value) =>
                    setState(() => _salesRange = value ?? SalesRange.all),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 12),
    ];
  }
}