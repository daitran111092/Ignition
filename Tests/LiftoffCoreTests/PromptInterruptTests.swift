import Testing
import Foundation
@testable import LiftoffCore

/// Auto-detection cuts the step's prompt line, and nothing else.
@Suite struct PromptInterruptTests {
    let display = DeviceSignature(kind: .display, name: "LG UltraFine")
    let k7 = DeviceSignature(kind: .audioOutput, name: "FiiO K7")
    let agentFactory = RunningApp(bundleID: nil, name: "Agent Factory")
    let teams = RunningApp(bundleID: "com.microsoft.teams2", name: "Microsoft Teams")

    @Test func tickDuringThePromptInterruptsIt() {
        var s = RunSession(config: .default, resumeAt: ix(.cables))
        _ = s.start(SystemSnapshot())
        s.lineStarted(LineKey(step: .cables, kind: .prompt))
        let commands = s.handle(.snapshot(SystemSnapshot(devices: [display])))
        #expect(RunSession.tickedStep(in: commands) == ix(.cables))
        #expect(s.interruptsSpokenPrompt(commands))
    }

    @Test func appActivationDuringThePromptInterruptsIt() {
        var s = RunSession(config: .default, resumeAt: ix(.teams))
        _ = s.start(SystemSnapshot())
        s.lineStarted(LineKey(step: .teams, kind: .prompt))
        #expect(s.interruptsSpokenPrompt(s.handle(.appActivated(teams))))
    }

    @Test func tickDuringThePreviousStepsConfirmLineDoesNotInterrupt() {
        var s = RunSession(config: .default, resumeAt: ix(.dac))
        _ = s.start(SystemSnapshot())
        s.lineStarted(LineKey(step: .dac, kind: .prompt))
        _ = s.handle(.snapshot(SystemSnapshot(devices: [k7])))
        s.lineEnded()
        s.lineStarted(LineKey(step: .dac, kind: .confirm))
        _ = s.advance()  // Agent Factory is next; its prompt hasn't started yet
        let commands = s.handle(.snapshot(SystemSnapshot(devices: [k7], runningApps: [agentFactory])))
        #expect(RunSession.tickedStep(in: commands) == ix(.agentFactory))
        #expect(!s.interruptsSpokenPrompt(commands))
    }

    @Test func greetingIsNeverCut() {
        var s = RunSession(config: .default, resumeAt: ix(.cables))
        _ = s.start(SystemSnapshot())
        s.lineStarted(LineKey(step: nil, kind: .greetingResume))
        #expect(!s.interruptsSpokenPrompt(s.handle(.snapshot(SystemSnapshot(devices: [display])))))
    }

    @Test func noLineOrNoTickMeansNoInterrupt() {
        var s = RunSession(config: .default, resumeAt: ix(.cables))
        _ = s.start(SystemSnapshot())
        s.lineStarted(LineKey(step: .cables, kind: .prompt))
        #expect(!s.interruptsSpokenPrompt(s.handle(.snapshot(SystemSnapshot()))))
        s.lineEnded()
        #expect(!s.interruptsSpokenPrompt(s.handle(.snapshot(SystemSnapshot(devices: [display])))))
    }

    @Test func appStepsOfferAnOpenButton() {
        let steps = LiftoffConfig.default.steps
        #expect(appLaunchTarget(for: steps[ix(.teams)])?.buttonTitle == "Open Teams")
        #expect(appLaunchTarget(for: steps[ix(.music)])?.buttonTitle == "Open Apple Music")
        #expect(appLaunchTarget(for: steps[ix(.music)])?.bundleIDs == ["com.apple.Music"])
        let af = appLaunchTarget(for: steps[ix(.agentFactory)])
        #expect(af?.buttonTitle == "Open Agent Factory")
        #expect(af?.candidatePaths(home: "/Users/x").first == "/Users/x/Applications/Agent Factory.app")
        #expect(appLaunchTarget(for: steps[ix(.cables)]) == nil)
        #expect(appLaunchTarget(for: steps[ix(.water)]) == nil)
    }
}
