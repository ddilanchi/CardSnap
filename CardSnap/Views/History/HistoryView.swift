import SwiftUI

struct HistoryView: View {
    @StateObject private var vm = HistoryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.batches.isEmpty {
                    ContentUnavailableView(
                        "No Scans Yet",
                        systemImage: "creditcard",
                        description: Text("Scan some business cards and they'll appear here.")
                    )
                } else {
                    List {
                        ForEach(vm.grouped, id: \.key) { day, batches in
                            Section(day) {
                                ForEach(batches) { batch in
                                    NavigationLink(value: batch) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(batch.name).font(.headline)
                                            Text("\(batch.cards.count) card\(batch.cards.count == 1 ? "" : "s")")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                                .onDelete { vm.delete(in: batches, at: $0) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: ScanBatch.self) { batch in
                BatchDetailView(batch: batch, onUpdate: vm.load)
            }
            .onAppear { vm.load() }
        }
    }
}
