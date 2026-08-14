import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/models/pet.dart';
import '../illustrated_pet_renderer.dart';
import '../pet_labels.dart';

class PetIllustrationCard extends StatelessWidget {
  const PetIllustrationCard({
    super.key,
    required this.companion,
    required this.todayEnergy,
    required this.nextStageDistance,
  });

  final PetCompanion companion;
  final int todayEnergy;
  final int? nextStageDistance;

  @override
  Widget build(BuildContext context) {
    final String semanticDistance =
        nextStageDistance == null ? '已达到冠军阶段' : '距离下一阶段 $nextStageDistance';
    final String displayDistance =
        nextStageDistance == null ? semanticDistance : '$semanticDistance 能量';
    return Semantics(
      container: true,
      label: '伙伴形象卡，${companion.nickname}，${petMoodLabel(companion.mood)}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.petPaper,
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(30),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(29),
          child: Stack(
            children: <Widget>[
              const Positioned.fill(child: _PetCardAtmosphere()),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        _PetPill(
                          icon: Icons.auto_awesome_rounded,
                          label: petStageLabel(companion.stage),
                        ),
                        _PetPill(
                          icon: Icons.bolt_rounded,
                          label: '今日能量 $todayEnergy',
                          accent: true,
                        ),
                      ],
                    ),
                    IllustratedPetRenderer(
                      species: companion.species,
                      stage: companion.stage,
                      mood: companion.mood,
                      semanticLabel:
                          '${companion.nickname}，${petStageLabel(companion.stage)}，'
                          '心情${petMoodLabel(companion.mood)}，今日获得 $todayEnergy 能量，$semanticDistance',
                      size: 220,
                    ),
                    Text(
                      companion.nickname,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${petMoodLabel(companion.mood)} · $displayDistance',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PetCardAtmosphere extends StatelessWidget {
  const _PetCardAtmosphere();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFFFF5EA),
            Color(0xFFFFFBF5),
            Color(0xFFEAF9F3),
          ],
        ),
      ),
      child: CustomPaint(painter: _PetAtmospherePainter()),
    );
  }
}

class _PetAtmospherePainter extends CustomPainter {
  const _PetAtmospherePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint peach = Paint()
      ..color = AppColors.secondary.withValues(alpha: 0.15);
    final Paint mint = Paint()
      ..color = const Color(0xFF72D6B3).withValues(alpha: 0.16);
    canvas.drawCircle(Offset(size.width * 0.06, size.height * 0.55), 62, peach);
    canvas.drawCircle(Offset(size.width * 0.94, size.height * 0.30), 70, mint);
    final Paint dot = Paint()..color = AppColors.secondary;
    canvas.drawCircle(Offset(size.width * 0.16, size.height * 0.25), 4, dot);
    canvas.drawCircle(Offset(size.width * 0.84, size.height * 0.70), 3, dot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PetPill extends StatelessWidget {
  const _PetPill({
    required this.icon,
    required this.label,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent
            ? AppColors.secondary.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 17, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
