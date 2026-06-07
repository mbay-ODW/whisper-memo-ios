import Foundation

final class APIClient {
    let baseURL: URL
    private let oidc: OIDCManager

    init(baseURL: URL, oidc: OIDCManager) {
        self.baseURL = baseURL
        self.oidc = oidc
    }

    // MARK: – Config (public, kein Auth)

    func fetchConfig() async throws -> ServerConfig {
        let req = URLRequest(url: baseURL.appendingPathComponent("api/config"))
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(ServerConfig.self, from: data)
    }

    // MARK: – Upload

    func upload(
        fileURL: URL,
        filename: String,
        prompt: String,
        model: String
    ) async throws -> [String] {
        let url = baseURL.appendingPathComponent("api/transcribe")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        try await injectAuth(&req)

        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }

        // File field
        let fileData = try Data(contentsOf: fileURL)
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: audio/mp4\r\n\r\n")
        body.append(fileData)
        append("\r\n")

        // Text fields
        for (key, value) in [("initial_prompt", prompt), ("model", model)] {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)--\r\n")
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(resp, data: data)

        struct SingleJob: Decodable { let job_id: String }
        let j = try JSONDecoder().decode(SingleJob.self, from: data)
        return [j.job_id]
    }

    // MARK: – Jobs

    func fetchJobs() async throws -> [Job] {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/jobs"))
        try await injectAuth(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(resp, data: data)
        return try JSONDecoder().decode([Job].self, from: data)
    }

    func fetchJob(id: String) async throws -> Job {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/jobs/\(id)"))
        try await injectAuth(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(resp, data: data)
        return try JSONDecoder().decode(Job.self, from: data)
    }

    func cancelJob(id: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/jobs/\(id)/cancel"))
        req.httpMethod = "POST"
        try await injectAuth(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(resp, data: data)
    }

    func deleteJob(id: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/jobs/\(id)/delete"))
        req.httpMethod = "DELETE"
        try await injectAuth(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(resp, data: data)
    }

    // MARK: – Download

    func downloadText(jobId: String, format: String) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/download/\(jobId)/\(format)"))
        try await injectAuth(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(resp, data: data)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: – Auth injection

    @MainActor
    private func injectAuth(_ req: inout URLRequest) async throws {
        let token = try await oidc.accessToken()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func checkResponse(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "HTTP \(http.statusCode)"
            throw APIError.serverError(msg)
        }
    }
}

enum APIError: LocalizedError {
    case unauthorized
    case serverError(String)
    var errorDescription: String? {
        switch self {
        case .unauthorized:       return "Nicht authentifiziert"
        case .serverError(let m): return m
        }
    }
}

private func fmtTime(_ s: Double) -> String {
    let m = Int(s / 60), sec = Int(s) % 60
    return String(format: "%d:%02d", m, sec)
}
