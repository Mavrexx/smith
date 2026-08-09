import Social
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: SLComposeServiceViewController {
    override func isContentValid() -> Bool { true }

    override func didSelectPost() {
        Task {
            let shared = await extractSharedContent()
            var components = URLComponents(string: "smith://share")!
            components.queryItems = [
                URLQueryItem(name: "text", value: [contentText, shared].filter { !$0.isEmpty }.joined(separator: "\n"))
            ]
            if let url = components.url {
                extensionContext?.open(url) { [weak self] _ in
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
            } else {
                extensionContext?.cancelRequest(withError: ShareError.invalidContent)
            }
        }
    }

    override func configurationItems() -> [Any]! { [] }

    private func extractSharedContent() async -> String {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return "" }
        var parts: [String] = []
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let value = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                parts.append(value.absoluteString)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                parts.append(value)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                      let value = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                parts.append("Shared file: \(value.lastPathComponent)")
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                parts.append("Shared image ready for Smith")
            }
        }
        return parts.joined(separator: "\n")
    }

    enum ShareError: Error {
        case invalidContent
    }
}
