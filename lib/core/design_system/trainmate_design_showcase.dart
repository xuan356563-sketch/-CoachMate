import 'package:flutter/material.dart';

import '../theme/trainflow_tokens.dart';
import 'trainmate_cards.dart';
import 'trainmate_date_selector.dart';
import 'trainmate_primitives.dart';
import 'trainmate_states.dart';

/// 基础组件 Showcase（Story）：集中渲染阶段 2 全部组件，供人工验收与
/// 视觉回归使用。与业务数据无关。
class TrainMateDesignShowcase extends StatelessWidget {
  const TrainMateDesignShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    final DateTime today = DateTime.now();
    final DateTime day = DateTime(today.year, today.month, today.day);
    return Scaffold(
      appBar: AppBar(title: const Text('TrainMate 基础组件')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: <Widget>[
          const _Section('按钮 · 尺寸'),
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              TrainMateButton(label: '大按钮', size: TrainMateButtonSize.large),
              TrainMateButton(label: '标准按钮'),
              TrainMateButton(label: '小按钮', size: TrainMateButtonSize.small),
            ],
          ),
          const SizedBox(height: 16),
          const _Section('按钮 · 变体与状态'),
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              TrainMateButton(label: '主要', variant: TrainMateButtonVariant.primary),
              TrainMateButton(label: '次要', variant: TrainMateButtonVariant.secondary),
              TrainMateButton(label: '文本', variant: TrainMateButtonVariant.tertiary),
              TrainMateButton(label: '危险', variant: TrainMateButtonVariant.destructive),
              TrainMateButton(label: '加载中', loading: true),
              TrainMateButton(label: '禁用', onPressed: null),
            ],
          ),
          const SizedBox(height: 16),
          const _Section('图标按钮'),
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              TrainMateIconButton(icon: Icons.search, tooltip: '搜索'),
              TrainMateIconButton(icon: Icons.add, tooltip: '新增', tone: TrainMateIconButtonTone.filled),
              TrainMateIconButton(icon: Icons.settings_outlined, tooltip: '设置', tone: TrainMateIconButtonTone.outline),
            ],
          ),
          const SizedBox(height: 16),
          const _Section('徽章族'),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              TrainMateBadge(label: '深紫', tone: TrainMateTone.purple),
              TrainMateBadge(label: '奖励', tone: TrainMateTone.yellow, dot: true),
              TrainMateBadge(label: '粉色', tone: TrainMateTone.pink),
              TrainMateBadge(label: '珊瑚', tone: TrainMateTone.coral),
              TrainMateBadge(label: '蓝色', tone: TrainMateTone.blue),
              TrainMateBadge(label: '薄荷', tone: TrainMateTone.mint),
              TrainMateStreakBadge(days: 7),
              TrainMateLevelBadge(level: 12),
              TrainMateRewardBadge(label: '+50 积分'),
            ],
          ),
          const SizedBox(height: 16),
          const _Section('进度'),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              TrainMateProgressRing(value: 0.42, child: Text('42%')),
              TrainMateProgressRing(
                value: 0.85,
                color: TrainFlowTokens.mint,
                child: Text('85%'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const TrainMateProgressBar(value: 0.62),
          const SizedBox(height: 16),
          const _Section('数据指标卡'),
          const Row(
            children: <Widget>[
              Expanded(
                child: TrainMateStatCard(
                  label: '今日时长',
                  value: '42',
                  unit: '分钟',
                  icon: Icons.timer_outlined,
                  tone: TrainMateTone.blue,
                  trend: '+12%',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: TrainMateStatCard(
                  label: '消耗',
                  value: '320',
                  unit: '千卡',
                  icon: Icons.local_fire_department_outlined,
                  tone: TrainMateTone.coral,
                  trend: '-3%',
                  trendUp: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const TrainMateStatCard(
            label: '数据加载中',
            value: '--',
            icon: Icons.straighten_outlined,
            loading: true,
          ),
          const SizedBox(height: 16),
          const _Section('挑战卡片'),
          TrainMateChallengeCard(
            title: '30 天晨跑挑战',
            subtitle: '每天 20 分钟，唤醒你的早晨',
            status: TrainMateChallengeStatus.active,
            progress: 0.4,
            progressLabel: '已完成 12 / 30 天',
            icon: Icons.directions_run_rounded,
            tone: TrainMateTone.purple,
            remaining: '剩 18 天',
            reward: '+200 积分',
            participants: 128,
          ),
          const SizedBox(height: 12),
          const TrainMateChallengeCard(
            title: '骑行百公里',
            subtitle: '累计骑行 100 公里',
            status: TrainMateChallengeStatus.completed,
            progress: 1,
            progressLabel: '已完成',
            icon: Icons.directions_bike_rounded,
            tone: TrainMateTone.mint,
            reward: '+500 积分',
          ),
          const SizedBox(height: 16),
          const _Section('骨架屏'),
          const TrainMateSkeletonListTile(),
          const TrainMateSkeletonListTile(showAvatar: false),
          const SizedBox(height: 16),
          const _Section('空状态'),
          const TrainMateEmptyState(
            title: '还没有参加挑战',
            message: '挑选一个喜欢的目标，开始你的第一次挑战。',
            actionLabel: '浏览挑战',
          ),
          const SizedBox(height: 16),
          const _Section('错误状态'),
          TrainMateErrorState(
            message: '网络连接失败，请检查网络后重试。',
            onRetry: () {},
          ),
          const SizedBox(height: 16),
          const _Section('Toast'),
          const TrainMateToast(message: '已保存成功', tone: TrainMateToastTone.success),
          const SizedBox(height: 16),
          const _Section('日期选择器'),
          TrainMateDateSelector(
            dates: List<DateTime>.generate(14, (int i) => day.add(Duration(days: i - 3))),
            selected: day,
            onChanged: (DateTime _) {},
            markedDates: <DateTime>{day, day.add(const Duration(days: 2))},
            onOpenCalendar: () {},
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 6),
      child: Row(
        children: <Widget>[
          Container(
            width: 20,
            height: 6,
            decoration: BoxDecoration(
              color: TrainFlowTokens.accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
