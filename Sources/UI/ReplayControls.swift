import SwiftUI

/// Borderless native control: a filled vector disk and a separate template icon.
/// No bitmap background, stroked path, rounded clipping mask, or default button chrome.
final class MapControlButton: UIControl {
    private let disk = CAShapeLayer()
    private let icon = UIImageView()
    var symbol = "location.fill" { didSet { if symbol != oldValue { updateIcon() } } }
    var darkAppearance = false { didSet { updateFill() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        layer.borderWidth = 0
        layer.shadowOpacity = 0
        layer.shouldRasterize = false
        disk.strokeColor = nil
        disk.lineWidth = 0
        disk.shadowOpacity = 0
        layer.addSublayer(disk)
        icon.contentMode = .center
        icon.tintColor = .systemBlue
        icon.isUserInteractionEnabled = false
        icon.isAccessibilityElement = false
        addSubview(icon)
        updateIcon()
        updateFill()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disk.frame = bounds
        disk.contentsScale = max(1, window?.screen.scale ?? contentScaleFactor)
        disk.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).cgPath
        icon.frame = bounds
        CATransaction.commit()
    }
    override func accessibilityActivate() -> Bool {
        guard isEnabled, isUserInteractionEnabled, !isHidden else { return false }
        sendActions(for: .touchUpInside)
        return true
    }
    private func updateFill() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disk.fillColor = (darkAppearance ? UIColor(white: 0.18, alpha: 1) : UIColor.white).cgColor
        CATransaction.commit()
    }
    private func updateIcon() {
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        icon.image = UIImage(systemName: symbol, withConfiguration: configuration)?.withRenderingMode(.alwaysTemplate)
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
                    Button(action: { controller.stop() }) { Text(controller.state == .finished ? L("收起") : L("停止重现")) }
                        .font(.subheadline).buttonStyle(PlainButtonStyle())
                }
                Spacer(minLength: 0)
            }
            if controller.isPresenting {
                ReplayProgressControl(controller: controller, progress: controller.progress)
                HStack {
                    Text(points.first?.timestamp ?? Date(), style: .time)
                    Spacer()
                    if recording { Text(L("最新")) }
                    Text(points.last?.timestamp ?? Date(), style: .time)
                }.font(.caption2).foregroundColor(.secondary)
            }
        }
        .onChange(of: "\(points.count):\(points.last?.id.uuidString ?? ""):\(recording)") { _ in
            controller.update(points, live: recording)
        }
    }
    private var title: String {
        switch controller.state {
        case .idle: return L("路途重现")
        case .playing: return L("暂停重现")
        case .live: return L("实时跟随")
        case .paused: return L("继续重现")
        case .finished: return L("再看一遍")
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
        return Self.timestamp.string(from: date) + (progress.position.inGap ? L(" · 暂停") : "")
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
        slider.minimumTrackTintColor = .systemBlue
        slider.maximumTrackTintColor = UIColor(red: 1, green: 0.87, blue: 0.48, alpha: 1)
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 34, height: 34)).image { renderer in
            let cg = renderer.cgContext
            cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.14).cgColor)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: 3, y: 3, width: 28, height: 28))
        }
        slider.setThumbImage(thumb, for: .normal)
        slider.setThumbImage(thumb, for: .highlighted)
        slider.accessibilityLabel = L("路线重现进度")
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
