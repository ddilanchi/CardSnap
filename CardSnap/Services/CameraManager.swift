import AVFoundation
import UIKit

class CameraManager: NSObject, ObservableObject {
    let captureSession = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer

    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.cardsnap.session")
    private let processingQueue = DispatchQueue(label: "com.cardsnap.processing")

    var onFrame: ((CVPixelBuffer) -> Void)?
    private var photoContinuation: CheckedContinuation<Data, Error>?

    @Published var permissionGranted = false

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        super.init()
    }

    func requestPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.permissionGranted = true }
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { self?.permissionGranted = granted }
                if granted { self?.setupSession() }
            }
        default:
            DispatchQueue.main.async { self.permissionGranted = false }
        }
    }

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            captureSession.beginConfiguration()
            captureSession.sessionPreset = .photo

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                captureSession.canAddInput(input)
            else {
                captureSession.commitConfiguration()
                return
            }
            captureSession.addInput(input)

            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                videoOutput.connection(with: .video)?.videoOrientation = .portrait
            }

            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
                photoOutput.connection(with: .video)?.videoOrientation = .portrait
            }

            captureSession.commitConfiguration()
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !captureSession.isRunning else { return }
            captureSession.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, captureSession.isRunning else { return }
            captureSession.stopRunning()
        }
    }

    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation
            DispatchQueue.main.async {
                let settings = AVCapturePhotoSettings()
                settings.flashMode = .auto
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    /// Convert Vision normalized point (bottom-left origin) to screen coordinates.
    func convertPoint(_ p: CGPoint) -> CGPoint {
        previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: p.x, y: 1 - p.y))
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            photoContinuation?.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation() {
            photoContinuation?.resume(returning: data)
        } else {
            photoContinuation?.resume(throwing: NSError(domain: "CardSnap", code: -1))
        }
        photoContinuation = nil
    }
}
