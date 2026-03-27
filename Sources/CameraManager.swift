// CameraManager.swift
// Manages AVFoundation capture, a JPEG-compressed circular frame buffer,
// and zoom control. Frames are compressed to ~75% JPEG quality so the
// 30-second buffer stays well under 100 MB even at 720p / 30 fps.

import AVFoundation
import UIKit
import CoreImage
import Combine

// MARK: - CameraManager

final class CameraManager: NSObject, ObservableObject {

    // ──────────────────────────────────────────────
    // MARK: Published State
    // ──────────────────────────────────────────────

    /// How many seconds back in time to display (1 – 30).
    @Published var delay: Double = 5.0

    /// Current camera zoom factor (reflects what's applied to the lens).
    @Published var zoom: Double = 1.0

    /// True while the session is running.
    @Published var isRunning = false

    /// True while the ring buffer hasn't collected enough frames for the
    /// requested delay yet.
    @Published var isBuffering = true

    /// Set to true when the user has denied camera permission.
    @Published var permissionDenied = false

    // ──────────────────────────────────────────────
    // MARK: Zoom Limits (read after session starts)
    // ──────────────────────────────────────────────

    private(set) var minZoom: Double = 1.0
    private(set) var maxZoom: Double = 5.0

    // ──────────────────────────────────────────────
    // MARK: AVFoundation
    // ──────────────────────────────────────────────

    private let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice?
    private let videoOutput = AVCaptureVideoDataOutput()

    /// Serial queue for session configuration / start / stop.
    private let sessionQueue = DispatchQueue(
        label: "com.delayedmirror.session", qos: .userInitiated)

    /// Serial queue on which AVFoundation delivers sample buffers.
    private let captureQueue = DispatchQueue(
        label: "com.delayedmirror.capture", qos: .userInitiated)

    // ──────────────────────────────────────────────
    // MARK: Ring Buffer
    // ──────────────────────────────────────────────

    /// One element in the ring buffer.
    private struct FrameEntry {
        /// Wall-clock time of capture (CACurrentMediaTime).
        let timestamp: Double
        /// JPEG-compressed pixel data.
        let jpeg: Data
    }

    /// Chronologically ordered array of compressed frames.
    private var ringBuffer = [FrameEntry]()
    private let ringLock = NSLock()

    /// Keep slightly more frames than the maximum delay to always have
    /// a valid frame to show even at the 30 s setting.
    private let maxBufferDuration: Double = 33.0

    // ──────────────────────────────────────────────
    // MARK: Compression
    // ──────────────────────────────────────────────

    /// Metal-backed CIContext for fast pixel-buffer → CGImage conversion.
    private let ciContext: CIContext = {
        if let mtl = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: mtl,
                            options: [.workingColorSpace: NSNull()])
        }
        return CIContext(options: [.workingColorSpace: NSNull()])
    }()

    /// JPEG compression quality (0.75 gives ~60–120 KB at 720p).
    private let jpegQuality: CGFloat = 0.75

    // ──────────────────────────────────────────────
    // MARK: Init
    // ──────────────────────────────────────────────

    override init() {
        super.init()
        checkPermission()
    }

    // ──────────────────────────────────────────────
    // MARK: Permission
    // ──────────────────────────────────────────────

    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.setupCaptureSession()
                } else {
                    DispatchQueue.main.async { self?.permissionDenied = true }
                }
            }
        default:
            DispatchQueue.main.async { self.permissionDenied = true }
        }
    }

    // ──────────────────────────────────────────────
    // MARK: Session Setup
    // ──────────────────────────────────────────────

    private func setupCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .hd1280x720

            // ── Camera device ──────────────────────────────
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            )
            guard let device = discovery.devices.first else {
                self.captureSession.commitConfiguration()
                return
            }
            self.videoDevice = device

            let rawMax = Double(device.activeFormat.videoMaxZoomFactor)
            DispatchQueue.main.async {
                self.minZoom = 1.0
                self.maxZoom = min(rawMax, 10.0)
            }

            // ── Input ──────────────────────────────────────
            guard
                let input = try? AVCaptureDeviceInput(device: device),
                self.captureSession.canAddInput(input)
            else {
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(input)

            // ── Output ─────────────────────────────────────
            // 32BGRA gives us a convenient layout for CIImage.
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(
                self, queue: self.captureQueue)

            guard self.captureSession.canAddOutput(self.videoOutput) else {
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addOutput(self.videoOutput)

            // Portrait orientation
            if let conn = self.videoOutput.connection(with: .video),
               conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }

            self.captureSession.commitConfiguration()
        }
    }

    // ──────────────────────────────────────────────
    // MARK: Session Control
    // ──────────────────────────────────────────────

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
                self.isBuffering = true
            }
        }
    }

    // ──────────────────────────────────────────────
    // MARK: Zoom
    // ──────────────────────────────────────────────

    /// Apply a zoom factor, clamped to the device's supported range.
    func setZoom(_ factor: Double) {
        guard let device = videoDevice else { return }
        let clamped = CGFloat(max(minZoom, min(factor, maxZoom)))
        do {
            try device.lockForConfiguration()
            // Smooth the zoom transition.
            device.ramp(toVideoZoomFactor: clamped, withRate: 8.0)
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.zoom = Double(clamped) }
        } catch {
            // Fall back to immediate set.
            try? device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.zoom = Double(clamped) }
        }
    }

    // ──────────────────────────────────────────────
    // MARK: Frame Retrieval
    // ──────────────────────────────────────────────

    /// Returns the delayed frame as a UIImage, or nil if not yet buffered.
    /// This may be called from any thread.
    func getDelayedFrame() -> UIImage? {
        let targetTime = CACurrentMediaTime() - delay

        ringLock.lock()
        let snapshot = ringBuffer          // cheap copy of array of structs
        ringLock.unlock()

        guard !snapshot.isEmpty else { return nil }

        // Binary-search for the entry whose timestamp is closest to targetTime.
        var lo = 0, hi = snapshot.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if snapshot[mid].timestamp < targetTime {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        // Check both neighbours and pick the closer one.
        var best = snapshot[lo]
        if lo > 0 {
            let prev = snapshot[lo - 1]
            if abs(prev.timestamp - targetTime) < abs(best.timestamp - targetTime) {
                best = prev
            }
        }

        return UIImage(data: best.jpeg)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CACurrentMediaTime()

        // ── Compress frame to JPEG ─────────────────────────────────────────
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
        else { return }

        // UIImage(cgImage:) is zero-copy; jpegData does the encode.
        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        guard let jpegData = uiImage.jpegData(compressionQuality: jpegQuality)
        else { return }

        let entry = FrameEntry(timestamp: now, jpeg: jpegData)

        // ── Update ring buffer ─────────────────────────────────────────────
        ringLock.lock()
        ringBuffer.append(entry)

        // Drop frames older than maxBufferDuration.
        let cutoff = now - maxBufferDuration
        if let firstKeep = ringBuffer.firstIndex(where: { $0.timestamp >= cutoff }) {
            if firstKeep > 0 { ringBuffer.removeFirst(firstKeep) }
        }

        let span = (ringBuffer.last?.timestamp ?? 0)
                 - (ringBuffer.first?.timestamp ?? 0)
        ringLock.unlock()

        // ── Buffering indicator ────────────────────────────────────────────
        // Read `delay` on the capture queue — safe because it's a plain Double
        // (value type) and the worst-case race is showing a stale indicator
        // for one frame.
        let currentDelay = delay
        let buffering = span < min(currentDelay, maxBufferDuration - 2)
        DispatchQueue.main.async { [weak self] in
            self?.isBuffering = buffering
        }
    }
}
