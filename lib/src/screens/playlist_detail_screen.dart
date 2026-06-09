import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/playlist_detail_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/works_provider.dart';
import '../models/work.dart';
import '../services/storage_service.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/scrollable_appbar.dart';
import '../utils/snackbar_util.dart';
import '../screens/work_detail_screen.dart';
import '../widgets/overscroll_next_page_detector.dart';
import '../utils/string_utils.dart';
import '../widgets/privacy_blur_cover.dart';
import '../widgets/va_chip.dart';
import '../widgets/tag_chip.dart';
import '../utils/scroll_optimization.dart';
import '../../l10n/app_localizations.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final String playlistId;
  final String? playlistName;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    this.playlistName,
  });

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  LayoutType _detailLayout = LayoutType.list;

  @override
  void initState() {
    super.initState();
    // 首次加载数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playlistDetailProvider(widget.playlistId).notifier).load();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateStr;
    }
  }

  /// 显示删除播放列表确认对话框
  Future<void> _showDeleteConfirmDialog() async {
    final state = ref.read(playlistDetailProvider(widget.playlistId));
    final playlist = state.metadata;
    if (playlist == null) return;

    final authState = ref.read(authProvider);
    final currentUserName = authState.currentUser?.name ?? '';
    final isOwner = playlist.userName == currentUserName;

    // 系统播放列表不能删除
    if (playlist.isSystemPlaylist && isOwner) {
      SnackBarUtil.showError(context, S.of(context).systemPlaylistCannotDelete);
      return;
    }

    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isOwner
            ? S.of(context).deletePlaylist
            : S.of(context).unfavoritePlaylist),
        content: Text(
          isOwner
              ? S.of(context).deletePlaylistConfirm
              : S.of(context).unfavoritePlaylistConfirm(playlist.displayName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(S.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
            ),
            child:
                Text(isOwner ? S.of(context).delete : S.of(context).unfavorite),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deletePlaylist();
    }
  }

  /// 删除播放列表
  Future<void> _deletePlaylist() async {
    final authState = ref.read(authProvider);
    final currentUserName = authState.currentUser?.name ?? '';

    try {
      // 显示加载提示
      if (!mounted) return;
      SnackBarUtil.showLoading(context, S.of(context).deleting);

      await ref
          .read(playlistDetailProvider(widget.playlistId).notifier)
          .deletePlaylist(currentUserName);

      if (!mounted) return;

      // 隐藏加载提示
      SnackBarUtil.hide(context);

      // 显示成功提示并返回上一页
      SnackBarUtil.showSuccess(context, S.of(context).deleteSuccess);

      // 延迟一点返回，让用户看到成功提示
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      Navigator.of(context).pop(true); // 返回 true 表示已删除
    } catch (e) {
      if (!mounted) return;

      // 隐藏加载提示
      SnackBarUtil.hide(context);

      // 显示错误提示
      SnackBarUtil.showError(
          context, S.of(context).deleteFailedWithError(e.toString()));
    }
  }

  /// 显示编辑对话框
  void _showEditDialog(metadata) {
    final tt = Theme.of(context).textTheme;
    // 检查权限：只有作者才能编辑
    final authState = ref.read(authProvider);
    final currentUserName = authState.currentUser?.name ?? '';
    final isOwner = metadata.userName == currentUserName;

    if (!isOwner) {
      SnackBarUtil.showError(context, S.of(context).onlyOwnerCanEdit);
      return;
    }

    final nameController = TextEditingController(text: metadata.displayName);
    final descriptionController =
        TextEditingController(text: metadata.description);
    int selectedPrivacy = metadata.privacy;

    showDialog(
      context: context,
      builder: (dialogContext) {
        final isLandscape =
            MediaQuery.of(dialogContext).orientation == Orientation.landscape;
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final dialogWidth = isLandscape ? screenWidth * 0.6 : screenWidth * 0.9;

        return StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: dialogWidth.clamp(300.0, 600.0),
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题栏
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                      child: Row(
                        children: [
                          Text(
                            S.of(context).editPlaylist,
                            style: tt.titleMedium,
                          ),
                        ],
                      ),
                    ),

                    // 内容区域
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 名称输入
                          TextField(
                            controller: nameController,
                            decoration: InputDecoration(
                              labelText: S.of(context).playlistName,
                              hintText: S.of(context).enterPlaylistName,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.title),
                            ),
                            autofocus: true,
                            maxLength: 50,
                          ),
                          const SizedBox(height: 16),

                          // 隐私设置
                          DropdownButtonFormField<int>(
                            initialValue: selectedPrivacy,
                            decoration: InputDecoration(
                              labelText: S.of(context).privacySetting,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.lock_outline),
                              helperText:
                                  _getPrivacyDescription(selectedPrivacy),
                              helperMaxLines: 2,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 0,
                                child:
                                    Text(S.of(context).playlistPrivacyPrivate),
                              ),
                              DropdownMenuItem(
                                value: 1,
                                child:
                                    Text(S.of(context).playlistPrivacyUnlisted),
                              ),
                              DropdownMenuItem(
                                value: 2,
                                child:
                                    Text(S.of(context).playlistPrivacyPublic),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() {
                                  selectedPrivacy = value;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 16),

                          // 描述输入
                          TextField(
                            controller: descriptionController,
                            decoration: InputDecoration(
                              labelText: S.of(context).playlistDescription,
                              hintText: S.of(context).addDescription,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.description),
                            ),
                            maxLines: 1,
                            maxLength: 200,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),

                    // 操作按钮
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(S.of(context).cancel),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () {
                              final name = nameController.text.trim();
                              if (name.isEmpty) {
                                SnackBarUtil.showWarning(context,
                                    S.of(context).playlistNameRequired);
                                return;
                              }
                              Navigator.of(context).pop();
                              _updateMetadata(
                                name: name,
                                privacy: selectedPrivacy,
                                description: descriptionController.text.trim(),
                              );
                            },
                            child: Text(S.of(context).save),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 获取隐私设置描述
  String _getPrivacyDescription(int privacy) {
    switch (privacy) {
      case 0:
        return S.of(context).privacyDescPrivate;
      case 1:
        return S.of(context).privacyDescUnlisted;
      case 2:
        return S.of(context).privacyDescPublic;
      default:
        return '';
    }
  }

  /// 显示添加作品对话框
  void _showAddWorksDialog() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final textController = TextEditingController();
    List<String> parsedWorkIds = [];

    showDialog(
      context: context,
      builder: (dialogContext) {
        final isLandscape =
            MediaQuery.of(dialogContext).orientation == Orientation.landscape;
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final dialogWidth = isLandscape ? screenWidth * 0.6 : screenWidth * 0.9;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: dialogWidth.clamp(300.0, 600.0),
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题栏
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                      child: Row(
                        children: [
                          Text(
                            S.of(context).addWorks,                            style: tt.titleMedium,
                          ),
                        ],
                      ),
                    ),

                    // 内容区域
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 提示文本
                            Text(
                              S.of(context).addWorksInputHint,
                              style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 12),

                            // 输入框
                            TextField(
                              controller: textController,
                              decoration: InputDecoration(
                                labelText: S.of(context).workId,
                                hintText: S.of(context).workIdHint,
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.music_note),
                              ),
                              maxLines: 5,
                              autofocus: true,
                              onChanged: (text) {
                                // 实时解析RJ号
                                final parsed = _parseWorkIds(text);
                                setDialogState(() {
                                  parsedWorkIds = parsed;
                                });
                              },
                            ),
                            const SizedBox(height: 8),

                            // 显示解析结果
                            if (parsedWorkIds.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: cs.primary.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle_outline,
                                          size: 16,
                                          color: cs.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          S.of(context).detectedNWorkIds(
                                              parsedWorkIds.length),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: cs.primary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: parsedWorkIds.map((id) {
                                        return Chip(
                                          label: Text(
                                            id,
                                            style: tt.bodySmall,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          backgroundColor: cs.primaryContainer,
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // 操作按钮
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(S.of(context).cancel),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: parsedWorkIds.isEmpty
                                  ? null
                                  : () {
                                      Navigator.of(context).pop();
                                      _addWorks(parsedWorkIds);
                                    },
                              child: Text(parsedWorkIds.isEmpty
                                  ? S.of(context).add
                                  : S
                                      .of(context)
                                      .addNWorks(parsedWorkIds.length)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 解析文本中的RJ号
  List<String> _parseWorkIds(String text) {
    if (text.isEmpty) return [];

    // 使用正则表达式提取所有RJ开头的作品号（不区分大小写）
    final rjPattern = RegExp(r'RJ\d+', caseSensitive: false);
    final matches = rjPattern.allMatches(text.toUpperCase());

    // 去重并返回
    return matches.map((m) => m.group(0)!).toSet().toList();
  }

  /// 添加作品到播放列表
  Future<void> _addWorks(List<String> workIds) async {
    if (workIds.isEmpty) {
      SnackBarUtil.showWarning(context, S.of(context).noValidWorkIds);
      return;
    }

    try {
      // 显示加载提示
      if (!mounted) return;
      SnackBarUtil.showLoading(
          context, S.of(context).addingNWorks(workIds.length));

      await ref
          .read(playlistDetailProvider(widget.playlistId).notifier)
          .addWorks(workIds);

      if (!mounted) return;

      // 隐藏加载提示
      SnackBarUtil.hide(context);

      // 显示成功提示
      SnackBarUtil.showSuccess(
          context, S.of(context).addedNWorksSuccess(workIds.length));
    } catch (e) {
      if (!mounted) return;

      // 隐藏加载提示
      SnackBarUtil.hide(context);

      // 显示错误提示
      SnackBarUtil.showError(
          context, S.of(context).addFailedWithError(e.toString()));
    }
  }

  /// 显示移除作品确认对话框
  Future<void> _showRemoveWorkConfirmDialog(Work work) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.of(context).removeWork),
        content: Text(S.of(context).removeWorkConfirm(work.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(S.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
            ),
            child: Text(S.of(context).remove),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _removeWork(work.id);
    }
  }

  /// 移除作品
  Future<void> _removeWork(int workId) async {
    try {
      // 乐观更新，UI会立即反应，不需要显示"正在移除"的阻塞式提示
      // 这样可以避免快速操作时SnackBar堆积导致显示延迟

      await ref
          .read(playlistDetailProvider(widget.playlistId).notifier)
          .removeWork(workId);

      if (!mounted) return;

      // 清除之前的提示，避免堆积
      SnackBarUtil.clearAll(context);

      // 显示成功提示，缩短显示时间
      SnackBarUtil.showSuccess(context, S.of(context).removeSuccess,
          duration: const Duration(seconds: 1));
    } catch (e) {
      if (!mounted) return;

      // 隐藏加载提示
      SnackBarUtil.hide(context);

      // 显示错误提示
      SnackBarUtil.showError(
          context, S.of(context).removeFailedWithError(e.toString()));
    }
  }

  /// 更新播放列表元数据
  Future<void> _updateMetadata({
    required String name,
    required int privacy,
    required String description,
  }) async {
    try {
      // 显示加载提示
      if (!mounted) return;
      SnackBarUtil.showLoading(context, S.of(context).saving);

      await ref
          .read(playlistDetailProvider(widget.playlistId).notifier)
          .updateMetadata(
            name: name,
            privacy: privacy,
            description: description,
          );

      if (!mounted) return;

      // 隐藏加载提示
      SnackBarUtil.hide(context);

      // 显示成功提示
      SnackBarUtil.showSuccess(context, S.of(context).saveSuccess);
    } catch (e) {
      if (!mounted) return;

      // 隐藏加载提示
      SnackBarUtil.hide(context);

      // 显示错误提示
      SnackBarUtil.showError(
          context, S.of(context).saveFailedWithError(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playlistDetailProvider(widget.playlistId));

    return Scaffold(
      appBar: ScrollableAppBar(
        actions: [
          IconButton(
            icon: Icon(
              _detailLayout == LayoutType.list
                  ? Icons.grid_view
                  : Icons.view_list,
            ),
            onPressed: () {
              setState(() {
                _detailLayout = _detailLayout == LayoutType.list
                    ? LayoutType.bigGrid
                    : LayoutType.list;
              });
            },
            tooltip: _detailLayout == LayoutType.list
                ? S.of(context).switchToSmallGrid
                : S.of(context).switchToList,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref
                  .read(playlistDetailProvider(widget.playlistId).notifier)
                  .refresh();
            },
            tooltip: S.of(context).refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddWorksDialog,
        tooltip: S.of(context).addWorks,
        child: const Icon(Icons.add),
      ),
      body: ScrollNotificationObserver(
        child: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(PlaylistDetailState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    // 错误状态
    if (state.error != null && state.metadata == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              S.of(context).loadFailed,
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              state.error!,
              style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref
                  .read(playlistDetailProvider(widget.playlistId).notifier)
                  .refresh(),
              icon: const Icon(Icons.refresh),
              label: Text(S.of(context).retry),
            ),
          ],
        ),
      );
    }

    // 加载中且无数据
    if (state.isLoading && state.metadata == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // 空状态
    if (state.works.isEmpty && !state.isLoading) {
      return RefreshIndicator(
        onRefresh: () async => ref
            .read(playlistDetailProvider(widget.playlistId).notifier)
            .refresh(),
        child: CustomScrollView(
          slivers: [
            if (state.metadata != null) _buildMetadataSection(state.metadata!, state),
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.music_note,
                      size: 64,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      S.of(context).noWorks,
                      style: textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      S.of(context).playlistNoWorksDescription,
                      style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => ref
          .read(playlistDetailProvider(widget.playlistId).notifier)
          .refresh(),
      child: OverscrollNextPageDetector(
        hasNextPage: state.hasMore,
        isLoading: state.isLoading,
        onNextPage: () async {
          await ref
              .read(playlistDetailProvider(widget.playlistId).notifier)
              .nextPage();
          // 等待一帧后滚动到顶部，确保内容已加载
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToTop();
          });
        },
        child: CustomScrollView(
          // ignore: deprecated_member_use
          cacheExtent: ScrollOptimization.cacheExtent, controller: _scrollController,
          physics: ScrollOptimization.physics,
          slivers: [
            // 元数据信息
            if (state.metadata != null) _buildMetadataSection(state.metadata!, state),

            // Listening stats
            if (state.works.isNotEmpty) _buildListeningStatsSection(state),

            // 作品列表
            if (_detailLayout == LayoutType.list) ...[
              SliverPadding(
                padding: const EdgeInsets.all(8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final work = state.works[index];
                      final currentUserName = ref.watch(currentUserProvider.select((u) => u?.name ?? ''));
                      final isOwner = state.metadata?.userName == currentUserName;
                      return RepaintBoundary(
                        key: ValueKey(work.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: _buildPlaylistWorkCard(work, isOwner),
                        ),
                      );
                    },
                    childCount: state.works.length,
                  ),
                ),
              ),
            ] else ...[
              // Grid view
              SliverPadding(
                padding: const EdgeInsets.all(4),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final work = state.works[index];
                      final currentUserName = ref.watch(currentUserProvider.select((u) => u?.name ?? ''));
                      final isOwner = state.metadata?.userName == currentUserName;
                      return RepaintBoundary(
                        key: ValueKey(work.id),
                        child: _buildPlaylistWorkCard(work, isOwner),
                      );
                    },
                    childCount: state.works.length,
                  ),
                ),
              ),
            ],

            // 分页控件
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
              sliver: SliverToBoxAdapter(
                child: PaginationBar(
                  currentPage: state.currentPage,
                  totalCount: state.totalCount,
                  pageSize: state.pageSize,
                  hasMore: state.hasMore,
                  isLoading: state.isLoading,
                  onPreviousPage: () {
                    ref
                        .read(
                            playlistDetailProvider(widget.playlistId).notifier)
                        .previousPage();
                    _scrollToTop();
                  },
                  onNextPage: () {
                    ref
                        .read(
                            playlistDetailProvider(widget.playlistId).notifier)
                        .nextPage();
                    _scrollToTop();
                  },
                  onGoToPage: (page) {
                    ref
                        .read(
                            playlistDetailProvider(widget.playlistId).notifier)
                        .goToPage(page);
                    _scrollToTop();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataSection(metadata, PlaylistDetailState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = S.of(context);

    // Compute aggregate data from works
    final totalDur = totalDurationFromWorks(state.works);
    final allFormats = <String>{};
    for (final work in state.works) {
      if (work.children != null) {
        allFormats.addAll(extractAudioFormats(work.children));
      }
    }
    final formatsStr = allFormats.isNotEmpty ? allFormats.join('+') : '';

    // Date display
    final displayDate = metadata.updatedAt.isNotEmpty &&
            metadata.updatedAt != metadata.createdAt
        ? _formatDate(metadata.updatedAt)
        : _formatDate(metadata.createdAt);
    final dateLabel = metadata.updatedAt.isNotEmpty &&
            metadata.updatedAt != metadata.createdAt
        ? s.lastUpdated
        : s.createdTime;

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row with actions
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            metadata.displayName,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.person_outline, size: 14, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(
                                metadata.userName,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Privacy badge
                              _buildPrivacyBadge(metadata.privacy),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Edit/delete actions
                    Builder(
                      builder: (context) {
                        final currentUserName = ref.watch(currentUserProvider.select((u) => u?.name ?? ''));
                        final isOwner = metadata.userName == currentUserName;
                        if (isOwner) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => _showEditDialog(metadata),
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: s.edit,
                                visualDensity: VisualDensity.compact,
                              ),
                              IconButton(
                                onPressed: _showDeleteConfirmDialog,
                                icon: const Icon(Icons.delete_outline),
                                tooltip: s.delete,
                                visualDensity: VisualDensity.compact,
                                color: colorScheme.error,
                              ),
                            ],
                          );
                        }
                        return IconButton(
                          onPressed: _showDeleteConfirmDialog,
                          icon: const Icon(Icons.delete_outline),
                          tooltip: s.unfavorite,
                          visualDensity: VisualDensity.compact,
                          color: colorScheme.error,
                        );
                      },
                    ),
                  ],
                ),

                // Description
                if (metadata.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    metadata.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Stats row: works, plays, duration
                Row(
                  children: [
                    _buildStatChip(Icons.music_note, s.nWorksCount(metadata.worksCount), colorScheme.primary),
                    if (metadata.playbackCount > 0) ...[
                      const SizedBox(width: 8),
                      _buildStatChip(Icons.play_circle_outline, s.nPlaysCount(metadata.playbackCount), colorScheme.primary),
                    ],
                    if (totalDur > 0) ...[
                      const SizedBox(width: 8),
                      _buildStatChip(Icons.access_time, formatDurationShort(totalDur), Colors.blue[700]!),
                    ],
                  ],
                ),

                if (formatsStr.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.audio_file, size: 14, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        formatsStr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 8),

                // Date
                if (displayDate.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 14, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                      Text(
                        '$dateLabel: $displayDate',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Aggregate listening statistics section for this playlist.
  Widget _buildListeningStatsSection(PlaylistDetailState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = S.of(context);
    final works = state.works;
    if (works.isEmpty) return const SliverToBoxAdapter();

    // --- Compute aggregates ---

    // Average rating (weighted by rateCount)
    double totalWeightedRating = 0;
    int totalRatings = 0;
    for (final w in works) {
      if (w.rateAverage != null && w.rateCount != null && w.rateCount! > 0) {
        totalWeightedRating += w.rateAverage! * w.rateCount!;
        totalRatings += w.rateCount!;
      }
    }
    final avgRating = totalRatings > 0 ? (totalWeightedRating / totalRatings) : 0.0;

    // Total dlCount (sales)
    int totalDlCount = 0;
    for (final w in works) {
      if (w.dlCount != null) totalDlCount += w.dlCount!;
    }

    // Top VAs: count occurrences
    final vaCount = <String, int>{};
    for (final w in works) {
      if (w.vas != null) {
        for (final va in w.vas!) {
          vaCount[va.name] = (vaCount[va.name] ?? 0) + 1;
        }
      }
    }
    final sortedVas = vaCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topVas = sortedVas.take(3).toList();

    // Top tags: count occurrences
    final tagCount = <String, int>{};
    for (final w in works) {
      if (w.tags != null) {
        for (final tag in w.tags!) {
          tagCount[tag.name] = (tagCount[tag.name] ?? 0) + 1;
        }
      }
    }
    final sortedTags = tagCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topTags = sortedTags.take(6).toList();

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(Icons.analytics_outlined, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      s.listeningStatsTitle,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Row 1: Avg Rating + Total Sales
                Row(
                  children: [
                    Expanded(
                      child: _buildStatTile(
                        icon: Icons.star,
                        iconColor: Colors.amber[700]!,
                        value: avgRating > 0 ? avgRating.toStringAsFixed(1) : '—',
                        label: s.ratingLabel,
                        subtitle: totalRatings > 0 ? s.ratingsCount(totalRatings) : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatTile(
                        icon: Icons.trending_up,
                        iconColor: Colors.green[700]!,
                        value: totalDlCount > 0 ? '${totalDlCount}' : '—',
                        label: s.salesLabel,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatTile(
                        icon: Icons.access_time,
                        iconColor: Colors.blue[700]!,
                        value: formatDurationShort(totalDurationFromWorks(works)),
                        label: s.durationLabel,
                      ),
                    ),
                  ],
                ),

                // Top VAs
                if (topVas.isNotEmpty) ...[
                  const SizedBox(height: 16),                    Text(
                    s.vaLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: topVas.map((entry) => _buildTopVaChip(entry.key, entry.value, works.length)).toList(),
                  ),
                ],

                // Top tags
                if (topTags.isNotEmpty) ...[
                  const SizedBox(height: 16),                    Text(
                    s.tagLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: topTags.map((entry) => _buildTopTagChip(entry.key, entry.value, works.length)).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatTile({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopVaChip(String name, int count, int totalWorks) {
    final pct = (count / totalWorks * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic, size: 12, color: Colors.blue[700]),
          const SizedBox(width: 4),
          Text(
            name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.blue[800],
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$pct%',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.blue[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTagChip(String name, int count, int totalWorks) {
    final pct = (count / totalWorks * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.indigo[800],
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '$pct%',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: Colors.indigo[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyBadge(int privacy) {
    final colorScheme = Theme.of(context).colorScheme;

    IconData icon;
    String label;
    switch (privacy) {
      case 0:
        icon = Icons.lock;
        label = S.of(context).playlistPrivacyPrivate;
        break;
      case 1:
        icon = Icons.link;
        label = S.of(context).playlistPrivacyUnlisted;
        break;
      case 2:
        icon = Icons.public;
        label = S.of(context).playlistPrivacyPublic;
        break;
      default:
        icon = Icons.lock;
        label = '';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Enhanced playlist work card with rich metadata.
  Widget _buildPlaylistWorkCard(Work work, bool isOwner) {
    final host = ref.watch(serverHostProvider) ?? '';
    final token = ref.watch(authTokenProvider) ?? '';
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = S.of(context);

    final httpHeaders = StorageService.serverCookieHeaders;

    // Extract audio formats from work children
    final formats = work.children != null ? extractAudioFormats(work.children) : <String>{};
    final formatsList = formats.take(2).toList();
    final hasMoreFormats = formats.length > 2;

    // Progress icon
    Widget? progressIcon;
    if (work.progress != null) {
      switch (work.progress) {
        case 'listening':
          progressIcon = Icon(Icons.headphones, size: 12, color: Colors.green[600]);
        case 'listened':
          progressIcon = Icon(Icons.check_circle, size: 12, color: Colors.blue[600]);
        case 'marked':
          progressIcon = Icon(Icons.bookmark, size: 12, color: Colors.orange[600]);
        case 'replay':
          progressIcon = Icon(Icons.replay, size: 12, color: Colors.purple[600]);
        case 'postponed':
          progressIcon = Icon(Icons.snooze, size: 12, color: Colors.grey[600]);
      }
    }

    // Age rating badge
    Widget? ageBadge;
    if (work.age != null && work.age!.isNotEmpty && work.age != 'general' && work.age != 'all') {
      final isAdult = work.age == 'adult' || work.age == 'r18' || work.age == 'R-18';
      ageBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: isAdult ? Colors.red.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          work.age!.toUpperCase(),
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: isAdult ? Colors.red[700] : Colors.orange[700],
          ),
        ),
      );
    }

    if (_detailLayout == LayoutType.list) {
      return InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => WorkDetailScreen(work: work)),
        ),
        child: Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top row: cover + info
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cover
                    Hero(
                      tag: 'work_cover_${work.id}',
                      child: PrivacyBlurCover(
                        borderRadius: BorderRadius.circular(6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: CachedNetworkImage(
                            imageUrl: work.getCoverImageUrl(host, token: token),
                            httpHeaders: httpHeaders,
                            cacheKey: 'work_cover_${work.id}',
                            memCacheWidth: (64 * MediaQuery.devicePixelRatioOf(context)).round(),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: colorScheme.surfaceContainerHighest,
                              child: Center(child: Icon(Icons.image, color: colorScheme.onSurfaceVariant, size: 24)),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: colorScheme.surfaceContainerHighest,
                              child: Center(child: Icon(Icons.broken_image, color: colorScheme.onSurfaceVariant, size: 24)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Info column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Title
                          Text(
                            work.title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),

                          // RJ + Circle + Age badge row
                          Wrap(
                            spacing: 6,
                            runSpacing: 3,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                formatRJCode(work.id),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 11,
                                ),
                              ),
                              if (work.name != null && work.name!.isNotEmpty)
                                Text(
                                  work.name!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              if (ageBadge != null) ageBadge,
                            ],
                          ),

                          const SizedBox(height: 4),

                          // Rating & Duration & Price row
                          Wrap(
                            spacing: 8,
                            runSpacing: 3,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // Rating stars
                              if (work.rateAverage != null && work.rateCount != null && work.rateCount! > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.star, size: 13, color: Colors.amber[700]),
                                    const SizedBox(width: 2),
                                    Text(
                                      work.rateAverage!.toStringAsFixed(1),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.amber[700],
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      ' (${work.rateCount})',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),

                              // Duration
                              if (work.duration != null && work.duration! > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.access_time, size: 12, color: Colors.blue[600]),
                                    const SizedBox(width: 2),
                                    Text(
                                      formatDurationShort(work.duration!),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.blue[700],
                                        fontWeight: FontWeight.w500,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),

                              // Price
                              if (work.price != null && work.price! > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.monetization_on, size: 12, color: Colors.red[600]),
                                    const SizedBox(width: 2),
                                    Text(
                                      s.priceInYen(work.price!),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.red[700],
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),

                          // Format badges + Subtitle + Progress row
                          if (formatsList.isNotEmpty || work.hasSubtitle == true || work.userRating != null && work.userRating! > 0 || progressIcon != null) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              runSpacing: 3,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                // Format badges
                                ...formatsList.map((fmt) => _buildFormatTag(fmt)),
                                if (hasMoreFormats)
                                  Text(
                                    '+${formats.length - 2}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 9,
                                    ),
                                  ),

                                // Subtitle badge
                                if (work.hasSubtitle == true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Icon(Icons.closed_caption, size: 12, color: Colors.teal[700]),
                                  ),

                                // User rating
                                if (work.userRating != null && work.userRating! > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.person, size: 9, color: colorScheme.onPrimaryContainer),
                                        const SizedBox(width: 1),
                                        Icon(Icons.star, size: 9, color: Colors.amber[700]),
                                        const SizedBox(width: 1),
                                        Text(
                                          '${work.userRating}',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onPrimaryContainer,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 9,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                // Progress icon
                                if (progressIcon != null) progressIcon!,
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Remove button (owner only)
                    if (isOwner)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                        color: colorScheme.error,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _showRemoveWorkConfirmDialog(work),
                        tooltip: s.removeFromPlaylist,
                      ),
                  ],
                ),

                // VA chips
                if (work.vas != null && work.vas!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: work.vas!.take(3).map((va) {
                      return VaChip(
                        va: va,
                        fontSize: 10,
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        borderRadius: 6,
                        fontWeight: FontWeight.w500,
                      );
                    }).toList(),
                  ),
                  if (work.vas!.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '+${work.vas!.length - 3} more',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 9,
                        ),
                      ),
                    ),
                ],

                // Tag chips
                if (work.tags != null && work.tags!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 3,
                    runSpacing: 2,
                    children: work.tags!.take(4).map((tag) {
                      return TagChip(
                        tag: tag,
                        fontSize: 9,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        borderRadius: 5,
                        fontWeight: FontWeight.w400,
                      );
                    }).toList(),
                  ),
                  if (work.tags!.length > 4)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '+${work.tags!.length - 4} more',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 9,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    } else {
      // Grid layout - compact version
      return InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => WorkDetailScreen(work: work)),
        ),
        child: Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cover
              AspectRatio(
                aspectRatio: 1.3,
                child: Stack(
                  children: [
                    PrivacyBlurCover(
                      borderRadius: BorderRadius.circular(0),
                      child: CachedNetworkImage(
                        imageUrl: work.getCoverImageUrl(host, token: token),
                        httpHeaders: httpHeaders,
                        cacheKey: 'work_cover_${work.id}',
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (context, url) => Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: Center(child: Icon(Icons.image, color: colorScheme.onSurfaceVariant)),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: Center(child: Icon(Icons.broken_image, color: colorScheme.onSurfaceVariant)),
                        ),
                      ),
                    ),
                    // RJ tag
                    Positioned(
                      top: 4, left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          formatRJCode(work.id),
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    // CC badge
                    if (work.hasSubtitle == true)
                      Positioned(
                        bottom: 4, left: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Icon(Icons.closed_caption, size: 12, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              // Info
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      work.title,
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (work.rateAverage != null && work.rateCount != null && work.rateCount! > 0) ...[
                          Icon(Icons.star, size: 10, color: Colors.amber[700]),
                          const SizedBox(width: 2),
                          Text(
                            work.rateAverage!.toStringAsFixed(1),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.amber[700], fontWeight: FontWeight.w600, fontSize: 10,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (work.duration != null && work.duration! > 0)
                          Text(
                            formatDurationShort(work.duration!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.blue[700], fontSize: 9,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  /// Build a small format tag like [MP3] [FLAC]
  Widget _buildFormatTag(String format) {
    final colorScheme = Theme.of(context).colorScheme;
    Color color;
    switch (format) {
      case 'FLAC':
        color = Colors.purple;
        break;
      case 'WAV':
        color = Colors.blue;
        break;
      case 'MP3':
        color = Colors.orange;
        break;
      case 'AAC':
        color = Colors.teal;
        break;
      default:
        color = colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        format,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
