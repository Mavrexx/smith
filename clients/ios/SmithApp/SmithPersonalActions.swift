import EventKit
import Foundation
import SwiftUI
import UIKit
import UserNotifications

#if canImport(AlarmKit)
import AlarmKit
#endif

struct SmithActionResult {
    let success: Bool
    let message: String
    var data: [String: Any] = [:]
}

@MainActor
final class SmithPersonalActions {
    private let eventStore = EKEventStore()

    func addCalendarEvent(_ args: [String: Any]) async -> SmithActionResult {
        guard let title = nonempty(args["title"]), let start = date(args["start_ms"]) else {
            return .init(success: false, message: "I need an event title and an exact start date and time.")
        }
        do {
            guard try await requestEventAccess(), let calendar = eventStore.defaultCalendarForNewEvents else {
                return .init(success: false, message: "Calendar access is not allowed. Open Smith Permissions and allow Full Access to Calendar.")
            }
            let event = EKEvent(eventStore: eventStore)
            event.title = title
            event.startDate = start
            event.endDate = date(args["end_ms"]) ?? start.addingTimeInterval(3600)
            event.location = nonempty(args["location"])
            event.notes = nonempty(args["description"])
            event.isAllDay = bool(args["all_day"])
            event.calendar = calendar
            try eventStore.save(event, span: .thisEvent, commit: true)
            guard let identifier = event.eventIdentifier,
                  let saved = eventStore.event(withIdentifier: identifier), saved.title == title else {
                return .init(success: false, message: "Calendar accepted the write but Smith could not verify the saved event, so I will not claim it is done.")
            }
            openCalendar(at: saved.startDate)
            return .init(success: true,
                         message: "Saved and verified \(title) in Apple Calendar for \(format(saved.startDate)).",
                         data: ["event_id": identifier, "title": saved.title ?? title, "start_ms": saved.startDate.timeIntervalSince1970 * 1000])
        } catch {
            return .init(success: false, message: "Calendar could not save that event: \(error.localizedDescription)")
        }
    }

