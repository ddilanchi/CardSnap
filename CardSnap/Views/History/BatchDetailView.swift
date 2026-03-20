import SwiftUI

struct BatchDetailView: View {
    @State var batch: ScanBatch
    let onUpdate: () -> Void
    @State private var showShare = false

    var body: some View {
        List {
            ForEach(batch.cards) { card in
                NavigationLink {
                    CardDetailView(card: card, batch: $batch, onUpdate: onUpdate)
                } label: {
                    cardRow(card)
                }
            }
            .onDelete(perform: deleteCards)
        }
        .navigationTitle(batch.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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

    private func cardRow(_ card: ScannedCard) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.displayName).font(.headline)
            if !card.entity.isEmpty { Text(card.entity).font(.subheadline).foregroundStyle(.secondary) }
            HStack(spacing: 4) {
                if !card.role.isEmpty { Text(card.role) }
                if !card.email.isEmpty { Text("· \(card.email)") }
            }
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private func deleteCards(at offsets: IndexSet) {
        batch.cards.remove(atOffsets: offsets)
        StorageService.shared.update(batch)
        onUpdate()
    }
}
