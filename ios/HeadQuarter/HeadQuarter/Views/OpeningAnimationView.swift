import AVFoundation
import SwiftUI
import UIKit
import OSLog

struct OpeningAnimationView: UIViewRepresentable {
    let onFinish: () -> Void

    func makeUIView(context: Context) -> OpeningPlayerView {
        OpeningPlayerView(onFinish: onFinish)
    }

    func updateUIView(_ uiView: OpeningPlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: OpeningPlayerView, coordinator: ()) {
        uiView.stop()
    }
}

final class OpeningPlayerView: UIView {
    private let logger = Logger(subsystem: "com.headquarter.app", category: "OpeningAnimation")
    private let player = AVPlayer()
    private let videoLayer = AVPlayerLayer()
    private let backdrop = UIImageView(image: UIImage(named: "LaunchBackdrop"))
    private let poster = UIImageView(image: UIImage(named: "LaunchPoster"))
    private var statusObservation: NSKeyValueObservation?
    private var displayObservation: NSKeyValueObservation?
    private var notifications: [NSObjectProtocol] = []
    private var startupTimeout: DispatchWorkItem?
    private var finished = false
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        super.init(frame: .zero)
        backgroundColor = UIColor(named: "LaunchBackground")
        clipsToBounds = true
        backdrop.contentMode = .scaleAspectFill
        addSubview(backdrop)
        poster.contentMode = .scaleAspectFit
        addSubview(poster)
        videoLayer.player = player
        videoLayer.videoGravity = .resizeAspect
        layer.addSublayer(videoLayer)
        player.actionAtItemEnd = .pause
        player.isMuted = true
        isAccessibilityElement = true
        accessibilityLabel = "Head Quarter opening animation"

        guard let url = Bundle.main.url(forResource: "Opening", withExtension: "mp4") else {
            DispatchQueue.main.async { [weak self] in self?.finish() }
            return
        }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.logger.info("Opening animation completed")
            self?.finish()
        })
        notifications.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.finish()
        })
        notifications.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.player.pause()
        })
        notifications.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.finished, self.player.currentItem?.status == .readyToPlay else { return }
            self.player.play()
        })
        displayObservation = videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                self?.poster.isHidden = true
                self?.startupTimeout?.cancel()
            }
        }
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, !self.finished else { return }
                switch item.status {
                case .readyToPlay:
                    self.logger.info("Opening animation ready for playback")
                    self.player.play()
                case .failed:
                    self.logger.error("Opening animation failed, continuing to workspace")
                    self.finish()
                default: break
                }
            }
        }
        // A missing decoder or first frame must never trap the user at startup.
        let timeout = DispatchWorkItem { [weak self] in self?.finish() }
        startupTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
    }

    required init?(coder: NSCoder) { fatalError("Use init(onFinish:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop.frame = bounds
        poster.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        stop()
        onFinish()
    }

    func stop() {
        startupTimeout?.cancel()
        player.pause()
        statusObservation = nil
        displayObservation = nil
        notifications.forEach(NotificationCenter.default.removeObserver)
        notifications.removeAll()
    }

    deinit { stop() }
}
