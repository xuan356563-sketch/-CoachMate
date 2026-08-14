import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../../data/models/exercise.dart';
import 'flow_mascot.dart';

class ExerciseMedia extends StatefulWidget {
  final Exercise exercise;
  final bool compact;

  const ExerciseMedia({
    super.key,
    required this.exercise,
    this.compact = false,
  });

  @override
  State<ExerciseMedia> createState() => _ExerciseMediaState();
}

class _ExerciseMediaState extends State<ExerciseMedia> {
  int _selectedFrame = 0;

  List<String> get _mediaPaths {
    if (widget.exercise.mediaUrls.isNotEmpty) {
      return widget.exercise.mediaUrls;
    }
    if (widget.exercise.mediaUrl == null || widget.exercise.mediaUrl!.isEmpty) {
      return const [];
    }
    return [widget.exercise.mediaUrl!];
  }

  @override
  Widget build(BuildContext context) {
    final List<String> paths = _mediaPaths;
    if (paths.isEmpty) {
      return const SizedBox.shrink();
    }

    final int selectedIndex = _selectedFrame.clamp(0, paths.length - 1);
    final String path = paths[selectedIndex];
    final bool isGif = _isGif(path);
    final bool isReference =
        widget.exercise.mediaStatus == ExerciseMediaStatus.reference;
    final String statusLabel = widget.exercise.mediaStatus.label;
    final Widget media = _buildMedia(context, paths, selectedIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: double.infinity,
            height: widget.compact ? 150 : 190,
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
                isReference
                    ? '$statusLabel，精确动作动图待补充'
                    : isGif
                        ? '$statusLabel · GIF 动图'
                        : statusLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isReference
                          ? AppColors.warning
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            if (paths.length > 1) ...[
              Semantics(
                label: '切换至${selectedIndex == 0 ? '关键位置' : '准备姿势'}',
                button: true,
                child: TextButton(
                  onPressed: () => setState(
                    () => _selectedFrame = selectedIndex == 0 ? 1 : 0,
                  ),
                  child: Text(selectedIndex == 0 ? '准备姿势' : '关键位置'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildMedia(
    BuildContext context,
    List<String> paths,
    int selectedIndex,
  ) {
    final String path = paths[selectedIndex];
    if (!_isSupportedImage(path)) {
      return const _MediaFallback(label: '仅支持图片或 GIF 动图');
    }
    if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
          if (selectedIndex == 0 && paths.length > 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedFrame = 1);
            });
            return const _MediaFallback(label: '正在切换动作关键位置');
          }
          return const _MediaFallback(label: '本地媒体加载失败');
        },
      );
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
          if (selectedIndex == 0 && paths.length > 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedFrame = 1);
            });
            return const _MediaFallback(label: '正在切换动作关键位置');
          }
          return const _MediaFallback(label: '远程媒体加载失败');
        },
      );
    }
    return _MediaFallback(label: '动作演示占位');
  }
}

bool _isGif(String path) {
  return Uri.tryParse(path)?.path.toLowerCase().endsWith('.gif') ?? false;
}

bool _isSupportedImage(String path) {
  if (path.startsWith('placeholder://')) {
    return true;
  }
  final String normalized = Uri.tryParse(path)?.path.toLowerCase() ?? '';
  return const ['.gif', '.webp', '.png', '.jpg', '.jpeg'].any(
    normalized.endsWith,
  );
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
            Icons.animation_outlined,
            color: AppColors.primary,
            size: 0,
          ),
          const FlowMascot(
            size: 56,
            mood: FlowMascotMood.empty,
            backgroundColor: AppColors.primaryLightest,
          ),
          const SizedBox(height: 6),
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
