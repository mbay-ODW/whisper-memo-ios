import Foundation
import Network
import Combine

struct QueuedUpload: Codable, Identifiable {
    let id: String
    let fileURL: URL
    let filename: String
    let prompt: String
    let model: String
    let createdAt: Date
    var retryCount: Int = 0
    var lastError: String?
}

@MainActor
final class UploadQueue: ObservableObject {
    @Published private(set) var pending: [QueuedUpload] = []
    @Published private(set) var isOnline = true

    private var api: APIClient?
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "upload-queue-monitor")
    private var isUploading = false

    private var storageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("upload_queue.json")
    }

    init() {
        load()
        startMonitoring()
    }

    func configure(api: APIClient) {
        self.api = api
        Task { await processQueue() }
    }

    func enqueue(fileURL: URL, filename: String, prompt: String, model: String) {
        let item = QueuedUpload(
            id: UUID().uuidString,
            fileURL: fileURL,
            filename: filename,
            prompt: prompt,
            model: model,
            createdAt: Date()
        )
        pending.append(item)
        save()
        Task { await processQueue() }
    }

    func processQueue() async {
        guard let api, isOnline, !isUploading, !pending.isEmpty else { return }
        isUploading = true
        defer { isUploading = false }

        var index = 0
        while index < pending.count, isOnline {
            let item = pending[index]

            // Skip items whose file is gone — mark and continue
            guard FileManager.default.fileExists(atPath: item.fileURL.path) else {
                if pending[index].lastError == nil {
                    pending[index].lastError = "Datei nicht mehr vorhanden"
                    save()
                }
                index += 1
                continue
            }

            do {
                _ = try await api.upload(
                    fileURL: item.fileURL,
                    filename: item.filename,
                    prompt: item.prompt,
                    model: item.model
                )
                pending.remove(at: index)
                try? FileManager.default.removeItem(at: item.fileURL)
                save()
                // don't increment index — next item slides into current position
            } catch {
                pending[index].retryCount += 1
                pending[index].lastError = error.localizedDescription
                save()
                index += 1  // skip failed item, try next
            }
        }
    }

    func remove(id: String) {
        pending.removeAll { $0.id == id }
        save()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = online
                if online && wasOffline {
                    await self.processQueue()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        pending = (try? JSONDecoder().decode([QueuedUpload].self, from: data)) ?? []
    }

    private func save() {
        try? JSONEncoder().encode(pending).write(to: storageURL)
    }
}
