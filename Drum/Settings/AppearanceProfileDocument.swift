import SwiftUI
import UniformTypeIdentifiers

struct AppearanceProfileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(profile: AppearanceProfile) throws {
        data = try AppearanceProfileEnvelope(profile: profile).encoded()
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw ProfileError.invalidAppearance }
        _ = try AppearanceProfileEnvelope.decode(data)
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    /// Read no more than the bound plus one byte, even for a huge selected file.
    static func read(from url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ProfileError.invalidAppearance }
        if let size = values.fileSize, size > AppearanceProfile.maximumFileBytes { throw ProfileError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: AppearanceProfile.maximumFileBytes + 1) ?? Data()
        guard data.count <= AppearanceProfile.maximumFileBytes else { throw ProfileError.tooLarge }
        return data
    }
}
