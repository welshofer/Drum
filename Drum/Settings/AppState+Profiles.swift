import Foundation

extension AppState {
    var appearanceProfiles: [AppearanceProfile] { AppearanceProfile.factory + userProfiles }

    var currentAppearance: AppearanceConfiguration {
        let p = crt.phosphor
        let matches = preset.phosphor.map { $0.red == p.red && $0.green == p.green && $0.blue == p.blue } ?? true
        return .init(crt: crt, preset: matches ? preset : .custom, font: font, fontSize: fontSize)
    }

    func apply(_ profile: AppearanceProfile) {
        let appearance = profile.appearance
        crt = appearance.crt
        preset = appearance.preset
        font = appearance.font
        fontSize = appearance.fontSize
    }

    @discardableResult
    func saveAppearance(named name: String) throws -> AppearanceProfile {
        try addUserProfile(.init(id: UUID().uuidString, name: try ProfileValidation.name(name), appearance: currentAppearance))
    }

    @discardableResult
    func importAppearance(_ data: Data) throws -> AppearanceProfile {
        try addUserProfile(AppearanceProfileEnvelope.decode(data))
    }
}
