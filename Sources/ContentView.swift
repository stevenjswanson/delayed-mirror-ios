// ContentView.swift
// Root SwiftUI view. Hosts the camera preview full-screen and overlays:
//   • A top status bar showing the current delay.
//   • A buffering spinner while the ring buffer fills up.
//   • A bottom control panel with the delay slider.
//   • A collapsible zoom slider (also controllable with pinch on the preview).

import SwiftUI

struct ContentView: View {

    @StateObject private var camera = CameraManager()
    @State private var showZoomPanel = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.permissionDenied {
                PermissionDeniedView()
            } else {
                liveView
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { camera.start() }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:               camera.start()
            case .background, .inactive: camera.stop()
            default: break
            }
        }
    }

    // ── Live camera + overlay ─────────────────────────────────────────────

    private var liveView: some View {
        ZStack(alignment: .bottom) {

            // Full-screen delayed preview
            CameraPreviewView(cameraManager: camera)
                .ignoresSafeArea()

            // Buffering spinner (shown until the buffer has enough history)
            if camera.isBuffering {
                bufferingBadge
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .top)
                    .padding(.top, 60)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: camera.isBuffering)
            }

            // Controls panel at the bottom
            controlsPanel
        }
    }

    // ── Buffering badge ───────────────────────────────────────────────────

    private var bufferingBadge: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(0.85)
            Text("Buffering…")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // ── Controls panel ────────────────────────────────────────────────────

    private var controlsPanel: some View {
        VStack(spacing: 0) {

            // Zoom slider — slides up from behind the main bar
            if showZoomPanel {
                zoomSlider
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            mainBar
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8),
                   value: showZoomPanel)
    }

    // ── Zoom slider ───────────────────────────────────────────────────────

    private var zoomSlider: some View {
        HStack(spacing: 12) {
            Image(systemName: "minus.magnifyingglass")
                .foregroundColor(.secondary)

            Slider(
                value: Binding(
                    get: { camera.zoom },
                    set: { camera.setZoom($0) }
                ),
                in: camera.minZoom ... max(camera.minZoom + 0.001, camera.maxZoom)
            )
            .tint(.white)

            Image(systemName: "plus.magnifyingglass")
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // ── Main control bar ──────────────────────────────────────────────────

    private var mainBar: some View {
        VStack(spacing: 10) {

            // Row 1: label + current value
            HStack {
                Label("Delay", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(camera.delay, specifier: "%.1f") s")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundColor(.primary)
            }

            // Row 2: delay slider
            HStack(spacing: 8) {
                Text("1 s")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 28, alignment: .leading)

                Slider(value: $camera.delay, in: 1.0 ... 30.0, step: 0.5)
                    .tint(.white)

                Text("30 s")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }

            // Row 3: zoom toggle button
            Button {
                showZoomPanel.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text(showZoomPanel
                         ? "Hide Zoom"
                         : String(format: "Zoom  %.1f×", camera.zoom))
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    showZoomPanel
                        ? Color.white.opacity(0.2)
                        : Color.white.opacity(0.08),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Permission Denied View

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.slash.fill")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Camera Access Required")
                .font(.title2.bold())

            Text("Delayed Mirror needs camera access to show a live delayed preview. Please enable it in Settings.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)

            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString)
                else { return }
                UIApplication.shared.open(url)
            } label: {
                Label("Open Settings", systemImage: "gear")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
