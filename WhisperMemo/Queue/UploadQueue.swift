import Foundation
import Network

struct QueuedUpload: Codable, Identifiable {
    let id: String
    let fileURL: URL
    let filename: String
    let prompt: String
    let model: String
    let createdAt: Date
    var retryCount: Int = 0
}

@MainActor
final class UploadQueue: ObservableObject {
    @Published private(set) var pending: [QueuedUpload] = []
    @Published private(set) var isOnline = true

    private let api: APIClient
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "upload-queue-monitor")
    private var isUploading = false

    private var storageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("upload_queue.json")
    }

    init(api: APIClient) {
        self.api = api
        load()
        startMonitoring()
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
        guard isOnline, !isUploading, !pending.isEmpty else { return }
        isUploading = true
        defer { isUploading = false }

        while let item = pending.first, isOnline {
            do {
                _ = try await api.upload(
                    fileURL: item.fileURL,
                    filename: item.filename,
                    prompt: item.prompt,
                    model: item.model
                )
                pending.removeFirst()
                try? FileManager.default.removeItem(at: item.fileURL)
                save()
            } catch {
                // Back-off: keep item, try again on next reconnect
                if var updated = pending.first {
                    updated.retryCount += 1
                    pending[0] = updated
                    save()
                }
                break
            }
        }
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
