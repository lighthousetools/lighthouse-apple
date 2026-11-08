import LighthouseKit
import SwiftUI

/// Connects the app to a server.
public struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var address = ""
    @State private var email = ""
    @State private var password = ""
    @State private var deviceName = ""
    @State private var busy = false
    /// What the typed server needs, once it answered.
    @State private var status: AuthStatus?

    public init() {}

    private func field(_ content: some View) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Theme.body(15))
            .padding(10)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
    }

    public var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LogoMark(size: 30)
                Text("Lighthouse").font(Theme.display(26)).foregroundStyle(Theme.ink)
            }
            Text(tr("Connect to the server you run."))
                .font(Theme.body(14))
                .foregroundStyle(Theme.ink2)
                .padding(.bottom, 6)
            field(
                TextField(tr("Server address"), text: $address)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    #endif
            )
            if needsEmail {
                field(
                    TextField(tr("Email"), text: $email)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        #endif
                )
            }
            field(SecureField(tr("Password"), text: $password).textContentType(.password))
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Name of this device")).font(Theme.body(12)).foregroundStyle(Theme.ink3)
                field(TextField(tr("Name of this device"), text: $deviceName).autocorrectionDisabled())
            }
            ErrorBanner()
            Button(tr(busy ? "Signing in…" : "Sign in")) {
                Task {
                    busy = true
                    let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { model.deviceName = name }
                    await model.signIn(address: address, email: needsEmail ? email : "", password: password)
                    password = ""
                    busy = false
                }
            }
            .buttonStyle(LampButtonStyle())
            .disabled(busy || address.isEmpty || password.isEmpty || (needsEmail && email.isEmpty))
            signupNote
            Picker(tr("Language"), selection: $model.language) {
                ForEach(Language.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground()
        .onAppear {
            address = model.serverAddress
            deviceName = model.deviceName
            email = model.lastEmail
        }
        .task(id: address) {
            status = nil
            guard !address.isEmpty else { return }
            // Waits for the typing to pause before asking the server.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let answer = await model.status(of: address)
            if !Task.isCancelled { status = answer }
        }
    }

    /// Servers with several users need the email; a single-user server only the password.
    private var needsEmail: Bool { status?.emailRequired == true }

    /// Accounts are created in the web app, so the app only points there.
    @ViewBuilder private var signupNote: some View {
        switch status?.signup {
        case .open:
            if let url = try? Client.serverURL(from: address), let signup = URL(string: url.absoluteString + "/#/signup") {
                HStack(spacing: 4) {
                    Text(tr("New here?")).foregroundStyle(Theme.ink2)
                    Link(tr("Create an account in the web app"), destination: signup)
                        .foregroundStyle(Theme.lampInk)
                }
                .font(Theme.body(13))
            }
        case .invite:
            Text(tr("Invited? Open the link in your invitation to set up your account, then sign in here."))
                .font(Theme.body(13))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }
}
