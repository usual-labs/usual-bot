import Foundation

/// One saved item as the gateway lists it: metadata only. The list never carries a secret, and
/// this type has nowhere to put one.
public struct VaultItem: Identifiable, Equatable, Sendable, Decodable {
    public let id: String
    /// `login`, `payment` or `address`.
    public let kind: String
    public let label: String
    public let origin: String?
    /// When it was saved, as the gateway wrote it.
    public let createdAt: String?
    /// The email, phone or username of a login. Visible to the agent by design.
    public let identifier: String?
    public let identifierType: String?
    /// A saved authenticator key: the gateway makes 2FA codes itself.
    public let hasOtp: Bool?
    /// `local`, or the password manager the item lives in.
    public let backend: String

    public init(
        id: String, kind: String, label: String, origin: String? = nil, createdAt: String? = nil,
        identifier: String? = nil, identifierType: String? = nil, hasOtp: Bool? = nil, backend: String = "local"
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.origin = origin
        self.createdAt = createdAt
        self.identifier = identifier
        self.identifierType = identifierType
        self.hasOtp = hasOtp
        self.backend = backend
    }

    /// Only items in the Hermes vault can be removed; a manager's stay in the manager.
    public var isRemovable: Bool { backend == "local" }

    public var added: Date? { createdAt.flatMap(Routine.date) }
}

/// Where logins can come from: the Hermes vault or a password manager on the gateway's machine.
public struct VaultSource: Identifiable, Equatable, Sendable, Decodable {
    /// `local`, `bitwarden` or `onepassword`.
    public let name: String
    public let displayName: String
    public var enabled: Bool
    /// A password manager, which needs its master password.
    public let needsUnlock: Bool
    public let unlocked: Bool
    /// Its command-line tool is on the gateway's machine.
    public let installed: Bool

    public var id: String { name }

    public init(
        name: String, displayName: String, enabled: Bool, needsUnlock: Bool, unlocked: Bool, installed: Bool
    ) {
        self.name = name
        self.displayName = displayName
        self.enabled = enabled
        self.needsUnlock = needsUnlock
        self.unlocked = unlocked
        self.installed = installed
    }
}

/// A new item on its way to `vault.add`, in the field names the vault expects. Doesn't print its
/// values, so it can't end up in a log by accident.
public struct VaultDraft: Sendable, CustomStringConvertible {
    public enum Kind: String, CaseIterable, Sendable {
        case login, payment, address
    }

    public enum IdentifierType: String, CaseIterable, Sendable {
        case email, phone, username
    }

    public let kind: Kind
    public let label: String
    public let origin: String?
    let secret: [String: String]

    public var description: String { "VaultDraft(\(kind.rawValue))" }

    private init(kind: Kind, label: String, origin: String? = nil, secret: [String: String?]) {
        self.kind = kind
        self.label = label.trimmed
        self.origin = origin
        self.secret = secret.compactMapValues { $0?.nonBlank }
    }

    /// `origin` may be a bare host, which is taken as `https`.
    public static func login(
        label: String, origin: String, identifierType: IdentifierType, identifier: String, password: String,
        authenticatorKey: String = ""
    ) -> VaultDraft {
        let origin = origin.trimmed
        return VaultDraft(
            kind: .login, label: label, origin: origin.contains("://") || origin.isEmpty ? origin : "https://" + origin,
            secret: [
                "identifier_type": identifierType.rawValue, "identifier": identifier.trimmed, "password": password,
                "otp_secret": authenticatorKey.trimmed,
            ])
    }

    public static func payment(
        label: String, cardNumber: String, cardholder: String = "", expMonth: String, expYear: String, cvc: String,
        postalCode: String = ""
    ) -> VaultDraft {
        VaultDraft(
            kind: .payment, label: label,
            secret: [
                "card_number": cardNumber.filter { !$0.isWhitespace }, "cardholder_name": cardholder.trimmed,
                "exp_month": expMonth.trimmed, "exp_year": expYear.trimmed, "cvc": cvc.trimmed,
                "billing_postal_code": postalCode.trimmed,
            ])
    }

    public static func address(
        label: String, line1: String, line2: String = "", city: String, state: String = "", postalCode: String,
        country: String
    ) -> VaultDraft {
        VaultDraft(
            kind: .address, label: label,
            secret: [
                "address_line1": line1.trimmed, "address_line2": line2.trimmed, "city": city.trimmed,
                "state": state.trimmed, "postal_code": postalCode.trimmed, "country": country.trimmed,
            ])
    }

    /// Everything `vault.add` would otherwise refuse.
    public var isComplete: Bool {
        guard !label.isEmpty else { return false }
        switch kind {
        case .login:
            return hasOrigin && secret["identifier"] != nil && secret["password"] != nil
        case .payment:
            return ["card_number", "exp_month", "exp_year", "cvc"].allSatisfy { secret[$0] != nil }
        case .address:
            return ["address_line1", "city", "postal_code", "country"].allSatisfy { secret[$0] != nil }
        }
    }

    /// The vault binds a login to a site, so the site has to be a real web address.
    private var hasOrigin: Bool {
        guard let origin, let parts = URLComponents(string: origin), let host = parts.host, !host.isEmpty else {
            return false
        }
        return ["http", "https"].contains(parts.scheme?.lowercased() ?? "")
    }

    /// The values to keep out of any error text.
    var secretValues: [String] {
        secret.filter { $0.key != "identifier_type" }.map(\.value)
    }

    var params: [String: JSONValue] {
        var params: [String: JSONValue] = [
            "kind": .string(kind.rawValue), "label": .string(label),
            "secret": .object(secret.mapValues(JSONValue.string)),
        ]
        if let origin { params["origin"] = .string(origin) }
        return params
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
