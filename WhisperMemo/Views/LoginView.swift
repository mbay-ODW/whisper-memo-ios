import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var oidc: OIDCManager
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.indigo)
                    Text("Whisper Memo")
                        .font(.largeTitle.bold())
                    Text("Baustellendiktate schnell transkribieren")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 16) {
                    if let err = oidc.error {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    AuthButton()

                    NavigationLink("Serveradresse einrichten", destination: SettingsView())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .overlay {
            if oidc.isLoading {
                ProgressView("Anmelden…")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

struct AuthButton: View {
    @EnvironmentObject var oidc: OIDCManager

    var body: some View {
        Button {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first else { return }
            Task { await oidc.login(from: window) }
        } label: {
            Label("Mit Authelia anmelden", systemImage: "person.badge.key.fill")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.indigo)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .font(.body.weight(.semibold))
        }
        .disabled(oidc.isLoading)
    }
}
