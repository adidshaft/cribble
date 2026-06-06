import EventKit
import Foundation

/// Where a note's checkbox can be sent. Reminders is the natural home for a
/// to-do; Calendar adds it as an all-day event for today.
enum TaskExportTarget: String, CaseIterable, Identifiable {
    case reminders
    case calendar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .reminders: "Add to Reminders"
        case .calendar: "Add to Calendar"
        }
    }

    var systemImage: String {
        switch self {
        case .reminders: "checklist"
        case .calendar: "calendar.badge.plus"
        }
    }
}

enum TaskExporterError: LocalizedError {
    case accessDenied
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied: "Cribble doesn't have permission to access that app. Grant access in System Settings → Privacy."
        case .saveFailed(let detail): "Couldn't save the task: \(detail)"
        }
    }
}

/// Thin EventKit wrapper for exporting a note checkbox into Reminders or
/// Calendar. Nothing leaves the device — EventKit talks to the local stores
/// (their iCloud sync, if any, is the user's own setting).
enum TaskExporter {
    static func export(_ target: TaskExportTarget, title: String, notes: String?) async throws {
        let store = EKEventStore()
        switch target {
        case .reminders:
            guard (try? await store.requestFullAccessToReminders()) == true else {
                throw TaskExporterError.accessDenied
            }
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.notes = notes
            reminder.calendar = store.defaultCalendarForNewReminders()
            do {
                try store.save(reminder, commit: true)
            } catch {
                throw TaskExporterError.saveFailed(error.localizedDescription)
            }
        case .calendar:
            guard (try? await store.requestFullAccessToEvents()) == true else {
                throw TaskExporterError.accessDenied
            }
            let event = EKEvent(eventStore: store)
            event.title = title
            event.notes = notes
            event.isAllDay = true
            let startOfDay = Calendar.current.startOfDay(for: Date())
            event.startDate = startOfDay
            event.endDate = startOfDay
            event.calendar = store.defaultCalendarForNewEvents
            do {
                try store.save(event, span: .thisEvent, commit: true)
            } catch {
                throw TaskExporterError.saveFailed(error.localizedDescription)
            }
        }
    }
}
