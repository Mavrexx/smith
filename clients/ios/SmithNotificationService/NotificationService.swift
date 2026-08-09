import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var handler: ((UNNotificationContent) -> Void)?
    private var mutable: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        handler = contentHandler
        mutable = request.content.mutableCopy() as? UNMutableNotificationContent
        mutable?.title = mutable?.title.isEmpty == false ? mutable!.title : "Smith"
        mutable?.threadIdentifier = "smith"
        contentHandler(mutable ?? request.content)
    }

    override func serviceExtensionTimeWillExpire() {
        if let handler, let mutable { handler(mutable) }
    }
}
