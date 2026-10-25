import SwiftUI

/// Draw the circle directly at the view's display scale, without a cached texture.
final class MapControlButton: UIControl {
    var symbol = "location.fill"
    var darkAppearance = false
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor((darkAppearance ? UIColor.black : UIColor.white).cgColor)
        let inset = 1 / max(1, contentScaleFactor)
        context.fillEllipse(in: bounds.insetBy(dx: inset, dy: inset))
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        if let icon = UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal) {
            let size = icon.size
            icon.draw(in: CGRect(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2, width: size.width, height: size.height))
        }
    }
}

struct MapCircleButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        NativeMapButton(symbol: symbol, label: label, action: action).frame(width: 44, height: 44)
    }
}

private struct NativeMapButton: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let label: String
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeUIView(context: Context) -> MapControlButton {
        let button = MapControlButton(frame: .zero)
        button.backgroundColor = .clear
        button.isOpaque = false
        button.layer.borderWidth = 0; button.layer.shadowOpacity = 0
        button.layer.shouldRasterize = false
        button.layer.masksToBounds = false
        button.contentMode = .redraw
        button.isAccessibilityElement = true
        button.accessibilityTraits = .button
        button.addTarget(context.coordinator, action: #selector(Coordinator.pressed), for: .touchUpInside)
        return button
    }
    func updateUIView(_ button: MapControlButton, context: Context) {
        context.coordinator.action = action
        button.symbol = symbol; button.darkAppearance = colorScheme == .dark
        button.accessibilityLabel = label
        button.setNeedsDisplay()
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func pressed() { action() }
    }
}

struct ReplayControls: View {
    @ObservedObject var controller: RouteReplayController
    let points: [TrackPoint]
    var recording = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Button(action: {
                    switch controller.state {
                    case .idle, .finished: controller.start(points, live: recording)
                    case .playing, .live: controller.pause()
                    case .paused: controller.resume()
                    }
                }) {
                    Label(title, systemImage: controller.isRunning ? "pause.fill" : "play.fill")
                        .font(.subheadline).padding(.horizontal, 14).frame(height: 40)
                        .background(Capsule().fill(Color.blue.opacity(0.1)))
                }.buttonStyle(PlainButtonStyle()).foregroundColor(.blue).disabled(points.isEmpty)
                if controller.isPresenting {
                    Button(controller.state == .finished ? "收起" : "停止重现") { controller.stop() }
                        .font(.subheadline).buttonStyle(PlainButtonStyle())
                }
                Spacer(minLength: 0)
            }
            if controller.isPresenting {
                ReplayProgressControl(controller: controller, progress: controller.progress)
                HStack {
                    Text(points.first?.timestamp ?? Date(), style: .time)
                    Spacer()
                    if recording { Text("最新") }
                    Text(points.last?.timestamp ?? Date(), style: .time)
                }.font(.caption2).foregroundColor(.secondary)
                if !controller.followsHead {
                    Button("跟随光点") { controller.followHead() }.font(.caption)
                }
            }
        }
        .onChange(of: "\(points.count):\(points.last?.id.uuidString ?? ""):\(recording)") { _ in
            controller.update(points, live: recording)
        }
    }
    private var title: String {
        switch controller.state {
        case .idle: return "路途重现"
        case .playing: return "暂停重现"
        case .live: return "实时跟随 · 暂停"
        case .paused: return "继续重现"
        case .finished: return "再看一遍"
        }
    }
}

private struct ReplayProgressControl: View {
    let controller: RouteReplayController
    @ObservedObject var progress: RouteReplayProgress
    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()
    private var timeText: String {
        guard let date = progress.position.recordedAt else { return "" }
        return Self.timestamp.string(from: date) + (progress.position.inGap ? " · 暂停" : "")
    }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ReplaySlider(controller: controller, fraction: progress.position.fraction, timeText: timeText)
                    .frame(height: 44)
                Text(timeText).font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary).lineLimit(1)
                    .frame(width: min(172, geometry.size.width), height: 18)
                    .position(x: min(max(geometry.size.width*CGFloat(progress.position.fraction), min(86, geometry.size.width/2)), max(geometry.size.width-86, geometry.size.width/2)), y: 9)
                    .frame(height: 18)
            }
        }.frame(height: 62)
    }
}

/// UISlider supplies native drag cancellation and VoiceOver adjustable actions on iOS 14.
private struct ReplaySlider: UIViewRepresentable {
    let controller: RouteReplayController
    let fraction: Double
    let timeText: String
    func makeCoordinator() -> Coordinator { Coordinator(controller) }
    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = 0; slider.maximumValue = 1; slider.isContinuous = true
        slider.minimumTrackTintColor = UIColor(red: 1, green: 0.87, blue: 0.48, alpha: 1)
        slider.maximumTrackTintColor = .systemBlue
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 34, height: 34)).image { renderer in
            let cg = renderer.cgContext
            cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.14).cgColor)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: 3, y: 3, width: 28, height: 28))
        }
        slider.setThumbImage(thumb, for: .normal)
        slider.setThumbImage(thumb, for: .highlighted)
        slider.accessibilityLabel = "路线重现进度"
        slider.addTarget(context.coordinator, action: #selector(Coordinator.begin), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.end), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return slider
    }
    func updateUIView(_ slider: UISlider, context: Context) {
        slider.setValue(Float(fraction), animated: false)
        slider.accessibilityValue = timeText
    }
    final class Coordinator: NSObject {
        let controller: RouteReplayController
        init(_ controller: RouteReplayController) { self.controller = controller }
        @objc func begin() { controller.beginScrubbing() }
        @objc func changed(_ slider: UISlider) {
            let accessibilityChange = !slider.isTracking
            if accessibilityChange { controller.beginScrubbing() }
            controller.seek(to: Double(slider.value))
            if accessibilityChange { controller.endScrubbing() }
        }
        @objc func end() { controller.endScrubbing() }
    }
}
