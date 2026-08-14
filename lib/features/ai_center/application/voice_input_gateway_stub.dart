abstract class VoiceInputGateway {
  bool get isSupported;

  Future<void> startListening();

  Future<String> stopListening();

  Future<void> cancelListening();
}

VoiceInputGateway createVoiceInputGateway() => _UnsupportedVoiceInputGateway();

class _UnsupportedVoiceInputGateway implements VoiceInputGateway {
  @override
  bool get isSupported => false;

  @override
  Future<void> cancelListening() async {}

  @override
  Future<void> startListening() {
    throw UnsupportedError('当前平台暂不支持本地语音转文字');
  }

  @override
  Future<String> stopListening() {
    throw UnsupportedError('当前平台暂不支持本地语音转文字');
  }
}
