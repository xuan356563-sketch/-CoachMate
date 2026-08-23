import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_showcase_widgets.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../auth/application/auth_controller.dart';
import 'application/data_rights_controller.dart';

class DataRightsPage extends ConsumerStatefulWidget {
  const DataRightsPage({super.key});

  @override
  ConsumerState<DataRightsPage> createState() => _DataRightsPageState();
}

class _DataRightsPageState extends ConsumerState<DataRightsPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<DataRightsState> asyncState =
        ref.watch(dataRightsControllerProvider);
    final DataRightsState state =
        asyncState.value ?? const DataRightsState.unavailable();
    return TrainFlowPage(
      title: '数据与隐私',
      layout: TrainFlowPageLayout.form,
      subtitle: '导出云端账号数据，并管理账号删除申请。',
      eyebrow: '账号数据权利',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.profile,
      ),
      artwork: const TrainMateIllustration(
        assetPath: 'assets/images/trainmate_data_shield.png',
        semanticLabel: '账号数据授权与隐私保护插画',
        fallback: Icon(
          Icons.shield_outlined,
          size: 64,
          color: TrainFlowTokens.accent,
        ),
      ),
      children: <Widget>[
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.file_download_outlined, color: TrainFlowTokens.accent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '导出账号数据',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                '导出文件由服务器即时生成，并通过系统保存面板写入你选择的位置；应用不会创建额外分享副本。',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: !state.available || state.busy
                    ? null
                    : () => ref
                        .read(dataRightsControllerProvider.notifier)
                        .exportAccount(),
                icon: const Icon(Icons.save_alt),
                label: const Text('导出 JSON'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _DeletionCard(
          state: state,
          emailController: _emailController,
          codeController: _codeController,
        ),
        const SizedBox(height: 16),
        Text(
          state.statusMessage,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: state.deletionStatus?.isPending == true
                    ? AppColors.warningDark
                    : TrainFlowTokens.darkTrainingMuted,
              ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _DeletionCard extends ConsumerWidget {
  final DataRightsState state;
  final TextEditingController emailController;
  final TextEditingController codeController;

  const _DeletionCard({
    required this.state,
    required this.emailController,
    required this.codeController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.deletionStatus?.isPending == true) {
      final DateTime? purgeAfter = state.deletionStatus?.purgeAfter;
      return TrainFlowCard(
        tone: TrainFlowCardTone.peach,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '账号删除申请待执行',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              purgeAfter == null
                  ? '删除时间正在确认。'
                  : '预计删除时间：${_dateLabel(purgeAfter.toLocal())}',
            ),
            const SizedBox(height: 8),
            const Text('撤销期内可以恢复账号；撤销不会自动恢复已主动清除的本机数据。'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: state.busy
                  ? null
                  : () => ref
                      .read(dataRightsControllerProvider.notifier)
                      .cancelDeletion(),
              child: const Text('撤销删除申请'),
            ),
          ],
        ),
      );
    }
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.delete_outline, color: AppColors.danger),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '删除账号',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            state.canDeleteOnline
                ? '需要使用当前账号的完整邮箱和验证码复核。提交后会退出账号，并进入可撤销等待期。'
                : '当前账号未绑定邮箱，暂时不能在应用内完成删除复核。',
          ),
          if (state.canDeleteOnline) ...[
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '当前账号完整邮箱'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '六位验证码',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: state.busy
                      ? null
                      : () => ref
                          .read(dataRightsControllerProvider.notifier)
                          .requestDeletionChallenge(emailController.text),
                  child: const Text('获取验证码'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: state.busy || state.deletionChallengeId == null
                  ? null
                  : () => _confirmDeletion(context, ref),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('申请删除账号'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDeletion(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('确认申请删除账号？'),
        content: const Text(
          '提交后所有登录会话会立即失效，云端数据将在撤销期结束后删除。'
          '请先确认已经保存需要的导出文件。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('暂不删除'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认申请'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final bool submitted =
        await ref.read(dataRightsControllerProvider.notifier).requestDeletion(
              email: emailController.text,
              code: codeController.text,
            );
    if (submitted && context.mounted) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

String _dateLabel(DateTime value) {
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
