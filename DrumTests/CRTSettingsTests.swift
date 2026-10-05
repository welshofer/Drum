import Testing
import Foundation
@testable import Drum

struct CRTSettingsTests {
    @Test func defaultsAreTheTunedValues() {
        let s = CRTSettings()
        #expect(s.phosphor == .p3Amber)
        #expect(s.barrelX == 0.02 && s.barrelY == 0.02)
        #expect(s.wobble == 0.0015)
        #expect(s.scanlines == 0.15)
        #expect(s.grille == 0.04)
        #expect(s.vignette == 0.25)
        #expect(s.brightness == 1.45)
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
        #expect(store.load(TerminalFontChoice.self, for: .font) == nil)
    }

    @Test func customAppearanceMigratesOnlyUntouchedLegacyTuning() throws {
        for key in ["drum.crt.v2", "drum.crt"] {
            let suite = "drum.tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = SettingsStore(defaults: defaults)
            var saved = CRTSettings()
            saved.phosphor = Phosphor(red: 0.12, green: 0.34, blue: 0.56,
                                      bloomRadius: 6, bloomStrength: 0.9)
            saved.barrelX = key == "drum.crt" ? 0.05 : 0.03
            saved.barrelY = 0.08 // A deliberate user edit.
            saved.scanlines = key == "drum.crt" ? 0.28 : 0.20
            saved.grille = key == "drum.crt" ? 0.08 : 0.06
            saved.vignette = 0.35
            saved.brightness = 1.25
            saved.enabled = false
            saved.animated = false
            defaults.set(try JSONEncoder().encode(saved), forKey: key)
            store.save(PhosphorPreset.custom, for: .preset)

            let appearance = store.loadAppearance()
            #expect(appearance.preset == .custom)
            #expect(appearance.crt.phosphor == saved.phosphor)
            #expect(appearance.crt.barrelX == CRTSettings().barrelX)
            #expect(appearance.crt.barrelY == saved.barrelY)
            #expect(appearance.crt.scanlines == CRTSettings().scanlines)
            #expect(appearance.crt.grille == CRTSettings().grille)
            #expect(appearance.crt.vignette == CRTSettings().vignette)
            #expect(appearance.crt.brightness == CRTSettings().brightness)
            #expect(!appearance.crt.enabled && !appearance.crt.animated)
            #expect(store.load(CRTSettings.self, for: .crt) == appearance.crt)
            // Once promoted, future launches prefer the current record.
            defaults.removeObject(forKey: key)
            #expect(store.loadAppearance().crt == appearance.crt)
        }
    }

    @Test func currentAppearanceKeepsTuningAndInfersMissingPreset() {
        let suite = "drum.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        var saved = CRTSettings()
        saved.phosphor = .p1Green
        saved.phosphor.bloomStrength = 0.2
        saved.barrelX = 0.03 // An old default deliberately saved in the current record.
        store.save(saved, for: .crt)
        #expect(store.loadAppearance().preset == .green)
        #expect(store.loadAppearance().crt == saved)
        saved.phosphor.red = 0.22
        store.save(saved, for: .crt)
        defaults.removeObject(forKey: "drum.preset")
        #expect(store.loadAppearance().preset == .custom)
        #expect(store.loadAppearance().crt == saved)
    }

    @Test func malformedTuningPreservesCustomColour() throws {
        let suite = "drum.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let phosphor = Phosphor(red: 0.2, green: 0.4, blue: 0.6,
                               bloomRadius: 5, bloomStrength: 0.3)
        let colour = String(decoding: try JSONEncoder().encode(phosphor), as: UTF8.self)
        defaults.set(Data("{\"phosphor\":\(colour),\"brightness\":\"invalid\"}".utf8), forKey: "drum.crt.v3")
        store.save(PhosphorPreset.custom, for: .preset)
        let appearance = store.loadAppearance()
        #expect(appearance.preset == .custom)
        #expect(appearance.crt.phosphor == phosphor)
        #expect(appearance.crt.brightness == CRTSettings().brightness)
    }
}
