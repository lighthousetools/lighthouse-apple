import LighthouseKit
import SwiftUI

/// Connects the app to a server.
public struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var address = ""
    @State private var password = ""
    @State private var busy = false

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LogoMark(size: 30)
                Text("Lighthouse").font(Theme.display(26)).foregroundStyle(Theme.ink)
            }
            Text("Connect to the server you run.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.ink2)
                .padding(.bottom, 6)
            field(
                TextField("Server address", text: $address)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    #endif
            )
            field(SecureField("Password", text: $password).textContentType(.password))
            ErrorBanner()
            Button(busy ? "Signing in…" : "Sign in") {
                Task {
                    busy = true
                    await model.signIn(address: address, password: password)
                    password = ""
                    busy = false
                }
            }
            .buttonStyle(LampButtonStyle())
            .disabled(busy || address.isEmpty || password.isEmpty)
        }
        .padding(24)
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground()
        .onAppear { address = model.serverAddress }
    }
}
