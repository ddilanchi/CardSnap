import Foundation

class StorageService {
    static let shared = StorageService()
    private init() {}

    private var storageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("CardSnap")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var batchesURL: URL { storageURL.appendingPathComponent("batches.json") }

    func loadBatches() -> [ScanBatch] {
        guard
            let data = try? Data(contentsOf: batchesURL),
            let batches = try? decoder.decode([ScanBatch].self, from: data)
        else { return [] }
        return batches.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ batches: [ScanBatch]) {
        guard let data = try? encoder.encode(batches) else { return }
        try? data.write(to: batchesURL)
    }

    func add(_ batch: ScanBatch) {
        var all = loadBatches()
        all.insert(batch, at: 0)
        save(all)
    }

    func update(_ batch: ScanBatch) {
        var all = loadBatches()
        if let i = all.firstIndex(where: { $0.id == batch.id }) {
            all[i] = batch
            save(all)
        }
    }

    func delete(id: UUID) {
        var all = loadBatches()
        all.removeAll { $0.id == id }
        save(all)
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
