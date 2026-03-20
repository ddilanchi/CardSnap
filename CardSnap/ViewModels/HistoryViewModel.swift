import SwiftUI

class HistoryViewModel: ObservableObject {
    @Published var batches: [ScanBatch] = []

    var grouped: [(key: String, value: [ScanBatch])] {
        let df = DateFormatter()
        df.dateStyle = .medium
        let dict = Dictionary(grouping: batches) { df.string(from: $0.createdAt) }
        return dict.sorted { a, b in
            (a.value.first?.createdAt ?? .distantPast) > (b.value.first?.createdAt ?? .distantPast)
        }
    }

    func load() { batches = StorageService.shared.loadBatches() }

    func delete(batch: ScanBatch) {
        StorageService.shared.delete(id: batch.id)
        load()
    }

    func delete(in section: [ScanBatch], at offsets: IndexSet) {
        offsets.forEach { StorageService.shared.delete(id: section[$0].id) }
        load()
    }
}
