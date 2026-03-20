import SwiftUI

struct CardDetailView: View {
    @State var card: ScannedCard
    @Binding var batch: ScanBatch
    let onUpdate: () -> Void

    var body: some View {
        Form {
            Section("Contact") {
                TextField("Name", text: $card.principal)
                TextField("Company", text: $card.entity)
                TextField("Role / Title", text: $card.role)
            }
            Section("Contact Info") {
                TextField("Email", text: $card.email)
                    .keyboardType(.emailAddress).textContentType(.emailAddress)
                TextField("Phone", text: $card.phone)
                    .keyboardType(.phonePad).textContentType(.telephoneNumber)
                TextField("LinkedIn", text: $card.linkedin)
                    .keyboardType(.URL)
                TextField("Instagram", text: $card.instagram)
                TextField("Website", text: $card.website)
                    .keyboardType(.URL)
            }
            Section("Notes") {
                TextEditor(text: $card.notes)
                    .frame(minHeight: 80)
            }
            if !card.tags.isEmpty {
                Section("Tags") {
                    Text(card.tags.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Edit Card")
        .onDisappear {
            if let i = batch.cards.firstIndex(where: { $0.id == card.id }) {
                batch.cards[i] = card
                StorageService.shared.update(batch)
                onUpdate()
            }
        }
    }
}
