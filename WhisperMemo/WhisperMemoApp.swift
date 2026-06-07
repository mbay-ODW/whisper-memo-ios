import SwiftUI

@main
struct WhisperMemoApp: App {
    @StateObject private var settings  = AppSettings()
    @StateObject private var oidc      = OIDCManager()
    @StateObject private var recorder  = AudioRecorder()
    @StateObject private var jobStore  = JobStore()

    // Queue und APIClient werden nach Settings-Init gebaut
    @StateObject private var queue: UploadQueue

    init() {
        let s = AppSettings()
        let o = OIDCManager()
        let url = URL(string: s.serverURL) ?? URL(string: "http://localhost:5050")!
        let client = APIClient(baseURL: url, oidc: o)
        _queue = StateObject(wrappedValue: UploadQueue(api: client))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(oidc)
                .environmentObject(recorder)
                .environmentObject(jobStore)
                .environmentObject(queue)
                .task {
                    // OIDC wiederherstellen wenn Issuer bekannt
                    if !settings.oidcIssuer.isEmpty {
                        await oidc.configure(
                            issuer: settings.oidcIssuer,
                            clientId: settings.oidcClientId
                        )
                    }
                    if !settings.serverURL.isEmpty,
                       let url = URL(string: settings.serverURL) {
                        jobStore.configure(api: APIClient(baseURL: url, oidc: oidc))
                    }
                }
                .onOpenURL { url in
                    // OIDC-Callback: whispermemo://oauth/callback?code=...
                    // wird automatisch von ASWebAuthenticationSession verarbeitet
                    _ = url
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
                    .navigationTitle("")
                    .navigationBarHidden(true)
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
