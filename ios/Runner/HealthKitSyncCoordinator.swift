import CoreLocation
import Flutter
import Foundation
import HealthKit

struct HeartRateRefreshWindow: Equatable {
  let start: Date
  let end: Date
  let usesConservativeDeletionLookback: Bool
}

struct HeartRateRefreshSummary: Equatable {
  let rawSampleCount: Int
  let averageHeartRate: Double?
  let maximumHeartRate: Double?
  let coverage: Double
}

final class HealthKitSyncCoordinator {
  private static let channelName = "trainflow.ai/healthkit_sync"
  private static let backgroundConfigurationKey =
    "trainmate.healthkit.background.configuration.v1"
  private static let queryVersion = 1
  private static let heartRateDeletionLookback = TimeInterval(7 * 24 * 60 * 60)
  private static let maximumHeartRateSupportGap = TimeInterval(10)

  private let healthStore: HKHealthStore
  private let pendingStore: HealthKitPendingBatchStore?
  private let localFileProtector: LocalHealthFileProtector
  private let defaults: UserDefaults
  private let workerQueue = DispatchQueue(label: "trainmate.healthkit.sync")
  private var observerQueries: [String: HKObserverQuery] = [:]

  init(
    healthStore: HKHealthStore = HKHealthStore(),
    pendingStore: HealthKitPendingBatchStore? = try? HealthKitPendingBatchStore(),
    localFileProtector: LocalHealthFileProtector = LocalHealthFileProtector(),
    defaults: UserDefaults = .standard
  ) {
    self.healthStore = healthStore
    self.pendingStore = pendingStore
    self.localFileProtector = localFileProtector
    self.defaults = defaults
  }

