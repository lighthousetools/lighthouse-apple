import LighthouseKit
import SwiftUI

/// A colored status label.
struct StatusBadge: View {
    let status: String

    private var tint: Color {
        switch status {
        case "succeeded", "done", "allowed", "approved": .green
        case "running", "waiting", "pending": .orange
        case "failed", "rejected", "denied", "limit_exceeded", "expired": .red
        default: .secondary
        }
    }

    var body: some View {
        Text(status.replacing("_", with: " "))
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
    }
}

/// Shows an error of the app model above its content.
struct ErrorBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let message = model.lastError {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }
}

extension Double {
    var euros: String { formatted(.currency(code: "EUR")) }
}
