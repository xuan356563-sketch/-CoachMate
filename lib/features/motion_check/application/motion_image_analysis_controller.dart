import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/models/motion_check.dart';
import '../../../data/models/motion_pose.dart';
import '../../../services/motion_pose_analysis_service.dart';
import 'pose_detector_gateway.dart';

class MotionImageFile {
  final String path;
  final Uint8List bytes;

  const MotionImageFile({required this.path, required this.bytes});
}

abstract class MotionImagePicker {
  Future<MotionImageFile?> pick(ImageSource source);
}

class PlatformMotionImagePicker implements MotionImagePicker {
  final ImagePicker _picker;

  const PlatformMotionImagePicker(this._picker);

  @override
  Future<MotionImageFile?> pick(ImageSource source) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      imageQuality: 92,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    return MotionImageFile(path: file.path, bytes: await file.readAsBytes());
  }
}

final motionImagePickerProvider = Provider<MotionImagePicker>(
  (Ref ref) => PlatformMotionImagePicker(ImagePicker()),
);
final poseDetectorGatewayProvider = Provider<PoseDetectorGateway>((Ref ref) {
  final PoseDetectorGateway gateway = createPoseDetectorGateway();
  ref.onDispose(gateway.dispose);
  return gateway;
});

final motionImageAnalysisControllerProvider =
    NotifierProvider<MotionImageAnalysisController, MotionImageAnalysisState>(
  MotionImageAnalysisController.new,
);

enum MotionImageAnalysisStatus { idle, picking, analyzing, success, failure }

class MotionImageAnalysisState {
  final MotionImageAnalysisStatus status;
  final String? ruleId;
  final MotionCheckType? type;
  final Uint8List? imageBytes;
  final MotionPoseFrame? frame;
  final MotionPoseAnalysis? analysis;
  final String statusMessage;

  const MotionImageAnalysisState({
    this.status = MotionImageAnalysisStatus.idle,
    this.ruleId,
    this.type,
    this.imageBytes,
    this.frame,
    this.analysis,
    this.statusMessage = '请选择动作，再拍照或从相册选择。',
  });

  bool get isBusy =>
      status == MotionImageAnalysisStatus.picking ||
      status == MotionImageAnalysisStatus.analyzing;
}

class MotionImageAnalysisController extends Notifier<MotionImageAnalysisState> {
  final MotionPoseAnalysisService _analysisService =
      MotionPoseAnalysisService();

  @override
  MotionImageAnalysisState build() => const MotionImageAnalysisState();

  bool get isSupported => ref.read(poseDetectorGatewayProvider).isSupported;

  void selectRule(MotionCheckRule rule) {
    state = MotionImageAnalysisState(
      ruleId: rule.id,
      type: rule.type,
      statusMessage: '已选择${rule.type.label}，请确保全身清晰入镜。',
    );
  }

  Future<void> pickAndAnalyze(ImageSource source) async {
    final MotionCheckType? type = state.type;
    final String? ruleId = state.ruleId;
    if (type == null || ruleId == null) {
      state = const MotionImageAnalysisState(
        status: MotionImageAnalysisStatus.failure,
        statusMessage: '请先选择需要纠错的动作。',
      );
      return;
    }
    if (!isSupported) {
      state = MotionImageAnalysisState(
        status: MotionImageAnalysisStatus.failure,
        ruleId: ruleId,
        type: type,
        statusMessage: '当前平台仅支持查看，照片姿态识别请在 iPhone 或 Android 手机使用。',
      );
      return;
    }
    state = MotionImageAnalysisState(
      status: MotionImageAnalysisStatus.picking,
      ruleId: ruleId,
      type: type,
      statusMessage: '正在读取照片…',
    );
    try {
      final MotionImageFile? file =
          await ref.read(motionImagePickerProvider).pick(source);
      if (file == null) {
        state = MotionImageAnalysisState(ruleId: ruleId, type: type);
        return;
      }
      final Uint8List bytes = file.bytes;
      state = MotionImageAnalysisState(
        status: MotionImageAnalysisStatus.analyzing,
        ruleId: ruleId,
        type: type,
        imageBytes: bytes,
        statusMessage: '正在设备端提取身体关键点…',
      );
      final MotionPoseFrame frame =
          await ref.read(poseDetectorGatewayProvider).detect(
                path: file.path,
                bytes: bytes,
              );
      final MotionPoseAnalysis analysis =
          _analysisService.analyze(type: type, frame: frame);
      state = MotionImageAnalysisState(
        status: MotionImageAnalysisStatus.success,
        ruleId: ruleId,
        type: type,
        imageBytes: bytes,
        frame: frame,
        analysis: analysis,
        statusMessage: '识别完成，请确认结果后再应用到今日训练。',
      );
    } on PlatformException catch (error) {
      state = MotionImageAnalysisState(
        status: MotionImageAnalysisStatus.failure,
        ruleId: ruleId,
        type: type,
        statusMessage:
            error.code == 'vision_failed' || error.code == 'invalid_path'
                ? (error.message ?? '设备端姿态识别失败，请更换照片后重试。')
                : source == ImageSource.camera
                    ? '无法使用相机，请在系统设置中允许相机权限。'
                    : '无法访问相册，请在系统设置中允许照片权限。',
      );
    } on FormatException catch (error) {
      state = MotionImageAnalysisState(
        status: MotionImageAnalysisStatus.failure,
        ruleId: ruleId,
        type: type,
        statusMessage: error.message,
      );
    } catch (_) {
      state = MotionImageAnalysisState(
        status: MotionImageAnalysisStatus.failure,
        ruleId: ruleId,
        type: type,
        statusMessage: '照片识别失败，请重新拍摄或选择其他照片。',
      );
    }
  }

  void clear() => state = const MotionImageAnalysisState();
}