  func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(Self.flutterError(
          code: "healthkit_unavailable",
          message: "Apple 健康服务暂不可用。"
        ))
        return
      }
      self.handle(call: call, result: result)
    }
  }

  func restoreObservers() {
    guard
      pendingStore != nil,
      let configuration = defaults.dictionary(
        forKey: Self.backgroundConfigurationKey
      ),
      let athleteId = configuration["athleteId"] as? String,
      !athleteId.isEmpty,
      let stageNames = configuration["stages"] as? [String]
    else {
      return
    }
    for stageName in stageNames {
      startObservers(stage: stageName, athleteId: athleteId)
      // 升级后 analysis 可能新增心率观察类型；重新声明后台投递可让已有
      // 配置获得新类型，而不要求用户删除并重建同步设置。
      for type in observerTypes(stage: stageName) ?? [] {
        healthStore.enableBackgroundDelivery(
          for: type,
          frequency: .immediate
        ) { _, _ in }
      }
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestAuthorization":
      requestAuthorization(arguments: call.arguments, result: result)
    case "fetchForeground":
      fetchForeground(arguments: call.arguments, result: result)
    case "fetchDailyActivitySummaries":
      fetchDailyActivitySummaries(arguments: call.arguments, result: result)
    case "fetchWorkoutDetails":
      fetchWorkoutDetails(arguments: call.arguments, result: result)
    case "enableBackgroundSync":
      enableBackgroundSync(arguments: call.arguments, result: result)
    case "drainPendingBatches":
      drainPendingBatches(arguments: call.arguments, result: result)
    case "ackPendingBatch":
      acknowledgePendingBatch(arguments: call.arguments, result: result)
    case "clearPendingBatches":
      clearPendingBatches(arguments: call.arguments, result: result)
    case "protectLocalFiles":
      protectLocalFiles(arguments: call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestAuthorization(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result([
        "requestCompleted": false,
        "message": "当前设备不支持 Apple 健康。",
      ])
      return
    }
    guard
      let values = arguments as? [String: Any],
      let stage = values["stage"] as? String,
      let athleteId = values["athleteId"] as? String,
      !athleteId.isEmpty,
      let readTypes = readTypes(stage: stage)
    else {
      result(Self.flutterError(
        code: "invalid_healthkit_arguments",
        message: "健康权限请求参数无效。"
      ))
      return
    }
    healthStore.requestAuthorization(toShare: [], read: readTypes) {
      success, error in
      DispatchQueue.main.async {
        if let error {
          result(Self.flutterError(
            code: "healthkit_authorization_failed",
            message: "Apple 健康权限请求失败。",
            details: error.localizedDescription
          ))
          return
        }
        result([
          "requestCompleted": success,
          "state": "undetermined",
          "athleteId": athleteId,
          "message": success
            ? "权限流程已完成；iOS 不公开逐项读取授权状态。"
            : "Apple 健康权限请求未完成。",
        ])
      }
    }
  }

  private func fetchForeground(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard
      let values = arguments as? [String: Any],
      let stage = values["stage"] as? String,
      let athleteId = values["athleteId"] as? String,
      let startMilliseconds = values["startTime"] as? NSNumber,
      let endMilliseconds = values["endTime"] as? NSNumber,
      !athleteId.isEmpty
    else {
      result(Self.flutterError(
        code: "invalid_healthkit_arguments",
        message: "健康数据同步参数无效。"
      ))
      return
    }
    let start = Date(timeIntervalSince1970: startMilliseconds.doubleValue / 1_000)
    let end = Date(timeIntervalSince1970: endMilliseconds.doubleValue / 1_000)
    guard start < end else {
      result(Self.flutterError(
        code: "invalid_healthkit_range",
        message: "健康数据同步时间范围无效。"
      ))
      return
    }

    fetchForegroundRecords(stage: stage, start: start, end: end) {
      [weak self] records, error in
      guard let self else { return }
      DispatchQueue.main.async {
        if let error {
          result(Self.flutterError(
            code: "healthkit_foreground_fetch_failed",
            message: "读取 Apple 健康数据失败。",
            details: error.localizedDescription
          ))
          return
        }
        var batch = self.makeBatch(
          athleteId: athleteId,
          objectType: "foreground.\(stage)",
          anchorKey: "foreground|\(athleteId)|\(stage)",
          upserts: records,
          deletedIds: [],
          nextAnchor: nil,
          requiresAcknowledgement: false
        )
        let formatter = ISO8601DateFormatter()
        batch["coverageStart"] = formatter.string(from: start)
        batch["coverageEnd"] = formatter.string(from: end)
        result(batch)
      }
    }
  }

  private func fetchDailyActivitySummaries(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result([])
      return
    }
    guard
      let values = arguments as? [String: Any],
      let startMilliseconds = values["startTime"] as? NSNumber,
      let endMilliseconds = values["endTime"] as? NSNumber
    else {
      result(Self.flutterError(
        code: "invalid_daily_activity_arguments",
        message: "每日活动摘要参数无效。"
      ))
      return
    }
    let start = Date(
      timeIntervalSince1970: startMilliseconds.doubleValue / 1_000
    )
    let end = Date(
      timeIntervalSince1970: endMilliseconds.doubleValue / 1_000
    )
    guard start < end else {
      result(Self.flutterError(
        code: "invalid_daily_activity_range",
        message: "每日活动摘要时间范围无效。"
      ))
      return
    }

    fetchDailyActivitySummaryRecords(start: start, end: end) { records in
      DispatchQueue.main.async {
        result(records)
      }
    }
  }

  private func fetchWorkoutDetails(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard
      let values = arguments as? [String: Any],
      let rawUuid = values["workoutUuid"] as? String,
      let uuid = UUID(uuidString: rawUuid)
    else {
      result(Self.flutterError(
        code: "invalid_workout_uuid",
        message: "训练记录标识无效。"
      ))
      return
    }
    let predicate = HKQuery.predicateForObjects(with: [uuid])
    let query = HKSampleQuery(
      sampleType: .workoutType(),
      predicate: predicate,
      limit: 1,
      sortDescriptors: nil
    ) { [weak self] _, samples, error in
      guard let self else { return }
      if let error {
        DispatchQueue.main.async {
          result(Self.flutterError(
            code: "healthkit_workout_fetch_failed",
            message: "读取训练详情失败。",
            details: error.localizedDescription
          ))
        }
        return
      }
      guard let workout = samples?.first as? HKWorkout else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      self.buildWorkoutDetails(workout) { details, detailError in
        DispatchQueue.main.async {
          if let detailError {
            result(Self.flutterError(
              code: "healthkit_workout_details_failed",
              message: "读取训练心率或路线详情失败。",
              details: detailError.localizedDescription
            ))
          } else {
            result(details)
          }
        }
      }
    }
    healthStore.execute(query)
  }

  func enableBackgroundSync(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard
      pendingStore != nil,
      let values = arguments as? [String: Any],
      let stage = values["stage"] as? String,
      let athleteId = values["athleteId"] as? String,
      !athleteId.isEmpty,
      let sampleTypes = observerTypes(stage: stage)
    else {
      result(Self.flutterError(
        code: pendingStore == nil
          ? "healthkit_queue_unavailable"
          : "invalid_healthkit_arguments",
        message: pendingStore == nil
          ? "本地健康数据队列不可用，未启用后台同步。"
          : "后台健康同步参数无效。"
      ))
      return
    }
    var stages = Set<String>()
    if let existing = defaults.dictionary(
      forKey: Self.backgroundConfigurationKey
    ), existing["athleteId"] as? String == athleteId {
      stages.formUnion(existing["stages"] as? [String] ?? [])
    } else {
      stopObservers()
    }
    stages.insert(stage)
    defaults.set(
      ["athleteId": athleteId, "stages": stages.sorted()],
      forKey: Self.backgroundConfigurationKey
    )
    startObservers(stage: stage, athleteId: athleteId)

    let group = DispatchGroup()
    let lock = NSLock()
    var firstError: Error?
    for type in sampleTypes {
      group.enter()
      healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) {
        success, error in
        if !success || error != nil {
          lock.lock()
          if firstError == nil {
            firstError = error ?? NSError(
              domain: "TrainMateHealthKit",
              code: 1,
              userInfo: [NSLocalizedDescriptionKey: "系统未启用后台健康更新。"]
            )
          }
          lock.unlock()
        }
        group.leave()
      }
    }
    group.notify(queue: .main) {
      if let firstError {
        result(Self.flutterError(
          code: "healthkit_background_enable_failed",
          message: "后台健康更新暂未启用。",
          details: firstError.localizedDescription
        ))
      } else {
        result(nil)
      }
    }
  }

  private func drainPendingBatches(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    let values = arguments as? [String: Any]
    let limit = (values?["limit"] as? NSNumber)?.intValue ?? 20
    guard let pendingStore else {
      result(Self.flutterError(
        code: "healthkit_queue_unavailable",
        message: "本地健康数据队列不可用。"
      ))
      return
    }
    do {
      let batches = try pendingStore.pending(limit: limit).map(channelBatch)
      result(batches)
    } catch {
      result(Self.flutterError(
        code: "healthkit_queue_read_failed",
        message: "读取本地健康数据队列失败。",
        details: error.localizedDescription
      ))
    }
  }

  private func acknowledgePendingBatch(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard
      let values = arguments as? [String: Any],
      let batchId = values["batchId"] as? String,
      !batchId.isEmpty,
      let pendingStore
    else {
      result(Self.flutterError(
        code: "invalid_healthkit_batch",
        message: "健康数据批次标识无效。"
      ))
      return
    }
    do {
      let metadata = try pendingStore.acknowledge(batchId: batchId)
      if let type = sampleType(identifier: metadata.objectType) {
        captureChanges(
          type: type,
          athleteId: metadata.athleteId,
          completion: {
            DispatchQueue.main.async { result(nil) }
          }
        )
      } else {
        result(nil)
      }
    } catch {
      result(Self.flutterError(
        code: "healthkit_batch_ack_failed",
        message: "确认健康数据批次失败。",
        details: error.localizedDescription
      ))
    }
  }

  private func clearPendingBatches(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard
      let values = arguments as? [String: Any],
      let athleteId = values["athleteId"] as? String,
      !athleteId.isEmpty,
      let pendingStore
    else {
      result(Self.flutterError(
        code: "invalid_healthkit_athlete",
        message: "运动员标识无效。"
      ))
      return
    }
    do {
      try pendingStore.clear(athleteId: athleteId)
      if let configuration = defaults.dictionary(
        forKey: Self.backgroundConfigurationKey
      ), configuration["athleteId"] as? String == athleteId {
        defaults.removeObject(forKey: Self.backgroundConfigurationKey)
        stopObservers()
        healthStore.disableAllBackgroundDelivery { _, _ in }
      }
      result(nil)
    } catch {
      result(Self.flutterError(
        code: "healthkit_clear_failed",
        message: "清除本地健康数据队列失败。",
        details: error.localizedDescription
      ))
    }
  }

  private func protectLocalFiles(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard
      let values = arguments as? [String: Any],
      let paths = values["paths"] as? [String],
      !paths.isEmpty
    else {
      result(Self.flutterError(
        code: "invalid_health_file_paths",
        message: "本地健康数据文件路径无效。"
      ))
      return
    }
    workerQueue.async { [localFileProtector] in
      do {
        try localFileProtector.protect(paths: paths)
        DispatchQueue.main.async { result(nil) }
      } catch {
        DispatchQueue.main.async {
          result(Self.flutterError(
            code: "health_file_protection_failed",
            message: "本地健康数据文件保护失败。",
            details: error.localizedDescription
          ))
        }
      }
    }
  }

  private func startObservers(stage: String, athleteId: String) {
    guard let types = observerTypes(stage: stage) else { return }
    for type in types {
      let identifier = type.identifier
      guard observerQueries[identifier] == nil else { continue }
      let query = HKObserverQuery(
        sampleType: type,
        predicate: nil
      ) { [weak self] _, completion, error in
        guard let self else {
          completion()
          return
        }
        guard error == nil else {
          completion()
          return
        }
        self.captureChanges(
          type: type,
          athleteId: athleteId,
          completion: completion
        )
      }
      observerQueries[identifier] = query
      healthStore.execute(query)
    }
  }

  private func stopObservers() {
    for query in observerQueries.values {
      healthStore.stop(query)
    }
    observerQueries.removeAll()
  }

  private func captureChanges(
    type: HKSampleType,
    athleteId: String,
    completion: @escaping () -> Void
  ) {
    if isHeartRateType(type) {
      captureHeartRateChanges(
        type: type,
        athleteId: athleteId,
        completion: completion
      )
      return
    }
    guard let pendingStore else {
      completion()
      return
    }
    let anchorKey = makeAnchorKey(athleteId: athleteId, type: type)
    if pendingStore.hasPendingBatch(anchorKey: anchorKey) {
      completion()
      return
    }
    let anchor = pendingStore.committedAnchorData(anchorKey: anchorKey)
      .flatMap(decodeAnchor)
    let hasCommittedAnchor = anchor != nil
    let query = HKAnchoredObjectQuery(
      type: type,
      predicate: nil,
      anchor: anchor,
      limit: 500
    ) { [weak self] _, added, deleted, nextAnchor, error in
      guard let self else {
        completion()
        return
      }
      guard error == nil, let nextAnchor else {
        completion()
        return
      }
      guard let encodedAnchor = self.encodeAnchor(nextAnchor) else {
        completion()
        return
      }
      let records = (added ?? []).map(self.serializeSample)
      let deletedIds = (deleted ?? []).map { $0.uuid.uuidString }
      guard self.shouldEnqueueAnchoredBatch(
        hasCommittedAnchor: hasCommittedAnchor,
        addedCount: records.count,
        deletedCount: deletedIds.count
      ) else {
        completion()
        return
      }
      let batch = self.makeBatch(
        athleteId: athleteId,
        objectType: type.identifier,
        anchorKey: anchorKey,
        upserts: records,
        deletedIds: deletedIds,
        nextAnchor: encodedAnchor.base64EncodedString(),
        requiresAcknowledgement: true
      )
      do {
        try pendingStore.enqueue(batch)
      } catch {
        completion()
        return
      }
      completion()
    }
    healthStore.execute(query)
  }

  /// 心率 anchored 增量只用来定位需要刷新的训练。逐秒样本和删除 UUID
  /// 不写入本地事实批次；Flutter 在训练摘要落库后按 UUID 即时回读详情并重算。
  private func captureHeartRateChanges(
    type: HKSampleType,
    athleteId: String,
    completion: @escaping () -> Void
  ) {
    guard let pendingStore else {
      completion()
      return
    }
    let anchorKey = makeAnchorKey(athleteId: athleteId, type: type)
    if pendingStore.hasPendingBatch(anchorKey: anchorKey) {
      completion()
      return
    }
    let anchor = pendingStore.committedAnchorData(anchorKey: anchorKey)
      .flatMap(decodeAnchor)
    let hasCommittedAnchor = anchor != nil
    let query = HKAnchoredObjectQuery(
      type: type,
      predicate: nil,
      anchor: anchor,
      limit: 500
    ) { [weak self] _, added, deleted, nextAnchor, error in
      guard let self else {
        completion()
        return
      }
      guard error == nil, let nextAnchor else {
        completion()
        return
      }
      guard let encodedAnchor = self.encodeAnchor(nextAnchor) else {
        completion()
        return
      }
      let addedSamples = added ?? []
      let deletedCount = deleted?.count ?? 0
      guard self.shouldEnqueueAnchoredBatch(
        hasCommittedAnchor: hasCommittedAnchor,
        addedCount: addedSamples.count,
        deletedCount: deletedCount
      ) else {
        completion()
        return
      }

      let enqueue: ([[String: Any]]) -> Void = { records in
        let batch = self.makeBatch(
          athleteId: athleteId,
          objectType: type.identifier,
          anchorKey: anchorKey,
          upserts: records,
          deletedIds: [],
          nextAnchor: encodedAnchor.base64EncodedString(),
          requiresAcknowledgement: true
        )
        do {
          try pendingStore.enqueue(batch)
        } catch {
          completion()
          return
        }
        completion()
      }

      guard let window = self.heartRateRefreshWindow(
        addedSamples: addedSamples,
        deletedCount: deletedCount,
        now: Date()
      ) else {
        // 首次空查询仍需让 Flutter 事务确认锚点，但不产生任何健康事实。
        enqueue([])
        return
      }
      self.fetchHeartRateWorkoutRefreshRecords(window: window) {
        records, refreshError in
        guard refreshError == nil else {
          // 不提交新锚点，下一次 observer 可从旧锚点安全重投。
          completion()
          return
        }
        enqueue(records)
      }
    }
    healthStore.execute(query)
  }

  private func fetchHeartRateWorkoutRefreshRecords(
    window: HeartRateRefreshWindow,
    completion: @escaping ([[String: Any]], Error?) -> Void
  ) {
    let predicate = HKQuery.predicateForSamples(
      withStart: window.start,
      end: window.end,
      options: []
    )
    let query = HKSampleQuery(
      sampleType: .workoutType(),
      predicate: predicate,
      limit: HKObjectQueryNoLimit,
      sortDescriptors: [
        NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true),
      ]
    ) { [weak self] _, samples, error in
      guard let self else { return }
      if let error {
        completion([], error)
        return
      }
      let workouts = (samples ?? []).compactMap { $0 as? HKWorkout }
      if workouts.isEmpty {
        completion([], nil)
        return
      }
      let lock = NSLock()
      let group = DispatchGroup()
      var records: [[String: Any]] = []
      var firstError: Error?
      for workout in workouts {
        group.enter()
        self.buildHeartRateWorkoutRefreshRecord(workout) { record, recordError in
          lock.lock()
          if let recordError {
            firstError = firstError ?? recordError
          } else if let record {
            records.append(record)
          }
          lock.unlock()
          group.leave()
        }
      }
      group.notify(queue: self.workerQueue) {
        records.sort {
          ($0["startTime"] as? Int64 ?? 0) < ($1["startTime"] as? Int64 ?? 0)
        }
        completion(records, firstError)
      }
    }
    healthStore.execute(query)
  }

  private func buildHeartRateWorkoutRefreshRecord(
    _ workout: HKWorkout,
    completion: @escaping ([String: Any]?, Error?) -> Void
  ) {
    guard let heartRateType = HKQuantityType.quantityType(
      forIdentifier: .heartRate
    ) else {
      completion(serializeSample(workout), nil)
      return
    }
    let query = HKSampleQuery(
      sampleType: heartRateType,
      predicate: HKQuery.predicateForObjects(from: workout),
      limit: HKObjectQueryNoLimit,
      sortDescriptors: [
        NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true),
      ]
    ) { [weak self] _, samples, error in
      guard let self else { return }
      if let error {
        completion(nil, error)
        return
      }
      let heartRateSamples = (samples ?? []).compactMap {
        $0 as? HKQuantitySample
      }
      completion(
        self.heartRateWorkoutRefreshRecord(
          workout: workout,
          samples: heartRateSamples
        ),
        nil
      )
    }
    healthStore.execute(query)
  }

  func heartRateRefreshWindow(
    addedSamples: [HKSample],
    deletedCount: Int,
    now: Date
  ) -> HeartRateRefreshWindow? {
    var start = addedSamples.map(\.startDate).min()?.addingTimeInterval(-1)
    var end = addedSamples.map(\.endDate).max()?.addingTimeInterval(1)
    let usesDeletionLookback = deletedCount > 0
    if usesDeletionLookback {
      // HKDeletedObject 不提供原样本时间。仅删除时无法定位所属训练，保守刷新
      // 最近七天；若同页也有新增，则与新增样本时间窗取并集。
      let recentStart = now.addingTimeInterval(-Self.heartRateDeletionLookback)
      start = min(start ?? recentStart, recentStart)
      end = max(end ?? now, now)
    }
    guard let rawStart = start, let rawEnd = end else { return nil }
    return HeartRateRefreshWindow(
      start: rawStart,
      end: rawEnd,
      usesConservativeDeletionLookback: usesDeletionLookback
    )
  }

  func heartRateWorkoutRefreshRecord(
    workout: HKWorkout,
    samples: [HKQuantitySample]
  ) -> [String: Any] {
    var record = serializeSample(workout)
    let summary = summarizeHeartRateForRefresh(
      samples: samples,
      workoutStart: workout.startDate,
      workoutEnd: workout.endDate
    )
    record["heartRateSampleCount"] = summary.rawSampleCount
    record["heartRateCoverage"] = summary.coverage
    if let average = summary.averageHeartRate {
      record["averageHeartRate"] = average
    }
    if let maximum = summary.maximumHeartRate {
      record["maximumHeartRate"] = maximum
    }
    return record
  }

  private func summarizeHeartRateForRefresh(
    samples: [HKQuantitySample],
    workoutStart: Date,
    workoutEnd: Date
  ) -> HeartRateRefreshSummary {
    let unit = HKUnit.count().unitDivided(by: .minute())
    let valid = samples.compactMap { sample -> (Date, Double)? in
      let bpm = sample.quantity.doubleValue(for: unit)
      guard
        bpm >= 30,
        bpm <= 240,
        sample.startDate >= workoutStart,
        sample.startDate <= workoutEnd
      else {
        return nil
      }
      return (sample.startDate, bpm)
    }.sorted { $0.0 < $1.0 }
    var supportedDuration = TimeInterval(0)
    if valid.count > 1 {
      for index in 1..<valid.count {
        let gap = valid[index].0.timeIntervalSince(valid[index - 1].0)
        if gap > 0, gap <= Self.maximumHeartRateSupportGap {
          supportedDuration += gap
        }
      }
    }
    let duration = max(0, workoutEnd.timeIntervalSince(workoutStart))
    let coverage = duration == 0
      ? 0
      : min(1, max(0, supportedDuration / duration))
    let average = valid.isEmpty
      ? nil
      : valid.reduce(0) { $0 + $1.1 } / Double(valid.count)
    let maximum = valid.map(\.1).max()
    return HeartRateRefreshSummary(
      rawSampleCount: samples.count,
      averageHeartRate: average,
      maximumHeartRate: maximum,
      coverage: coverage
    )
  }

  /// 首次查询即使没有样本也要提交初始锚点；已有锚点且没有变化时停止排队，
  /// 避免每次确认后继续生成无限空批次。
  func shouldEnqueueAnchoredBatch(
    hasCommittedAnchor: Bool,
    addedCount: Int,
    deletedCount: Int
  ) -> Bool {
    !hasCommittedAnchor || addedCount > 0 || deletedCount > 0
  }

  private func fetchForegroundRecords(
    stage: String,
    start: Date,
    end: Date,
    completion: @escaping ([[String: Any]], Error?) -> Void
  ) {
    let predicate = HKQuery.predicateForSamples(
      withStart: start,
      end: end,
      options: [.strictStartDate]
    )
    let lock = NSLock()
    var records: [[String: Any]] = []
    var firstError: Error?
    let group = DispatchGroup()

    if stage == "workout" || stage == "analysis" {
      group.enter()
      let workoutQuery = HKSampleQuery(
        sampleType: .workoutType(),
        predicate: predicate,
        limit: HKObjectQueryNoLimit,
        sortDescriptors: [
          NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true),
        ]
      ) { [weak self] _, samples, error in
        guard let self else {
          group.leave()
          return
        }
        if let error {
          lock.lock()
          firstError = firstError ?? error
          lock.unlock()
          group.leave()
          return
        }
        // 前台事实回填只跨通道传训练摘要。逐秒心率和 GPS 在后续按单次
        // 训练分析时即时读取，避免长周期回填一次性展开百万级采样点。
        let workouts = (samples ?? []).compactMap { $0 as? HKWorkout }
        let summaries = workouts.map(self.serializeSample)
        lock.lock()
        records.append(contentsOf: summaries)
        lock.unlock()
        group.leave()
      }
      healthStore.execute(workoutQuery)
    }

    for type in foregroundObservationTypes(stage: stage) {
      group.enter()
      let query = HKSampleQuery(
        sampleType: type,
        predicate: predicate,
        limit: HKObjectQueryNoLimit,
        sortDescriptors: nil
      ) { [weak self] _, samples, error in
        guard let self else {
          group.leave()
          return
        }
        if let error {
          lock.lock()
          firstError = firstError ?? error
          lock.unlock()
        } else {
          let values = (samples ?? []).map(self.serializeSample)
          lock.lock()
          records.append(contentsOf: values)
          lock.unlock()
        }
        group.leave()
      }
      healthStore.execute(query)
    }
    if stage == "analysis" {
      group.enter()
      fetchDailyStepRecords(start: start, end: end) { values, error in
        lock.lock()
        if let error {
          firstError = firstError ?? error
        } else {
          records.append(contentsOf: values)
        }
        lock.unlock()
        group.leave()
      }
    }
    group.notify(queue: workerQueue) {
      completion(records, firstError)
    }
  }

  /// 步数和活动圆环分别查询；任一查询失败时仍返回另一查询的可用字段。
  /// 查询错误代表该组字段当前不可用，不应被升级为整个同步失败。
  private func fetchDailyActivitySummaryRecords(
    start: Date,
    end: Date,
    completion: @escaping ([[String: Any]]) -> Void
  ) {
    let lock = NSLock()
    let group = DispatchGroup()
    var stepRecords: [[String: Any]] = []
    var activityRecords: [[String: Any]] = []

    group.enter()
    fetchDailyStepSummaryRecords(start: start, end: end) { records, _ in
      lock.lock()
      stepRecords = records
      lock.unlock()
      group.leave()
    }

    group.enter()
    fetchActivitySummaryRecords(start: start, end: end) { records, _ in
      lock.lock()
      activityRecords = records
      lock.unlock()
      group.leave()
    }

    group.notify(queue: workerQueue) { [weak self] in
      guard let self else {
        completion([])
        return
      }
      completion(self.mergeDailyActivitySummaryRecords(
        stepRecords: stepRecords,
        activityRecords: activityRecords,
        syncedAt: Date()
      ))
    }
  }

  private func fetchDailyStepSummaryRecords(
    start: Date,
    end: Date,
    completion: @escaping ([[String: Any]], Error?) -> Void
  ) {
    fetchDailyStepRecords(start: start, end: end) {
      [weak self] records, error in
      guard let self else {
        completion([], error)
        return
      }
      let summaries = records.compactMap { record -> [String: Any]? in
        guard
          let startMilliseconds = record["startTime"] as? NSNumber,
          let timeZoneName = record["timeZoneName"] as? String,
          let timeZone = TimeZone(identifier: timeZoneName),
          let offset = record["timeZoneOffsetMinutes"] as? Int,
          let value = record["value"] as? NSNumber
        else {
          return nil
        }
        let date = Date(
          timeIntervalSince1970: startMilliseconds.doubleValue / 1_000
        )
        return [
          "localDate": self.dailyActivityLocalDate(
            for: date,
            timeZone: timeZone
          ),
          "timeZoneName": timeZoneName,
          "timeZoneOffsetMinutes": offset,
          "steps": Int(value.doubleValue.rounded()),
          "availableFields": ["steps"],
        ]
      }
      completion(summaries, error)
    }
  }

  private func fetchActivitySummaryRecords(
    start: Date,
    end: Date,
    completion: @escaping ([[String: Any]], Error?) -> Void
  ) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let startComponents = calendar.dateComponents(
      [.era, .year, .month, .day],
      from: calendar.startOfDay(for: start)
    )
    let inclusiveEnd = end.addingTimeInterval(-0.001)
    let endComponents = calendar.dateComponents(
      [.era, .year, .month, .day],
      from: calendar.startOfDay(for: inclusiveEnd)
    )
    let predicate = HKQuery.predicate(
      forActivitySummariesBetweenStart: startComponents,
      end: endComponents
    )
    let query = HKActivitySummaryQuery(predicate: predicate) {
      [weak self] _, summaries, error in
      guard let self else {
        completion([], error)
        return
      }
      if let error {
        completion([], error)
        return
      }
      let activeEnergyUnit = self.dailyActivityUnit(
        for: "activeEnergyKcal"
      )
      let exerciseUnit = self.dailyActivityUnit(for: "exerciseMinutes")
      let standUnit = self.dailyActivityUnit(for: "standHours")
      let records = (summaries ?? []).compactMap {
        summary -> [String: Any]? in
        let dateComponents = summary.dateComponents(for: calendar)
        guard let day = calendar.date(from: dateComponents) else {
          return nil
        }
        let exerciseGoal: HKQuantity
        let standGoal: HKQuantity
        if #available(iOS 16.0, *) {
          exerciseGoal =
            summary.exerciseTimeGoal ?? summary.appleExerciseTimeGoal
          standGoal = summary.standHoursGoal ?? summary.appleStandHoursGoal
        } else {
          exerciseGoal = summary.appleExerciseTimeGoal
          standGoal = summary.appleStandHoursGoal
        }
        return [
          "localDate": self.dailyActivityLocalDate(
            for: day,
            timeZone: calendar.timeZone
          ),
          "timeZoneName": calendar.timeZone.identifier,
          "timeZoneOffsetMinutes":
            calendar.timeZone.secondsFromGMT(for: day) / 60,
          "activeEnergyKcal": summary.activeEnergyBurned.doubleValue(
            for: activeEnergyUnit
          ),
          "activeEnergyGoalKcal":
            summary.activeEnergyBurnedGoal.doubleValue(
              for: activeEnergyUnit
            ),
          "exerciseMinutes": Int(
            summary.appleExerciseTime.doubleValue(for: exerciseUnit).rounded()
          ),
          "exerciseGoalMinutes": Int(
            exerciseGoal.doubleValue(for: exerciseUnit).rounded()
          ),
          "standHours": Int(
            summary.appleStandHours.doubleValue(for: standUnit).rounded()
          ),
          "standGoalHours": Int(
            standGoal.doubleValue(for: standUnit).rounded()
          ),
          "availableFields": [
            "activeEnergyKcal",
            "activeEnergyGoalKcal",
            "exerciseMinutes",
            "exerciseGoalMinutes",
            "standHours",
            "standGoalHours",
          ],
        ]
      }
      completion(records, nil)
    }
    healthStore.execute(query)
  }

  /// 将两个独立查询按本地自然日和时区合并，并始终输出固定字段集合。
  /// 测试可直接调用此纯合并函数验证部分授权和缺失值语义。
  func mergeDailyActivitySummaryRecords(
    stepRecords: [[String: Any]],
    activityRecords: [[String: Any]],
    syncedAt: Date
  ) -> [[String: Any]] {
    let valueFields = [
      "steps",
      "activeEnergyKcal",
      "activeEnergyGoalKcal",
      "exerciseMinutes",
      "exerciseGoalMinutes",
      "standHours",
      "standGoalHours",
    ]
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let syncedAtString = formatter.string(from: syncedAt)
    var merged: [String: [String: Any]] = [:]

    for record in stepRecords + activityRecords {
      guard
        let localDate = record["localDate"] as? String,
        let timeZoneName = record["timeZoneName"] as? String,
        let offset = record["timeZoneOffsetMinutes"] as? Int
      else {
        continue
      }
      let key = "\(localDate)|\(timeZoneName)"
      var payload = merged[key] ?? [
        "localDate": localDate,
        "timeZoneName": timeZoneName,
        "timeZoneOffsetMinutes": offset,
        "steps": NSNull(),
        "activeEnergyKcal": NSNull(),
        "activeEnergyGoalKcal": NSNull(),
        "exerciseMinutes": NSNull(),
        "exerciseGoalMinutes": NSNull(),
        "standHours": NSNull(),
        "standGoalHours": NSNull(),
        "availableFields": [String](),
        "syncedAt": syncedAtString,
      ]
      for field in valueFields {
        if let value = record[field], !(value is NSNull) {
          payload[field] = value
        }
      }
      let existing = payload["availableFields"] as? [String] ?? []
      let incoming = record["availableFields"] as? [String] ?? []
      payload["availableFields"] = Array(Set(existing + incoming)).sorted()
      merged[key] = payload
    }

    return merged.values.sorted { left, right in
      let leftDate = left["localDate"] as? String ?? ""
      let rightDate = right["localDate"] as? String ?? ""
      if leftDate != rightDate {
        return leftDate < rightDate
      }
      let leftTimeZone = left["timeZoneName"] as? String ?? ""
      let rightTimeZone = right["timeZoneName"] as? String ?? ""
      return leftTimeZone < rightTimeZone
    }
  }

  /// 使用 HealthKit 按自然日累计统计，避免把 iPhone 与 Apple Watch
  /// 的重叠原始步数样本直接相加。
  private func fetchDailyStepRecords(
    start: Date,
    end: Date,
    completion: @escaping ([[String: Any]], Error?) -> Void
  ) {
    guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
    else {
      completion([], nil)
      return
    }
    let calendar = Calendar.current
    let anchor = calendar.startOfDay(for: start)
    let predicate = HKQuery.predicateForSamples(
      withStart: anchor,
      end: end,
      options: [.strictStartDate]
    )
    let query = HKStatisticsCollectionQuery(
      quantityType: stepType,
      quantitySamplePredicate: predicate,
      options: [.cumulativeSum],
      anchorDate: anchor,
      intervalComponents: DateComponents(day: 1)
    )
    query.initialResultsHandler = { _, collection, error in
      if let error {
        completion([], error)
        return
      }
      guard let collection else {
        completion([], nil)
        return
      }
      let formatter = DateFormatter()
      formatter.calendar = calendar
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = calendar.timeZone
      formatter.dateFormat = "yyyy-MM-dd"
      var records: [[String: Any]] = []
      collection.enumerateStatistics(from: anchor, to: end) {
        statistics, _ in
        guard
          let sum = statistics.sumQuantity(),
          sum.doubleValue(for: .count()) > 0
        else {
          return
        }
        let dayStart = calendar.startOfDay(for: statistics.startDate)
        let dayEnd = min(
          calendar.date(byAdding: .day, value: 1, to: dayStart) ?? end,
          end
        )
        let dayKey = formatter.string(from: dayStart)
        records.append([
          "uuid": "daily-step-\(dayKey)",
          "healthKitType": stepType.identifier,
          "kind": "observation",
          "startTime": Self.milliseconds(dayStart),
          "endTime": Self.milliseconds(dayEnd),
          "sourceBundleId": "com.apple.health.daily-aggregate",
          "sourceName": "Apple 健康日累计",
          "timeZoneName": calendar.timeZone.identifier,
          "timeZoneOffsetMinutes":
            calendar.timeZone.secondsFromGMT(for: dayStart) / 60,
          "value": sum.doubleValue(for: .count()),
          "unit": HKUnit.count().unitString,
        ])
      }
      completion(records, nil)
    }
    healthStore.execute(query)
  }

  private func buildWorkoutDetails(
    _ workout: HKWorkout,
    completion: @escaping ([String: Any]?, Error?) -> Void
  ) {
    let lock = NSLock()
    var heartRateSamples: [[String: Any]] = []
    var routes: [[String: Any]] = []
    var firstError: Error?
    let group = DispatchGroup()
    let predicate = HKQuery.predicateForObjects(from: workout)

    if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
      group.enter()
      let query = HKSampleQuery(
        sampleType: heartRateType,
        predicate: predicate,
        limit: HKObjectQueryNoLimit,
        sortDescriptors: [
          NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true),
        ]
      ) { [weak self] _, samples, error in
        guard let self else {
          group.leave()
          return
        }
        lock.lock()
        if let error {
          firstError = firstError ?? error
        } else {
          heartRateSamples = (samples ?? []).map(self.serializeSample)
        }
        lock.unlock()
        group.leave()
      }
      healthStore.execute(query)
    }

    let routeType = HKSeriesType.workoutRoute()
    group.enter()
    let routeSampleQuery = HKSampleQuery(
      sampleType: routeType,
      predicate: predicate,
      limit: HKObjectQueryNoLimit,
      sortDescriptors: nil
    ) { [weak self] _, samples, error in
      guard let self else {
        group.leave()
        return
      }
      if let error {
        lock.lock()
        firstError = firstError ?? error
        lock.unlock()
        group.leave()
        return
      }
      let routeGroup = DispatchGroup()
      for route in (samples ?? []).compactMap({ $0 as? HKWorkoutRoute }) {
        routeGroup.enter()
        self.readRoute(route) { value, routeError in
          lock.lock()
          if let routeError {
            firstError = firstError ?? routeError
          } else if let value {
            routes.append(value)
          }
          lock.unlock()
          routeGroup.leave()
        }
      }
      routeGroup.notify(queue: self.workerQueue) {
        group.leave()
      }
    }
    healthStore.execute(routeSampleQuery)

    group.notify(queue: workerQueue) { [weak self] in
      guard let self else { return }
      if let firstError {
        completion(nil, firstError)
        return
      }
      var details = self.serializeSample(workout)
      details["heartRateSamples"] = heartRateSamples
      details["routes"] = routes
      details["heartRateSampleCount"] = heartRateSamples.count
      details["routeCount"] = routes.count
      completion(details, nil)
    }
  }

  private func readRoute(
    _ route: HKWorkoutRoute,
    completion: @escaping ([String: Any]?, Error?) -> Void
  ) {
    let lock = NSLock()
    var locations: [[String: Any]] = []
    var didFinish = false
    let query = HKWorkoutRouteQuery(route: route) { _, chunk, done, error in
      lock.lock()
      if didFinish {
        lock.unlock()
        return
      }
      if let error {
        didFinish = true
        lock.unlock()
        completion(nil, error)
        return
      }
      if let chunk {
        let values = chunk.map(Self.serializeLocation)
        locations.append(contentsOf: values)
      }
      if done {
        didFinish = true
        let value: [String: Any] = [
          "kind": "workoutRoute",
          "uuid": route.uuid.uuidString,
          "startTime": Self.milliseconds(route.startDate),
          "endTime": Self.milliseconds(route.endDate),
          "locations": locations,
        ]
        lock.unlock()
        completion(value, nil)
        return
      }
      lock.unlock()
    }
    healthStore.execute(query)
  }

  func serializeSample(_ sample: HKSample) -> [String: Any] {
    let timeZone = sampleTimeZone(sample)
    var value: [String: Any] = [
      "uuid": sample.uuid.uuidString,
      "healthKitType": sample.sampleType.identifier,
      "startTime": Self.milliseconds(sample.startDate),
      "endTime": Self.milliseconds(sample.endDate),
      "sourceBundleId": sample.sourceRevision.source.bundleIdentifier,
      "sourceName": sample.sourceRevision.source.name,
      "timeZoneName": timeZone.identifier,
      "timeZoneOffsetMinutes": timeZone.secondsFromGMT(
        for: sample.startDate
      ) / 60,
    ]
    if let deviceModel = sample.device?.model {
      value["deviceModel"] = deviceModel
    }
    if let workout = sample as? HKWorkout {
      value.merge([
        "kind": "workout",
        "activityType": workout.workoutActivityType.rawValue,
        "discipline": workoutDiscipline(workout.workoutActivityType),
        "runContext": "unspecified",
        "durationSeconds": workout.duration,
        "timeZoneName": timeZone.identifier,
        "timeZoneOffsetMinutes": timeZone.secondsFromGMT(
          for: workout.startDate
        ) / 60,
      ]) { _, new in new }
      if let distance = workout.totalDistance {
        value["totalDistanceMeters"] = distance.doubleValue(for: .meter())
      }
      if let energy = workout.totalEnergyBurned {
        value["totalEnergyKilocalories"] = energy.doubleValue(for: .kilocalorie())
      }
    } else if let quantity = sample as? HKQuantitySample {
      let unit = preferredUnit(identifier: quantity.quantityType.identifier)
      value["kind"] = "observation"
      value["value"] = quantity.quantity.doubleValue(for: unit)
      value["unit"] = unit.unitString
    } else if let category = sample as? HKCategorySample {
      value["kind"] = "category"
      value["value"] = category.value
    } else if sample is HKWorkoutRoute {
      value["kind"] = "workoutRoute"
    } else {
      value["kind"] = "sample"
    }
    return value
  }

  private static func serializeLocation(_ location: CLLocation) -> [String: Any] {
    var value: [String: Any] = [
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "timestamp": milliseconds(location.timestamp),
    ]
    if location.horizontalAccuracy >= 0 {
      value["horizontalAccuracy"] = location.horizontalAccuracy
    }
    if location.verticalAccuracy >= 0 {
      value["verticalAccuracy"] = location.verticalAccuracy
      value["altitude"] = location.altitude
    }
    if location.speed >= 0 {
      value["speed"] = location.speed
    }
    if location.speedAccuracy >= 0 {
      value["speedAccuracy"] = location.speedAccuracy
    }
    return value
  }

  private func readTypes(stage: String) -> Set<HKObjectType>? {
    guard let observerTypes = observerTypes(stage: stage) else { return nil }
    var result = Set(observerTypes.map { $0 as HKObjectType })
    if stage == "analysis" {
      if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
        result.insert(steps)
      }
      result.insert(HKObjectType.activitySummaryType())
    }
    return result
  }

  private func sampleTypes(stage: String) -> [HKSampleType]? {
    switch stage {
    case "workout":
      return compactTypes([
        .workoutType(),
        HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
        HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
      ])
    case "analysis":
      return compactTypes([
        .workoutType(),
        HKSeriesType.workoutRoute(),
        HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
        HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
        HKQuantityType.quantityType(forIdentifier: .vo2Max),
      ])
    case "body":
      return compactTypes([
        HKQuantityType.quantityType(forIdentifier: .bodyMass),
        HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage),
      ])
    default:
      return nil
    }
  }

  /// analysis 阶段额外观察心率变化，但不会把心率作为离散事实同步。
  private func observerTypes(stage: String) -> [HKSampleType]? {
    guard var result = sampleTypes(stage: stage) else { return nil }
    if stage == "analysis",
       let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate),
       !result.contains(where: { $0.identifier == heartRate.identifier })
    {
      result.append(heartRate)
    }
    return result
  }

  func observerTypeIdentifiers(stage: String) -> [String] {
    observerTypes(stage: stage)?.map(\.identifier) ?? []
  }

  func readTypeIdentifiers(stage: String) -> [String] {
    readTypes(stage: stage)?.map(\.identifier).sorted() ?? []
  }

  func dailyActivityLocalDate(
    for date: Date,
    timeZone: TimeZone
  ) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }

  func dailyActivityUnitStrings() -> [String: String] {
    [
      "activeEnergyKcal": dailyActivityUnit(
        for: "activeEnergyKcal"
      ).unitString,
      "activeEnergyGoalKcal": dailyActivityUnit(
        for: "activeEnergyGoalKcal"
      ).unitString,
      "exerciseMinutes": dailyActivityUnit(
        for: "exerciseMinutes"
      ).unitString,
      "exerciseGoalMinutes": dailyActivityUnit(
        for: "exerciseGoalMinutes"
      ).unitString,
      "standHours": dailyActivityUnit(for: "standHours").unitString,
      "standGoalHours": dailyActivityUnit(for: "standGoalHours").unitString,
    ]
  }

  private func dailyActivityUnit(for field: String) -> HKUnit {
    switch field {
    case "activeEnergyKcal", "activeEnergyGoalKcal":
      return .kilocalorie()
    case "exerciseMinutes", "exerciseGoalMinutes":
      return .minute()
    case "standHours", "standGoalHours":
      return .count()
    default:
      return .count()
    }
  }

  private func isHeartRateType(_ type: HKSampleType) -> Bool {
    type.identifier == HKQuantityTypeIdentifier.heartRate.rawValue
  }

  private func foregroundObservationTypes(stage: String) -> [HKSampleType] {
    switch stage {
    case "analysis":
      return compactTypes([
        HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
        HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
        HKQuantityType.quantityType(forIdentifier: .vo2Max),
      ])
    case "body":
      return compactTypes([
        HKQuantityType.quantityType(forIdentifier: .bodyMass),
        HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage),
      ])
    default:
      return []
    }
  }

  private func compactTypes(_ values: [HKSampleType?]) -> [HKSampleType] {
    values.compactMap { $0 }
  }

  private func sampleType(identifier: String) -> HKSampleType? {
    let allStages = ["workout", "analysis", "body"]
    for stage in allStages {
      if let match = observerTypes(stage: stage)?.first(
        where: { $0.identifier == identifier }
      ) {
        return match
      }
    }
    return nil
  }

  private func preferredUnit(identifier: String) -> HKUnit {
    switch identifier {
    case HKQuantityTypeIdentifier.heartRate.rawValue,
         HKQuantityTypeIdentifier.restingHeartRate.rawValue:
      return .count().unitDivided(by: .minute())
    case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
      return .secondUnit(with: .milli)
    case HKQuantityTypeIdentifier.vo2Max.rawValue:
      return HKUnit(from: "ml/kg*min")
    case HKQuantityTypeIdentifier.bodyMass.rawValue:
      return .gramUnit(with: .kilo)
    case HKQuantityTypeIdentifier.bodyFatPercentage.rawValue:
      return .percent()
    case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
      return .kilocalorie()
    case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
      return .meter()
    case HKQuantityTypeIdentifier.stepCount.rawValue:
      return .count()
    default:
      return .count()
    }
  }

  private func workoutDiscipline(_ type: HKWorkoutActivityType) -> String {
    switch type {
    case .running:
      return "roadRun"
    case .traditionalStrengthTraining, .functionalStrengthTraining:
      return "strength"
    case .badminton:
      return "badminton"
    case .highIntensityIntervalTraining, .crossTraining:
      return "hyrox"
    default:
      return "other"
    }
  }

  private func sampleTimeZone(_ sample: HKSample) -> TimeZone {
    if let name = sample.metadata?[HKMetadataKeyTimeZone] as? String,
       let timeZone = TimeZone(identifier: name)
    {
      return timeZone
    }
    return .current
  }

  private func makeAnchorKey(athleteId: String, type: HKSampleType) -> String {
    "\(athleteId)|\(type.identifier)|\(Self.queryVersion)"
  }

  private func makeBatch(
    athleteId: String,
    objectType: String,
    anchorKey: String,
    upserts: [[String: Any]],
    deletedIds: [String],
    nextAnchor: String?,
    requiresAcknowledgement: Bool
  ) -> [String: Any] {
    var batch: [String: Any] = [
      "batchId": UUID().uuidString,
      "athleteId": athleteId,
      "objectType": objectType,
      "anchorKey": anchorKey,
      "queryVersion": Self.queryVersion,
      "upserts": upserts,
      "deletedExternalIds": deletedIds,
      "createdAt": ISO8601DateFormatter().string(from: Date()),
      "requiresAcknowledgement": requiresAcknowledgement,
    ]
    if let nextAnchor {
      batch["nextAnchor"] = nextAnchor
    }
    return batch
  }

  private func channelBatch(_ stored: [String: Any]) -> [String: Any] {
    var batch = stored
    batch.removeValue(forKey: "anchorKey")
    return batch
  }

  private func encodeAnchor(_ anchor: HKQueryAnchor) -> Data? {
    try? NSKeyedArchiver.archivedData(
      withRootObject: anchor,
      requiringSecureCoding: true
    )
  }

  private func decodeAnchor(_ data: Data) -> HKQueryAnchor? {
    try? NSKeyedUnarchiver.unarchivedObject(
      ofClass: HKQueryAnchor.self,
      from: data
    )
  }

  private static func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private static func flutterError(
    code: String,
    message: String,
    details: Any? = nil
  ) -> FlutterError {
    FlutterError(code: code, message: message, details: details)
  }
}
