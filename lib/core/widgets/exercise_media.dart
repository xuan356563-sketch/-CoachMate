import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../../data/models/exercise.dart';

class ExerciseMedia extends StatelessWidget {
  final Exercise exercise;
  final bool compact;

  const ExerciseMedia({
    super.key,
    required this.exercise,
    this.compact = false,
  });

  List<String> get _mediaPaths {
    if (exercise.mediaUrls.isNotEmpty) {
      return exercise.mediaUrls;
    }
    if (exercise.mediaUrl == null || exercise.mediaUrl!.isEmpty) {
      return const [];
    }
    return [exercise.mediaUrl!];
  }

  @override
  Widget build(BuildContext context) {
    final List<String> paths = _mediaPaths;
    if (paths.isEmpty) {
      return const SizedBox.shrink();
    }

    final String path = paths.first;
    final bool isReference =
        exercise.mediaStatus == ExerciseMediaStatus.reference;
    final String statusLabel = exercise.mediaStatus.label;
    final Widget media = _buildMedia(context, path);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: double.infinity,
            height: compact ? 150 : 190,
            child: media,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              isReference ? Icons.info_outline : Icons.check_circle_outline,
              size: 16,
              color: isReference ? AppColors.warning : AppColors.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                isReference ? '$statusLabel，精确纠错示范待补充' : statusLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isReference
                          ? AppColors.warning
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            if (paths.length > 1)
              Text(
                '${paths.length} 张参考图',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildMedia(BuildContext context, String path) {
    if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
          return _MediaFallback(label: '本地媒体加载失败');
        },
      );
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
          return _MediaFallback(label: '远程媒体加载失败');
        },
      );
    }
    return _MediaFallback(label: '动作演示占位');
  }
}

class _MediaFallback extends StatelessWidget {
  final String label;

  const _MediaFallback({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryLightest,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.movie_filter_outlined,
            color: AppColors.primary,
            size: 36,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
