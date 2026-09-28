import AVFoundation
import CoreImage
import Flutter
import HealthKit
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }

  override func tearDownWithError() throws {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
  }

  func testPendingBatchIsRemovedOnlyAfterAnchorIsCommitted() throws {
    let store = try HealthKitPendingBatchStore(
      rootDirectory: temporaryDirectory
    )
    let anchor = Data([0x01, 0x02, 0x03])
    let anchorKey = "athlete-a|HKWorkoutTypeIdentifier|1"
    try store.enqueue(makeBatch(
      batchId: "batch-a",
      athleteId: "athlete-a",
      anchorKey: anchorKey,
      nextAnchor: anchor.base64EncodedString()
    ))

    XCTAssertNil(store.committedAnchorData(anchorKey: anchorKey))
    XCTAssertEqual(try store.pending(limit: 20).count, 1)

    let metadata = try store.acknowledge(batchId: "batch-a")

    XCTAssertEqual(metadata.athleteId, "athlete-a")
    XCTAssertEqual(store.committedAnchorData(anchorKey: anchorKey), anchor)
    XCTAssertTrue(try store.pending(limit: 20).isEmpty)
  }

  func testInvalidAnchorDoesNotDeletePendingBatch() throws {
    let store = try HealthKitPendingBatchStore(
      rootDirectory: temporaryDirectory
    )
    try store.enqueue(makeBatch(
      batchId: "invalid-anchor",
      athleteId: "athlete-a",
      anchorKey: "athlete-a|HKWorkoutTypeIdentifier|1",
      nextAnchor: "%%%"
    ))

    XCTAssertThrowsError(
      try store.acknowledge(batchId: "invalid-anchor")
    )
    XCTAssertEqual(try store.pending(limit: 20).count, 1)
  }

  func testPendingPrioritizesWorkoutBeforeEarlierRoute() throws {
    let store = try HealthKitPendingBatchStore(
      rootDirectory: temporaryDirectory
    )
    try store.enqueue(makeBatch(
      batchId: "route-first",
      athleteId: "athlete-a",
      anchorKey: "athlete-a|HKSeriesTypeWorkoutRoute|1",
      nextAnchor: "",
      objectType: "HKSeriesTypeWorkoutRoute",
      createdAt: "2026-07-15T00:00:00Z"
    ))
    try store.enqueue(makeBatch(
      batchId: "workout-later",
      athleteId: "athlete-a",
      anchorKey: "athlete-a|HKWorkoutTypeIdentifier|1",
      nextAnchor: "",
      createdAt: "2026-07-15T00:01:00Z"
    ))

    let first = try XCTUnwrap(store.pending(limit: 1).first)

    XCTAssertEqual(first["batchId"] as? String, "workout-later")
  }

  func testClearOnlyRemovesSpecifiedAthleteQueueAndAnchors() throws {
    let store = try HealthKitPendingBatchStore(
      rootDirectory: temporaryDirectory
    )
    let anchorAKey = "athlete-a|HKWorkoutTypeIdentifier|1"
    let anchorBKey = "athlete-b|HKWorkoutTypeIdentifier|1"
    let anchorA = Data([0x0a])
    let anchorB = Data([0x0b])
    try store.enqueue(makeBatch(
      batchId: "anchor-a",
      athleteId: "athlete-a",
      anchorKey: anchorAKey,
      nextAnchor: anchorA.base64EncodedString()
    ))
    try store.enqueue(makeBatch(
      batchId: "anchor-b",
      athleteId: "athlete-b",
      anchorKey: anchorBKey,
      nextAnchor: anchorB.base64EncodedString()
    ))
    try store.acknowledge(batchId: "anchor-a")
    try store.acknowledge(batchId: "anchor-b")
    try store.enqueue(makeBatch(
      batchId: "pending-a",
      athleteId: "athlete-a",
      anchorKey: anchorAKey,
      nextAnchor: anchorA.base64EncodedString()
    ))
    try store.enqueue(makeBatch(
      batchId: "pending-b",
      athleteId: "athlete-b",
      anchorKey: anchorBKey,
      nextAnchor: anchorB.base64EncodedString()
    ))

    try store.clear(athleteId: "athlete-a")

    XCTAssertNil(store.committedAnchorData(anchorKey: anchorAKey))
    XCTAssertEqual(store.committedAnchorData(anchorKey: anchorBKey), anchorB)
    let pending = try store.pending(limit: 20)
    XCTAssertEqual(pending.count, 1)
    XCTAssertEqual(pending.first?["athleteId"] as? String, "athlete-b")
  }

  func testLocalHealthFileProtectionAppliesInsideSandbox() throws {
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    let databaseURL = temporaryDirectory.appendingPathComponent("trainflow.db")
    try Data([0x01]).write(to: databaseURL)
    let protector = LocalHealthFileProtector(
      sandboxRoot: temporaryDirectory
    )

    try protector.protect(paths: [temporaryDirectory.path, databaseURL.path])

    #if !targetEnvironment(simulator)
      let attributes = try FileManager.default.attributesOfItem(
        atPath: databaseURL.path
      )
      XCTAssertEqual(
        attributes[.protectionKey] as? FileProtectionType,
        FileProtectionType.completeUntilFirstUserAuthentication
      )
    #endif
    let values = try databaseURL.resourceValues(
      forKeys: [.isExcludedFromBackupKey]
    )
    XCTAssertEqual(values.isExcludedFromBackup, true)
    let directoryValues = try temporaryDirectory.resourceValues(
      forKeys: [.isExcludedFromBackupKey]
    )
    XCTAssertEqual(directoryValues.isExcludedFromBackup, true)
  }

  func testLocalHealthFileProtectionRejectsOutsideSandboxAndEmptyInput() throws {
    let outsideURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("outside-\(UUID().uuidString)")
    try Data([0x01]).write(to: outsideURL)
    defer { try? FileManager.default.removeItem(at: outsideURL) }
    let protector = LocalHealthFileProtector(
      sandboxRoot: temporaryDirectory
    )

    XCTAssertThrowsError(try protector.protect(paths: []))
    XCTAssertThrowsError(try protector.protect(paths: [outsideURL.path]))
  }

  func testObservationSerializationKeepsMetadataTimeZoneAndOffset() throws {
    let heartRateType = try XCTUnwrap(
      HKQuantityType.quantityType(forIdentifier: .heartRate)
    )
    let date = try XCTUnwrap(
      ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")
    )
    let sample = HKQuantitySample(
      type: heartRateType,
      quantity: HKQuantity(
        unit: .count().unitDivided(by: .minute()),
        doubleValue: 60
      ),
      start: date,
      end: date,
      metadata: [HKMetadataKeyTimeZone: "America/New_York"]
    )
    let coordinator = HealthKitSyncCoordinator(pendingStore: nil)

    let serialized = coordinator.serializeSample(sample)

    XCTAssertEqual(serialized["timeZoneName"] as? String, "America/New_York")
    XCTAssertEqual(serialized["timeZoneOffsetMinutes"] as? Int, -240)
  }

  func testAnchoredQueryOnlyQueuesEmptyBatchForInitialAnchor() {
    let coordinator = HealthKitSyncCoordinator(pendingStore: nil)

    XCTAssertTrue(coordinator.shouldEnqueueAnchoredBatch(
      hasCommittedAnchor: false,
      addedCount: 0,
      deletedCount: 0
    ))
    XCTAssertFalse(coordinator.shouldEnqueueAnchoredBatch(
      hasCommittedAnchor: true,
      addedCount: 0,
      deletedCount: 0
    ))
    XCTAssertTrue(coordinator.shouldEnqueueAnchoredBatch(
      hasCommittedAnchor: true,
      addedCount: 1,
      deletedCount: 0
    ))
    XCTAssertTrue(coordinator.shouldEnqueueAnchoredBatch(
      hasCommittedAnchor: true,
      addedCount: 0,
      deletedCount: 1
    ))
  }

  func testAnalysisObserverIncludesHeartRateWithoutChangingWorkoutStage() {
    let coordinator = HealthKitSyncCoordinator(pendingStore: nil)
    let heartRateIdentifier = HKQuantityTypeIdentifier.heartRate.rawValue

    XCTAssertTrue(
      coordinator.observerTypeIdentifiers(stage: "analysis")
        .contains(heartRateIdentifier)
    )
    XCTAssertFalse(
      coordinator.observerTypeIdentifiers(stage: "workout")
        .contains(heartRateIdentifier)
    )
  }

  func testAnalysisRequestsStepCountButDoesNotQueueRawStepObservers() {
    let coordinator = HealthKitSyncCoordinator(pendingStore: nil)
    let stepIdentifier = HKQuantityTypeIdentifier.stepCount.rawValue

    XCTAssertTrue(
      coordinator.readTypeIdentifiers(stage: "analysis")
        .contains(stepIdentifier)
    )
    XCTAssertFalse(
      coordinator.observerTypeIdentifiers(stage: "analysis")
        .contains(stepIdentifier)
    )
  }

  func testAnalysisRequestsActivitySummaryButDoesNotQueueAnchoredObserver() {
    let coordinator = HealthKitSyncCoordinator(pendingStore: nil)
    let summaryIdentifier = HKObjectType.activitySummaryType().identifier

    XCTAssertTrue(
      coordinator.readTypeIdentifiers(stage: "analysis")
        .contains(summaryIdentifier)
    )
    XCTAssertFalse(
      coordinator.observerTypeIdentifiers(stage: "analysis")
        .contains(summaryIdentifier)
    )
  }

  func testDailyActivityCalendarDateAndUnitsAreStable() throws {
    let coordinator = HealthKitSyncCoordinator(pendingStore: nil)
    let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
    let date = try XCTUnwrap(
      ISO8601DateFormatter().date(from: "2026-07-15T16:30:00Z")
    )

    XCTAssertEqual(
      coordinator.dailyActivityLocalDate(for: date, timeZone: timeZone),
      "2026-07-16"
    )
    XCTAssertEqual(
      coordinator.dailyActivityUnitStrings(),
      [
        "activeEnergyKcal": HKUnit.kilocalorie().unitString,
        "activeEnergyGoalKcal": HKUnit.kilocalorie().unitString,
        "exerciseMinutes": HKUnit.minute().unitString,
        "exerciseGoalMinutes": HKUnit.minute().unitString,
        "standHours": HKUnit.count().unitString,
        "standGoalHours": HKUnit.count().unitString,
      ]
    )
  }

  func testDailyActivityMergeKeepsUnavailableFieldsNullAndKeysFixed() throws {
    let coordinator = HealthKitSyncCoordinator(pendingStore: nil)
    let syncedAt = try XCTUnwrap(
      ISO8601DateFormatter().date(from: "2026-07-16T00:00:00Z")
    )

    let values = coordinator.mergeDailyActivitySummaryRecords(
      stepRecords: [[
        "localDate": "2026-07-15",
        "timeZoneName": "Asia/Shanghai",
        "timeZoneOffsetMinutes": 480,
        "steps": 8123,
        "availableFields": ["steps"],
      ]],
      activityRecords: [],
      syncedAt: syncedAt
    )

    let payload = try XCTUnwrap(values.first)
    XCTAssertEqual(values.count, 1)
    XCTAssertEqual(
      Set(payload.keys),
      Set([
        "localDate",
        "timeZoneName",
        "timeZoneOffsetMinutes",
        "steps",
        "activeEnergyKcal",
        "activeEnergyGoalKcal",
        "exerciseMinutes",
        "exerciseGoalMinutes",
        "standHours",
        "standGoalHours",
        "availableFields",
        "syncedAt",
      ])
    )
    XCTAssertEqual(payload["steps"] as? Int, 8123)
    XCTAssertTrue(payload["activeEnergyKcal"] is NSNull)
    XCTAssertTrue(payload["exerciseMinutes"] is NSNull)
    XCTAssertTrue(payload["standHours"] is NSNull)
    XCTAssertEqual(payload["availableFields"] as? [String], ["steps"])
    XCTAssertNil(payload["stepGoal"])
  }

  func testHeartRateAddedSamplesUseTheirTimeRangeForWorkoutRefresh() throws {
    let coordinator = HealthKitSyncCoordinator(pendingStore: nil)
    let type = try XCTUnwrap(
      HKQuantityType.quantityType(forIdentifier: .heartRate)
    )
    let start = try XCTUnwrap(
      ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")
    )
    let first = HKQuantitySample(
      type: type,
      quantity: HKQuantity(
        unit: .count().unitDivided(by: .minute()),
        doubleValue: 120
      ),
      start: start,
      end: start
    )
    let secondDate = start.addingTimeInterval(30)
    let second = HKQuantitySample(
      type: type,
      quantity: HKQuantity(
        unit: .count().unitDivided(by: .minute()),
        doubleValue: 130
      ),
      start: secondDate,
      end: secondDate
    )

    let window = try XCTUnwrap(coordinator.heartRateRefreshWindow(
      addedSamples: [second, first],
      deletedCount: 0,
      now: start.addingTimeInterval(3_600)
    ))

    XCTAssertEqual(window.start, start.addingTimeInterval(-1))
    XCTAssertEqual(window.end, secondDate.addingTimeInterval(1))
    XCTAssertFalse(window.usesConservativeDeletionLookback)
  }

  func testHeartRateDeletionUsesSevenDayConservativeWorkoutRefresh() throws {
    let coordinator = HealthKitSyncCoordinator(pendingStore: nil)
    let now = try XCTUnwrap(
      ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")
    )

    let window = try XCTUnwrap(coordinator.heartRateRefreshWindow(
      addedSamples: [],
      deletedCount: 1,
      now: now
    ))

    XCTAssertEqual(window.start, now.addingTimeInterval(-7 * 24 * 60 * 60))
    XCTAssertEqual(window.end, now)
    XCTAssertTrue(window.usesConservativeDeletionLookback)
  }

  func testHeartRateWorkoutRefreshContainsSummaryWithoutRawSamples() throws {
    let coordinator = HealthKitSyncCoordinator(pendingStore: nil)
    let type = try XCTUnwrap(
      HKQuantityType.quantityType(forIdentifier: .heartRate)
    )
    let start = try XCTUnwrap(
      ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")
    )
    let workout = HKWorkout(
      activityType: .running,
      start: start,
      end: start.addingTimeInterval(60),
      duration: 60,
      totalEnergyBurned: nil,
      totalDistance: nil,
      metadata: nil
    )
    let samples = [0.0, 10.0, 20.0].enumerated().map { index, offset in
      HKQuantitySample(
        type: type,
        quantity: HKQuantity(
          unit: .count().unitDivided(by: .minute()),
          doubleValue: 120 + Double(index * 10)
        ),
        start: start.addingTimeInterval(offset),
        end: start.addingTimeInterval(offset)
      )
    }

    let record = coordinator.heartRateWorkoutRefreshRecord(
      workout: workout,
      samples: samples
    )

    XCTAssertEqual(record["kind"] as? String, "workout")
    XCTAssertEqual(record["heartRateSampleCount"] as? Int, 3)
    XCTAssertEqual(record["averageHeartRate"] as? Double, 130)
    XCTAssertEqual(record["maximumHeartRate"] as? Double, 140)
    XCTAssertEqual(record["heartRateCoverage"] as? Double, 1.0 / 3.0)
    XCTAssertNil(record["heartRateSamples"])
    XCTAssertNil(record["routes"])
  }

  func testBackgroundSyncFailsWhenProtectedQueueCannotOpen() {
    let coordinator = HealthKitSyncCoordinator(pendingStore: nil)
    var returnedError: FlutterError?

    coordinator.enableBackgroundSync(
      arguments: [
        "stage": "workout",
        "athleteId": "athlete-a",
      ],
      result: { value in
        returnedError = value as? FlutterError
      }
    )

    XCTAssertEqual(returnedError?.code, "healthkit_queue_unavailable")
    XCTAssertEqual(
      returnedError?.message,
      "本地健康数据队列不可用，未启用后台同步。"
    )
  }

  func testPauseAndResumeKeepPendingBatchAnchorAndRestartConfiguration() throws {
    let store = try HealthKitPendingBatchStore(rootDirectory: temporaryDirectory)
    let defaultsName = "RunnerTests.HealthKitPause.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let configurationKey = "trainmate.healthkit.background.configuration.v1"
    defaults.set(
      ["athleteId": "athlete-a", "stages": []],
      forKey: configurationKey
    )
    let anchorKey = "athlete-a|HKWorkoutTypeIdentifier|1"
    let anchor = Data([0x0a, 0x0b])
    try store.enqueue(makeBatch(
      batchId: "committed-before-pause",
      athleteId: "athlete-a",
      anchorKey: anchorKey,
      nextAnchor: anchor.base64EncodedString()
    ))
    try store.acknowledge(batchId: "committed-before-pause")
    try store.enqueue(makeBatch(
      batchId: "pending-during-pause",
      athleteId: "athlete-a",
      anchorKey: anchorKey,
      nextAnchor: anchor.base64EncodedString()
    ))
    let coordinator = HealthKitSyncCoordinator(
      pendingStore: store,
      defaults: defaults
    )
    var pauseResult: Any?

    coordinator.pauseBackgroundSync(
      arguments: ["athleteId": "athlete-a"],
      result: { pauseResult = $0 }
    )

    XCTAssertNil(pauseResult)
    XCTAssertTrue(coordinator.isBackgroundSyncPaused(athleteId: "athlete-a"))
    XCTAssertEqual(
      defaults.dictionary(forKey: configurationKey)?["athleteId"] as? String,
      "athlete-a"
    )
    XCTAssertEqual(try store.pending(limit: 20).count, 1)
    XCTAssertEqual(store.committedAnchorData(anchorKey: anchorKey), anchor)

    var pausedAckResult: Any?
    coordinator.acknowledgePendingBatch(
      arguments: ["batchId": "pending-during-pause"],
      result: { pausedAckResult = $0 }
    )
    XCTAssertNil(pausedAckResult)
    XCTAssertEqual(try store.pending(limit: 20).count, 1)
    XCTAssertEqual(store.committedAnchorData(anchorKey: anchorKey), anchor)

    let restarted = HealthKitSyncCoordinator(
      pendingStore: store,
      defaults: defaults
    )
    XCTAssertFalse(restarted.shouldRestoreObservers(athleteId: "athlete-a"))

    var resumeResult: Any?
    restarted.resumeBackgroundSync(
      arguments: ["athleteId": "athlete-a"],
      result: { resumeResult = $0 }
    )

    XCTAssertNil(resumeResult)
    XCTAssertTrue(restarted.shouldRestoreObservers(athleteId: "athlete-a"))
    XCTAssertEqual(
      defaults.dictionary(forKey: configurationKey)?["athleteId"] as? String,
      "athlete-a"
    )
    XCTAssertEqual(try store.pending(limit: 20).count, 1)
    XCTAssertEqual(store.committedAnchorData(anchorKey: anchorKey), anchor)
  }

  private func makeBatch(
    batchId: String,
    athleteId: String,
    anchorKey: String,
    nextAnchor: String,
    objectType: String = "HKWorkoutTypeIdentifier",
    createdAt: String = "2026-07-15T00:00:00Z"
  ) -> [String: Any] {
    [
      "batchId": batchId,
      "athleteId": athleteId,
      "objectType": objectType,
      "anchorKey": anchorKey,
      "queryVersion": 1,
      "upserts": [],
      "deletedExternalIds": [],
      "nextAnchor": nextAnchor,
      "createdAt": createdAt,
      "requiresAcknowledgement": true,
    ]
  }
}

