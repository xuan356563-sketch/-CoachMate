import AVFoundation
import Flutter
import Speech
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let voiceInputCoordinator = VoiceInputCoordinator()
  private let healthKitSyncCoordinator = HealthKitSyncCoordinator()
  private let runningVideoCoordinator = RunningVideoPoseCoordinator()
  private let workoutAssistCoordinator = WorkoutAssistCoordinator()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    healthKitSyncCoordinator.restoreObservers()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    healthKitSyncCoordinator.register(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    runningVideoCoordinator.register(messenger: engineBridge.applicationRegistrar.messenger())
    let channel = FlutterMethodChannel(
      name: "trainflow.ai/vision_pose",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "detectPose" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String,
        !path.isEmpty
      else {
        result(FlutterError(
          code: "invalid_path",
          message: "没有读取到照片路径。",
          details: nil
        ))
        return
      }
      Self.detectPose(path: path, result: result)
    }
    let voiceChannel = FlutterMethodChannel(
      name: "trainflow.ai/voice_input",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    voiceChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(
          code: "voice_unavailable",
          message: "本地语音转文字暂不可用。",
          details: nil
        ))
        return
      }
      switch call.method {
      case "startListening":
        self.voiceInputCoordinator.start(result: result)
      case "stopListening":
        self.voiceInputCoordinator.stop(result: result)
      case "cancelListening":
        self.voiceInputCoordinator.cancel()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let workoutAssistChannel = FlutterMethodChannel(
      name: "trainflow.ai/workout_assist",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    workoutAssistChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(
          code: "workout_assist_unavailable",
          message: "跟练语音和屏幕常亮暂不可用。",
          details: nil
        ))
        return
      }
      switch call.method {
      case "speak":
        self.workoutAssistCoordinator.speak(
          arguments: call.arguments,
          result: result
        )
      case "stopSpeech":
        self.workoutAssistCoordinator.stopSpeech()
        result(nil)
      case "setScreenAwake":
        self.workoutAssistCoordinator.setScreenAwake(
          arguments: call.arguments,
          result: result
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func detectPose(path: String, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(url: URL(fileURLWithPath: path))
        try handler.perform([request])
        guard let observation = request.results?.first else {
          DispatchQueue.main.async { result([]) }
          return
        }
        let points = try observation.recognizedPoints(.all)
        let mapping: [(VNHumanBodyPoseObservation.JointName, String)] = [
          (.nose, "nose"),
          (.leftShoulder, "left_shoulder"),
          (.rightShoulder, "right_shoulder"),
          (.leftElbow, "left_elbow"),
          (.rightElbow, "right_elbow"),
          (.leftWrist, "left_wrist"),
          (.rightWrist, "right_wrist"),
          (.leftHip, "left_hip"),
          (.rightHip, "right_hip"),
          (.leftKnee, "left_knee"),
          (.rightKnee, "right_knee"),
          (.leftAnkle, "left_ankle"),
          (.rightAnkle, "right_ankle"),
        ]
        let landmarks: [[String: Any]] = mapping.compactMap { joint, label in
          guard let point = points[joint], point.confidence > 0.1 else {
            return nil
          }
          return [
            "type": label,
            "x": point.location.x,
            "y": 1 - point.location.y,
            "confidence": point.confidence,
          ]
        }
        DispatchQueue.main.async { result(landmarks) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "vision_failed",
            message: "设备端姿态识别失败，请更换照片后重试。",
            details: nil
          ))
        }
      }
    }
  }
}

private final class WorkoutAssistCoordinator: NSObject, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func speak(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let values = arguments as? [String: Any],
      let rawText = values["text"] as? String
    else {
      result(FlutterError(
        code: "invalid_speech_text",
        message: "没有读取到需要播报的跟练内容。",
        details: nil
      ))
      return
    }
    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      result(false)
      return
    }
    let configuredRate = min(max(values["rate"] as? Double ?? 1, 0.5), 2)
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(
        .playback,
        mode: .spokenAudio,
        options: [.mixWithOthers, .duckOthers, .allowBluetoothA2DP]
      )
      try audioSession.setActive(true)
    } catch {
      result(FlutterError(
        code: "speech_audio_session_failed",
        message: "无法准备跟练语音，请检查设备音频状态。",
        details: nil
      ))
      return
    }
    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: text)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(configuredRate)
    if
      let voiceName = values["voiceName"] as? String,
      !voiceName.isEmpty,
      let voice = AVSpeechSynthesisVoice(identifier: voiceName)
    {
      utterance.voice = voice
    } else {
      utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
    }
    synthesizer.speak(utterance)
    result(true)
  }

  func stopSpeech() {
    synthesizer.stopSpeaking(at: .immediate)
    deactivateAudioSession()
  }

  func setScreenAwake(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let values = arguments as? [String: Any],
      let enabled = values["enabled"] as? Bool
    else {
      result(FlutterError(
        code: "invalid_screen_awake_value",
        message: "没有读取到屏幕常亮设置。",
        details: nil
      ))
      return
    }
    DispatchQueue.main.async {
      UIApplication.shared.isIdleTimerDisabled = enabled
      result(true)
    }
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    deactivateAudioSession()
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    deactivateAudioSession()
  }

  private func deactivateAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setActive(
        false,
        options: .notifyOthersOnDeactivation
      )
    } catch {
      // 语音结束后的会话恢复失败不应中断训练流程。
    }
  }
}

