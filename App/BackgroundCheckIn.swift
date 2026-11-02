#if os(iOS)
    import BackgroundTasks
    import HermesKit
    import SwiftUI
    import UIKit

    /// Keeps iPhone notifications going for as long as iOS allows. A reply running when you leave
    /// keeps the socket open for iOS's short grace period; after that the app can only ask to be
    /// woken, and iOS picks when.
    @MainActor
    @Observable
    final class BackgroundLink {
        /// Also listed in `Config/Info.plist`, or scheduling it fails.
        nonisolated static let checkInID = "labs.usual.UsualBot.check-in"

        /// Sooner is pointless: iOS treats this as the earliest, and usually waits far longer.
        private static let checkInterval: TimeInterval = 15 * 60
        /// iOS gives about 30 s, and ends the app if it overruns.
        private static let graceLimit: Duration = .seconds(25)

        private let model: AppModel
        @ObservationIgnored private var hold: Task<Void, Never>?
        @ObservationIgnored private var grace = UIBackgroundTaskIdentifier.invalid

        init(model: AppModel) {
            self.model = model
        }

        func sceneChanged(to phase: ScenePhase) {
            guard phase == .background else {
                endHold()
                model.setForeground(true)
                return
            }
            scheduleCheckIn()
            guard model.isWorking else {
                model.setForeground(false)
                return
            }
            grace = UIApplication.shared.beginBackgroundTask { [weak self] in
                MainActor.assumeIsolated {
                    self?.endHold()
                    self?.model.setForeground(false)
                }
            }
            hold = Task { [weak self, model] in
                await model.finishWork(within: Self.graceLimit)
                guard !Task.isCancelled else { return }
                model.setForeground(false)
                self?.endHold()
            }
        }

        /// iOS woke the app, which may have launched just for this.
        func checkIn() async {
            scheduleCheckIn()
            if UIApplication.shared.applicationState == .background { model.setForeground(false) }
            await model.checkIn()
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
