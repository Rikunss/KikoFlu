import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/my_reviews_provider.dart';
import '../utils/snackbar_util.dart';
import '../../l10n/app_localizations.dart';
import 'review_progress_dialog.dart';

/// 作品标记管理器 - 封装标记状态的逻辑和UI
/// 可被多个页面复用，确保状态和刷新机制一致
class WorkBookmarkManager {
  final WidgetRef ref;
  final BuildContext context;

  WorkBookmarkManager({
    required this.ref,
    required this.context,
  });

  /// 显示标记对话框并处理更新
  /// 返回包含进度和评分的Map（如果有变化）
  Future<Map<String, dynamic>?> showMarkDialog({
    required int workId,
    required String? currentProgress,
    required int? currentRating,
    required Function(String? newProgress, int? newRating) onChanged,
    String? workTitle,
  }) async {
    // Capture all labels before any async gap to avoid use_build_context_synchronously.
    final markWorkLabel = S.of(context).markWork;
    final bookmarkRemovedLabel = S.of(context).bookmarkRemoved;
    final updatedLabel = S.of(context).updated;
    final setProgressAndRatingLabel = S.of(context).setProgressAndRating;
    final setProgressToLabel = S.of(context).setProgressTo;
    final ratingSetToLabel = S.of(context).ratingSetTo;
    final errorLabelBase = S.of(context).operationFailedWithError;

    final result = await ReviewProgressDialog.show(
      context: context,
      currentProgress: currentProgress,
      currentRating: currentRating,
      title: markWorkLabel,
      workId: workId,
      workTitle: workTitle,
    );

    if (result == null || !context.mounted) return null;

    try {
      final apiService = ref.read(kikoeruApiServiceProvider);

      if (result['progress'] == '__REMOVE__') {
        await apiService.deleteReview(workId);

        if (context.mounted) {
          SnackBarUtil.showSuccess(context, bookmarkRemovedLabel);
        }

        onChanged(null, null);
        ref.read(myReviewsProvider.notifier).load(refresh: true);

        return {'progress': null, 'rating': null};
      } else {
        final newProgress = result['progress'];
        final newRating = result['rating'];

        // Resolve progress label while context is still mounted.
        String? filterLabel;
        if (newProgress != null) {
          filterLabel = ReviewProgressDialog.getProgressLabel(newProgress, context);
        }
        if (!context.mounted) return null;

        await apiService.updateReviewProgress(
          workId,
          progress: result['progress'],
          rating: result['rating'],
        );

        if (!context.mounted) return null;

        String message;
        if (newProgress != null && newRating != null) {
          message = setProgressAndRatingLabel(filterLabel!, newRating);
        } else if (newProgress != null) {
          message = setProgressToLabel(filterLabel!);
        } else if (newRating != null) {
          message = ratingSetToLabel(newRating);
        } else {
          message = updatedLabel;
        }

        if (context.mounted) {
          SnackBarUtil.showSuccess(context, message);
        }

        onChanged(result['progress'], result['rating']);
        ref.read(myReviewsProvider.notifier).load(refresh: true);

        return result;
      }
    } catch (e) {
      if (context.mounted) {
        final errorLabel = errorLabelBase(e.toString());
        SnackBarUtil.showError(context, errorLabel);
      }
    }

    return null;
  }
}
