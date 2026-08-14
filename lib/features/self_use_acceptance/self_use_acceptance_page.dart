import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/self_use_acceptance.dart';
import '../../data/repositories/self_use_acceptance_repository.dart';
import '../../services/local_storage_service.dart';

class SelfUseAcceptancePage extends ConsumerStatefulWidget {
  const SelfUseAcceptancePage({super.key});

  @override
  ConsumerState<SelfUseAcceptancePage> createState() =>
      _SelfUseAcceptancePageState();
}

class _SelfUseAcceptancePageState extends ConsumerState<SelfUseAcceptancePage> {
  late final PersistedSelfUseAcceptanceRepository _repository;
  late final TextEditingController _notesController;
  late SelfUseAcceptanceRecord _record;
  int _selectedDayNumber = 1;

  @override
  void initState() {
    super.initState();
    _repository = PersistedSelfUseAcceptanceRepository(
      ref.read(localStorageServiceProvider),
    );
    _record = _repository.getRecord();
    _selectedDayNumber = _preferredDayNumber();
    _notesController = TextEditingController(text: _selectedDay?.notes ?? '');
  }

  SelfUseAcceptanceDay? get _selectedDay => _record.findDay(_selectedDayNumber);

  int _availableThroughDayNumber() {
    if (!_record.isStarted) {
      return 0;
    }
    final DateTime startedDate = _dateOnly(_record.startedAt!);
    final DateTime today = _dateOnly(DateTime.now());
    return today.difference(startedDate).inDays.clamp(0, 13).toInt() + 1;
  }

  int _preferredDayNumber() {
    final int availableThroughDay = _availableThroughDayNumber();
    for (final SelfUseAcceptanceDay day in _record.days) {
      if (day.dayNumber <= availableThroughDay && !day.checklistComplete) {
        return day.dayNumber;
      }
    }
    return _record.days.isEmpty ? 1 : _record.days.last.dayNumber;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _startAcceptance() {
    setState(() {
      _record = _repository.start(DateTime.now());
      _selectedDayNumber = 1;
      _notesController.text = '';
    });
  }

  void _selectDay(int dayNumber) {
    final SelfUseAcceptanceDay? day = _record.findDay(dayNumber);
    if (day == null || dayNumber > _availableThroughDayNumber()) {
      return;
    }
    setState(() {
      _selectedDayNumber = dayNumber;
      _notesController.text = day.notes;
    });
  }

  void _updateSelectedDay(
    SelfUseAcceptanceDay Function(SelfUseAcceptanceDay day) update,
  ) {
    final SelfUseAcceptanceDay? day = _selectedDay;
    if (day == null) {
      return;
    }
    setState(() {
      _record = _repository.updateDay(update(day));
    });
  }

  void _saveNotes() {
    _updateSelectedDay(
      (SelfUseAcceptanceDay day) => day.copyWith(notes: _notesController.text),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('今日验收记录已保存。')),
    );
  }

