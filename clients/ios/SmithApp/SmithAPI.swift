import Foundation
import UIKit
import UniformTypeIdentifiers

actor SmithAPI {
    struct RegistrationResponse: Decodable {
        let deviceToken: String
        let sessionToken: String
        let expiresAt: Date
    }

    struct SessionResponse: Decodable {
        let sessionToken: String
        let expiresAt: Date
    }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let encoder = JSONEncoder()
    private var sessionToken: String?
    private var sessionExpiry: Date?

    var baseURL: URL {
        get throws {
            guard let value = UserDefaults.standard.string(forKey: "smith.serverURL"),
                  let url = URL(string: value),
                  url.scheme == "https" else {
                throw APIError.serverNotConfigured
            }
            return url
        }
    }

    func configure(serverURL: URL) throws {
        guard serverURL.scheme == "https", serverURL.host != nil else {
            throw APIError.secureServerRequired
        }
        UserDefaults.standard.set(serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forKey: "smith.serverURL")
    }

    func register(accessCode: String) async throws {
        let deviceID = try persistentDeviceID()
        let payload: [String: String] = [
            "deviceId": deviceID,
            "name": UIDevice.current.name,
            "platform": "iOS \(UIDevice.current.systemVersion)",
        ]
        var request = try request(path: "/api/auth/register", method: "POST")
        request.setValue("Bearer \(accessCode)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)
        let response: RegistrationResponse = try await send(request)
        try SmithKeychain.set(response.deviceToken, for: "device-token")
        sessionToken = response.sessionToken
        sessionExpiry = response.expiresAt
    }

    func session() async throws -> String {
        if let token = sessionToken,
           let expiry = sessionExpiry,
           expiry.timeIntervalSinceNow > 60 {
            return token
        }
        guard let deviceToken = SmithKeychain.get("device-token") else {
            throw APIError.deviceNotRegistered
        }
        var request = try request(path: "/api/auth/session", method: "POST")
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        let response: SessionResponse = try await send(request)
        sessionToken = response.sessionToken
        sessionExpiry = response.expiresAt
        return response.sessionToken
    }

    func webSocketURL() async throws -> URL {
        let token = try await session()
        var ticketRequest = try request(path: "/api/auth/ws-ticket", method: "POST")
        ticketRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let result: [String: String] = try await send(ticketRequest)
        guard let ticket = result["ticket"] else { throw APIError.invalidResponse }
        var components = URLComponents(url: try baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = "wss"
        components.path = "/ws/smith/realtime"
        components.queryItems = [
            URLQueryItem(name: "ticket", value: ticket),
            URLQueryItem(name: "voice", value: "Charon"),
            URLQueryItem(name: "sessionId", value: try persistentDeviceID()),
            URLQueryItem(name: "platform", value: "ios"),
        ]
        guard let url = components.url else { throw APIError.invalidResponse }
        return url
    }

    func post(path: String, json: [String: String]) async throws {
        let token = try await session()
        var request = try request(path: path, method: "POST")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(json)
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    func get<T: Decodable>(path: String, as type: T.Type = T.self) async throws -> T {
        let token = try await session()
        var request = try request(path: path, method: "GET")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    func sendJSON<T: Decodable>(path: String, method: String, json: [String: String]) async throws -> T {
        let token = try await session()
        var request = try request(path: path, method: method)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(json)
        return try await send(request)
    }

    func uploadFile(from url: URL) async throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw APIError.unsupportedFile
        }
        guard let size = values.fileSize, size <= 5 * 1024 * 1024 else {
            throw APIError.fileTooLarge
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let token = try await session()
        let boundary = "SmithBoundary-\(UUID().uuidString)"
        let safeName = url.lastPathComponent
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let mediaType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mediaType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = try request(path: "/api/smith/files", method: "POST")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 60
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    func revokeLocalDevice() {
        SmithKeychain.remove("device-token")
        sessionToken = nil
        sessionExpiry = nil
    }

    private func request(path: String, method: String) throws -> URLRequest {
        let url = try baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try decoder.decode(T.self, from: data)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { revokeLocalDevice() }
            throw APIError.http(http.statusCode)
        }
    }

    private func persistentDeviceID() throws -> String {
        if let value = SmithKeychain.get("device-id") { return value }
        let value = UUID().uuidString
        try SmithKeychain.set(value, for: "device-id")
        return value
    }

    enum APIError: LocalizedError {
        case serverNotConfigured
        case secureServerRequired
        case deviceNotRegistered
        case invalidResponse
        case http(Int)
        case fileTooLarge
        case unsupportedFile

        var errorDescription: String? {
            switch self {
            case .serverNotConfigured: "Enter the private HTTPS Smith address."
            case .secureServerRequired: "Smith requires a private HTTPS server address."
            case .deviceNotRegistered: "Register this device with the server access code."
            case .invalidResponse: "Smith returned an invalid response."
            case .http(let status): "Smith returned HTTP \(status)."
            case .fileTooLarge: "Smith files must be 5 MB or smaller."
            case .unsupportedFile: "Choose a regular text, PDF, JSON, CSV, JPEG, PNG or WebP file."
            }
        }
    }
}
