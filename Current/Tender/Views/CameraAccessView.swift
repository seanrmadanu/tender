import SwiftUI
import AVFoundation

/// Mounted only after a camera action. Never asks during launch or navigation.
struct CameraPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var authorization = AVAuthorizationStatus.notDetermined
    @State private var unavailable = false
    var onCapture: (Data) -> Void
    static var isAvailable: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--camera-denied-test") { return true }
        #endif
        return UIImagePickerController.isSourceTypeAvailable(.camera)
    }
    var body: some View {
        Group {
            if unavailable {
                ContentUnavailableView { Label("Camera unavailable", systemImage: "camera") }
                description: { Text("Choose an image from Photos or Files on this device.") }
                actions: { Button("Close") { dismiss() } }
            } else if authorization == .authorized {
                CameraCapture(onCapture: onCapture).ignoresSafeArea()
            } else if authorization == .denied || authorization == .restricted {
                ContentUnavailableView {
                    Label("Camera access needed", systemImage: "camera")
                } description: {
                    Text(authorization == .restricted ? "Camera access is restricted on this device." : "Allow camera access in Settings to scan price labels or photograph receipts, bills and your profile.")
                } actions: {
                    if authorization == .denied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        } label: { Text("Open Settings").foregroundStyle(Ink.paper) }
                            .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("camera-open-settings")
                    }
                    Button("Close") { dismiss() }.buttonStyle(.bordered)
                }
            } else {
                ProgressView("Requesting camera access…")
            }
        }.tint(Ink.green).task { await prepare() }
            .onChange(of: phase) { _, value in if value == .active { Task { await prepare() } } }
    }
    private func prepare() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--camera-denied-test") { authorization = .denied; return }
        #endif
        guard Self.isAvailable else { unavailable = true; return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorization = granted ? .authorized : .denied
        } else { authorization = status }
    }
}
