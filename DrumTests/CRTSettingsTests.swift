import Testing
import Foundation
@testable import Drum

struct CRTSettingsTests {
    @Test func defaultsAreTheTunedValues() {
        let s = CRTSettings()
        #expect(s.phosphor == .p3Amber)
        #expect(s.barrelX == 0.03 && s.barrelY == 0.03)
        #expect(s.wobble == 0.0015)
        #expect(s.scanlines == 0.20)
        #expect(s.grille == 0.06)
        #expect(s.vignette == 0.35)
        #expect(s.brightness == 1.25)
        #expect(s.scale == 1)
        #expect(s.animated)
    }

    @Test func decodingToleratesMissingKeys() throws {
        let json = #"{"barrelX":0.09,"scanlines":0.1}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(CRTSettings.self, from: json)
        #expect(s.barrelX == 0.09)
        #expect(s.scanlines == 0.1)
        #expect(s.brightness == CRTSettings().brightness)
        #expect(s.phosphor == .p3Amber)
    }

    @Test func ribbonTuningCurvesLessHorizontally() {
        let r = CRTSettings.ribbon
        #expect(r.barrelX < r.barrelY)
    }

    @Test func roundTripsThroughJSON() throws {
        var s = CRTSettings()
        s.phosphor = .p1Green
        s.wobble = 0.004
        s.enabled = false
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(CRTSettings.self, from: data)
        #expect(back == s)
    }

    @Test func presetsResolveToPhosphors() {
        #expect(PhosphorPreset.amber.phosphor == .p3Amber)
        #expect(PhosphorPreset.green.phosphor == .p1Green)
        #expect(PhosphorPreset.white.phosphor == .p4White)
        #expect(PhosphorPreset.custom.phosphor == nil)
    }

    @Test func settingsStoreRoundTrips() {
        let suite = "drum.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        store.save(PhosphorPreset.green, for: .preset)
        store.save(24.0, for: .fontSize)
        #expect(store.load(PhosphorPreset.self, for: .preset) == .green)
        #expect(store.load(Double.self, for: .fontSize) == 24.0)
        #expect(store.load(String?.self, for: .pinnedScreen) == nil)
    }
}
