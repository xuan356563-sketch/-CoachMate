// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSObject? _wakeLockSentinel;

Future<bool> speak(
  String text, {
  double rate = 1,
  String? voiceName,
}) async {
  final String trimmedText = text.trim();
  if (trimmedText.isEmpty) {
    return false;
  }
  try {
    final html.SpeechSynthesis? synthesis = html.window.speechSynthesis;
    if (synthesis == null) {
      return false;
    }
    synthesis.cancel();
    final html.SpeechSynthesisUtterance utterance =
        html.SpeechSynthesisUtterance(trimmedText);
    utterance.lang = 'zh-CN';
    utterance.rate = rate.clamp(0.5, 2).toDouble();
    final String selectedName = voiceName?.trim() ?? '';
    if (selectedName.isNotEmpty) {
      for (final html.SpeechSynthesisVoice voice in synthesis.getVoices()) {
        if (voice.name == selectedName) {
          utterance.voice = voice;
          break;
        }
      }
    }
    synthesis.speak(utterance);
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> stopSpeech() async {
  try {
    html.window.speechSynthesis?.cancel();
  } catch (_) {}
}

Future<bool> setScreenAwake(bool enabled) async {
  if (!enabled) {
    final JSObject? sentinel = _wakeLockSentinel;
    _wakeLockSentinel = null;
    if (sentinel == null) {
      return true;
    }
    try {
      final JSPromise<JSAny?> releaseResult =
          sentinel.callMethodVarArgs<JSPromise<JSAny?>>('release'.toJS);
      await releaseResult.toDart;
    } catch (_) {}
    return true;
  }

  try {
    final JSObject windowObject = JSObject.fromInteropObject(html.window);
    final JSObject navigator = windowObject['navigator']! as JSObject;
    final JSObject? wakeLock = navigator['wakeLock'] as JSObject?;
    if (wakeLock == null) {
      return false;
    }
    final JSPromise<JSObject> requestResult = wakeLock.callMethodVarArgs(
      'request'.toJS,
      <JSAny?>['screen'.toJS],
    );
    _wakeLockSentinel = await requestResult.toDart;
    return _wakeLockSentinel != null;
  } catch (_) {
    return false;
  }
}
