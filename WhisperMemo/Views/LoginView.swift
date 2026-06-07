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
                    }

                    SignInButton()
                        .frame(height: 56)
                        .cornerRadius(14)

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

private struct SignInButton: UIViewRepresentable {
    @EnvironmentObject var oidc: OIDCManager

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        // We repurpose the Apple button style for a "Weiter mit Authelia" button.
        // In production you'd use a custom UIButton.
        let btn = UIButton(type: .system)
        btn.setTitle("Mit Authelia anmelden", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        btn.backgroundColor = UIColor(named: "AccentColor") ?? .systemIndigo
        btn.setTitleColor(.white, for: .normal)
        btn.layer.cornerRadius = 14
        btn.addTarget(context.coordinator, action: #selector(Coordinator.login), for: .touchUpInside)
        return btn as! ASAuthorizationAppleIDButton
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(oidc: oidc) }

    final class Coordinator: NSObject {
        let oidc: OIDCManager
        init(oidc: OIDCManager) { self.oidc = oidc }

        @objc func login(_ sender: UIButton) {
            guard let window = sender.window else { return }
            Task { await oidc.login(from: window) }
        }
    }
}

// Simpler SwiftUI-only sign-in button
struct AuthButton: View {
    @EnvironmentObject var oidc: OIDCManager

    var body: some View {
        Button {
            // anchor ist UIWindow – über UIApplication
            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first {
                Task { await oidc.login(from: window) }
            }
        } label: {
            Label("Mit Authelia anmelden", systemImage: "person.badge.key.fill")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.indigo)
                .foregroundStyle(.white)
                .cornerRadius(14)
                .font(.body.weight(.semibold))
        }
    }
}
