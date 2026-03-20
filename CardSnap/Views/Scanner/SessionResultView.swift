import SwiftUI

struct SessionResultView: View {
    let batch: ScanBatch
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            List(batch.cards) { card in
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.displayName).font(.headline)
                    if !card.entity.isEmpty {
                        Text(card.entity).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !card.role.isEmpty {
                        Text(card.role).font(.caption).foregroundStyle(.secondary)
                    }
                    if !card.email.isEmpty {
                        Text(card.email).font(.caption).foregroundStyle(.blue)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("\(batch.cards.count) Cards Scanned")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                ActivityView(items: ExportService.exportItems(from: batch.cards))
            }
        }
    }
}
