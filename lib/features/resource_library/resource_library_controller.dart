import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../plugins/application/plugin_runtime_provider.dart';
import '../../plugins/features/resource_library_plugin.dart';
import '../../services/local_storage_service.dart';
import 'resource_catalog.dart';
import 'assessment_record.dart';
import 'assessment_record_repository.dart';

String newResourceRecordId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';
final resourceCatalogProvider = Provider<ResourceCatalog?>((ref) {
  final runtime = ref.watch(pluginRuntimeProvider);
  return runtime.registry
      .readCapability<ResourceCatalog>(ResourceLibraryPlugin.catalog);
});
final assessmentRecordRepositoryProvider =
    Provider<AssessmentRecordRepository>((ref) {
  ref.watch(pluginRuntimeProvider.select((r) => r.accountEpoch));
  return AssessmentRecordRepository(ref.watch(localStorageServiceProvider));
});
final assessmentControllerProvider =
    NotifierProvider<AssessmentController, int>(AssessmentController.new);

class AssessmentController extends Notifier<int> {
  @override
  int build() {
    ref.watch(pluginRuntimeProvider.select((r) => r.accountEpoch));
    return 0;
  }

  Future<void> save(AssessmentRecord record) async {
    final resource =
        (ref.read(resourceCatalogProvider) ?? (throw StateError('运动资源库尚未启用')))
            .require(record.resourceRef.id);
    if (resource is! AssessmentGuide || resource.ref != record.resourceRef) {
      throw StateError('评估内容已变化，请重新打开指引');
    }
    final operation = ref.read(featureAccessProvider).beginOperation(
        ResourceLibraryPlugin.id,
        dependencies: [resource.ownerPluginId]);
    final repository = ref.read(assessmentRecordRepositoryProvider);
    await operation.commit(() => repository.save(record));
    operation.checkActive();
    state++;
  }

  Future<void> delete(AssessmentRecord record) async {
    final resource =
        (ref.read(resourceCatalogProvider) ?? (throw StateError('运动资源库尚未启用')))
            .require(record.resourceRef.id);
    final operation = ref.read(featureAccessProvider).beginOperation(
        ResourceLibraryPlugin.id,
        dependencies: [resource.ownerPluginId]);
    final repository = ref.read(assessmentRecordRepositoryProvider);
    await operation.commit(() => repository.delete(record.id));
    operation.checkActive();
    state++;
  }
}
