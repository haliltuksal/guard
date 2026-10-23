import AVFoundation
import CoreVideo
import Foundation

public enum CameraError: Error, Sendable {
    case noBuiltInCamera
    case cannotAddInput
    case cannotAddOutput
}

/// Yalnızca dahili kamerayı kullanır (Continuity/iPhone ve harici kameralar hariç),
/// Center Stage'i kapatır, video efekti açıksa uyarır. Kareleri delegate ile yayar.
/// Kamera kesintisi/hatası dışarı bildirilir (çekirdek T7 sayar). Cihazda doğrulanır.
public final class CameraSource: NSObject, @unchecked Sendable {
    public struct Warnings: Sendable {
        public var centerStageCouldNotBeDisabled = false
        public var videoEffectsActive = false
    }

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.halil.nobetci.camera")
    private let onFrame: @Sendable (CVPixelBuffer, TimeInterval) -> Void
    private let onInterruption: @Sendable () -> Void

    public private(set) var warnings = Warnings()
    public private(set) var deviceUniqueID: String?

    public init(onFrame: @escaping @Sendable (CVPixelBuffer, TimeInterval) -> Void,
                onInterruption: @escaping @Sendable () -> Void) {
        self.onFrame = onFrame
        self.onInterruption = onInterruption
        super.init()
    }

    /// Dahili kamerayı seçer. Yoksa (ör. Mac mini) `preferredUniqueID` ile sabitlenen kamera kullanılır.
    public func configure(preferredUniqueID: String? = nil) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720

        guard let device = Self.selectCamera(preferredUniqueID: preferredUniqueID) else {
            throw CameraError.noBuiltInCamera
        }
        deviceUniqueID = device.uniqueID
        disableCenterStageAndDetectEffects(on: device)

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraError.cannotAddOutput }
        session.addOutput(output)

        // Bildirim adları macOS 15'te yeniden adlandırıldı; 14 tabanında belgelenmiş
        // ad dizeleriyle bağlanmak hem uyumlu hem uyarısızdır.
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted),
                                               name: Notification.Name("AVCaptureSessionWasInterruptedNotification"), object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted),
                                               name: Notification.Name("AVCaptureSessionRuntimeErrorNotification"), object: session)
    }

    public func start() { if !session.isRunning { session.startRunning() } }
    public func stop() { if session.isRunning { session.stopRunning() } }

    /// Yalnızca dahili geniş açılı kamera; Continuity ve harici cihazlar elenir.
    static func selectCamera(preferredUniqueID: String?) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified)
        let devices = discovery.devices
        if let id = preferredUniqueID, let pinned = devices.first(where: { $0.uniqueID == id }) {
            return pinned
        }
        return devices.first { device in
            if device.isContinuityCamera { return false }
            return device.deviceType == .builtInWideAngleCamera
        }
    }

    private func disableCenterStageAndDetectEffects(on device: AVCaptureDevice) {
        AVCaptureDevice.centerStageControlMode = .app
        if AVCaptureDevice.isCenterStageEnabled {
            AVCaptureDevice.isCenterStageEnabled = false
            if AVCaptureDevice.isCenterStageEnabled { warnings.centerStageCouldNotBeDisabled = true }
        }
        if device.isPortraitEffectActive || device.isStudioLightActive {
            warnings.videoEffectsActive = true   // bulanık arka plan uzaktaki kişiyi gizleyebilir
        }
    }

    @objc private func interrupted() { onInterruption() }
}

extension CameraSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        onFrame(buffer, seconds)
    }
}
