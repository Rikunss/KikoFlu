import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../models/audio_bookmark.dart';
import '../../providers/audio_provider.dart';
import '../../services/bookmark_service.dart';
import '../responsive_dialog.dart';

/// Bottom sheet showing all bookmarks for the current track.
///
/// Each bookmark shows its timestamp, optional note, and a delete button.
/// Tapping a bookmark seeks to that position in the track.
class BookmarksSheet extends ConsumerStatefulWidget {
  const BookmarksSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const BookmarksSheet(),
    );
  }

  @override
  ConsumerState<BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends ConsumerState<BookmarksSheet> {
  @override
  Widget build(BuildContext context) {
    final currentTrack = ref.watch(currentTrackProvider).valueOrNull;
    final bookmarksAsync = ref.watch(
      trackBookmarksProvider(currentTrack?.id ?? ''),
    );
    final bookmarks = bookmarksAsync.valueOrNull ?? [];
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final s = S.of(context);

    return DraggableScrollableSheet(
      initialChildSize: bookmarks.isEmpty ? 0.3 : 0.55,
      maxChildSize: 0.85,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.bookmark_rounded,
                        color: colorScheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      s.audioBookmarksTitle,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (bookmarks.isNotEmpty)
                      Text(
                        '${bookmarks.length}',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(),
              // Bookmark list or empty state
              Expanded(
                child: bookmarks.isEmpty
                    ? _buildEmptyState(context, theme, s, currentTrack)
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: bookmarks.length,
                        itemBuilder: (context, index) {
                          return _BookmarkTile(
                            bookmark: bookmarks[index],
                            onTap: () {
                              ref
                                  .read(audioPlayerControllerProvider.notifier)
                                  .seekAndPersist(bookmarks[index].position);
                              Navigator.pop(context);
                            },
                            onDelete: () {
                              ref.read(bookmarkServiceProvider).remove(bookmarks[index].id);
                            },
                            onEditNote: () {
                              _showEditNoteDialog(
                                  context, bookmarks[index], ref.read(bookmarkServiceProvider), s);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    S s,
    dynamic currentTrack,
  ) {
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border_rounded,
                size: 56, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              currentTrack != null
                  ? s.audioBookmarksEmptyTrack
                  : s.audioBookmarksEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              s.audioBookmarksHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showEditNoteDialog(
    BuildContext context,
    AudioBookmark bookmark,
    BookmarkService service,
    S s,
  ) {
    final controller = TextEditingController(text: bookmark.note ?? '');
    showDialog(
      context: context,
      builder: (ctx) => ResponsiveAlertDialog(
        title: Text(s.audioBookmarksEditNote),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: s.audioBookmarksNoteHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              service.updateNote(bookmark.id, controller.text.trim());
              Navigator.pop(ctx);
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  final AudioBookmark bookmark;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEditNote;

  const _BookmarkTile({
    required this.bookmark,
    required this.onTap,
    required this.onDelete,
    required this.onEditNote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dismissible(
      key: ValueKey(bookmark.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: colorScheme.error,
        child: Icon(Icons.delete_outline, color: colorScheme.onError),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return true;
      },
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          radius: 22,
          child: Icon(
            Icons.bookmark_rounded,
            size: 18,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          bookmark.formattedPosition,
          style: theme.textTheme.titleSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: bookmark.note != null && bookmark.note!.isNotEmpty
            ? Text(
                bookmark.note!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : Text(
                'Tap to seek',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
        trailing: IconButton(
          icon: Icon(Icons.edit_outlined,
              size: 18, color: colorScheme.onSurfaceVariant),
          onPressed: onEditNote,
        ),
        onTap: onTap,
      ),
    );
  }
}
