import SwiftUI

struct ScannerView: View {
    @StateObject private var vm = ScannerViewModel()
    @State private var completedBatch: ScanBatch?
    @State private var showResult = false
    @State private var showNote = false
    @State private var noteCardId: UUID?

    var body: some View {
        ZStack {
            // Camera feed
            CameraPreview(camera: vm.camera)
                .ignoresSafeArea()

            // Detection overlay
            CardOverlayView(points: vm.overlayPoints, color: vm.overlayColor)
                .ignoresSafeArea()

            if !vm.camera.permissionGranted {
                permissionView
            } else {
                controls
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .alert("Duplicate Card", isPresented: $vm.showDuplicateAlert) {
            Button("Keep Both") { vm.acceptDuplicate() }
            Button("Discard", role: .destructive) { vm.rejectDuplicate() }
        } message: {
            Text("This looks like \(vm.duplicateOf?.displayName ?? "an existing card"). Add it anyway?")
        }
        .alert("Error", isPresented: $vm.showError) {
            Button("OK") {}
        } message: {
            Text(vm.errorMessage ?? "Unknown error")
        }
        .sheet(isPresented: $showNote) {
            if let id = noteCardId,
               let card = vm.scannedCards.first(where: { $0.id == id }) {
                NoteInputView(cardName: card.displayName) { note in
                    vm.appendNote(note, to: id)
                }
            }
        }
        .sheet(isPresented: $showResult) {
            if let batch = completedBatch {
                SessionResultView(batch: batch)
            }
        }
    }

    // MARK: - Controls overlay

    private var controls: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack {
                statusPill
                Spacer()
                if !vm.scannedCards.isEmpty {
                    countBadge
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            // Processing spinner
            if vm.isProcessing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }

            Spacer()

            // Last scanned banner + note button
            if let card = vm.lastCard {
                lastCardBanner(card)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Done button
            if !vm.scannedCards.isEmpty {
                doneButton
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .animation(.spring(duration: 0.3), value: vm.lastCard?.id)
        .animation(.spring(duration: 0.3), value: vm.isProcessing)
    }

    private var statusPill: some View {
        Text(vm.statusText)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var countBadge: some View {
        Text("\(vm.scannedCards.count)")
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(.red, in: Circle())
    }

    private func lastCardBanner(_ card: ScannedCard) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if !card.entity.isEmpty && card.entity != card.displayName {
                    Text(card.entity)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            Spacer()
            Button {
                noteCardId = card.id
                showNote = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var doneButton: some View {
        Button {
            completedBatch = vm.finishSession()
            showResult = true
        } label: {
            Text("Done  —  \(vm.scannedCards.count) card\(vm.scannedCards.count == 1 ? "" : "s")")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.red, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Permission view

    private var permissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 56))
                .foregroundStyle(.gray)
            Text("Camera Access Required")
                .font(.title2.weight(.semibold))
            Text("CardSnap needs your camera to scan business cards.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }
}
