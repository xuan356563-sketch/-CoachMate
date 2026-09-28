import 'package:flutter/material.dart';

import '../theme/trainflow_tokens.dart';

const List<String> _weekdayLabels = <String>['一', '二', '三', '四', '五', '六', '日'];

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// 胶囊日期选择器（计划 7.6）：横向滚动，当前日期高亮，今天显示「今」，
/// 有记录日期显示小圆点，支持进入完整日历。
class TrainMateDateSelector extends StatelessWidget {
  const TrainMateDateSelector({
    super.key,
    required this.dates,
    required this.selected,
    required this.onChanged,
    this.markedDates,
    this.onOpenCalendar,
  });

  final List<DateTime> dates;
  final DateTime selected;
  final ValueChanged<DateTime> onChanged;
  final Set<DateTime>? markedDates;
  final VoidCallback? onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    return Row(
      children: <Widget>[
        Expanded(
          child: SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: dates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (BuildContext context, int index) {
                return _DateChip(
                  date: dates[index],
                  selected: _sameDay(dates[index], selected),
                  today: _sameDay(dates[index], now),
                  marked: markedDates?.any((d) => _sameDay(d, dates[index])) ??
                      false,
                  onTap: () => onChanged(dates[index]),
                );
              },
            ),
          ),
        ),
        if (onOpenCalendar != null) ...<Widget>[
          const SizedBox(width: 8),
          Tooltip(
            message: '打开完整日历',
            child: IconButton(
              onPressed: onOpenCalendar,
              icon: const Icon(Icons.calendar_month_outlined),
              color: TrainFlowTokens.accent,
            ),
          ),
        ],
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.date,
    required this.selected,
    required this.today,
    required this.marked,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool today;
  final bool marked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg = selected
        ? TrainFlowTokens.brandDark
        : TrainFlowTokens.darkTrainingRaised;
    final Color fg = selected
        ? Colors.white
        : TrainFlowTokens.darkTrainingOnSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: '${date.month}月${date.day}日${today ? '，今天' : ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TrainFlowTokens.mainTabCardRadius),
        child: AnimatedContainer(
          duration: TrainFlowMotion.selection,
          curve: TrainFlowMotion.easeOut,
          width: 52,
          decoration: BoxDecoration(
            color: bg,
            borderRadius:
                BorderRadius.circular(TrainFlowTokens.mainTabCardRadius),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                today ? '今' : _weekdayLabels[date.weekday - 1],
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected ? Colors.white70 : TrainFlowTokens.darkTrainingMuted,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                '${date.day}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              SizedBox(
                height: 4,
                child: marked
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: selected
                              ? TrainFlowTokens.accent
                              : TrainFlowTokens.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(dimension: 4),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
