enum TerminalColourMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case monochrome
    case preserveColours

    var id: String { rawValue }
    var title: String {
        switch self {
        case .monochrome: "Monochrome phosphor"
        case .preserveColours: "Preserve colours"
        }
    }
}