/// 合成视频只验证解码、坐标和拒绝路径，不能代替真人跑姿精度验收。
final class RunningVideoTests: XCTestCase {
  func testCleanupDeletesOnlyCancelledTaskDirectory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let id = UUID().uuidString
    let directory = root.appendingPathComponent(id, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("original.mov")
    try Data([1, 2]).write(to: source)
    try Data([1, 2]).write(to: directory.appendingPathComponent("source.mov"))
    let task = RunningVideoTask(id: id, directory: directory)
    XCTAssertThrowsError(try task.cleanupFiles())
    task.cancel()
    try task.cleanupFiles(); try task.cleanupFiles()
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    XCTAssertEqual(try Data(contentsOf: source), Data([1, 2]))
  }

  func testCleanupRejectsMismatchedDirectory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let task = RunningVideoTask(id: UUID().uuidString, directory: root)
    task.cancel()
    XCTAssertThrowsError(try task.cleanupFiles())
    XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
  }

  func testCancellationRemainsInvalidAfterRepeatedCancel() throws {
    let task = RunningVideoTask(id: UUID().uuidString, directory: FileManager.default.temporaryDirectory)
    XCTAssertNoThrow(try task.check())
    task.cancel(); task.cancel()
    XCTAssertThrowsError(try task.check())
  }

  func testOrientationNormalizesRotationAndMirrorOrigin() {
    let image = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
    let rotated = RunningVideoPoseCoordinator.orientedImage(image, transform: CGAffineTransform(rotationAngle: .pi / 2))
    XCTAssertEqual(rotated.extent.minX, 0, accuracy: 0.001)
    XCTAssertEqual(rotated.extent.minY, 0, accuracy: 0.001)
    XCTAssertEqual(rotated.extent.width, 480, accuracy: 0.001)
    XCTAssertEqual(rotated.extent.height, 640, accuracy: 0.001)
    let mirrored = RunningVideoPoseCoordinator.orientedImage(image, transform: CGAffineTransform(scaleX: -1, y: 1))
    XCTAssertEqual(mirrored.extent, image.extent)
  }

  func testBlackVideoKeepsTimestampsAndDoesNotInventPerson() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("black.mov")
    try makeBlackVideo(url: url)
    let task = RunningVideoTask(id: UUID().uuidString, directory: directory)
    var frames: [[String: Any]] = []
    let result = try RunningVideoPoseCoordinator().extract(task: task, url: url, onFrame: { frames.append($0) })
    XCTAssertEqual(result["frameCount"] as? Int, 72)
    XCTAssertEqual(frames.count, 72)
    XCTAssertTrue(frames.allSatisfy { ($0["status"] as? String) == "missing" })
    for index in 1..<frames.count {
      let time = frames[index]["seconds"] as! Double
      let before = frames[index-1]["seconds"] as! Double
      XCTAssertEqual(time-before, 1.0/12.0, accuracy: 0.001)
    }
  }

  func testCancellationStopsDecodingBeforeNextFrame() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("black.mov")
    try makeBlackVideo(url: url)
    let task = RunningVideoTask(id: UUID().uuidString, directory: directory)
    var count = 0
    XCTAssertThrowsError(try RunningVideoPoseCoordinator().extract(task: task, url: url, onFrame: { _ in count += 1; task.cancel() }))
    XCTAssertEqual(count, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
  }

  func testDecoderPreservesTimestampsWithoutDependingOnVisionAvailability() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("black.mov")
    try makeBlackVideo(url: url)
    let task = RunningVideoTask(id: UUID().uuidString, directory: directory)
    var times: [Double] = []
    let result = try RunningVideoPoseCoordinator().extract(task: task, url: url,
      onFrame: { times.append($0["seconds"] as! Double) }, detector: { _ in [] })
    XCTAssertEqual(result["frameCount"] as? Int, 72)
    XCTAssertEqual(times.count, 72)
    XCTAssertEqual(times.last!, 71.0/12.0, accuracy: 0.001)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
  }

  func testDecoderCancellationStopsWithoutDependingOnVisionAvailability() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("black.mov")
    try makeBlackVideo(url: url)
    let task = RunningVideoTask(id: UUID().uuidString, directory: directory)
    var count = 0
    XCTAssertThrowsError(try RunningVideoPoseCoordinator().extract(task: task, url: url,
      onFrame: { _ in count += 1; task.cancel() }, detector: { _ in [] }))
    XCTAssertEqual(count, 1)
  }

  private func makeBlackVideo(url: URL) throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240
    ])
    writer.add(input)
    XCTAssertTrue(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    for index in 0..<72 {
      let deadline = Date().addingTimeInterval(5)
      while !input.isReadyForMoreMediaData && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
      guard input.isReadyForMoreMediaData else { throw RunningVideoError.message("合成视频编码超时") }
      var buffer: CVPixelBuffer?
      guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
        throw RunningVideoError.message("无法创建合成视频画面")
      }
      CVPixelBufferLockBaseAddress(buffer, [])
      memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
      CVPixelBufferUnlockBaseAddress(buffer, [])
      XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 12)))
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    XCTAssertEqual(done.wait(timeout: .now()+10), .success)
    XCTAssertEqual(writer.status, .completed)
  }
}
