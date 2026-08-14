import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_colors.dart';
import 'trainmate_action_character.dart';

/// 智练 TrainMate 业务子页面统一返回按钮。
class TrainMateBackButton extends StatelessWidget {
  final String fallbackRoute;
  final VoidCallback? onPressed;
  final TrainMateAction action;

  const TrainMateBackButton({
    super.key,
    required this.fallbackRoute,
    this.onPressed,
    this.action = TrainMateAction.pointingGuide,
  });

  @override
  Widget build(BuildContext context) {
    final Color foreground = IconTheme.of(context).color ?? AppColors.primary;
    final bool isOnDarkHeader = foreground.computeLuminance() > 0.7;
    final Color characterBackground =
        isOnDarkHeader ? AppColors.primary : AppColors.background;

    void handleBack() {
      if (onPressed != null) {
        onPressed!();
      } else if (context.canPop()) {
        context.pop();
      } else {
        context.go(fallbackRoute);
      }
    }

    return Semantics(
      label: '返回',
      button: true,
      onTap: handleBack,
      excludeSemantics: true,
      child: Tooltip(
        message: '返回',
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            onTap: handleBack,
            radius: 24,
            containedInkWell: true,
            customBorder: const CircleBorder(),
            child: SizedBox.square(
              key: const ValueKey<String>('trainmate-back-button'),
              dimension: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    right: 1,
                    child: Transform.flip(
                      flipX: true,
                      child: TrainMateActionCharacter(
                        action: action,
                        size: 36,
                        backgroundColor: characterBackground,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 1,
                    child: Icon(
                      Icons.arrow_back,
                      size: 20,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
