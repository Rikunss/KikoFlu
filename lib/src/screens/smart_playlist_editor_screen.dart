import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../models/smart_playlist.dart';
import '../providers/smart_playlists_provider.dart';

/// Screen for creating or editing a smart playlist.
class SmartPlaylistEditorScreen extends ConsumerStatefulWidget {
  final SmartPlaylist? existing;

  const SmartPlaylistEditorScreen({super.key, this.existing});

  @override
  ConsumerState<SmartPlaylistEditorScreen> createState() =>
      _SmartPlaylistEditorScreenState();
}

class _SmartPlaylistEditorScreenState
    extends ConsumerState<SmartPlaylistEditorScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagController = TextEditingController();
  final _vaController = TextEditingController();
  final _circleController = TextEditingController();

  bool _isTagExclude = false;
  SmartPlaylistSortField _sortField = SmartPlaylistSortField.release;
  String _sortDirection = 'desc';

  double _minRating = 0;

  String _subtitleFilter = 'any';

  String _ageFilter = 'any';

  final List<_RuleChip> _ruleChips = [];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final p = widget.existing!;
      _nameController.text = p.name;
      _descriptionController.text = p.description;
      _sortField = p.sortField;
      _sortDirection = p.sortDirection;

      for (final rule in p.rules) {
        switch (rule.type) {
          case SmartPlaylistRuleType.tag:
            _ruleChips.add(_RuleChip(
              type: _RuleChipType.tag,
              value: rule.value,
              isExclude: rule.isExclude,
            ));
          case SmartPlaylistRuleType.va:
            _ruleChips.add(_RuleChip(
              type: _RuleChipType.va,
              value: rule.value,
            ));
          case SmartPlaylistRuleType.circle:
            _ruleChips.add(_RuleChip(
              type: _RuleChipType.circle,
              value: rule.value,
            ));
          case SmartPlaylistRuleType.rating:
            _minRating = double.tryParse(rule.value) ?? 0;
          case SmartPlaylistRuleType.subtitle:
            _subtitleFilter = rule.value == 'true' ? 'yes' : 'no';
          case SmartPlaylistRuleType.age:
            _ageFilter = rule.value;
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    _vaController.dispose();
    _circleController.dispose();
    super.dispose();
  }

  void _addTag() {
    final text = _tagController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _ruleChips.add(_RuleChip(
        type: _RuleChipType.tag,
        value: text,
        isExclude: _isTagExclude,
      ));
      _tagController.clear();
    });
  }

  void _addVa() {
    final text = _vaController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _ruleChips.add(_RuleChip(
        type: _RuleChipType.va,
        value: text,
      ));
      _vaController.clear();
    });
  }

  void _addCircle() {
    final text = _circleController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _ruleChips.add(_RuleChip(
        type: _RuleChipType.circle,
        value: text,
      ));
      _circleController.clear();
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).enterPlaylistNameWarning),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_ruleChips.isEmpty &&
        _minRating == 0 &&
        _subtitleFilter == 'any' &&
        _ageFilter == 'any') {
      final addMore = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(S.of(context).warning),
          content: Text(S.of(context).addAtLeastOneSearchCondition),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.of(context).cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(S.of(context).confirm),
            ),
          ],
        ),
      );
      if (addMore != true) return;
    }

    final rules = <SmartPlaylistRule>[
      ..._ruleChips
          .where((c) => c.type == _RuleChipType.tag)
          .map((c) => SmartPlaylistRule(
                type: SmartPlaylistRuleType.tag,
                value: c.value,
                isExclude: c.isExclude,
              )),
      ..._ruleChips
          .where((c) => c.type == _RuleChipType.va)
          .map((c) => SmartPlaylistRule(
                type: SmartPlaylistRuleType.va,
                value: c.value,
              )),
      ..._ruleChips
          .where((c) => c.type == _RuleChipType.circle)
          .map((c) => SmartPlaylistRule(
                type: SmartPlaylistRuleType.circle,
                value: c.value,
              )),
      if (_minRating > 0)
        SmartPlaylistRule(
          type: SmartPlaylistRuleType.rating,
          value: _minRating.round().toString(),
        ),
      if (_subtitleFilter != 'any')
        SmartPlaylistRule(
          type: SmartPlaylistRuleType.subtitle,
          value: (_subtitleFilter == 'yes').toString(),
        ),
      if (_ageFilter != 'any')
        SmartPlaylistRule(
          type: SmartPlaylistRuleType.age,
          value: _ageFilter,
        ),
    ];

    final notifier = ref.read(smartPlaylistsProvider.notifier);

    if (widget.existing != null) {
      await notifier.update(widget.existing!.copyWith(
        name: name,
        description: _descriptionController.text.trim(),
        rules: rules,
        sortField: _sortField,
        sortDirection: _sortDirection,
      ));
    } else {
      await notifier.create(
        name: name,
        description: _descriptionController.text.trim(),
        rules: rules,
        sortField: _sortField,
        sortDirection: _sortDirection,
      );
    }

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing != null ? s.editPlaylist : s.createPlaylist),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(s.save),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: s.playlistName,
                hintText: s.enterPlaylistName,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.auto_awesome),
              ),
              autofocus: widget.existing == null,
              maxLength: 50,
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: s.playlistDescription,
                hintText: s.addDescription,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.description),
              ),
              maxLines: 2,
              maxLength: 200,
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Icon(Icons.rule, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Search Rules',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _buildRuleInputSection(
              icon: Icons.label_outline,
              label: 'Tags',
              controller: _tagController,
              onAdd: _addTag,
              chipLabel: _isTagExclude ? s.excludeMode : s.includeMode,
              onToggleMode: () => setState(() => _isTagExclude = !_isTagExclude),
              color: colorScheme.primary,
            ),

            _buildRuleInputSection(
              icon: Icons.mic,
              label: s.vaLabel,
              controller: _vaController,
              onAdd: _addVa,
              color: colorScheme.tertiary,
            ),

            _buildRuleInputSection(
              icon: Icons.groups,
              label: s.circleLabel,
              controller: _circleController,
              onAdd: _addCircle,
              color: Colors.orange,
            ),

            const SizedBox(height: 16),

            _buildFilterDropdown(
              label: s.ageRatingLabel,
              icon: Icons.family_restroom,
              value: _ageFilter,
              items: {
                'any': s.ageRatingAll,
                'general': s.ageRatingGeneral,
                'adult': s.ageRatingAdult,
              },
              onChanged: (v) => setState(() => _ageFilter = v),
            ),
            const SizedBox(height: 12),

            _buildRatingSlider(s),
            const SizedBox(height: 12),

            _buildFilterDropdown(
              label: s.hasSubtitle,
              icon: Icons.subtitles,
              value: _subtitleFilter,
              items: {
                'any': s.all,
                'yes': 'Yes',
                'no': 'No',
              },
              onChanged: (v) => setState(() => _subtitleFilter = v),
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Icon(Icons.sort, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  s.sortOptions,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _buildFilterDropdown(
              label: s.sortField,
              icon: Icons.swap_vert,
              value: _sortField.value,
              items: {
                'release': s.sortRelease,
                'create_date': s.sortCreateAt,
                'rating': s.sortRating,
                'dl_count': s.sortDlCount,
                'price': s.sortPrice,
              },
              onChanged: (v) => setState(
                  () => _sortField = SmartPlaylistSortField.fromValue(v)),
            ),
            const SizedBox(height: 12),

            _buildFilterDropdown(
              label: s.sortDirection,
              icon: Icons.arrow_upward,
              value: _sortDirection,
              items: {
                'desc': s.sortDesc,
                'asc': s.sortAsc,
              },
              onChanged: (v) => setState(() => _sortDirection = v),
            ),

            const SizedBox(height: 24),

            if (_ruleChips.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.list, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Active Rules (${_ruleChips.length})',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _ruleChips.asMap().entries.map((entry) {
                  final chip = entry.value;
                  final index = entry.key;
                  return Chip(
                    avatar: Icon(
                      chip.type == _RuleChipType.tag
                          ? (chip.isExclude ? Icons.block : Icons.label)
                          : chip.type == _RuleChipType.va
                              ? Icons.mic
                              : Icons.groups,
                      size: 16,
                    ),
                    label: Text(
                      chip.isExclude
                          ? '✕ ${chip.value}'
                          : chip.value,
                      style: const TextStyle(fontSize: 13),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setState(() => _ruleChips.removeAt(index)),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 32),

            if (_ruleChips.isNotEmpty || _minRating > 0 || _subtitleFilter != 'any' || _ageFilter != 'any') ...[
              Card(
                color: colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.preview, size: 20, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _buildPreview(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _buildPreview() {
    final parts = <String>[];
    for (final chip in _ruleChips) {
      parts.add(chip.value);
    }
    if (_ageFilter != 'any') parts.add('Age: $_ageFilter');
    if (_minRating > 0) parts.add('☆$_minRating+');
    if (_subtitleFilter != 'any') {
      parts.add(_subtitleFilter == 'yes' ? 'Subbed' : 'No sub');
    }
    return 'Search: ${parts.join(', ')} · Sort: ${_sortField.value} $_sortDirection';
  }

  Widget _buildRuleInputSection({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required VoidCallback onAdd,
    Color color = Colors.blue,
    String? chipLabel,
    VoidCallback? onToggleMode,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon, color: color, size: 20),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onSubmitted: (_) => onAdd(),
            ),
          ),
          const SizedBox(width: 8),
          if (chipLabel != null && onToggleMode != null)
            IconButton(
              icon: Text(
                chipLabel,
                style: TextStyle(fontSize: 11, color: color),
              ),
              onPressed: onToggleMode,
              visualDensity: VisualDensity.compact,
              tooltip: 'Toggle include/exclude',
            ),
          IconButton(
            icon: Icon(Icons.add_circle_outline, color: color),
            onPressed: onAdd,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required IconData icon,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: items.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _buildRatingSlider(S s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            const Icon(Icons.star, size: 20, color: Colors.amber),
            const SizedBox(width: 8),
            Text(
              _minRating == 0
                  ? 'Min Rating: Any'
                  : 'Min Rating: ${_minRating.round()} ★',
              style: const TextStyle(fontSize: 14),
            ),
            Expanded(
              child: Slider(
                value: _minRating,
                min: 0,
                max: 5,
                divisions: 5,
                label: _minRating == 0
                    ? 'Any'
                    : '${_minRating.round()} ★',
                onChanged: (v) => setState(() => _minRating = v),
              ),
            ),
            if (_minRating > 0)
              IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () => setState(() => _minRating = 0),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}

/// Internal representation of a rule chip for the editor UI.
class _RuleChip {
  final _RuleChipType type;
  final String value;
  final bool isExclude;

  const _RuleChip({
    required this.type,
    required this.value,
    this.isExclude = false,
  });
}

enum _RuleChipType { tag, va, circle }