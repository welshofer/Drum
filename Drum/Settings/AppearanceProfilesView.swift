import SwiftUI
import UniformTypeIdentifiers

struct AppearanceProfilesView: View {
    @Environment(AppState.self) private var state
    @State private var selectedID = "factory.amber"
    @State private var name = ""
    @State private var importing = false
    @State private var exporting = false
    @State private var document: AppearanceProfileDocument?
    @State private var errorMessage: String?

    private var selected: AppearanceProfile? { state.appearanceProfiles.first { $0.id == selectedID } }

    var body: some View {
        Form {
            Section {
                Picker("Profile", selection: $selectedID) {
                    Section("Factory") {
                        ForEach(AppearanceProfile.factory) { Text($0.name).tag($0.id) }
                    }
                    Section("Saved") {
                        ForEach(state.userProfiles) { Text($0.name).tag($0.id) }
                    }
                }
                if let profile = selected {
                    Text("\(profile.appearance.font.title), \(profile.appearance.fontSize.formatted()) pt")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Apply Profile") { if let selected { state.apply(selected) } }
                        .disabled(selected == nil)
                    Button("Remove", role: .destructive) {
                        state.removeAppearance(id: selectedID)
                        selectedID = "factory.amber"
                    }
                    .disabled(!state.userProfiles.contains { $0.id == selectedID })
                }
            } header: { Text("Appearance profiles") } footer: {
                Text("Apply changes the font, colours, and tube effects. The shell keeps running. Changing font size reflows text and clears its selection.")
            }

            Section {
                TextField("Name", text: $name)
                Button("Save Current Appearance") {
                    perform {
                        selectedID = try state.saveAppearance(named: name).id
                        name = ""
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: { Text("Save a profile") } footer: {
                Text("Save the current Appearance settings, including your font size. Sound and shell settings stay separate.")
            }

            Section {
                HStack {
                    Button("Import JSON…") { importing = true }
                    Button("Export Selected…") {
                        perform {
                            guard let selected else { return }
                            document = try AppearanceProfileDocument(profile: selected)
                            exporting = true
                        }
                    }
                    .disabled(selected == nil)
                }
            } header: { Text("Share profiles") } footer: {
                Text("Import adds a saved profile. Choose Apply Profile to use it.")
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            perform {
                guard let url = try result.get().first else { return }
                selectedID = try state.importAppearance(AppearanceProfileDocument.read(from: url)).id
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "Drum Appearance") { result in
            if case .failure(let error) = result { showError(error) }
        }
        .alert("Profile Could Not Be Saved or Opened", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { showError(error) }
    }

    private func showError(_ error: any Error) {
        let cocoa = error as NSError
        guard cocoa.domain != NSCocoaErrorDomain || cocoa.code != NSUserCancelledError else { return }
        errorMessage = error.localizedDescription
    }
}
