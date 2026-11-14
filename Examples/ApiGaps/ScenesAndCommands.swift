import SwiftUI
import UniformTypeIdentifiers

// macOS scenes, commands, window modifiers, Digital Crown and pasteboard input: all accepted, none drawn.
// The preview renders the main window's content; `inspector` shows as the sheet it is on iPhone.

final class Selection: ObservableObject {
    @Published var name = "Notes"
}

struct NotesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text = ""
    init() {}
    init(configuration: ReadConfiguration) throws {}
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

struct NotesApp: App {
    var body: some Scene {
        WindowGroup {
            ScenesContent()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 900, height: 600)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) { Button("Preferences…") {} }
            CommandGroup(after: .newItem) { Button("New From Clipboard") {}.keyboardShortcut("n", modifiers: [.command, .shift]) }
            CommandGroup(before: .help) { Divider() }
            CommandMenu("Format") { Button("Bold") {}.keyboardShortcut("b") }
            SidebarCommands()
            TextEditingCommands()
        }
        .backgroundTask(.appRefresh("refresh")) { }

        WindowGroup("Note", id: "note", for: String.self) { $id in
            Text(id)
        } defaultValue: { "new" }

        Window("Activity", id: "activity") { Text("Activity") }
            .keyboardShortcut("0")
        UtilityWindow("Inspector", id: "inspector") { Text("Details") }
        MenuBarExtra("Notes", systemImage: "note.text") { Button("Quit") {} }
            .menuBarExtraStyle(.window)
        Settings { Text("Settings") }
        DocumentGroup(newDocument: NotesDocument()) { file in Text(file.document.text) }
    }
}

struct ScenesContent: View {
    @StateObject private var selection = Selection()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var crown = 0.0
    @State private var showsInspector = true

    var body: some View {
        List {
            Text(selection.name)
                .digitalCrownRotation($crown, from: 0, through: 10, by: 1, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                .digitalCrownAccessory(.hidden)
                .itemProvider { NSItemProvider() }
                .onCopyCommand { [NSItemProvider()] }
                .onPasteCommand(of: [.plainText]) { _ in }
                .onDeleteCommand { }
                .copyable(["Notes"])
                .pointerStyle(.link)
            Button("Open note") { openWindow(id: "note", value: "a") }
            Button("Settings") { openSettings() }
        }
        .focusedSceneObject(selection)
        .navigationDocument(URL(string: "file:///notes.txt")!)
        .windowResizeBehavior(.enabled)
        .inspector(isPresented: $showsInspector) {
            Text("Inspector").inspectorColumnWidth(min: 200, ideal: 250, max: 300)
        }
    }
}

#Preview("Scenes and commands") {
    ScenesContent()
}