  Future<void> _confirmClear() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('重置 14 天记录？'),
          content: const Text('这只会删除本地验收记录，不会删除训练、身体数据或训练计划。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认重置'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _repository.clear();
      _record = _repository.getRecord();
      _selectedDayNumber = 1;
      _notesController.text = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return TrainFlowPage(
      title: '14 天自用验收',
      layout: TrainFlowPageLayout.form,
      subtitle: '记录真实使用，不自动宣称 Gate A 已通过。',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.profile,
      ),
      artwork: const TrainMateActionCharacter(
        action: TrainMateAction.plank,
        backgroundColor: AppColors.primary,
      ),
      action: _record.isStarted
          ? IconButton(
              tooltip: '重置验收记录',
              onPressed: _confirmClear,
              icon: const Icon(Icons.restart_alt),
            )
          : null,
      children: [
        _OverviewCard(record: _record),
        if (!_record.isStarted)
          _StartCard(onStart: _startAcceptance)
        else ...[
          const SectionTitle(title: '选择记录日'),
          TrainFlowCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final SelfUseAcceptanceDay day in _record.days)
                  ChoiceChip(
                    label: Text('第 ${day.dayNumber} 天'),
                    selected: day.dayNumber == _selectedDayNumber,
                    onSelected: day.dayNumber <= _availableThroughDayNumber()
                        ? (_) => _selectDay(day.dayNumber)
                        : null,
                    avatar: Icon(
                      day.checklistComplete
                          ? Icons.check_circle_outline
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: day.blockingIssue
                          ? AppColors.warningDark
                          : AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '按开始日期开放记录；未来日期不会提前写入。当前开放到第 ${_availableThroughDayNumber()} 天。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
          if (_selectedDay != null)
            _DailyAcceptanceCard(
              day: _selectedDay!,
              notesController: _notesController,
              onBodyDataChanged: (bool value) => _updateSelectedDay(
                (SelfUseAcceptanceDay day) =>
                    day.copyWith(bodyDataLogged: value),
              ),
              onPlanChanged: (bool value) => _updateSelectedDay(
                (SelfUseAcceptanceDay day) => day.copyWith(planReviewed: value),
              ),
              onWorkoutChanged: (bool value) => _updateSelectedDay(
                (SelfUseAcceptanceDay day) =>
                    day.copyWith(workoutExecuted: value),
              ),
              onFeedbackChanged: (bool value) => _updateSelectedDay(
                (SelfUseAcceptanceDay day) =>
                    day.copyWith(feedbackLogged: value),
              ),
              onStarterChanged: (bool value) => _updateSelectedDay(
                (SelfUseAcceptanceDay day) =>
                    day.copyWith(starterProgramChecked: value),
              ),
              onBlockingIssueChanged: (bool value) => _updateSelectedDay(
                (SelfUseAcceptanceDay day) =>
                    day.copyWith(blockingIssue: value),
              ),
              onSaveNotes: _saveNotes,
            ),
          const SectionTitle(title: 'Gate A 说明'),
          TrainFlowCard(
            child: Text(
              '只有 14 天记录齐全后，才进入人工验收：逐条复核硬性规则、页面速度、手机触控和阻断性问题。这个页面不会替代真实连续使用。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

class _OverviewCard extends StatelessWidget {
  final SelfUseAcceptanceRecord record;

  const _OverviewCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final double progress = record.completedDayCount / 14;
    final String status = !record.isStarted
        ? '未开始'
        : record.checklistReady
            ? '记录齐全，待人工复核'
            : '进行中';
    final String detail = !record.isStarted
        ? '开始后每天记录身体数据、计划、训练、反馈和 30 天引导检查。'
        : '已完成 ${record.completedDayCount}/14 天 · 阻断记录 ${record.blockingDayCount} 天';

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '自用验收进度',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(
                label: status,
                color: record.checklistReady
                    ? AppColors.warning
                    : AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(detail),
          if (record.isStarted) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: AppColors.primary,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            const SizedBox(height: 8),
            Text(
              '开始日期：${_formatDate(record.startedAt!)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  final VoidCallback onStart;

  const _StartCard({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '开始记录真实使用',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text('每天完成后勾选，不要求为了通过验收而编造训练记录。'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始 14 天验收'),
          ),
        ],
      ),
    );
  }
}

class _DailyAcceptanceCard extends StatelessWidget {
  final SelfUseAcceptanceDay day;
  final TextEditingController notesController;
  final ValueChanged<bool> onBodyDataChanged;
  final ValueChanged<bool> onPlanChanged;
  final ValueChanged<bool> onWorkoutChanged;
  final ValueChanged<bool> onFeedbackChanged;
  final ValueChanged<bool> onStarterChanged;
  final ValueChanged<bool> onBlockingIssueChanged;
  final VoidCallback onSaveNotes;

  const _DailyAcceptanceCard({
    required this.day,
    required this.notesController,
    required this.onBodyDataChanged,
    required this.onPlanChanged,
    required this.onWorkoutChanged,
    required this.onFeedbackChanged,
    required this.onStarterChanged,
    required this.onBlockingIssueChanged,
    required this.onSaveNotes,
  });

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '第 ${day.dayNumber} 天 · ${_formatDate(day.date)}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(
                label: day.checklistComplete ? '今日已齐' : '待记录',
                color: day.checklistComplete
                    ? AppColors.primary
                    : AppColors.secondary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _CheckItem(
            title: '早上录入身体数据',
            value: day.bodyDataLogged,
            onChanged: onBodyDataChanged,
          ),
          _CheckItem(
            title: '查看并确认今日训练/现实约束',
            value: day.planReviewed,
            onChanged: onPlanChanged,
          ),
          _CheckItem(
            title: '按计划完成训练或记录主动降级',
            value: day.workoutExecuted,
            onChanged: onWorkoutChanged,
          ),
          _CheckItem(
            title: '晚上填写训练反馈',
            value: day.feedbackLogged,
            onChanged: onFeedbackChanged,
          ),
          _CheckItem(
            title: '检查 30 天引导当天坡度是否合理',
            value: day.starterProgramChecked,
            onChanged: onStarterChanged,
          ),
          const Divider(height: 20),
          _CheckItem(
            title: '今天出现阻断性问题',
            subtitle: '例如无法打开、无法保存、核心流程无法继续。',
            value: day.blockingIssue,
            onChanged: onBlockingIssueChanged,
            activeColor: AppColors.warning,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: notesController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '今日 bug / 别扭之处 / 训练备注',
              hintText: '真实使用后再记录，不要凭记忆补写。',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onSaveNotes,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存今日记录'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;

  const _CheckItem({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: activeColor,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged: (bool? next) => onChanged(next ?? false),
    );
  }
}

String _formatDate(DateTime date) => '${date.month} 月 ${date.day} 日';