    func listCalendarEvents() async -> SmithActionResult {
        do {
            guard try await requestEventAccess() else { return .init(success: false, message: "Calendar access is not allowed.") }
            let start = Calendar.current.startOfDay(for: .now)
            let end = Calendar.current.date(byAdding: .day, value: 30, to: start)!
            let events = eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: nil))
            let items = events.prefix(12).map { ["event_id": $0.eventIdentifier ?? "", "title": $0.title ?? "Untitled", "start_ms": $0.startDate.timeIntervalSince1970 * 1000] as [String: Any] }
            let summary = events.isEmpty ? "There are no calendar events in the next 30 days." : "Found \(events.count) calendar event\(events.count == 1 ? "" : "s") in the next 30 days."
            return .init(success: true, message: summary, data: ["events": items])
        } catch {
            return .init(success: false, message: "Calendar could not be read: \(error.localizedDescription)")
        }
    }

    func addReminder(_ args: [String: Any]) async -> SmithActionResult {
        guard let title = nonempty(args["title"] ?? args["text"]) else {
            return .init(success: false, message: "I need the reminder text.")
        }
        do {
            guard try await requestReminderAccess(), let calendar = eventStore.defaultCalendarForNewReminders() else {
                return .init(success: false, message: "Reminders access is not allowed. Open Smith Permissions and allow Full Access to Reminders.")
            }
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = title
            reminder.notes = nonempty(args["description"])
            reminder.calendar = calendar
            if let due = date(args["due_ms"]) {
                reminder.dueDateComponents = Calendar.current.dateComponents(in: .current, from: due)
                reminder.addAlarm(EKAlarm(absoluteDate: due))
            }
            try eventStore.save(reminder, commit: true)
            let identifier = reminder.calendarItemIdentifier
            guard let saved = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder, saved.title == title else {
                return .init(success: false, message: "Reminders accepted the write but Smith could not verify it, so I will not claim it is done.")
            }
            openReminders()
            let dueText = saved.dueDateComponents?.date.map { " for \(format($0))" } ?? ""
            return .init(success: true, message: "Saved and verified the reminder \(title)\(dueText).",
                         data: ["reminder_id": identifier, "title": saved.title ?? title])
        } catch {
            return .init(success: false, message: "Reminders could not save that item: \(error.localizedDescription)")
        }
    }

    func listReminders() async -> SmithActionResult {
        do {
            guard try await requestReminderAccess() else { return .init(success: false, message: "Reminders access is not allowed.") }
            let reminders: [EKReminder] = await withCheckedContinuation { continuation in
                eventStore.fetchReminders(matching: eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) {
                    continuation.resume(returning: $0 ?? [])
                }
            }
            let items = reminders.prefix(12).map { ["reminder_id": $0.calendarItemIdentifier, "title": $0.title ?? "Untitled"] }
            let summary = reminders.isEmpty ? "There are no incomplete reminders." : "Found \(reminders.count) incomplete reminder\(reminders.count == 1 ? "" : "s")."
            return .init(success: true, message: summary, data: ["reminders": items])
        } catch {
            return .init(success: false, message: "Reminders could not be read: \(error.localizedDescription)")
        }
    }

    func setAlarm(_ args: [String: Any]) async -> SmithActionResult {
        guard let fireDate = date(args["alarm_ms"] ?? args["due_ms"]), fireDate > .now else {
            return .init(success: false, message: "I need an alarm time in the future.")
        }
        let title = nonempty(args["title"]) ?? "Smith Alarm"
#if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return await setAlarmKitAlarm(title: title, fireDate: fireDate) }
#endif
        return await setNotificationAlarm(title: title, fireDate: fireDate)
    }

    private func requestEventAccess() async throws -> Bool {
        if #available(iOS 17.0, *) { return try await eventStore.requestFullAccessToEvents() }
        return try await eventStore.requestAccess(to: .event)
    }

    private func requestReminderAccess() async throws -> Bool {
        if #available(iOS 17.0, *) { return try await eventStore.requestFullAccessToReminders() }
        return try await eventStore.requestAccess(to: .reminder)
    }

    private func setNotificationAlarm(title: String, fireDate: Date) async -> SmithActionResult {
        do {
            let center = UNUserNotificationCenter.current()
            let allowed = try await center.requestAuthorization(options: [.alert, .sound])
            guard allowed else { return .init(success: false, message: "Notifications are not allowed, so no alarm notification was scheduled.") }
            let identifier = "smith-alarm-\(UUID().uuidString)"
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = "Alarm set by Smith"
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            let verified = await center.pendingNotificationRequests().contains { $0.identifier == identifier }
            guard verified else { return .init(success: false, message: "The alarm notification was not present after saving, so I will not claim it is done.") }
            return .init(success: true, message: "Scheduled and verified a Smith notification for \(format(fireDate)). This iOS version cannot create a full system alarm.", data: ["alarm_id": identifier, "alarm_ms": fireDate.timeIntervalSince1970 * 1000, "kind": "notification"])
        } catch {
            return .init(success: false, message: "The alarm notification could not be scheduled: \(error.localizedDescription)")
        }
    }

    private func nonempty(_ value: Any?) -> String? {
        guard let value else { return nil }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    private func date(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue / 1000)
    }
    private func bool(_ value: Any?) -> Bool { (value as? NSNumber)?.boolValue ?? false }
    private func format(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) }
    private func openCalendar(at date: Date) {
        if let url = URL(string: "calshow:\(date.timeIntervalSinceReferenceDate)") { UIApplication.shared.open(url) }
    }
    private func openReminders() {
        if let url = URL(string: "x-apple-reminderkit://") { UIApplication.shared.open(url) }
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct SmithAlarmMetadata: AlarmMetadata {}

@available(iOS 26.0, *)
private extension SmithPersonalActions {
    func setAlarmKitAlarm(title: String, fireDate: Date) async -> SmithActionResult {
        do {
            let manager = AlarmManager.shared
            let authorization = try await manager.requestAuthorization()
            guard authorization == .authorized else {
                return .init(success: false, message: "Alarm access was denied, so no alarm was scheduled. Allow Smith under Settings > Apps > Smith > Alarms.")
            }
            let id = UUID()
            let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle.fill")
            let alert = AlarmPresentation.Alert(title: title, stopButton: stop)
            let attributes = AlarmAttributes<SmithAlarmMetadata>(presentation: AlarmPresentation(alert: alert), tintColor: .cyan)
            let configuration = AlarmManager.AlarmConfiguration<SmithAlarmMetadata>(schedule: .fixed(fireDate), attributes: attributes)
            let saved = try await manager.schedule(id: id, configuration: configuration)
            let verified = try manager.alarms.contains { $0.id == saved.id }
            guard verified else { return .init(success: false, message: "AlarmKit did not return the alarm during verification, so I will not claim it is done.") }
            return .init(success: true, message: "Set and verified \(title) for \(format(fireDate)). It will use the iOS system alarm even in silent or Focus mode.", data: ["alarm_id": id.uuidString, "alarm_ms": fireDate.timeIntervalSince1970 * 1000, "kind": "alarmkit"])
        } catch {
            return .init(success: false, message: "The system alarm could not be scheduled: \(error.localizedDescription)")
        }
    }
}
#endif
