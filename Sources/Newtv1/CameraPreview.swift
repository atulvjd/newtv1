import SwiftUI
@preconcurrency import AVFoundation
import AppKit

@MainActor
final class CameraPreview: ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var active = false
    @Published private(set) var starting = false
    @Published private(set) var message = "Camera stays off until you start the mirror."
    private let queue = DispatchQueue(label: "dev.newtv1.camera")
    private var generation = UUID()
    func start() {
        guard !active, !starting else { return }
        starting = true; let token = UUID(); generation = token
        Task { [self] in
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard generation == token else { return }
            guard allowed else { starting = false; message = "Enable Camera for Newtv1 in Privacy & Security."; return }
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else { starting = false; message = "No camera is available."; return }
            let session = self.session
            queue.async { [weak self] in
                session.beginConfiguration()
                for existing in session.inputs { session.removeInput(existing) }
                session.sessionPreset = .medium
                let usable = session.canAddInput(input)
                if usable { session.addInput(input) }
                session.commitConfiguration()
                if usable { session.startRunning() }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.generation == token else { self.stop(); return }
                    self.starting = false; self.active = usable && session.isRunning
                    self.message = self.active ? "Live mirror · nothing is recorded or uploaded." : "Camera could not start."
                }
            }
        }
    }
    func stop() {
        generation = UUID(); active = false; starting = false
        let session = self.session
        queue.async { session.stopRunning(); session.beginConfiguration(); for input in session.inputs { session.removeInput(input) }; session.commitConfiguration() }
    }
}
struct CameraLayerView: NSViewRepresentable {
    let session: AVCaptureSession
    final class Preview: NSView {
        let preview = AVCaptureVideoPreviewLayer()
        override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer?.addSublayer(preview); preview.videoGravity = .resizeAspectFill }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layout() { super.layout(); preview.frame = bounds }
    }
    func makeNSView(context: Context) -> Preview { let view = Preview(frame: .zero); view.preview.session = session; return view }
    func updateNSView(_ view: Preview, context: Context) { view.preview.session = session }
}
struct CameraModule: View {
    @ObservedObject var camera: CameraPreview
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if camera.active { CameraLayerView(session: camera.session).frame(height: 90).scaleEffect(x: -1, y: 1).clipShape(RoundedRectangle(cornerRadius: 8)) }
            Text(camera.message).font(.system(size: 10)).foregroundStyle(.gray)
            Button(camera.active || camera.starting ? "Stop camera" : "Start mirror") { if camera.active || camera.starting { camera.stop() } else { camera.start() } }.font(.system(size: 11)).buttonStyle(.plain)
        }.onDisappear { camera.stop() }
    }
}
