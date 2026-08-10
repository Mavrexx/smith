import AVFoundation
import Contacts
import CoreLocation
import EventKit
import Photos
import UIKit
import UserNotifications

struct SmithPermissionItem: Identifiable {
    let id: String
    let title: String
    let status: String
    let symbol: String

    var granted: Bool { status == "Allowed" || status == "Limited" }
}

@MainActor
final class SmithPermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var revision = UUID()
    @Published private(set) var requesting = false
    @Published var message = "iOS requires you to approve each category. Smith cannot approve permissions for other apps."

    private let locationManager = CLLocationManager()
    private let eventStore = EKEventStore()
    private let contactStore = CNContactStore()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    var items: [SmithPermissionItem] {
        [
            .init(id: "microphone", title: "Microphone", status: microphoneStatus, symbol: "mic.fill"),
            .init(id: "camera", title: "Camera", status: cameraStatus, symbol: "camera.fill"),
            .init(id: "photos", title: "Photos", status: photosStatus, symbol: "photo.fill"),
            .init(id: "contacts", title: "Contacts", status: contactsStatus, symbol: "person.crop.circle.fill"),
            .init(id: "calendar", title: "Calendar", status: calendarStatus, symbol: "calendar"),
            .init(id: "reminders", title: "Reminders", status: remindersStatus, symbol: "checklist"),
            .init(id: "location", title: "Location", status: locationStatus, symbol: "location.fill"),
            .init(id: "notifications", title: "Notifications", status: "Check Settings", symbol: "bell.fill"),
            .init(id: "files", title: "Files / Google Drive", status: "OAuth required", symbol: "folder.fill"),
        ]
    }

    func refresh() {
        revision = UUID()
    }

    func requestAllAvailable() async {
        guard !requesting else { return }
        requesting = true
        message = "Requesting available Smith permissions..."

        _ = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        _ = await AVCaptureDevice.requestAccess(for: .video)
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        _ = await withCheckedContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { granted, _ in continuation.resume(returning: granted) }
        }
        do {
            _ = try await eventStore.requestFullAccessToEvents()
            _ = try await eventStore.requestFullAccessToReminders()
        } catch {
            message = "Calendar or Reminders permission could not be requested: \(error.localizedDescription)"
        }
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            message = "Notification permission could not be requested: \(error.localizedDescription)"
        }
        locationManager.requestWhenInUseAuthorization()

        requesting = false
        message = "Permission requests complete. Denied permissions can only be changed in iOS Settings."
        refresh()
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refresh()
    }

    private var microphoneStatus: String {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: "Allowed"
        case .denied: "Denied"
        case .undetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private var cameraStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: "Allowed"
        case .denied, .restricted: "Denied"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private var photosStatus: String {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: "Allowed"
        case .limited: "Limited"
        case .denied, .restricted: "Denied"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private var contactsStatus: String {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: "Allowed"
        case .denied, .restricted: "Denied"
        case .notDetermined: "Not requested"
        case .limited: "Limited"
        @unknown default: "Unknown"
        }
    }

    private var calendarStatus: String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: "Allowed"
        case .writeOnly: "Write only"
        case .denied, .restricted: "Denied"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private var remindersStatus: String {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized: "Allowed"
        case .writeOnly: "Write only"
        case .denied, .restricted: "Denied"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private var locationStatus: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: "Allowed"
        case .denied, .restricted: "Denied"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }
}