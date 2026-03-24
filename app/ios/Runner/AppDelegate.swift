import Flutter
import UIKit
import SwiftUI

#if canImport(AlarmKit)
import AlarmKit
#endif

#if canImport(AppIntents)
import AppIntents
#endif

private let pendingRewardMlKey = "alarmkit_pending_reward_ml"
private let reminderIDsKey = "alarmkit_reminder_alarm_ids"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      AlarmKitBridge.shared.register(binaryMessenger: controller.binaryMessenger)
    }
    return didFinish
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

final class AlarmKitBridge {
  static let shared = AlarmKitBridge()

  private var channel: FlutterMethodChannel?

  private init() {}

  func register(binaryMessenger: FlutterBinaryMessenger) {
    guard channel == nil else {
      return
    }
    let channel = FlutterMethodChannel(name: "jinshi/alarmkit", binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler(handle(_:result:))
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "consumePendingRewardMl":
      let defaults = UserDefaults.standard
      let pendingRewardMl = defaults.double(forKey: pendingRewardMlKey)
      defaults.set(0, forKey: pendingRewardMlKey)
      result(pendingRewardMl)
    case "syncReminderAlarms":
      guard #available(iOS 26.0, *), let arguments = call.arguments as? [String: Any] else {
        result(
          FlutterError(
            code: "unsupported",
            message: "AlarmKit requires iOS 26 or newer.",
            details: nil
          )
        )
        return
      }
      let rawTasks = arguments["tasks"] as? [[String: Any]] ?? []
      Task {
        do {
          try await self.syncReminderAlarms(rawTasks)
          result(nil)
        } catch {
          result(
            FlutterError(
              code: "alarmkit_sync_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

#if canImport(AlarmKit) && canImport(AppIntents)
@available(iOS 26.0, *)
private struct JinshiReminderPayload: Codable {
  let index: Int
  let title: String
  let emoji: String
  let description: String
  let hour: Int
  let minute: Int
  let alertMode: String

  var reminderKey: String {
    String(index)
  }

  var displayTitle: String {
    let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedEmoji.isEmpty else {
      return title
    }
    return "\(trimmedEmoji) \(title)"
  }
}

@available(iOS 26.0, *)
private struct JinshiAlarmMetadata: AlarmMetadata, Codable, Hashable, Sendable {
  let reminderIndex: Int
  let title: String
  let emoji: String
  let detail: String
  let hour: Int
  let minute: Int
}

@available(iOS 26.0, *)
struct CompleteReminderIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Complete Reminder"
  static var description = IntentDescription("Close the alarm and award 10 ml.")
  static var openAppWhenRun = false

  @Parameter(title: "Alarm ID")
  var alarmID: String

  init(alarmID: String) {
    self.alarmID = alarmID
  }

  init() {
    self.alarmID = ""
  }

  func perform() async throws -> some IntentResult {
    let defaults = UserDefaults.standard
    let current = defaults.double(forKey: pendingRewardMlKey)
    defaults.set(current + 10, forKey: pendingRewardMlKey)
    if let id = UUID(uuidString: alarmID) {
      try? await AlarmManager.shared.stop(id: id)
    }
    return .result()
  }
}

@available(iOS 26.0, *)
struct MissReminderIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Miss Reminder"
  static var description = IntentDescription("Close the alarm without awarding ml.")
  static var openAppWhenRun = false

  @Parameter(title: "Alarm ID")
  var alarmID: String

  init(alarmID: String) {
    self.alarmID = alarmID
  }

  init() {
    self.alarmID = ""
  }

  func perform() async throws -> some IntentResult {
    if let id = UUID(uuidString: alarmID) {
      try? await AlarmManager.shared.stop(id: id)
    }
    return .result()
  }
}

@available(iOS 26.0, *)
extension AlarmKitBridge {
  fileprivate func syncReminderAlarms(_ rawTasks: [[String: Any]]) async throws {
    try await ensureAuthorization()

    let decoder = JSONDecoder()
    let defaults = UserDefaults.standard
    var reminderIDs = defaults.dictionary(forKey: reminderIDsKey) as? [String: String] ?? [:]
    var activeKeys = Set<String>()

    for task in rawTasks {
      let data = try JSONSerialization.data(withJSONObject: task)
      let payload = try decoder.decode(JinshiReminderPayload.self, from: data)
      activeKeys.insert(payload.reminderKey)

      let alarmID = UUID(uuidString: reminderIDs[payload.reminderKey] ?? "") ?? UUID()
      reminderIDs[payload.reminderKey] = alarmID.uuidString

      try? await AlarmManager.shared.stop(id: alarmID)

      let fireDate = nextOccurrence(for: payload)
      let schedule = Alarm.Schedule.fixed(fireDate)
      let stopButton = AlarmButton(
        text: LocalizedStringResource(stringLiteral: "完成"),
        textColor: Color.white,
        systemImageName: "checkmark.circle.fill"
      )
      let secondaryButton = AlarmButton(
        text: LocalizedStringResource(stringLiteral: "未完成"),
        textColor: Color.white,
        systemImageName: "xmark.circle.fill"
      )
      let alertPresentation = AlarmPresentation.Alert(
        title: LocalizedStringResource(stringLiteral: payload.displayTitle),
        stopButton: stopButton,
        secondaryButton: secondaryButton,
        secondaryButtonBehavior: .custom
      )
      let attributes = AlarmAttributes<JinshiAlarmMetadata>(
        presentation: AlarmPresentation(alert: alertPresentation),
        metadata: JinshiAlarmMetadata(
          reminderIndex: payload.index,
          title: payload.title,
          emoji: payload.emoji,
          detail: payload.description,
          hour: payload.hour,
          minute: payload.minute
        ),
        tintColor: Color.blue
      )
      let configuration = AlarmManager.AlarmConfiguration<JinshiAlarmMetadata>(
        countdownDuration: nil,
        schedule: schedule,
        attributes: attributes,
        stopIntent: CompleteReminderIntent(alarmID: alarmID.uuidString),
        secondaryIntent: MissReminderIntent(alarmID: alarmID.uuidString),
        sound: .default
      )
      try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
    }

    for (key, rawID) in reminderIDs where !activeKeys.contains(key) {
      if let alarmID = UUID(uuidString: rawID) {
        try? await AlarmManager.shared.stop(id: alarmID)
      }
      reminderIDs.removeValue(forKey: key)
    }

    defaults.set(reminderIDs, forKey: reminderIDsKey)
  }

  private func ensureAuthorization() async throws {
    switch AlarmManager.shared.authorizationState {
    case .authorized:
      return
    case .notDetermined:
      let result = try await AlarmManager.shared.requestAuthorization()
      guard result == .authorized else {
        throw NSError(
          domain: "JinshiAlarmKit",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "AlarmKit authorization was denied."]
        )
      }
    case .denied:
      throw NSError(
        domain: "JinshiAlarmKit",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "AlarmKit authorization was denied."]
      )
    @unknown default:
      return
    }
  }

  private func nextOccurrence(for payload: JinshiReminderPayload) -> Date {
    let calendar = Calendar.current
    let now = Date()
    let todayCandidate =
      calendar.date(
        bySettingHour: payload.hour,
        minute: payload.minute,
        second: 0,
        of: now
      ) ?? now
    if todayCandidate.timeIntervalSince(now) > 1 {
      return todayCandidate
    }
    return calendar.date(byAdding: .day, value: 1, to: todayCandidate) ?? todayCandidate
  }
}
#endif
