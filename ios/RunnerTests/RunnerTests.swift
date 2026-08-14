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
