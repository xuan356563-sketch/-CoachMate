import AVFoundation
import CoreImage
import Flutter
import UIKit
import Vision

/// 任务取消同步生效；队列排空后才清理文件并确认取消完成。
final class RunningVideoTask {
  let id: String
  let directory: URL
  private let lock = NSLock()
  private var cancelled = false
  init(id: String, directory: URL) { self.id = id; self.directory = directory }
  var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
  func cancel() { lock.lock(); cancelled = true; lock.unlock() }
  func check() throws {
    if isCancelled { throw RunningVideoError.message("视频分析已取消") }
  }
  func cleanupFiles() throws {
    guard isCancelled, UUID(uuidString: id) != nil, directory.lastPathComponent == id else {
      throw RunningVideoError.message("拒绝清理不属于已取消任务的目录")
    }
    if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
  }
}

enum RunningVideoError: Error { case message(String) }

final class RunningVideoPoseCoordinator: NSObject, FlutterStreamHandler {
  private let queue = DispatchQueue(label: "trainflow.running.video", qos: .userInitiated)
  private var tasks: [String: RunningVideoTask] = [:]
  private var sink: FlutterEventSink?
  private var startupCleanupFailed = false
  private let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("TrainMateRunningVideo", isDirectory: true)

  func register(messenger: FlutterBinaryMessenger) {
    // 仅清理此功能自己的缓存，不访问相册原件或其他业务目录。
    queue.async {
      do {
        if FileManager.default.fileExists(atPath: self.root.path) { try FileManager.default.removeItem(at: self.root) }
      } catch { self.startupCleanupFailed = true }
    }
    FlutterEventChannel(name: "trainflow.ai/running_video_progress", binaryMessenger: messenger)
      .setStreamHandler(self)
    FlutterMethodChannel(name: "trainflow.ai/running_video", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard let self else { result(nil); return }
        if call.method == "protectPreferences" {
          do {
            var preferences = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
              .appendingPathComponent("Preferences", isDirectory: true)
            try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try preferences.setResourceValues(values)
            result(nil)
          } catch { self.fail("本机报告备份排除保护失败，暂不能保存", result) }
          return
        }
        let args = call.arguments as? [String: Any] ?? [:]
        guard let id = args["taskId"] as? String, UUID(uuidString: id) != nil else {
          self.fail("视频任务标识无效", result); return
        }
        switch call.method {
        case "analyze":
          guard let path = args["path"] as? String else { self.fail("没有读取到视频路径", result); return }
          self.start(id: id, path: path, result: result)
        case "cancel":
          let task = self.tasks[id]
          task?.cancel()
          self.queue.async {
            do {
              try task?.cleanupFiles()
              DispatchQueue.main.async {
                if self.tasks[id] === task { self.tasks.removeValue(forKey: id) }
                result(nil)
              }
            } catch { DispatchQueue.main.async { self.fail("视频临时文件清理失败，请重启应用后重试", result) } }
          }
        case "thumbnail":
          guard let task = self.tasks[id], let seconds = args["seconds"] as? Double else {
            result(nil); return
          }
          self.queue.async {
            do {
              try task.check()
              let asset = AVURLAsset(url: task.directory.appendingPathComponent("source.mov"))
              let generator = AVAssetImageGenerator(asset: asset)
              generator.appliesPreferredTrackTransform = true
              generator.maximumSize = CGSize(width: 960, height: 960)
              generator.requestedTimeToleranceBefore = .zero
              generator.requestedTimeToleranceAfter = .zero
              let cg = try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 60000), actualTime: nil)
              try task.check()
              let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.75)
              DispatchQueue.main.async { result(task.isCancelled ? nil : data.map(FlutterStandardTypedData.init(bytes:))) }
            } catch { DispatchQueue.main.async { result(nil) } }
          }
        default: result(FlutterMethodNotImplemented)
        }
      }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events; return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }

  private func fail(_ message: String, _ result: FlutterResult) {
    result(FlutterError(code: "running_video_failed", message: message, details: nil))
  }

  private func start(id: String, path: String, result: @escaping FlutterResult) {
    guard tasks.isEmpty else { fail("请先结束上一段视频分析", result); return }
    let source = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
    let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
    guard source.path.hasPrefix(home + "/"), FileManager.default.fileExists(atPath: source.path) else {
      fail("视频必须来自本机相册选择的应用临时文件", result); return
    }
    let task = RunningVideoTask(id: id, directory: root.appendingPathComponent(id, isDirectory: true))
    tasks[id] = task
    queue.async {
      do {
        if self.startupCleanupFailed { throw RunningVideoError.message("旧视频临时文件清理失败，请重启应用后重试") }
        try task.check()
        try FileManager.default.createDirectory(at: task.directory, withIntermediateDirectories: true)
        var protected = task.directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try protected.setResourceValues(values)
        let destination = task.directory.appendingPathComponent("source.mov")
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
        let summary = try self.extract(task: task, url: destination)
        try task.check()
        DispatchQueue.main.async {
          if task.isCancelled { self.fail("视频分析已取消", result) } else { result(summary) }
        }
      } catch {
        task.cancel()
        var cleanupFailed = false
        do {
          try task.cleanupFiles()
        } catch { cleanupFailed = true }
        DispatchQueue.main.async {
          if !cleanupFailed && self.tasks[id] === task { self.tasks.removeValue(forKey: id) }
          if cleanupFailed { self.fail("视频处理失败且临时文件尚未清理，请重试取消或重启应用", result) }
          else if case let RunningVideoError.message(message) = error { self.fail(message, result) }
          else { self.fail("视频解码或关键点提取失败，请更换视频后重试", result) }
        }
      }
    }
  }

  /// 检测回调仅用于把解码测试与系统模型可用性分开；正式调用始终使用 Vision。
  func extract(task: RunningVideoTask, url: URL, onFrame: (([String: Any]) -> Void)? = nil,
               detector: ((CGImage) throws -> [VNHumanBodyPoseObservation])? = nil) throws -> [String: Any] {
    let asset = AVURLAsset(url: url)
    let duration = asset.duration.seconds
    guard duration.isFinite, duration >= 5, duration <= 20,
          let track = asset.tracks(withMediaType: .video).first else {
      throw RunningVideoError.message("请选择 5–20 秒的常速侧面跑步视频")
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw RunningVideoError.message("视频格式暂不支持") }
    reader.add(output)
    guard reader.startReading() else { throw RunningVideoError.message("无法解码这段视频") }
    defer { reader.cancelReading() }
    let context = CIContext(options: [.cacheIntermediates: false])
    let request = VNDetectHumanBodyPoseRequest()
    #if targetEnvironment(simulator)
    // 模拟器未提供真机的计算设备；仍运行同一个 Vision 请求，不返回模拟关键点。
    request.usesCPUOnly = true
    #endif
    var lastSample = -Double.infinity
    var lastDecoded = -Double.infinity
    var count = 0
    var previousCenter: CGPoint?
    var continuityLost = false
    while let sample = output.copyNextSampleBuffer() {
      try task.check()
      let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
      guard timestamp.isFinite, timestamp >= 0, timestamp > lastDecoded else {
        throw RunningVideoError.message("视频时间戳异常，不能进行时序评估")
      }
      lastDecoded = timestamp
      if timestamp - lastSample < 1.0 / 30.0 - 0.00001 { continue }
      lastSample = timestamp
      if timestamp > duration + 0.1 || count >= 601 { throw RunningVideoError.message("视频时间范围异常") }
      guard let buffer = CMSampleBufferGetImageBuffer(sample) else { throw RunningVideoError.message("视频画面解码不完整") }
      let frame: [String: Any] = try autoreleasepool {
        let normalized = Self.orientedImage(CIImage(cvPixelBuffer: buffer), transform: track.preferredTransform)
        let extent = normalized.extent
        let scale = min(1, 960 / max(extent.width, extent.height))
        let image = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(image, from: image.extent) else { throw RunningVideoError.message("视频画面无法读取") }
        let people: [VNHumanBodyPoseObservation]
        if let detector { people = try detector(cg) }
        else {
          try VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
          people = request.results ?? []
        }
        var status = "valid"
        var landmarks: [[String: Any]] = []
        if people.count != 1 {
          status = people.isEmpty ? "missing" : "multiple"
          previousCenter = nil
          continuityLost = true
        } else {
          let points = try people[0].recognizedPoints(.all)
          landmarks = Self.mapping.compactMap { joint, label in
            guard let p = points[joint], p.confidence > 0 else { return nil }
            return ["type": label, "x": p.location.x, "y": 1 - p.location.y, "visibility": p.confidence]
          }
          let hips = [points[.leftHip], points[.rightHip]].compactMap { $0 }.filter { $0.confidence >= 0.6 }
          if !hips.isEmpty {
            let center = CGPoint(x: hips.map { $0.location.x }.reduce(0, +) / Double(hips.count),
                                 y: hips.map { $0.location.y }.reduce(0, +) / Double(hips.count))
            if let previousCenter, hypot(center.x - previousCenter.x, center.y - previousCenter.y) > 0.2 {
              continuityLost = true
            }
            // 一旦无法确认同一主体，不跨身份变化重新建立可评分序列。
            if continuityLost { status = "discontinuous" }
            previousCenter = center
          } else {
            status = "missing"
          }
        }
        return ["seconds": timestamp, "width": extent.width, "height": extent.height,
                "status": status, "landmarks": landmarks]
      }
      count += 1
      onFrame?(frame)
      DispatchQueue.main.async {
        if !task.isCancelled {
          self.sink?(["taskId": task.id, "progress": min(timestamp / duration, 1), "frame": frame])
        }
      }
    }
    if reader.status == .failed { throw RunningVideoError.message("视频未完整解码，请重试") }
    guard count > 0 else { throw RunningVideoError.message("没有读取到视频画面") }
    return ["duration": duration, "frameCount": count,
            "detectorVersion": "AppleVision-revision-\(request.revision)-iOS-\(UIDevice.current.systemVersion)"]
  }

  static func orientedImage(_ image: CIImage, transform: CGAffineTransform) -> CIImage {
    let transformed = image.transformed(by: transform)
    return transformed.transformed(by: CGAffineTransform(translationX: -transformed.extent.minX, y: -transformed.extent.minY))
  }

  private static let mapping: [(VNHumanBodyPoseObservation.JointName, String)] = [
    (.nose, "nose"), (.leftShoulder, "left_shoulder"), (.rightShoulder, "right_shoulder"),
    (.leftElbow, "left_elbow"), (.rightElbow, "right_elbow"), (.leftWrist, "left_wrist"),
    (.rightWrist, "right_wrist"), (.leftHip, "left_hip"), (.rightHip, "right_hip"),
    (.leftKnee, "left_knee"), (.rightKnee, "right_knee"), (.leftAnkle, "left_ankle"), (.rightAnkle, "right_ankle")
  ]
}
