#if os(iOS)
    import BackgroundTasks
    import HermesKit
    import SwiftUI
    import UIKit

    /// Keeps iPhone notifications going for as long as iOS allows. Leaving keeps the socket open for
    /// iOS's short grace period, so a quick look at another app comes back without reconnecting; a
    /// reply running holds it until it ends. After that the app can only ask to be woken, and iOS
    /// picks when.
    @MainActor
    @Observable
    final class BackgroundLink {
        /// Also listed in `Config/Info.plist`, or scheduling it fails.
        nonisolated static let checkInID = "labs.usual.UsualBot.check-in"

        /// Sooner is pointless: iOS treats this as the earliest, and usually waits far longer.
        private static let checkInterval: TimeInterval = 15 * 60
        /// iOS gives about 30 s, and ends the app if it overruns.
        private static let graceLimit: Duration = .seconds(25)
        /// How long the socket outlives leaving with nothing running: long enough for a quick
        /// trip to another app, short enough not to keep the radio up for nothing.
        private static let returnWindow: Duration = .seconds(20)

        /// How long a notification's wake may spend loading its chat. iOS gives about 30 s in all.
        private static let wakeLimit: Duration = .seconds(20)
        /// How long the link stays up after a notification woke the app, so tapping it soon finds the
        /// chat connected. Short: iOS wakes an app less often the more each wake costs.
        private static let wakeHold: Duration = .seconds(15)

        private let model: AppModel
        /// Stops what a suspended app can't keep, once the app has let go of the gateway.
        private let suspend: @MainActor () -> Void
        @ObservationIgnored private var hold: Task<Void, Never>?
        @ObservationIgnored private var grace = UIBackgroundTaskIdentifier.invalid
        /// Counts notification wakes, so only the latest closes the link they share.
        @ObservationIgnored private var wakes = 0

        init(model: AppModel, suspend: @escaping @MainActor () -> Void) {
            self.model = model
            self.suspend = suspend
        }

        func sceneChanged(to phase: ScenePhase) {
            guard phase == .background else {
                endHold()
                model.setForeground(true)
                return
            }
            // Now, not once a running reply lets the app go: a locked iPhone stops the write.
            model.drafts.save()
            scheduleCheckIn()
            guard hold == nil else { return }
            grace = UIApplication.shared.beginBackgroundTask { [weak self] in
                MainActor.assumeIsolated {
                    self?.endHold()
                    self?.letGo()
                }
            }
            hold = Task { [weak self, model] in
                let deadline = ContinuousClock.now + Self.graceLimit
                if !model.isWorking { try? await Task.sleep(for: Self.returnWindow) }
                // A reply that started meanwhile, a routine's say, gets what's left.
                await model.finishWork(within: deadline - .now)
                guard !Task.isCancelled else { return }
                self?.letGo()
                self?.endHold()
            }
        }

        /// iOS woke the app, which may have launched just for this.
        func checkIn() async {
            scheduleCheckIn()
            if UIApplication.shared.applicationState == .background { model.setForeground(false) }
            await model.checkIn()
            if UIApplication.shared.applicationState == .background { suspend() }
        }

        /// A notification woke the app (the relay's `wake`): loads its chat and holds the link a
        /// moment for the tap. Nothing to do while the app is on screen, or still holding the link
        /// after you left it, as the message comes over that.
        func woken(by news: PushRelay.News) async {
            guard UIApplication.shared.applicationState == .background, hold == nil else { return }
            wakes += 1
            let wake = wakes
            let start = ContinuousClock.now
            // Launched just for this, the model still thinks it's on screen.
            model.setForeground(false)
            await model.warmUp(news.chat, on: news.gateway, within: Self.wakeLimit)
            try? await Task.sleep(until: start + Self.wakeHold)
            // You came in, left again into `hold`, or a newer wake holds the link now.
            guard wake == wakes, hold == nil, UIApplication.shared.applicationState == .background else { return }
            if model.endWarmUp() { suspend() }
        }

        private func letGo() {
            model.setForeground(false)
            suspend()
        }

        private func endHold() {
            hold?.cancel()
            hold = nil
            guard grace != .invalid else { return }
            UIApplication.shared.endBackgroundTask(grace)
            grace = .invalid
        }

        private func scheduleCheckIn() {
            let request = BGAppRefreshTaskRequest(identifier: Self.checkInID)
            request.earliestBeginDate = Date(timeIntervalSinceNow: Self.checkInterval)
            try? BGTaskScheduler.shared.submit(request)
        }
    }
#endif
