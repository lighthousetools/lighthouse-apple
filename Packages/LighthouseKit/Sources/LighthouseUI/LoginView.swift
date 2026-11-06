import LighthouseKit
import SwiftUI

/// Connects the app to a server.
public struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var address = ""
    @State private var password = ""
    @State private var busy = false

    public init() {}

    public var body: some View {
        Form {
            Section {
                TextField("Server address", text: $address, prompt: Text("lighthouse.example"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    #endif
                SecureField("Password", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Your Lighthouse server")
            } footer: {
                Text("The address of the server you run. Sign-in uses the password you set there.")
            }
            ErrorBanner()
            Button(busy ? "Signing in…" : "Sign in") {
                Task {
                    busy = true
                    await model.signIn(address: address, password: password)
                    password = ""
                    busy = false
                }
            }
            .disabled(busy || address.isEmpty || password.isEmpty)
        }
        .formStyle(.grouped)
        .onAppear { address = model.serverAddress }
    }
}
