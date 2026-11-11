import HermesKit
import Testing

@testable import UsualUI

/// What the goal bar says and offers in each state.
struct GoalBarTests {
    private let goal = Goal(
        text: "Write the weekly report", turnsUsed: 3, turnsAllowed: 20, criteria: ["Cite sources"],
        lastCheck: "Two sections left.")

    @Test func eachStateOffersItsOwnWayOut() {
        // Never plain "Stop": that's the message box's, for one reply.
        #expect(GoalWording.mainAction(for: .working).label == "Stop Goal")
        #expect(GoalWording.actions(for: .working) == [.stop])
        #expect(GoalWording.actions(for: .waiting) == [.stop])
        #expect(GoalWording.actions(for: .notRunning) == [.carryOn, .clear])
        #expect(GoalWording.actions(for: .stopped) == [.carryOn, .clear])
        #expect(GoalWording.actions(for: .done) == [.clear])
    }

    @Test func theDetailsSayHowItStandsAndWhy() {
        #expect(
            GoalWording.details(goal, .working, agent: "Scout", offline: false) == [
                "Scout keeps working on this by itself. After each reply, Hermes checks whether it's done.",
                "3 of 20 turns used", "Last check: Two sections left.", "Also has to hold: Cite sources",
            ])
        var stopped = goal
        stopped.status = .paused
        stopped.turnsUsed = 20
        #expect(GoalWording.details(stopped, .stopped, agent: "Scout", offline: true).first == "Stopped by you.")
        #expect(
            GoalWording.details(stopped, .stopped, agent: "Scout", offline: true).last
                == "You're offline, so this is how it stood when last seen.")
        var done = goal
        done.status = .done
        done.lastCheck = "The report has every section."
        #expect(
            GoalWording.details(done, .done, agent: "Scout", offline: false) == [
                "Hermes judged it done: The report has every section.", "Also has to hold: Cite sources",
            ])
    }

    @Test func voiceOverHearsTheStateTheGoalAndHowFar() {
        #expect(
            GoalWording.spoken(goal, .working, offline: false) == "Goal: Write the weekly report. 3 of 20 turns used")
        #expect(GoalWording.spoken(goal, .stopped, offline: false) == "Goal stopped: Write the weekly report")
    }
}
