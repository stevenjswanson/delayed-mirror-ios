// CameraPreviewView.swift
// A UIViewRepresentable that drives a UIImageView at up to 30 fps using a
// CADisplayLink. JPEG decoding is off the main thread; a guard flag prevents
// overlapping decode operations.
//
// Pinch-to-zoom is handled here so it works with any SwiftUI layout without
// fighting the gesture recogniser system.

import UIKit
import SwiftUI

// MARK: - UIKit Layer

final class CameraPreviewViewController: UIViewController {

    // Set by the SwiftUI wrapper before the view appears.
    var cameraManager: CameraManager!

    // ── Subviews ──────────────────────────────────────────────────────────

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.backgroundColor = .black
        iv.clipsToBounds = true
        return iv
    }()

    // ── Display link ──────────────────────────────────────────────────────

    private var displayLink: CADisplayLink?
    /// Guards against multiple overlapping background decode operations.
    private var isDecoding = false
    /// Dedicated queue for JPEG decompression so the main thread stays free.
    private let decodeQueue = DispatchQueue(
        label: "com.delayedmirror.decode", qos: .userInteractive)

    // ── Pinch state ───────────────────────────────────────────────────────

    private var pinchStartZoom: Double = 1.0

    // ── Lifecycle ─────────────────────────────────────────────────────────

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        imageView.frame = view.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(imageView)

        let pinch = UIPinchGestureRecognizer(
            target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startDisplayLink()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopDisplayLink()
    }

    // ── Display link helpers ──────────────────────────────────────────────

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let dl = CADisplayLink(target: self, selector: #selector(tick))
        // Request 30 fps; the system can drop to 15 fps if needed.
        dl.preferredFrameRateRange = CAFrameRateRange(
            minimum: 15, maximum: 30, preferred: 30)
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    // ── Per-frame update ──────────────────────────────────────────────────

    @objc private func tick() {
        guard !isDecoding else { return }
        isDecoding = true

        decodeQueue.async { [weak self] in
            guard let self else { return }
            let image = self.cameraManager.getDelayedFrame()
            DispatchQueue.main.async {
                if let image {
                    // Disable implicit layer animations for zero-latency
                    // image swaps.
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.imageView.image = image
                    CATransaction.commit()
                }
                self.isDecoding = false
            }
        }
    }

    // ── Pinch gesture ─────────────────────────────────────────────────────

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartZoom = cameraManager.zoom
        case .changed:
            let newZoom = pinchStartZoom * Double(gesture.scale)
            cameraManager.setZoom(newZoom)
        default:
            break
        }
    }
}

// MARK: - SwiftUI Wrapper

struct CameraPreviewView: UIViewControllerRepresentable {

    @ObservedObject var cameraManager: CameraManager

    func makeUIViewController(context: Context) -> CameraPreviewViewController {
        let vc = CameraPreviewViewController()
        vc.cameraManager = cameraManager
        return vc
    }

    func updateUIViewController(
        _ uiViewController: CameraPreviewViewController,
        context: Context
    ) {
        // CameraManager is accessed directly; no per-update wiring needed.
    }
}
