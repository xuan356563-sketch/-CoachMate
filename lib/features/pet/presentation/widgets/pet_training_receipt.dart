import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/trainflow_tokens.dart';
import '../../../../core/widgets/trainflow_widgets.dart';
import '../../application/pet_controller.dart';

const Duration petReceiptAnimationDuration = Duration(milliseconds: 450);

/// 训练完成后的伙伴正差额回执。
class PetTrainingReceiptCard extends StatelessWidget {
  const PetTrainingReceiptCard({
    super.key,
    required this.settlement,
    required this.hasValidTraining,
    required this.onAcknowledged,
  });

  final PetPendingSettlement? settlement;
  final bool hasValidTraining;
  final VoidCallback onAcknowledged;

  @override
  Widget build(BuildContext context) {
    final PetPendingSettlement? value = settlement;
    if (!hasValidTraining || value == null || value.awardedDelta <= 0) {
      return const SizedBox.shrink();
    }
    final Duration duration =
        MediaQuery.maybeOf(context)?.disableAnimations == true
            ? Duration.zero
            : petReceiptAnimationDuration;
    return AnimatedScale(
      duration: duration,
      curve: TrainFlowMotion.easeOut,
      scale: 1,
      child: TrainFlowCard(
        tone: TrainFlowCardTone.peach,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.pets_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  '伙伴主食 +${value.awardedDelta}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('本次只展示幂等结算产生的真实正差额，不会因重复反馈再次发放。'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onAcknowledged,
                child: const Text('收下奖励'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
