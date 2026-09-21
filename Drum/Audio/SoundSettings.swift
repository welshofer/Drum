import Foundation

enum TerminalSound: String, CaseIterable, Codable, Sendable, Identifiable {
    case boot, bell, keyClick, flyback, hum
    var id: Self { self }
    var title: String {
        switch self {
        case .boot: "Boot tone"
        case .bell: "Terminal bell (BEL)"
        case .keyClick: "Key clicks"
        case .flyback: "CRT flyback whine"
        case .hum: "System hum"
        }
    }
    var isAmbient: Bool { self == .flyback || self == .hum }
}

struct SoundOption: Codable, Equatable, Sendable {
    var enabled = false
    var volume: Double = 0.3
}

/// Separate from CRT visuals: turning the shader off does not mute the terminal.
struct SoundSettings: Codable, Equatable, Sendable {
    var boot = SoundOption()
    var bell = SoundOption()
    var keyClick = SoundOption(volume: 0.25)
    var flyback = SoundOption(volume: 0.1)
    var hum = SoundOption(volume: 0.2)
    var mains: Mains = .hz60
    var flybackPitch: FlybackPitch = .hz15734

    enum Mains: Int, Codable, CaseIterable { case hz50 = 50, hz60 = 60 }
    enum FlybackPitch: Int, Codable, CaseIterable { case hz15625 = 15625, hz15734 = 15734 }

    subscript(sound: TerminalSound) -> SoundOption {
        get {
            switch sound {
            case .boot: boot
            case .bell: bell
            case .keyClick: keyClick
            case .flyback: flyback
            case .hum: hum
            }
        }
        set {
            switch sound {
            case .boot: boot = newValue
            case .bell: bell = newValue
            case .keyClick: keyClick = newValue
            case .flyback: flyback = newValue
            case .hum: hum = newValue
            }
        }
    }

    func gain(for sound: TerminalSound) -> Float {
        let volume = self[sound].volume
        return Float(volume.isFinite ? min(1, max(0, volume)) : 0)
    }

    private enum CodingKeys: CodingKey { case boot, bell, keyClick, flyback, hum, mains, flybackPitch }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        boot = try c.decodeIfPresent(SoundOption.self, forKey: .boot) ?? boot
        bell = try c.decodeIfPresent(SoundOption.self, forKey: .bell) ?? bell
        keyClick = try c.decodeIfPresent(SoundOption.self, forKey: .keyClick) ?? keyClick
        flyback = try c.decodeIfPresent(SoundOption.self, forKey: .flyback) ?? flyback
        hum = try c.decodeIfPresent(SoundOption.self, forKey: .hum) ?? hum
        mains = try c.decodeIfPresent(Mains.self, forKey: .mains) ?? mains
        flybackPitch = try c.decodeIfPresent(FlybackPitch.self, forKey: .flybackPitch) ?? flybackPitch
        for sound in TerminalSound.allCases {
            let volume = self[sound].volume
            self[sound].volume = volume.isFinite ? min(1, max(0, volume)) : 0
        }
    }
}
