import Foundation
import AuthenticationServices
import CryptoKit

@MainActor
final class OIDCManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: String?

    private var codeVerifier: String?

    // Keychain keys
    private let kAccessToken  = "oidc_access_token"
    private let kRefreshToken = "oidc_refresh_token"
    private let kExpiry       = "oidc_token_expiry"
    private let kIssuer       = "oidc_issuer"

    // Loaded from /api/config
    private(set) var issuer: String = ""
    private(set) var clientId: String = ""

    // Endpoints (from OIDC discovery)
    private var authEndpoint: URL?
    private var tokenEndpoint: URL?

    override init() {
        super.init()
        isAuthenticated = Keychain.load(for: "oidc_access_token") != nil
    }

    // MARK: – Setup from server config

    func configure(issuer: String, clientId: String) async {
        self.issuer = issuer
        self.clientId = clientId
        await discoverEndpoints(issuer: issuer)
    }

    private func discoverEndpoints(issuer: String) async {
        guard let url = URL(string: "\(issuer)/.well-known/openid-configuration") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONDecoder().decode(OIDCDiscovery.self, from: data)
            authEndpoint  = URL(string: json.authorization_endpoint)
            tokenEndpoint = URL(string: json.token_endpoint)
        } catch {
            self.error = "OIDC Discovery fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: – Login

    func login(from anchor: ASPresentationAnchor) async {
        guard let authEndpoint else {
            self.error = "Auth-Endpoint nicht verfügbar"
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }

        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        codeVerifier = verifier

        var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id",             value: clientId),
            .init(name: "redirect_uri",          value: "whispermemo://oauth/callback"),
            .init(name: "response_type",         value: "code"),
            .init(name: "scope",                 value: "openid profile email"),
            .init(name: "code_challenge",        value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]

        guard let authURL = components.url else { return }

        do {
            let callbackURL = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: "whispermemo"
                ) { url, err in
                    if let err { cont.resume(throwing: err) }
                    else if let url { cont.resume(returning: url) }
                    else { cont.resume(throwing: URLError(.badServerResponse)) }
                }
                session.presentationContextProvider = PresentationAnchorProvider(anchor: anchor)
                session.prefersEphemeralWebBrowserSession = false
                session.start()
            }
            guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
                throw URLError(.badServerResponse)
            }
            try await exchangeCode(code, verifier: verifier)
            isAuthenticated = true
        } catch ASWebAuthenticationSessionError.canceledLogin {
            // user cancelled – do nothing
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: – Token exchange

    private func exchangeCode(_ code: String, verifier: String) async throws {
        guard let tokenEndpoint else { throw URLError(.unsupportedURL) }
        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type":   "authorization_code",
            "client_id":    clientId,
            "code":         code,
            "redirect_uri": "whispermemo://oauth/callback",
            "code_verifier": verifier,
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
         .joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        storeTokens(token)
    }

    // MARK: – Token refresh

    func refreshIfNeeded() async throws {
        guard let expiry = Keychain.load(for: kExpiry).flatMap(Double.init),
              expiry - Date().timeIntervalSince1970 < 60 else { return }
        try await refresh()
    }

    private func refresh() async throws {
        guard let tokenEndpoint,
              let refreshToken = Keychain.load(for: kRefreshToken) else {
            logout()
            throw URLError(.userAuthenticationRequired)
        }
        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type":    "refresh_token",
            "client_id":     clientId,
            "refresh_token": refreshToken,
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        storeTokens(token)
    }

    // MARK: – Access token (public, auto-refreshes)

    func accessToken() async throws -> String {
        try await refreshIfNeeded()
        guard let t = Keychain.load(for: kAccessToken) else {
            isAuthenticated = false
            throw URLError(.userAuthenticationRequired)
        }
        return t
    }

    // MARK: – Logout

    func logout() {
        Keychain.delete(for: kAccessToken)
        Keychain.delete(for: kRefreshToken)
        Keychain.delete(for: kExpiry)
        isAuthenticated = false
    }

    // MARK: – Helpers

    private func storeTokens(_ token: TokenResponse) {
        Keychain.save(token.access_token, for: kAccessToken)
        if let r = token.refresh_token { Keychain.save(r, for: kRefreshToken) }
        if let exp = token.expires_in {
            Keychain.save(String(Date().timeIntervalSince1970 + Double(exp)), for: kExpiry)
        }
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .prefix(128).description
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: – Supporting types

private struct OIDCDiscovery: Decodable {
    let authorization_endpoint: String
    let token_endpoint: String
}

private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
}

private final class PresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}
