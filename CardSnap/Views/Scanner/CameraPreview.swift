import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let camera: CameraManager

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer = camera.previewLayer
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

class PreviewView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            guard let layer = previewLayer else { return }
            self.layer.addSublayer(layer)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}
