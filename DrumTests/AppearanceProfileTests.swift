import Foundation
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct AppearanceProfileTests {
    @Test func savedAppearanceRoundTripsAndAppliesWithoutChangingSound() throws {
        let suite = "drum.profiles.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        defer { state.terminal.shutdown() }
        state.preset = .custom
        state.crt.phosphor.red = 0.13
        state.crt.phosphor.bloomRadius = 6.5
        state.crt.barrelX = 0.13
        state.crt.animated = false
        state.crt.enabled = false
        state.crt.colourMode = .preserveColours
        state.font = .ibmVGA
        state.fontSize = 27
        let appearance = state.currentAppearance
        let profile = try state.saveAppearance(named: "  My Tube  ")
        #expect(profile.name == "My Tube")
        let data = try AppearanceProfileEnvelope(profile: profile).encoded()
        let envelope = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let encodedAppearance = envelope["appearance"] as! [String: Any]
        let encodedCRT = encodedAppearance["crt"] as! [String: Any]
        #expect(encodedCRT["scale"] == nil)
        let imported = try state.importAppearance(data)
        #expect(imported.id != profile.id)
        #expect(imported.appearance == appearance)
        let restored = AppState(defaults: defaults)
        defer { restored.terminal.shutdown() }
        #expect(restored.userProfiles == state.userProfiles)
        let sound = state.sound
        let view = state.terminal.view
        let terminal = view.getTerminal()
        state.apply(AppearanceProfile.factory[0])
        state.apply(imported)
        #expect(state.currentAppearance == appearance)
        #expect(state.sound == sound)
        #expect(state.terminal.view === view && view.getTerminal() === terminal)
    }

    @Test func importRejectsInvalidDocumentsWithoutPartialMutation() throws {
        let suite = "drum.profiles.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        defer { state.terminal.shutdown() }
        let original = state.currentAppearance
        let data = try AppearanceProfileEnvelope(profile: AppearanceProfile.factory[0]).encoded()
        let malformed: [Data] = [
            Data("{}".utf8), Data(repeating: 32, count: AppearanceProfile.maximumFileBytes + 1),
            try changed(data) { $0["version"] = 99 },
            try changed(data) { $0["name"] = "bad\nname" },
            try changedAppearance(data) { $0["fontSize"] = 100 },
            try changedCRT(data) { $0["brightness"] = "bright" },
            try changedCRT(data) { $0["barrelX"] = 0.151 },
            try changedCRT(data) { $0["enabled"] = 1 },
            try changedCRT(data) { $0["scanlines"] = nil },
            try changedCRT(data) { $0["colourMode"] = "unknown" },
            try changedCRT(data) {
                var p = $0["phosphor"] as! [String: Any]
                p["red"] = "red"
                $0["phosphor"] = p
            }
        ]
        for invalid in malformed {
            #expect(throws: ProfileError.self) { try state.importAppearance(invalid) }
            #expect(state.userProfiles.isEmpty)
            #expect(state.currentAppearance == original)
        }
    }

    @Test func unknownFontFallsBackAndRuntimeScaleIsExcluded() throws {
        let data = try AppearanceProfileEnvelope(profile: AppearanceProfile.factory[0]).encoded()
        let changed = try changedAppearance(data) { $0["font"] = "a-font-this-machine-does-not-have" }
        let imported = try AppearanceProfileEnvelope.decode(changed)
        #expect(imported.appearance.font == .system)
        #expect(imported.appearance.fontSize == 20)
        var crt = CRTSettings()
        crt.scale = 3
        let configuration = AppearanceConfiguration(crt: crt, preset: .amber, font: .system, fontSize: 14)
        #expect(configuration.crt.scale == 1)
    }

    @Test func everySliderUpperBoundCanBeShared() throws {
        var crt = CRTSettings()
        crt.barrelX = 0.15; crt.barrelY = 0.15; crt.wobble = 0.01
        crt.scanlines = 0.5; crt.grille = 0.3; crt.vignette = 1.5
        crt.brightness = 2; crt.bezelCornerRadius = 120
        crt.phosphor.bloomRadius = 8; crt.phosphor.bloomStrength = 2
        let profile = AppearanceProfile(id: "test", name: "Bounds", appearance: .init(
            crt: crt, preset: .amber, font: .system, fontSize: 48))
        let data = try AppearanceProfileEnvelope(profile: profile).encoded()
        #expect(try AppearanceProfileEnvelope.decode(data).appearance == profile.appearance)
    }

    @Test func userProfileLimitAndFactoryProtection() throws {
        let suite = "drum.profiles.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        defer { state.terminal.shutdown() }
        for index in 0..<AppearanceProfile.maximumCount { try state.saveAppearance(named: "Profile \(index)") }
        #expect(throws: ProfileError.self) { try state.saveAppearance(named: "One too many") }
        state.removeAppearance(id: "factory.amber")
        #expect(state.appearanceProfiles.count == AppearanceProfile.maximumCount + AppearanceProfile.factory.count)
        state.removeAppearance(id: state.userProfiles[0].id)
        try state.saveAppearance(named: "Replacement")
        #expect(state.userProfiles.count == AppearanceProfile.maximumCount)
        #expect(throws: ProfileError.self) { try state.saveAppearance(named: String(repeating: "a", count: 65)) }
    }

    @Test func selectedLargeFileIsRejectedByBoundedReader() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("drum-profile-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data().write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 200_000_000)
        try handle.close()
        #expect(throws: ProfileError.self) { try AppearanceProfileDocument.read(from: url) }
    }

    private func changed(_ data: Data, edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func changedAppearance(_ data: Data, edit: (inout [String: Any]) -> Void) throws -> Data {
        try changed(data) {
            var appearance = $0["appearance"] as! [String: Any]
            edit(&appearance)
            $0["appearance"] = appearance
        }
    }

    private func changedCRT(_ data: Data, edit: (inout [String: Any]) -> Void) throws -> Data {
        try changedAppearance(data) {
            var crt = $0["crt"] as! [String: Any]
            edit(&crt)
            $0["crt"] = crt
        }
    }
}
