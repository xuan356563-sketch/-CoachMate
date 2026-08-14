import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trainflow_ai/data/local/local_storage_bootstrap_coordinator.dart';
import 'package:trainflow_ai/data/local/trainflow_database_schema.dart';

typedef RecoveryDiagnosticsCopier = Future<void> Function(String value);

/// 数据库无法安全打开时展示的保护页。
///
/// 页面只暴露脱敏诊断和显式重试，不读取陈旧副本，也不执行清库或自动恢复。
class LocalStorageRecoveryPage extends StatefulWidget {
  const LocalStorageRecoveryPage({
    super.key,
    required this.result,
    required this.onRetry,
    this.copyDiagnostics,
  });

  final LocalStorageBootstrapResult result;
  final Future<void> Function() onRetry;
  final RecoveryDiagnosticsCopier? copyDiagnostics;

  @override
  State<LocalStorageRecoveryPage> createState() =>
      _LocalStorageRecoveryPageState();
}

class _LocalStorageRecoveryPageState extends State<LocalStorageRecoveryPage> {
  bool _showRecoveryDetails = false;
  bool _isRetrying = false;

  Future<void> _retry() async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);
    try {
      await widget.onRetry();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('重试失败，数据仍处于保护状态，请稍后再试。'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }
  }

  Future<void> _copyDiagnostics() async {
    final RecoveryDiagnosticsCopier copier =
        widget.copyDiagnostics ?? _copyWithSystemClipboard;
    await copier(_buildDiagnostics(widget.result));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('脱敏诊断信息已复制。')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.shield_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    '本地数据保护模式',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.result.fallbackReason ?? '本地数据库暂时无法安全打开，请稍后重试。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isRetrying ? null : _retry,
                    icon: _isRetrying
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(_isRetrying ? '正在重试…' : '重试打开数据库'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showRecoveryDetails = !_showRecoveryDetails;
                      });
                    },
                    icon: const Icon(Icons.visibility_outlined),
                    label: Text(
                      _showRecoveryDetails ? '收起只读恢复信息' : '查看只读恢复信息',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _copyDiagnostics,
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('复制诊断信息'),
                  ),
                  if (_showRecoveryDetails) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            '当前不会读取陈旧设备副本，也不会自动清除或覆盖数据库。'
                            '训练数据仍保留在原数据库文件中；重试成功前仅提供脱敏诊断信息。',
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _copyWithSystemClipboard(String value) {
  return Clipboard.setData(ClipboardData(text: value));
}

String _buildDiagnostics(LocalStorageBootstrapResult result) {
  return <String>[
    'TrainMate 本地存储诊断',
    '存储后端：${result.backend.name}',
    '数据库版本：${TrainFlowDatabaseSchema.version}',
    '保护原因：${result.fallbackReason ?? '未提供'}',
    '错误类型：${result.fallbackError?.runtimeType ?? '未知'}',
  ].join('\n');
}
