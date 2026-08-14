import 'dart:io';

import 'package:flutter/services.dart';

abstract class VoiceInputGateway {
  bool get isSupported;

  Future<void> startListening();

  Future<String> stopListening();

  Future<void> cancelListening();
}

VoiceInputGateway createVoiceInputGateway() => _IosVoiceInputGateway();

class _IosVoiceInputGateway implements VoiceInputGateway {
  static const MethodChannel _channel =
      MethodChannel('trainflow.ai/voice_input');

  @override
  bool get isSupported => Platform.isIOS;

  @override
  Future<void> startListening() async {
    if (!isSupported) {
      throw UnsupportedError('当前平台暂不支持本地语音转文字');
    }
    await _channel.invokeMethod<void>('startListening');
  }

  @override
  Future<String> stopListening() async {
    if (!isSupported) {
      throw UnsupportedError('当前平台暂不支持本地语音转文字');
    }
    return await _channel.invokeMethod<String>('stopListening') ?? '';
  }

  @override
  Future<void> cancelListening() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('cancelListening');
  }
}
