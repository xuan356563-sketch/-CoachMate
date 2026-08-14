import 'dart:io';

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('trainflow.ai/workout_assist');

Future<bool> speak(
  String text, {
  double rate = 1,
  String? voiceName,
}) async {
  if (!Platform.isIOS || text.trim().isEmpty) return false;
  try {
    return await _channel.invokeMethod<bool>(
          'speak',
          <String, Object?>{
            'text': text.trim(),
            'rate': rate.clamp(0.5, 2).toDouble(),
            if (voiceName?.trim().isNotEmpty ?? false)
              'voiceName': voiceName!.trim(),
          },
        ) ??
        false;
  } on PlatformException {
    return false;
  }
}

Future<void> stopSpeech() async {
  if (!Platform.isIOS) return;
  try {
    await _channel.invokeMethod<void>('stopSpeech');
  } on PlatformException {
    // 平台不支持时保持静默，不中断训练流程。
  }
}

Future<bool> setScreenAwake(bool enabled) async {
  if (!Platform.isIOS) return false;
  try {
    return await _channel.invokeMethod<bool>(
          'setScreenAwake',
          <String, Object?>{'enabled': enabled},
        ) ??
        false;
  } on PlatformException {
    return false;
  }
}
