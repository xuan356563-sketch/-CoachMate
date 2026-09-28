import Foundation

struct HealthKitPendingBatchMetadata {
  let athleteId: String
  let objectType: String
  let anchorKey: String
}

enum HealthKitPendingBatchStoreError: LocalizedError {
  case invalidBatch
  case batchNotFound
  case invalidAnchor

  var errorDescription: String? {
    switch self {
    case .invalidBatch:
      return "健康数据批次格式无效。"
    case .batchNotFound:
      return "待确认的健康数据批次不存在。"
    case .invalidAnchor:
      return "健康数据同步锚点无效。"
    }
  }
}

enum LocalHealthFileProtectorError: LocalizedError {
  case invalidPaths
  case pathOutsideSandbox

  var errorDescription: String? {
    switch self {
    case .invalidPaths:
      return "本地健康数据文件路径无效。"
    case .pathOutsideSandbox:
      return "只能保护应用沙盒内的健康数据文件。"
    }
  }
}

final class LocalHealthFileProtector {
  private let fileManager: FileManager
  private let sandboxRoot: URL

  init(
    fileManager: FileManager = .default,
    sandboxRoot: URL? = nil
  ) {
    self.fileManager = fileManager
    self.sandboxRoot = (
      sandboxRoot ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    )
      .standardizedFileURL
      .resolvingSymlinksInPath()
  }

  func protect(paths: [String]) throws {
    guard !paths.isEmpty, paths.count <= 16 else {
      throw LocalHealthFileProtectorError.invalidPaths
    }
    for path in Set(paths) {
      guard path.hasPrefix("/"), !path.contains("\0") else {
        throw LocalHealthFileProtectorError.invalidPaths
      }
      let url = resolvedURL(path: path)
      guard isInsideSandbox(url) else {
        throw LocalHealthFileProtectorError.pathOutsideSandbox
      }
      var isDirectory = ObjCBool(false)
      guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      else {
        continue
      }
      try fileManager.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: url.path
      )
      var protectedURL = url
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try protectedURL.setResourceValues(values)
    }
  }

  private func resolvedURL(path: String) -> URL {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    if fileManager.fileExists(atPath: url.path) {
      return url.resolvingSymlinksInPath()
    }
    let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
    return parent.appendingPathComponent(url.lastPathComponent)
  }

  private func isInsideSandbox(_ url: URL) -> Bool {
    url.path == sandboxRoot.path || url.path.hasPrefix(sandboxRoot.path + "/")
  }
}

final class HealthKitPendingBatchStore {
  private let fileManager: FileManager
  private let rootDirectory: URL
  private let pendingDirectory: URL
  private let anchorDirectory: URL
  private let queue = DispatchQueue(label: "trainmate.healthkit.pending-batches")

  init(
    fileManager: FileManager = .default,
    rootDirectory: URL? = nil
  ) throws {
    self.fileManager = fileManager
    if let rootDirectory {
      self.rootDirectory = rootDirectory
    } else {
      let applicationSupport = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      self.rootDirectory = applicationSupport
        .appendingPathComponent("TrainMateHealthKit", isDirectory: true)
    }
    pendingDirectory = self.rootDirectory
      .appendingPathComponent("pending", isDirectory: true)
    anchorDirectory = self.rootDirectory
      .appendingPathComponent("anchors", isDirectory: true)
    try prepareDirectory(self.rootDirectory)
    try prepareDirectory(pendingDirectory)
    try prepareDirectory(anchorDirectory)
  }

  func enqueue(_ batch: [String: Any]) throws {
    try queue.sync {
      guard
        let batchId = batch["batchId"] as? String,
        !batchId.isEmpty,
        batch["athleteId"] is String,
        batch["anchorKey"] is String,
        JSONSerialization.isValidJSONObject(batch)
      else {
        throw HealthKitPendingBatchStoreError.invalidBatch
      }
      let data = try JSONSerialization.data(withJSONObject: batch, options: [.sortedKeys])
      try writeProtected(data, to: pendingURL(batchId: batchId))
    }
  }

  func pending(limit: Int) throws -> [[String: Any]] {
    try queue.sync {
      let safeLimit = max(1, min(limit, 100))
      let urls = try fileManager.contentsOfDirectory(
        at: pendingDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
      let batches = try urls
        .filter { $0.pathExtension == "json" }
        .map(readBatch)
        .sorted {
          let leftRoute = isWorkoutRouteBatch($0)
          let rightRoute = isWorkoutRouteBatch($1)
          if leftRoute != rightRoute {
            // 路线可能早于父训练到达；先让训练事实落库，避免路线占据队首阻塞。
            return !leftRoute
          }
          let leftCreatedAt = $0["createdAt"] as? String ?? ""
          let rightCreatedAt = $1["createdAt"] as? String ?? ""
          if leftCreatedAt != rightCreatedAt {
            return leftCreatedAt < rightCreatedAt
          }
          return ($0["batchId"] as? String ?? "") <
            ($1["batchId"] as? String ?? "")
        }
      return Array(batches.prefix(safeLimit))
    }
  }

  private func isWorkoutRouteBatch(_ batch: [String: Any]) -> Bool {
    let objectType = (batch["objectType"] as? String ?? "").lowercased()
    if objectType.contains("workoutroute") {
      return true
    }
    let upserts = batch["upserts"] as? [[String: Any]] ?? []
    return upserts.contains {
      ($0["kind"] as? String ?? "").lowercased() == "workoutroute"
    }
  }

  func hasPendingBatch(anchorKey: String) -> Bool {
    queue.sync {
      guard
        let urls = try? fileManager.contentsOfDirectory(
          at: pendingDirectory,
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles]
        )
      else {
        return false
      }
      return urls.contains { url in
        guard let batch = try? readBatch(url) else { return false }
        return batch["anchorKey"] as? String == anchorKey
      }
    }
  }

