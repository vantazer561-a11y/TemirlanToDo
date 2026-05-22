import SwiftUI

struct AISettingsView: View {
    let service: AssistantService
    let onSaved: () -> Void

    @State private var apiKey = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 20)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(CyberpunkTheme.cyan)

            Text("Connect Fireworks")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Paste your Fireworks API key once. It stays in iOS Keychain on this device and is not stored in GitHub.")
                .font(.subheadline)
                .foregroundColor(CyberpunkTheme.softText)

            SecureField("sk-...", text: $apiKey)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(14)
                .glassPanel(accent: CyberpunkTheme.cyan)
                .foregroundColor(.white)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(CyberpunkTheme.magenta)
            }

            Button {
                save()
            } label: {
                Label("Save API Key", systemImage: "key.fill")
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(CyberpunkTheme.cyan)
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Link(destination: URL(string: "https://app.fireworks.ai/api-keys")!) {
                Label("Get API key", systemImage: "safari")
                    .foregroundColor(CyberpunkTheme.cyan)
            }

            Spacer()
        }
        .padding(20)
        .background(CyberpunkTheme.backgroundGradient.ignoresSafeArea())
    }

    private func save() {
        do {
            try service.saveAPIKey(apiKey)
            apiKey = ""
            errorMessage = nil
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
