#if DEBUG
    import Foundation

    extension UsageOverview {
        /// Made-up usage for the demo's Bots: Forge codes most days, Ops runs nightly routines,
        /// Ledger works weekdays only. Each period is cut from the same 90 days, so the numbers
        /// agree when you switch.
        static func demo(agents: @escaping @MainActor () -> [Contact], now: Date) -> UsageOverview {
            UsageOverview(agents: agents, now: { now }) { profile, days in
                try await Task.sleep(for: .milliseconds(350))
                return DemoUsage.report(for: profile, days: days, now: now)
            }
        }
    }

    private enum DemoUsage {
        struct Habit {
            /// Tokens on a typical working day.
            let daily: Double
            let weekends: Bool
            /// Background work as a share of the Bot's own tokens.
            let jobs: [(String, Double)]
        }

        static let habits: [String: Habit] = [
            "forge": Habit(
                daily: 1_900_000, weekends: false,
                jobs: [
                    ("compression", 0.07), ("background_review", 0.04), ("approval", 0.012),
                    ("title_generation", 0.002),
                ]),
            "atlas": Habit(
                daily: 820_000, weekends: false,
                jobs: [("compression", 0.05), ("vision", 0.03), ("session_search", 0.02), ("title_generation", 0.002)]),
            "ops": Habit(
                daily: 380_000, weekends: true, jobs: [("background_review", 0.05), ("compression", 0.03)]),
            "scribe": Habit(daily: 260_000, weekends: false, jobs: [("vision", 0.02), ("title_generation", 0.004)]),
            "ledger": Habit(daily: 110_000, weekends: false, jobs: [("compression", 0.02)]),
        ]

        static func report(for profile: String, days: Int, now: Date) -> UsageReport {
            guard let habit = habits[profile] else { return UsageReport() }
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            var report = UsageReport()
            for back in 0..<days {
                guard let date = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
                if !habit.weekends, calendar.isDateInWeekend(date) { continue }
                // Today is only part-way through.
                let share = back == 0 ? 0.4 : 1.0
                let total = habit.daily * share * (0.45 + noise(profile, back))
                let written = Int(total * 0.11)
                let tokens = UsageReport.Tokens(
                    fresh: Int(total * 0.17), reused: Int(total * 0.72), written: written, thinking: written * 2 / 5)
                report.days.append(UsageReport.Day(date: date, tokens: tokens))
                report.main = report.main + tokens
            }
            report.days.sort { $0.date < $1.date }
            let main = Double(report.main.total)
            report.jobs = habit.jobs.map { name, share in
                UsageReport.BackgroundJob(
                    name: name, tokens: Int(main * share), calls: max(1, Int(main * share / 9_000)))
            }
            report.calls = report.main.total / 26_000
            // Hermes's estimate at a typical price list: cached reading is a tenth of fresh.
            let dollars =
                (Double(report.main.fresh) * 3 + Double(report.main.reused) * 0.3 + Double(report.main.written) * 15)
                / 1_000_000 + Double(report.jobs.reduce(0) { $0 + $1.tokens }) / 1_000_000
            report.cost = report.isEmpty ? nil : UsageReport.Cost(amount: dollars, isEstimate: true)
            return report
        }

        /// A steady 0…1 from the Bot and day, the same on every launch.
        private static func noise(_ profile: String, _ day: Int) -> Double {
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in "\(profile)-\(day)".utf8 {
                hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
            }
            return Double(hash % 1000) / 1000
        }
    }
#endif
