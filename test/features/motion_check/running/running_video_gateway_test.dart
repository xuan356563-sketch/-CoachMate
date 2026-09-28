import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/motion_check/running/running_video_pose_gateway.dart';
import 'package:trainflow_ai/features/motion_check/running/running_pose_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('未知类型和缺失置信度不得转换为默认关键点', () {
    final frame = {
      'seconds': 0,
      'width': 1920,
      'height': 1080,
      'status': 'valid',
      'landmarks': [
        {'type': 'not_known', 'x': .2, 'y': .3, 'visibility': .9}
      ]
    };
    expect(() => RunningPoseFrame.fromJson(frame), throwsFormatException);
    frame['landmarks'] = [
      {'type': 'nose', 'x': .2, 'y': .3}
    ];
    expect(() => RunningPoseFrame.fromJson(frame), throwsFormatException);
    frame['landmarks'] = [];
    for (final invalid in [
      {'width': 0},
      {'height': double.nan},
      {'seconds': -1},
      {'seconds': double.infinity},
    ]) {
      expect(() => RunningPoseFrame.fromJson({...frame, ...invalid}),
          throwsFormatException);
    }
  });
  test('不支持的平台不能调用原生视频处理', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final gateway = PlatformRunningVideoPoseGateway();
    expect(gateway.isSupported, isFalse);
    await expectLater(
        gateway.analyze(taskId: 'test', path: 'unused', onProgress: (_) {}),
        throwsStateError);
    await gateway.dispose();
  });
  test('取消与销毁重复调用不会重复发送原生取消', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const method = MethodChannel('trainflow.ai/running_video');
    const events = MethodChannel('trainflow.ai/running_video_progress');
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call.method);
      if (call.method == 'analyze') {
        return {'duration': 10.0, 'frameCount': 0, 'detectorVersion': 'test'};
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(method, null);
      messenger.setMockMethodCallHandler(events, null);
    });
    final gateway = PlatformRunningVideoPoseGateway();
    await gateway.analyze(taskId: 'test', path: 'test', onProgress: (_) {});
    await gateway.cancel('test');
    await gateway.cancel('test');
    await gateway.dispose();
    expect(calls, ['analyze', 'cancel']);
  });
}
