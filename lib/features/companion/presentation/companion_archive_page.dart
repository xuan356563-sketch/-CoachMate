import 'package:flutter/widgets.dart';
import 'package:trainflow_ai/features/pet/presentation/pet_home_page.dart';

/// 原伙伴仪表盘、能量明细和活动补录统一收纳到成长档案。
class CompanionArchivePage extends StatelessWidget {
  const CompanionArchivePage({super.key});

  @override
  Widget build(BuildContext context) => const PetHomePage(archiveMode: true);
}
