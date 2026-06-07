import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var oidc: OIDCManager
    @EnvironmentObject var jobStore: JobStore
    @Environment(\.dismiss) var dismiss

    @State private var serverURL = ""
    @State private var isFetching = false
    @State private var configError: String?

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("URL") {
                    TextField("https://whisper.example.com", text: $serverURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .multilineTextAlignment(.trailing)
                }

                Button("Konfiguration laden") {
                    Task { await fetchConfig() }
                }
                .disabled(serverURL.isEmpty || isFetching)

                if isFetching { ProgressView() }
                if let err = configError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }

            Section("OIDC (wird automatisch geladen)") {
                LabeledContent("Issuer", value: settings.oidcIssuer.isEmpty ? "—" : settings.oidcIssuer)
                LabeledContent("Client ID", value: settings.oidcClientId.isEmpty ? "—" : settings.oidcClientId)
            }

            Section("Modell") {
                Picker("Standard-Modell", selection: $settings.defaultModel) {
                    ForEach(settings.availableModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
            }

            Section("Konto") {
                if oidc.isAuthenticated {
                    Button("Abmelden", role: .destructive) {
                        oidc.logout()
                    }
                }
            }
        }
        .navigationTitle("Einstellungen")
        .onAppear { serverURL = settings.serverURL }
    }

    private func fetchConfig() async {
        isFetching = true
        configError = nil
        defer { isFetching = false }

        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            configError = "Ungültige URL"
            return
        }

        settings.serverURL = url.absoluteString
        let client = APIClient(baseURL: url, oidc: oidc)

        do {
            let config = try await client.fetchConfig()
            settings.oidcIssuer   = config.oidc_issuer
            settings.oidcClientId = config.oidc_client_id
            settings.defaultModel = config.model_default
            settings.availableModels = config.models
            await oidc.configure(issuer: config.oidc_issuer, clientId: config.oidc_client_id)
            jobStore.configure(api: client)
        } catch {
            configError = error.localizedDescription
        }
    }
}
