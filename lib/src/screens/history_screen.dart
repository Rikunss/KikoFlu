import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/history_provider.dart';
import '../widgets/history_work_card.dart';
import '../widgets/pagination_bar.dart';
import '../utils/scroll_optimization.dart';
import '../../l10n/app_localizations.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen>
    with AutomaticKeepAliveClientMixin {
  bool _hasVisited = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final history = ref.watch(historyProvider.select((s) => s.records));
    final isLoading = ref.watch(historyProvider.select((s) => s.isLoading));
    final (currentPage, totalCount, pageSize, hasMore) = ref.watch(
      historyProvider.select(
        (s) => (s.currentPage, s.totalCount, s.pageSize, s.hasMore),
      ),
    );

    if (!_hasVisited) {
      _hasVisited = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && history.isEmpty && !isLoading) {
          ref.read(historyProvider.notifier).load(refresh: true);
        }
      });
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: history.isEmpty && !isLoading
          ? _buildEmptyState(context)
          : CustomScrollView(
              // ignore: deprecated_member_use
              cacheExtent: ScrollOptimization.cacheExtent, physics: ScrollOptimization.physics,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 210,
                      childAspectRatio: 0.72,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final record = history[index];
                        return RepaintBoundary(
                          child: HistoryWorkCard(
                            key: ValueKey(record.work.id),
                            record: record,
                          ),
                        );
                      },
                      childCount: history.length,
                    ),
                  ),
                ),
                if (history.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 80, top: 16),
                      child: PaginationBar(
                        currentPage: currentPage,
                        totalCount: totalCount,
                        pageSize: pageSize,
                        hasMore: hasMore,
                        isLoading: isLoading,
                        onGoToPage: (page) {
                          ref.read(historyProvider.notifier).goToPage(page);
                        },
                        onPreviousPage: () {
                          ref.read(historyProvider.notifier).previousPage();
                        },
                        onNextPage: () {
                          ref.read(historyProvider.notifier).nextPage();
                        },
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: history.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => _showClearConfirmation(context, ref),
              tooltip: S.of(context).clearHistory,
              child: const Icon(Icons.delete_outline),
            )
          : null,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = S.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history,
                size: 56,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              s.noPlayHistory,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              S.of(context).noData,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showClearConfirmation(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).clearHistoryTitle),
        content: Text(S.of(context).clearHistoryConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.of(context).clear),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(historyProvider.notifier).clear();
    }
  }
}