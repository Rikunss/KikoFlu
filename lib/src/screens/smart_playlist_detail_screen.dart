import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../models/smart_playlist.dart';
import '../providers/smart_playlists_provider.dart';
import '../providers/smart_playlist_evaluator_provider.dart';

import '../widgets/works_grid_view.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/overscroll_next_page_detector.dart';
import 'smart_playlist_editor_screen.dart';

/// Screen displaying works from a smart playlist.
class SmartPlaylistDetailScreen extends ConsumerStatefulWidget {
  final SmartPlaylist playlist;

  const SmartPlaylistDetailScreen({super.key, required this.playlist});

  @override
  ConsumerState<SmartPlaylistDetailScreen> createState() =>
      _SmartPlaylistDetailScreenState();
}

class _SmartPlaylistDetailScreenState
    extends ConsumerState<SmartPlaylistDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _edit() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) =>
            SmartPlaylistEditorScreen(existing: widget.playlist),
      ),
    );
    if (result == true && mounted) {
      // Refresh the evaluator via the new playlist state
      final playlists = ref.read(smartPlaylistsProvider);
      final updated =
          playlists.where((p) => p.id == widget.playlist.id).firstOrNull;
      if (updated != null) {
        ref.invalidate(smartPlaylistEvaluatorProvider(updated));
        ref.read(smartPlaylistEvaluatorProvider(updated).notifier).refresh();
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(context).deletePlaylist),
        content: Text(S.of(context).deletePlaylistConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(S.of(context).delete),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      ref.read(smartPlaylistsProvider.notifier).delete(widget.playlist.id);
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = S.of(context);
    final evalState = ref.watch(smartPlaylistEvaluatorProvider(widget.playlist));
    final layoutType = ref.watch(smartPlaylistLayoutProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: _edit,
            tooltip: s.edit,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(smartPlaylistEvaluatorProvider(widget.playlist).notifier)
                .refresh(),
            tooltip: s.refresh,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: colorScheme.error),
            onPressed: _delete,
            tooltip: s.delete,
          ),
        ],
      ),
      body: evalState.error != null && evalState.works.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: colorScheme.error),
                  const SizedBox(height: 16),
                  Text(s.loadFailed, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      evalState.error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => ref
                        .read(
                            smartPlaylistEvaluatorProvider(widget.playlist).notifier)
                        .refresh(),
                    icon: const Icon(Icons.refresh),
                    label: Text(s.retry),
                  ),
                ],
              ),
            )
          : evalState.isLoading && evalState.works.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : evalState.works.isEmpty
                  ? RefreshIndicator(
                      onRefresh: () => ref
                          .read(smartPlaylistEvaluatorProvider(widget.playlist)
                              .notifier)
                          .load(refresh: true),
                      child: ListView(
                        children: [
                          const SizedBox(height: 100),
                          Center(
                            child: Column(
                              children: [
                                Icon(Icons.search_off,
                                    size: 64, color: colorScheme.onSurfaceVariant),
                                const SizedBox(height: 16),
                                Text(s.noResults,
                                    style: theme.textTheme.titleLarge),
                                const SizedBox(height: 8),
                                Text(
                                  s.playlistEmpty,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => ref
                          .read(
                              smartPlaylistEvaluatorProvider(widget.playlist).notifier)
                          .load(refresh: true),
                      child: OverscrollNextPageDetector(
                        hasNextPage: evalState.hasMore,
                        isLoading: evalState.isLoading,
                        onNextPage: () {
                            ref
                                .read(smartPlaylistEvaluatorProvider(widget.playlist)
                                    .notifier)
                                .loadNextPage();
                          },
                        child: WorksGridView(
                          works: evalState.works,
                          layoutType: layoutType,
                          scrollController: _scrollController,
                          isLoading: evalState.isLoading,
                          paginationWidget: PaginationBar(
                            currentPage: evalState.currentPage,
                            totalCount: evalState.totalCount,
                            pageSize: 40,
                            hasMore: evalState.hasMore,
                            isLoading: evalState.isLoading,
                            onPreviousPage: () {},
                            onNextPage: () {
                                ref
                                    .read(smartPlaylistEvaluatorProvider(
                                            widget.playlist)
                                        .notifier)
                                    .loadNextPage();
                              },
                            onGoToPage: (page) {},
                          ),
                        ),
                      ),
                    ),
    );
  }
}


