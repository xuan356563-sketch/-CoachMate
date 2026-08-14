import 'package:flutter/material.dart';

import '../../../../core/widgets/trainflow_widgets.dart';
import '../../../../data/models/pet.dart';

class PetEnergyBreakdownCard extends StatelessWidget {
  const PetEnergyBreakdownCard({super.key, required this.energy});

  final PetDailyEnergy? energy;

  @override
  Widget build(BuildContext context) {
    final PetDailyEnergy? item = energy;
    final List<(String, IconData)> sources = <(String, IconData)>[
      ('步数 +${item?.stepsEnergy ?? 0}', Icons.directions_walk),
      ('站立 +${item?.standEnergy ?? 0}', Icons.accessibility_new),
      ('运动 +${item?.exerciseEnergy ?? 0}', Icons.timer_outlined),
      ('消耗 +${item?.activeEnergy ?? 0}', Icons.local_fire_department_outlined),
    ];
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('今日来源', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final (String label, IconData icon) in sources)
                Chip(avatar: Icon(icon, size: 18), label: Text(label)),
            ],
          ),
          if ((item?.trainingEnergy ?? 0) > 0) ...<Widget>[
            const SizedBox(height: 10),
            const Text('主食 +100'),
          ] else if ((item?.recoveryEnergy ?? 0) > 0) ...<Widget>[
            const SizedBox(height: 10),
            Text('恢复零食 +${item!.recoveryEnergy}'),
          ],
        ],
      ),
    );
  }
}
