import HermesKit
import SwiftUI

/// Adds a login, card or address to the agent's vault. What's typed lives only in this sheet, and
/// goes when it's saved or closed.
struct VaultAddSheet: View {
    /// Everything the form holds, cleared in one go.
    private struct Form {
        var label = ""
        var origin = ""
        var identifierType = VaultDraft.IdentifierType.email
        var identifier = ""
        var password = ""
        var authenticatorKey = ""
        var cardNumber = ""
        var cardholder = ""
        var expMonth = ""
        var expYear = ""
        var cvc = ""
        var line1 = ""
        var line2 = ""
        var city = ""
        var state = ""
        var postalCode = ""
        var country = ""
    }

    let list: VaultList

    @Environment(\.dismiss) private var dismiss
    @State private var kind: VaultDraft.Kind
    @State private var form = Form()
    @State private var allowsUnencrypted = false
    @State private var isSaving = false

    init(list: VaultList, kind: VaultDraft.Kind) {
        self.list = list
        _kind = State(initialValue: kind)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add to Vault")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Picker("Kind", selection: $kind) {
                    Text("Login").tag(VaultDraft.Kind.login)
                    Text("Card").tag(VaultDraft.Kind.payment)
                    Text("Address").tag(VaultDraft.Kind.address)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                VaultTextField(title: "Name", text: $form.label)
                switch kind {
                case .login: login
                case .payment: card
                case .address: address
                }
                if list.isUnencrypted { UnencryptedConsent(isAllowed: $allowsUnencrypted) }
                if let problem = list.problem {
                    Text(problem)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("Cancel") {
                        form = Form()
                        dismiss()
                    }
                    .buttonStyle(CardButtonStyle(primary: false))
                    Button("Save", action: save)
                        .buttonStyle(CardButtonStyle(primary: true))
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.4)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 340, idealWidth: 420, maxWidth: 480, minHeight: 420)
    }

    @ViewBuilder private var login: some View {
        VaultTextField(title: "Site, like https://example.com", text: $form.origin, isLiteral: true)
        Picker("Sign in with", selection: $form.identifierType) {
            Text("Email").tag(VaultDraft.IdentifierType.email)
            Text("Phone").tag(VaultDraft.IdentifierType.phone)
            Text("Username").tag(VaultDraft.IdentifierType.username)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        VaultTextField(title: "Email, phone or username", text: $form.identifier, isLiteral: true)
        VaultSecureField(title: "Password", text: $form.password)
        VaultSecureField(title: "Authenticator key (optional)", text: $form.authenticatorKey)
    }

    @ViewBuilder private var card: some View {
        VaultSecureField(title: "Card number", text: $form.cardNumber)
        VaultTextField(title: "Name on card (optional)", text: $form.cardholder)
        HStack(spacing: 8) {
            VaultTextField(title: "MM", text: $form.expMonth, isLiteral: true)
            VaultTextField(title: "YYYY", text: $form.expYear, isLiteral: true)
            VaultSecureField(title: "CVC", text: $form.cvc)
        }
        VaultTextField(title: "Billing postal code (optional)", text: $form.postalCode, isLiteral: true)
    }

    @ViewBuilder private var address: some View {
        VaultTextField(title: "Address", text: $form.line1)
        VaultTextField(title: "Address line 2 (optional)", text: $form.line2)
        VaultTextField(title: "City", text: $form.city)
        VaultTextField(title: "State or region (optional)", text: $form.state)
        VaultTextField(title: "Postal code", text: $form.postalCode, isLiteral: true)
        VaultTextField(title: "Country", text: $form.country)
    }

    private var draft: VaultDraft {
        switch kind {
        case .login:
            .login(
                label: form.label, origin: form.origin, identifierType: form.identifierType,
                identifier: form.identifier, password: form.password, authenticatorKey: form.authenticatorKey)
        case .payment:
            .payment(
                label: form.label, cardNumber: form.cardNumber, cardholder: form.cardholder, expMonth: form.expMonth,
                expYear: form.expYear, cvc: form.cvc, postalCode: form.postalCode)
        case .address:
            .address(
                label: form.label, line1: form.line1, line2: form.line2, city: form.city, state: form.state,
                postalCode: form.postalCode, country: form.country)
        }
    }

    private var canSave: Bool {
        draft.isComplete && !isSaving && (!list.isUnencrypted || allowsUnencrypted)
    }

    private func save() {
        isSaving = true
        Task {
            // A failure keeps the form to fix and try again, unless you cancel.
            if await list.add(draft, allowingUnencrypted: allowsUnencrypted) {
                form = Form()
                dismiss()
            }
            isSaving = false
        }
    }
}
