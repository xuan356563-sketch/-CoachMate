import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/data/authenticated_api_client.dart';

final raceImagePickerProvider = Provider<RaceImagePicker>(
  (Ref ref) => PlatformRaceImagePicker(ImagePicker()),
);

final raceImageRecognitionControllerProvider = AsyncNotifierProvider<
    RaceImageRecognitionController,
    RaceImageRecognitionState>(RaceImageRecognitionController.new);

enum RaceImageSource { camera, gallery }

enum RaceImageRecognitionStatus {
  idle,
  picking,
  recognizing,
  success,
  failure,
}

class RaceImageFile {
  final Uint8List bytes;
  final String name;

  const RaceImageFile({required this.bytes, required this.name});
}

class RaceImageRecognitionResult {
  final String provider;
  final String model;
  final String? name;
  final String? type;
  final String? raceDate;
  final String? targetResult;
  final String? courseInfo;
  final String normalizedText;
  final int matchedFieldCount;
  final List<String> warnings;

  const RaceImageRecognitionResult({
    required this.provider,
    required this.model,
    required this.name,
    required this.type,
    required this.raceDate,
    required this.targetResult,
    required this.courseInfo,
    required this.normalizedText,
    required this.matchedFieldCount,
    required this.warnings,
  });

  factory RaceImageRecognitionResult.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> fields =
        json['fields'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return RaceImageRecognitionResult(
      provider: json['provider'] as String,
      model: json['model'] as String,
      name: fields['name'] as String?,
      type: fields['type'] as String?,
      raceDate: fields['race_date'] as String?,
      targetResult: fields['target_result'] as String?,
      courseInfo: fields['course_info'] as String?,
      normalizedText: json['normalized_text'] as String? ?? '',
      matchedFieldCount: json['matched_field_count'] as int? ?? 0,
      warnings: (json['warnings'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}

class RaceImageRecognitionState {
  final RaceImageRecognitionStatus status;
  final RaceImageFile? image;
  final RaceImageRecognitionResult? result;
  final String? errorMessage;

  const RaceImageRecognitionState({
    this.status = RaceImageRecognitionStatus.idle,
    this.image,
    this.result,
    this.errorMessage,
  });

  bool get isBusy =>
      status == RaceImageRecognitionStatus.picking ||
      status == RaceImageRecognitionStatus.recognizing;

  RaceImageRecognitionState copyWith({
    RaceImageRecognitionStatus? status,
    RaceImageFile? image,
    RaceImageRecognitionResult? result,
    String? errorMessage,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return RaceImageRecognitionState(
      status: status ?? this.status,
      image: image ?? this.image,
      result: clearResult ? null : (result ?? this.result),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

abstract class RaceImagePicker {
  Future<RaceImageFile?> pick(RaceImageSource source);
}

class PlatformRaceImagePicker implements RaceImagePicker {
  final ImagePicker _picker;

  const PlatformRaceImagePicker(this._picker);

  @override
  Future<RaceImageFile?> pick(RaceImageSource source) async {
    final XFile? file = await _picker.pickImage(
      source: source == RaceImageSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 92,
      requestFullMetadata: false,
    );
    if (file == null) {
      return null;
    }
    return RaceImageFile(bytes: await file.readAsBytes(), name: file.name);
  }
}

class RaceImageRecognitionController
    extends AsyncNotifier<RaceImageRecognitionState> {
  static const int maxImageBytes = 10 * 1024 * 1024;

  late final RaceImagePicker _picker;
  late final AuthenticatedApiClient _apiClient;

  @override
  Future<RaceImageRecognitionState> build() async {
    _picker = ref.read(raceImagePickerProvider);
    _apiClient = ref.read(authenticatedApiClientProvider);
    return const RaceImageRecognitionState();
  }

  Future<void> pickAndRecognize(RaceImageSource source) async {
    _setState(_current.copyWith(
      status: RaceImageRecognitionStatus.picking,
      clearResult: true,
      clearError: true,
    ));
    try {
      final RaceImageFile? image = await _picker.pick(source);
      if (image == null) {
        _setState(const RaceImageRecognitionState());
        return;
      }
      if (image.bytes.length > maxImageBytes) {
        _setState(RaceImageRecognitionState(
          status: RaceImageRecognitionStatus.failure,
          image: image,
          errorMessage: '图片不能超过 10MB',
        ));
        return;
      }
      _setState(RaceImageRecognitionState(
        status: RaceImageRecognitionStatus.recognizing,
        image: image,
      ));
      await recognizeSelected();
    } on PlatformException catch (error) {
      _setState(RaceImageRecognitionState(
        status: RaceImageRecognitionStatus.failure,
        errorMessage: _permissionMessage(error.code),
      ));
    } catch (_) {
      _setState(const RaceImageRecognitionState(
        status: RaceImageRecognitionStatus.failure,
        errorMessage: '无法读取图片，请重新选择',
      ));
    }
  }

  Future<void> recognizeSelected() async {
    final RaceImageFile? image = _current.image;
    if (image == null ||
        _current.isBusy &&
            _current.status != RaceImageRecognitionStatus.recognizing) {
      return;
    }
    _setState(_current.copyWith(
      status: RaceImageRecognitionStatus.recognizing,
      clearResult: true,
      clearError: true,
    ));
    try {
      final Map<String, dynamic> payload = await _apiClient.postMultipartImage(
        '/v1/races/image-recognition',
        bytes: image.bytes,
        filename: image.name,
      );
      _setState(_current.copyWith(
        status: RaceImageRecognitionStatus.success,
        result: RaceImageRecognitionResult.fromJson(payload),
        clearError: true,
      ));
    } on ApiException catch (error) {
      _setState(_current.copyWith(
        status: RaceImageRecognitionStatus.failure,
        errorMessage: error.message,
        clearResult: true,
      ));
    } catch (_) {
      _setState(_current.copyWith(
        status: RaceImageRecognitionStatus.failure,
        errorMessage: '赛事图片识别失败，请稍后重试',
        clearResult: true,
      ));
    }
  }

  void clear() {
    _setState(const RaceImageRecognitionState());
  }

  RaceImageRecognitionState get _current {
    final AsyncValue<RaceImageRecognitionState> current = state;
    if (current case AsyncData<RaceImageRecognitionState>(:final value)) {
      return value;
    }
    return const RaceImageRecognitionState();
  }

  void _setState(RaceImageRecognitionState value) {
    state = AsyncData<RaceImageRecognitionState>(value);
  }

  String _permissionMessage(String code) {
    if (code.contains('camera')) {
      return '无法使用相机，请在系统设置中允许 TrainFlow 访问相机';
    }
    if (code.contains('photo') || code.contains('gallery')) {
      return '无法访问相册，请在系统设置中允许 TrainFlow 访问照片';
    }
    return '无法选择图片，请检查系统权限后重试';
  }
}