private final class VoiceInputCoordinator {
  private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
  private let audioEngine = AVAudioEngine()
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var pendingStopResult: FlutterResult?
  private var latestTranscript = ""
  private var latestError: String?
  private var isRecording = false

  deinit {
    resetAudioResources(cancelTask: true)
  }

  func start(result: @escaping FlutterResult) {
    guard !isRecording else {
      result(FlutterError(
        code: "voice_already_recording",
        message: "正在进行本地语音转文字。",
        details: nil
      ))
      return
    }
    requestSpeechPermission { [weak self] granted in
      guard let self else { return }
      guard granted else {
        result(FlutterError(
          code: "speech_permission_denied",
          message: "请在系统设置中允许语音识别权限。",
          details: nil
        ))
        return
      }
      self.requestMicrophonePermission { microphoneGranted in
        guard microphoneGranted else {
          result(FlutterError(
            code: "microphone_permission_denied",
            message: "请在系统设置中允许麦克风权限。",
            details: nil
          ))
          return
        }
        self.startEngine(result: result)
      }
    }
  }

  func stop(result: @escaping FlutterResult) {
    if let error = latestError, !isRecording {
      latestError = nil
      result(FlutterError(
        code: "voice_recognition_failed",
        message: error,
        details: nil
      ))
      return
    }
    guard isRecording || recognitionTask != nil else {
      result(latestTranscript)
      latestTranscript = ""
      return
    }
    pendingStopResult = result
    isRecording = false
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    recognitionRequest?.endAudio()
    recognitionTask?.finish()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.finishStop()
    }
  }

  func cancel() {
    pendingStopResult = nil
    latestTranscript = ""
    latestError = nil
    resetAudioResources(cancelTask: true)
  }

  private func requestSpeechPermission(completion: @escaping (Bool) -> Void) {
    let status = SFSpeechRecognizer.authorizationStatus()
    if status == .notDetermined {
      SFSpeechRecognizer.requestAuthorization { authorizationStatus in
        DispatchQueue.main.async {
          completion(authorizationStatus == .authorized)
        }
      }
      return
    }
    completion(status == .authorized)
  }

  private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
    let session = AVAudioSession.sharedInstance()
    if session.recordPermission == .undetermined {
      session.requestRecordPermission { granted in
        DispatchQueue.main.async {
          completion(granted)
        }
      }
      return
    }
    completion(session.recordPermission == .granted)
  }

  private func startEngine(result: @escaping FlutterResult) {
    guard let recognizer, recognizer.isAvailable else {
      result(FlutterError(
        code: "speech_unavailable",
        message: "当前设备暂时无法使用语音识别。",
        details: nil
      ))
      return
    }
    guard recognizer.supportsOnDeviceRecognition else {
      result(FlutterError(
        code: "speech_on_device_unavailable",
        message: "当前设备未提供离线语音识别，请使用文字输入。",
        details: nil
      ))
      return
    }

    resetAudioResources(cancelTask: true)
    latestTranscript = ""
    latestError = nil
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = true
    recognitionRequest = request

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: .duckOthers)
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      let inputNode = audioEngine.inputNode
      let format = inputNode.outputFormat(forBus: 0)
      inputNode.removeTap(onBus: 0)
      inputNode.installTap(
        onBus: 0,
        bufferSize: 1024,
        format: format
      ) { [weak request] buffer, _ in
        request?.append(buffer)
      }
      audioEngine.prepare()
      try audioEngine.start()
      isRecording = true
      recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
        DispatchQueue.main.async {
          guard let self else { return }
          if let result {
            self.latestTranscript = result.bestTranscription.formattedString
            if result.isFinal {
              self.finishStop()
            }
          }
          if error != nil {
            self.latestError = "语音转写失败，请重新尝试。"
            self.finishStop()
          }
        }
      }
      result(nil)
    } catch {
      resetAudioResources(cancelTask: true)
      result(FlutterError(
        code: "voice_start_failed",
        message: "无法启动本地语音转文字，请稍后重试。",
        details: nil
      ))
    }
  }

  private func finishStop() {
    guard let result = pendingStopResult else {
      if !isRecording {
        resetAudioResources(cancelTask: false)
      }
      return
    }
    pendingStopResult = nil
    let transcript = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    let error = latestError
    resetAudioResources(cancelTask: false)
    latestTranscript = ""
    latestError = nil
    if let error {
      result(FlutterError(
        code: "voice_recognition_failed",
        message: error,
        details: nil
      ))
    } else {
      result(transcript)
    }
  }

  private func resetAudioResources(cancelTask: Bool) {
    isRecording = false
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    recognitionRequest?.endAudio()
    if cancelTask {
      recognitionTask?.cancel()
    }
    recognitionTask = nil
    recognitionRequest = nil
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )
  }
}
