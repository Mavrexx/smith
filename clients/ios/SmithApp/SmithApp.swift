import CoreSpotlight
import SwiftUI

@main
struct SmithApp: App {
    @StateObject private var model = SmithModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onOpenURL { model.handle(url: $0) }
                .task { await indexShortcuts() }
        }
    }

    private func indexShortcuts() async {
        let items = SmithRoute.allCases.map { route in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = "Smith \(route.rawValue.capitalized)"
            attributes.contentDescription = "Open Smith \(route.rawValue) mode"
            attributes.relatedUniqueIdentifier = route.url.absoluteString
            return CSSearchableItem(
                uniqueIdentifier: "smith.\(route.rawValue)",
                domainIdentifier: "com.farhan.smith.routes",
                attributeSet: attributes
            )
        }
        try? await CSSearchableIndex.default().indexSearchableItems(items)
    }
}
