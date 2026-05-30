import AppKit
import QuartzCore

struct ClipboardFeedbackEmission: Equatable {
    let soundEnabled: Bool
    let soundAssetLoaded: Bool
    let soundPlayed: Bool
    let animationEnabled: Bool
    let reduceMotionEnabled: Bool
    let statusButtonAvailable: Bool
    let animationStarted: Bool
}

@MainActor
final class ClipboardFeedbackController {
    private static let animationKey = "forkclip.copyFeedback.cushion"
    private let statusButtonProvider: () -> NSStatusBarButton?
    private var sound: NSSound?

    init(statusButtonProvider: @escaping () -> NSStatusBarButton?) {
        self.statusButtonProvider = statusButtonProvider
    }

    @discardableResult
    func emit(settings: AppSettings) -> ClipboardFeedbackEmission {
        var soundAssetLoaded = false
        var soundPlayed = false
        var statusButtonAvailable = false
        var animationStarted = false
        let reduceMotionEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if settings.copyFeedbackSoundEnabled {
            let soundResult = playSound()
            soundAssetLoaded = soundResult.assetLoaded
            soundPlayed = soundResult.played
        }

        if settings.copyFeedbackAnimationEnabled,
           !reduceMotionEnabled {
            let animationResult = animateStatusButton()
            statusButtonAvailable = animationResult.statusButtonAvailable
            animationStarted = animationResult.started
        }

        return ClipboardFeedbackEmission(
            soundEnabled: settings.copyFeedbackSoundEnabled,
            soundAssetLoaded: soundAssetLoaded,
            soundPlayed: soundPlayed,
            animationEnabled: settings.copyFeedbackAnimationEnabled,
            reduceMotionEnabled: reduceMotionEnabled,
            statusButtonAvailable: statusButtonAvailable,
            animationStarted: animationStarted
        )
    }

    private func playSound() -> (assetLoaded: Bool, played: Bool) {
        if sound == nil,
           let soundURL = Bundle.main.url(forResource: "ClipboardFeedbackClick", withExtension: "wav") {
            sound = NSSound(contentsOf: soundURL, byReference: false)
            sound?.volume = 0.42
        }

        guard let sound else {
            return (assetLoaded: false, played: false)
        }

        sound.stop()
        sound.currentTime = 0
        return (assetLoaded: true, played: sound.play())
    }

    private func animateStatusButton() -> (statusButtonAvailable: Bool, started: Bool) {
        guard let button = statusButtonProvider() else {
            return (statusButtonAvailable: false, started: false)
        }
        button.wantsLayer = true
        guard let layer = button.layer else {
            return (statusButtonAvailable: true, started: false)
        }

        layer.removeAnimation(forKey: Self.animationKey)

        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [1.0, 0.88, 1.07, 1.0]
        animation.keyTimes = [0, 0.32, 0.68, 1]
        animation.duration = 0.22
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut)
        ]
        animation.isRemovedOnCompletion = true

        layer.add(animation, forKey: Self.animationKey)
        return (statusButtonAvailable: true, started: true)
    }
}
