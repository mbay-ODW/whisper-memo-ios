import SwiftUI

@main
struct WhisperMemoApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var oidc     = OIDCManager()
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var jobStore = JobStore()
    @StateObject private var queue    = UploadQueue()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(oidc)
                .environmentObject(recorder)
                .environmentObject(jobStore)
                .environmentObject(queue)
                .task {
                    // OIDC-Konfiguration wiederherstellen
                    if !settings.oidcIssuer.isEmpty {
                        await oidc.configure(
                            issuer: settings.oidcIssuer,
                            clientId: settings.oidcClientId
                        )
                    }
                    // APIClient und JobStore konfigurieren
                    if let url = URL(string: settings.serverURL), !settings.serverURL.isEmpty {
                        let client = APIClient(baseURL: url, oidc: oidc)
                        jobStore.configure(api: client)
                        queue.configure(api: client)
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var oidc: OIDCManager
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        if settings.serverURL.isEmpty {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Einrichtung")
            }
        } else if !oidc.isAuthenticated {
            NavigationStack {
                LoginView()
            }
        } else {
            MainTabView()
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var jobStore: JobStore

    var body: some View {
        TabView {
            RecordView()
                .tabItem { Label("Aufnahme", systemImage: "mic.circle.fill") }

            JobListView()
                .tabItem { Label("Aufträge", systemImage: "list.bullet.clipboard") }

            NavigationStack { SettingsView() }
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
        .onAppear { jobStore.startPolling() }
    }
}
