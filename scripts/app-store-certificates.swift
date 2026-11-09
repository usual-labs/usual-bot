// Lists the team's signing certificates, or deletes the development certificates made since a list
// was taken. On a fresh CI runner Xcode makes a new Apple Development certificate each time it signs,
// and Apple limits how many a team may have, so the TestFlight workflow removes them after each run.
// Anything else that appeared meanwhile, such as a distribution certificate, is left alone.
//
// Usage: swift scripts/app-store-certificates.swift list > before.txt
//        swift scripts/app-store-certificates.swift delete-new-development before.txt
//
// Signs in with the App Store Connect API key in APP_STORE_CONNECT_KEY_PATH (the .p8 file),
// APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_ISSUER_ID.

import CryptoKit
import Foundation

struct Certificate {
    let id: String
    let type: String
    let name: String
}

let certificatesURL = URL(string: "https://api.appstoreconnect.apple.com/v1/certificates")!
let developmentTypes: Set = ["DEVELOPMENT", "IOS_DEVELOPMENT", "MAC_APP_DEVELOPMENT"]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func environment(_ name: String) -> String {
    guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
        fail("Set \(name).")
    }
    return value
}

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// A short-lived token for the App Store Connect API, signed with the team's key.
func token() throws -> String {
    let pem = try String(
        contentsOfFile: environment("APP_STORE_CONNECT_KEY_PATH"), encoding: .utf8)
    let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
    let now = Int(Date().timeIntervalSince1970)
    func segment(_ object: [String: Any]) throws -> String {
        base64URL(try JSONSerialization.data(withJSONObject: object))
    }
    let header = ["alg": "ES256", "kid": environment("APP_STORE_CONNECT_KEY_ID"), "typ": "JWT"]
    let claims: [String: Any] = [
        "iss": environment("APP_STORE_CONNECT_ISSUER_ID"), "iat": now, "exp": now + 600,
        "aud": "appstoreconnect-v1",
    ]
    let unsigned = try segment(header) + "." + segment(claims)
    let signature = try key.signature(for: Data(unsigned.utf8))
    return unsigned + "." + base64URL(signature.rawRepresentation)
}

func send(_ request: URLRequest) async throws -> Data {
    var request = request
    request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
        fail("App Store Connect answered \(status): \(String(decoding: data, as: UTF8.self))")
    }
    return data
}

func certificates() async throws -> [Certificate] {
    struct Page: Decodable {
        struct Item: Decodable {
            struct Attributes: Decodable {
                let certificateType: String?
                let name: String?
            }
            let id: String
            let attributes: Attributes
        }
        struct Links: Decodable { let next: String? }
        let data: [Item]
        let links: Links?
    }
    var components = URLComponents(url: certificatesURL, resolvingAgainstBaseURL: false)!
    components.queryItems = [
        URLQueryItem(name: "limit", value: "200"),
        URLQueryItem(name: "fields[certificates]", value: "certificateType,name"),
    ]
    let page = try JSONDecoder().decode(
        Page.self, from: try await send(URLRequest(url: components.url!)))
    // A partial list would make certificates that were already there look new.
    guard page.links?.next == nil else {
        fail("The team has more than 200 certificates; this script reads only one page.")
    }
    return page.data.map {
        Certificate(
            id: $0.id, type: $0.attributes.certificateType ?? "UNKNOWN",
            name: $0.attributes.name ?? "unnamed")
    }
}

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "list":
    for certificate in try await certificates() {
        print("\(certificate.id) \(certificate.type) \(certificate.name)")
    }
case "delete-new-development":
    guard let path = arguments.dropFirst().first else {
        fail("Name the file that `list` wrote before the run.")
    }
    let before = Set(
        try String(contentsOfFile: path, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { $0.split(separator: " ").first.map(String.init) })
    let new = try await certificates().filter { !before.contains($0.id) }
    if new.isEmpty { print("No certificates were made during this run.") }
    for certificate in new {
        guard developmentTypes.contains(certificate.type) else {
            print("Left \(certificate.name) (\(certificate.type)): not a development certificate.")
            continue
        }
        var request = URLRequest(url: certificatesURL.appendingPathComponent(certificate.id))
        request.httpMethod = "DELETE"
        _ = try await send(request)
        print("Deleted \(certificate.name) (\(certificate.type)), which this run made.")
    }
default:
    fail("Usage: app-store-certificates.swift list | delete-new-development <file from list>")
}