  func metadata(batchId: String) throws -> HealthKitPendingBatchMetadata {
    try queue.sync {
      let url = pendingURL(batchId: batchId)
      guard fileManager.fileExists(atPath: url.path) else {
        throw HealthKitPendingBatchStoreError.batchNotFound
      }
      let batch = try readBatch(url)
      guard
        let athleteId = batch["athleteId"] as? String,
        let objectType = batch["objectType"] as? String,
        let anchorKey = batch["anchorKey"] as? String
      else {
        throw HealthKitPendingBatchStoreError.invalidBatch
      }
      return HealthKitPendingBatchMetadata(
        athleteId: athleteId,
        objectType: objectType,
        anchorKey: anchorKey
      )
    }
  }

  @discardableResult
  func acknowledge(batchId: String) throws -> HealthKitPendingBatchMetadata {
    try queue.sync {
      let url = pendingURL(batchId: batchId)
      guard fileManager.fileExists(atPath: url.path) else {
        throw HealthKitPendingBatchStoreError.batchNotFound
      }
      let batch = try readBatch(url)
      guard
        let athleteId = batch["athleteId"] as? String,
        let objectType = batch["objectType"] as? String,
        let anchorKey = batch["anchorKey"] as? String
      else {
        throw HealthKitPendingBatchStoreError.invalidBatch
      }
      if let encodedAnchor = batch["nextAnchor"] as? String,
         !encodedAnchor.isEmpty
      {
        guard let anchorData = Data(base64Encoded: encodedAnchor) else {
          throw HealthKitPendingBatchStoreError.invalidAnchor
        }
        try writeProtected(anchorData, to: anchorURL(anchorKey: anchorKey))
      }
      try fileManager.removeItem(at: url)
      return HealthKitPendingBatchMetadata(
        athleteId: athleteId,
        objectType: objectType,
        anchorKey: anchorKey
      )
    }
  }

  func committedAnchorData(anchorKey: String) -> Data? {
    queue.sync {
      try? Data(contentsOf: anchorURL(anchorKey: anchorKey))
    }
  }

  func clear(athleteId: String) throws {
    try queue.sync {
      let pendingURLs = try fileManager.contentsOfDirectory(
        at: pendingDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
      for url in pendingURLs {
        guard
          let batch = try? readBatch(url),
          batch["athleteId"] as? String == athleteId
        else {
          continue
        }
        try fileManager.removeItem(at: url)
      }

      let anchorPrefix = encodedFileName(athleteId) + "--"
      let anchorURLs = try fileManager.contentsOfDirectory(
        at: anchorDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
      for url in anchorURLs where url.lastPathComponent.hasPrefix(anchorPrefix) {
        try fileManager.removeItem(at: url)
      }
    }
  }

  private func prepareDirectory(_ url: URL) throws {
    try fileManager.createDirectory(
      at: url,
      withIntermediateDirectories: true,
      attributes: [
        .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
      ]
    )
    try protectAndExcludeFromBackup(url)
  }

  private func writeProtected(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: [.atomic])
    try fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path
    )
    try protectAndExcludeFromBackup(url)
  }

  private func protectAndExcludeFromBackup(_ sourceURL: URL) throws {
    var url = sourceURL
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }

  private func readBatch(_ url: URL) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    guard let batch = object as? [String: Any] else {
      throw HealthKitPendingBatchStoreError.invalidBatch
    }
    return batch
  }

  private func pendingURL(batchId: String) -> URL {
    pendingDirectory
      .appendingPathComponent(encodedFileName(batchId))
      .appendingPathExtension("json")
  }

  private func anchorURL(anchorKey: String) -> URL {
    let athleteId = anchorKey.split(separator: "|", maxSplits: 1)
      .first
      .map(String.init) ?? ""
    return anchorDirectory
      .appendingPathComponent(
        encodedFileName(athleteId) + "--" + encodedFileName(anchorKey)
      )
      .appendingPathExtension("anchor")
  }

  private func encodedFileName(_ value: String) -> String {
    Data(value.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "=", with: "")
  }
}
