/// 只校验本次输入，沿用既有字段定义，不将格式校验当成健康评估。
void validateBodyMetricInput(Map<String, num?> values) {
  for (final entry in values.entries) {
    final value = entry.value;
    if (value == null) continue;
    if (!value.isFinite) {
      throw FormatException('${entry.key} 必须是有限数值。');
    }
    if (entry.key == '疲劳' || entry.key == '酸痛') {
      if (value < 0 || value > 10 || value != value.truncate()) {
        throw FormatException('${entry.key} 必须是 0 至 10 的整数，不会自动截断。');
      }
    } else if (value <= 0) {
      throw FormatException('${entry.key} 必须大于 0，缺失值请留空。');
    }
  }
}
