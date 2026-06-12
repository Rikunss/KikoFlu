import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/work.dart';
import '../../providers/auth_provider.dart';
import '../../providers/series_works_provider.dart';
import '../../screens/work_detail_screen.dart';
import '../privacy_blur_cover.dart';
import '../../../l10n/app_localizations.dart';

/// Shows other works from the same circle/series in a horizontal scrollable row.
/// Placed below the recommendation section in the work detail page.
class SeriesSection extends ConsumerStatefulWidget {
  final Work work;

  const SeriesSection({super.key, required this.work});

  @override
  ConsumerState<SeriesSection> createState() => _SeriesSectionState();
}

class _SeriesSectionState extends ConsumerState<SeriesSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Lazy load after first frame to not block detail page rendering
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier =
          ref.read(seriesWorksProvider(widget.work.id).notifier);
      final state = ref.read(seriesWorksProvider(widget.work.id));
      if (state.works.isEmpty && !state.isLoading) {
        notifier.loadCircleWorks(widget.work);
      }
    });
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

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
    // Don't show if work has no circle
    final circleName = widget.work.name;
    if (circleName == null || circleName.isEmpty) {
      return const SizedBox.shrink();
    }

    final state = ref.watch(seriesWorksProvider(widget.work.id));
    _syncShimmer(state.isLoading);

    // Loading shimmer
    if (state.isLoading) {
      return _buildSection(
        context,
        circleName,
        child: SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, __) => _buildShimmerCard(context),
          ),
        ),
      );
    }

    // No results or error: hide
    if (state.works.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildSection(
      context,
      circleName,
      child: SizedBox(
        height: 190,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: state.works.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            return _SeriesCard(
              work: state.works[index],
              circleName: circleName,
            );
          },
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String circleName, {required Widget child}) {
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
                    Icons.collections_bookmark_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      S.of(context).moreFromCircle(circleName),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

/// Card for a series/circle work in the horizontal scroll.
class _SeriesCard extends ConsumerWidget {
  final Work work;
  final String circleName;

  const _SeriesCard({required this.work, required this.circleName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (host, token) = ref.watch(authProvider.select(
      (s) => (s.host ?? '', s.token ?? ''),
    ));

    return SizedBox(
      width: 120,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => WorkDetailScreen(
                work: work,
                heroTag: 'series_work_cover_${work.id}',
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                height: 120,
                child: _buildCover(context, host, token),
              ),
            ),
            const SizedBox(height: 6),
            // Title
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
            // Rating
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

    return Hero(
      tag: 'series_work_cover_${work.id}',
      child: PrivacyBlurCover(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: url,
          cacheKey: 'work_cover_${work.id}',
          memCacheWidth:
              (120 * MediaQuery.of(context).devicePixelRatio).round(),
          fadeInDuration: const Duration(milliseconds: 120),
          fit: BoxFit.cover,
          placeholder: (context, _) => _buildPlaceholder(context),
          errorWidget: (context, _, __) => _buildPlaceholder(context),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(
        child: Icon(Icons.audiotrack, color: Colors.grey, size: 32),
      ),
    );
  }
}
