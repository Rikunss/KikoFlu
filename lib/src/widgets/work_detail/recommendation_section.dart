import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../blur_hash_widget.dart';

import '../../models/work.dart';
import '../../providers/auth_provider.dart';
import '../../providers/recommendation_provider.dart';
import '../../providers/work_detail_display_provider.dart';
import '../../services/cookie_service.dart';
import '../../services/blurhash_service.dart';
import '../../screens/work_detail_screen.dart';
import '../../widgets/privacy_blur_cover.dart';
import '../../../l10n/app_localizations.dart';

/// 作品详情页底部的"相关推荐"横向滚动区域
class RecommendationSection extends ConsumerStatefulWidget {
  final Work work;

  const RecommendationSection({super.key, required this.work});

  @override
  ConsumerState<RecommendationSection> createState() =>
      _RecommendationSectionState();
}

class _RecommendationSectionState
    extends ConsumerState<RecommendationSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier =
          ref.read(recommendationProvider(widget.work.id).notifier);
      final state = ref.read(recommendationProvider(widget.work.id));
      if (state.recommendations.isEmpty && !state.isLoading) {
        notifier.loadRecommendations(widget.work);
      }
    });
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  /// Start/stop the shimmer animation based on whether shimmer is visible.
  /// Prevents wasting CPU when data has loaded or section is hidden.
  void _syncShimmer(bool showShimmer) {
    if (!mounted) return;
    if (showShimmer && !_shimmerController.isAnimating) {
      _shimmerController.repeat(reverse: true);
    } else if (!showShimmer && _shimmerController.isAnimating) {
      _shimmerController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(workDetailDisplayProvider);
    final showRecommendations = settings.showRecommendations;
    if (!showRecommendations) {
      _syncShimmer(false);
      return const SizedBox.shrink();
    }

    final state = ref.watch(recommendationProvider(widget.work.id));

    _syncShimmer(state.isLoading);

    if (state.isLoading) {
      return _buildSection(
        context,
        child: SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, __) => _buildShimmerCard(context),
          ),
        ),
      );
    }

    if (state.recommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildSection(
      context,
      child: SizedBox(
        height: 190,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: state.recommendations.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            return _RecommendationCard(
              work: state.recommendations[index],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, {required Widget child}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    Icons.recommend_outlined,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    S.of(context).relatedRecommendations,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        child,
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildShimmerCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: _shimmerController.drive(
        Tween<double>(begin: 0.3, end: 0.7),
      ),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 14,
              width: 100,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 12,
              width: 60,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 推荐作品卡片
class _RecommendationCard extends ConsumerWidget {
  final Work work;

  const _RecommendationCard({required this.work});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (host, token) = ref.watch(authProvider.select(
      (s) => (s.host ?? '', s.token ?? ''),
    ));

    return SizedBox(
      width: 120,        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => WorkDetailScreen(
                work: work,
                heroTag: 'rec_work_cover_${work.id}',
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                height: 120,
                child: _buildCover(context, host, token),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              work.title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            if (work.rateAverage != null && work.rateAverage! > 0)
              Row(
                children: [
                  Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: Colors.amber.shade700,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    work.rateAverage!.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context, String host, String token) {
    if (host.isEmpty) {
      return _buildPlaceholder(context);
    }

    final url = work.getCoverImageUrl(host, token: token);
    final blurHash = work.blurHash ??
        BlurHashService.instance.getBlurHash(work.id);

    return Hero(
      tag: 'rec_work_cover_${work.id}',
      child: PrivacyBlurCover(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: url,
          httpHeaders: CookieService.coverHttpHeaders(token: token),
          cacheKey: 'work_cover_${work.id}',
          memCacheWidth:
              (120 * MediaQuery.of(context).devicePixelRatio).round(),
          fadeInDuration: const Duration(milliseconds: 120),
          fit: BoxFit.cover,
          placeholder: (context, _) => _buildPlaceholder(context, blurHash: blurHash),
          errorWidget: (context, _, __) => _buildPlaceholder(context, blurHash: blurHash),
          imageBuilder: (context, imageProvider) {
            if (work.blurHash == null &&
                !BlurHashService.instance.hasBlurHash(work.id)) {
              BlurHashService.instance.generateIfNeeded(work.id, url);
            }
            return Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: imageProvider,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context, {String? blurHash}) {
    if (blurHash != null && blurHash.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BlurHashWidget(
          hash: blurHash,
          imageFit: BoxFit.cover,
        ),
      );
    }
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(
        child: Icon(Icons.audiotrack, color: Colors.grey, size: 32),
      ),
    );
  }
}