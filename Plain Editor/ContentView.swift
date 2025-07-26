import SwiftUI
import CodeEditor
import AppKit
import UniformTypeIdentifiers
import Combine

class FileItem: Identifiable, ObservableObject {
    let id = UUID()
    let name: String
    let url: URL
    let isDirectory: Bool
    weak var parent: FileItem?
    @Published var children: [FileItem]?
    @Published var isExpanded = false
    
    init(name: String, url: URL, isDirectory: Bool = false, parent: FileItem? = nil) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.parent = parent
    }
    
    func loadChildren() {
        guard isDirectory, children == nil else { return }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            children = fileURLs.map { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return FileItem(name: url.lastPathComponent, url: url, isDirectory: isDirectory, parent: self)
            }
        } catch {
            print("Error loading children: \(error)")
            children = []
        }
    }
}

class ContentViewModel: ObservableObject {
    @Published var source: String = ""
    @Published var currentFile: URL?
    @Published var isDocumentEdited = false
    
    func saveCurrentFile() {
        guard let fileURL = currentFile, isDocumentEdited else { return }
        
        do {
            try source.write(to: fileURL, atomically: true, encoding: .utf8)
            isDocumentEdited = false
        } catch {
            print("Failed to save file: \(error)")
        }
    }
    
    func loadFile(at url: URL) {
        do {
            source = try String(contentsOf: url, encoding: .utf8)
            currentFile = url
            isDocumentEdited = false
        } catch {
            print("Failed to read file: \(error)")
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @StateObject private var terminalManager = TerminalManager()
    @State private var terminalInput: String = ""
    @State private var isDocumentEdited = false
    @State private var isFilePanelOpen: Bool = false
    @State private var isTerminalPanelOpen: Bool = false
    @State private var terminalPanelHeight: CGFloat = 200
    @State private var panelWidth: CGFloat = 180
    @State private var isShowingFileImporter = false
    @State private var selectedFolder: URL?
    @State private var folderName: String = ""
    @State private var rootItem: FileItem?
    @State private var selectedItem: FileItem?
    
    private func loadFiles(from url: URL) {
        print("\n=== Loading files from: \(url.path) ===")
        let newRootItem = FileItem(name: url.lastPathComponent, url: url, isDirectory: true)
        rootItem = newRootItem
        folderName = url.lastPathComponent
        selectedItem = newRootItem
        newRootItem.loadChildren()
        print("=== Finished loading files ===\n")
    }

    var body: some View {
        ZStack {
            Color(hex: "#1E1E1E").ignoresSafeArea()
            
            HStack(spacing: 0) {
                // File panel with resizing
                if isFilePanelOpen {
                    ZStack(alignment: .topLeading) {
                        // Main content
                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                // Header
                                HStack {
                                    Text("Files")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    
                                    Button(action: {
                                        isShowingFileImporter = true
                                    }) {
                                        Image(systemName: "plus")
                                            .foregroundColor(.white)
                                            .imageScale(.medium)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .fileImporter(
                                        isPresented: $isShowingFileImporter,
                                        allowedContentTypes: [.folder],
                                        allowsMultipleSelection: false
                                    ) { result in
                                        do {
                                            let selectedURL = try result.get().first
                                            guard let url = selectedURL else { return }
                                            
                                            // Start accessing the security-scoped resource
                                            guard url.startAccessingSecurityScopedResource() else {
                                                print("Failed to access security scoped resource")
                                                return
                                            }
                                            
                                            // Store the bookmark for the URL
                                            let bookmarkData = try url.bookmarkData(
                                                options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil
                                            )
                                            
                                            // Save the bookmark to UserDefaults
                                            UserDefaults.standard.set(bookmarkData, forKey: "savedFolderBookmark")
                                            
                                            // Update the UI
                                            selectedFolder = url
                                            folderName = url.lastPathComponent
                                            loadFiles(from: url)
                                            
                                        } catch {
                                            print("Error selecting folder:", error.localizedDescription)
                                        }
                                    }
                                }
                                .padding()
                                .frame(width: panelWidth, height: 40)
                                .background(Color(hex: "#2D2D2D"))
                                
                                // File list
                                FilePanelView(selectedFolder: $selectedFolder, folderName: $folderName, rootItem: $rootItem, selectedItem: $selectedItem, viewModel: viewModel)
                                    .frame(width: panelWidth)
                            }
                            .frame(width: panelWidth)
                            
                            // Resize handle
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 2)
                                .onHover { isHovering in
                                    if isHovering {
                                        NSCursor.resizeLeftRight.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            let newWidth = panelWidth + value.translation.width
                                            let threshold: CGFloat = 100
                                            
                                            if newWidth < threshold {
                                                withAnimation {
                                                    isFilePanelOpen = false
                                                    panelWidth = 180
                                                }
                                            } else {
                                                panelWidth = min(300, newWidth)
                                            }
                                        }
                                )
                        }
                    }
                    .transition(.move(edge: .leading))
                }
                
                // Main editor area
                VStack(spacing: 0) {
                    CodeEditor(source: $viewModel.source, language: .swift, theme: .default)
                        .padding(.horizontal)
                        .padding(.top, 40)
                        .onChange(of: viewModel.source) {
                            viewModel.isDocumentEdited = true
                        }
                        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                            viewModel.saveCurrentFile()
                        }
                        .onAppear {
                            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                                if event.modifierFlags.contains(.command),
                                   let chars = event.charactersIgnoringModifiers,
                                   chars == "s" {
                                    viewModel.saveCurrentFile()
                                    return nil
                                }
                                return event
                            }
                        }

                    // Terminal Panel
                    if isTerminalPanelOpen {
                        VStack(spacing: 0) {
                            // Resize handle
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 4)
                                .gesture(
                                    DragGesture()
                                        .onChanged { gesture in
                                            let newHeight = max(100, min(500, terminalPanelHeight - gesture.translation.height))
                                            if newHeight != terminalPanelHeight {
                                                terminalPanelHeight = newHeight
                                            }
                                        }
                                )
                                .onHover { hovering in
                                    if hovering {
                                        NSCursor.resizeUpDown.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }
                            HStack {
                                Text("Terminal")
                                    .foregroundColor(.white)
                                    .padding(.leading, 8)
                                Spacer()
                                Button(action: {
                                    isTerminalPanelOpen = false
                                }) {
                                    Image(systemName: "xmark")
                                        .foregroundColor(.white)
                                        .padding(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .frame(height: 30)
                            .background(Color(hex: "#252526"))
                            
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                            
                            // Terminal output
                            ScrollViewReader { scrollView in
                                ScrollView {
                                    Text(terminalManager.output)
                                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .id("terminalOutput")
                                        .onChange(of: terminalManager.output) {
                                            withAnimation {
                                                scrollView.scrollTo("terminalOutput", anchor: .bottom)
                                            }
                                        }
                                }
                                .background(Color.black)
                            }
                            
                            // Terminal input
                            HStack(spacing: 4) {
                                Text("$")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: "#4CAF50"))
                                    .padding(.leading, 12)
                                TerminalInputView(text: $terminalInput, onCommit: sendTerminalCommand)
                                    .onAppear {
                                        // Focus the text field when the terminal panel opens
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            NSApp.keyWindow?.makeFirstResponder(NSApp.keyWindow?.contentView?.subviews.first { $0 is NSTextField })
                                        }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        NSApp.keyWindow?.makeFirstResponder(NSApp.keyWindow?.contentView?.subviews.first { $0 is NSTextField })
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color(hex: "#252526"))
                            .cornerRadius(6)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 4)
                        }
                        .frame(height: terminalPanelHeight)
                        .background(Color.black)
                        .padding(.bottom, 4)
                    }
                    
                    HStack {
                        // Left group
                        HStack(spacing: 24) {
                            Button("Files") {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    if isFilePanelOpen {
                                        isFilePanelOpen = false
                                    } else {
                                        panelWidth = 180 // Reset to default width
                                        isFilePanelOpen = true
                                    }
                                }
                            }
                            .foregroundColor(.white)
                            .buttonStyle(PlainButtonStyle())
                            
                            Text("Terminal")
                                .onTapGesture {
                                    isTerminalPanelOpen.toggle()
                                }
                            Text("Debug")
                        }
                        .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Right group
                        HStack(spacing: 24) {
                            Text("Run")
                            Text("Settings")
                            Text("AI Chat Bot")
                        }
                        .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color(hex: "#1E1E1E"))
                }
            }
        }
    }
    
    private func sendTerminalCommand() {
        terminalManager.sendCommand(terminalInput)
        terminalInput = ""
    }
    
    private struct TerminalInputView: NSViewRepresentable {
        @Binding var text: String
        var onCommit: () -> Void
        
        func makeNSView(context: Context) -> NSTextField {
            let textField = NSTextField()
            textField.delegate = context.coordinator
            textField.isBordered = false
            textField.isEditable = true
            textField.isSelectable = true
            textField.focusRingType = .none
            textField.backgroundColor = .clear
            textField.textColor = .white
            textField.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            
            DispatchQueue.main.async {
                textField.window?.makeFirstResponder(textField)
            }
            
            return textField
        }
        
        func updateNSView(_ nsView: NSTextField, context: Context) {
            if nsView.stringValue != text {
                nsView.stringValue = text
            }
        }
        
        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
        
        class Coordinator: NSObject, NSTextFieldDelegate {
            let parent: TerminalInputView
            private var isCommitting = false
            
            init(_ parent: TerminalInputView) {
                self.parent = parent
            }
            
            private func completePath(_ input: String) -> String? {
                let fileManager = FileManager.default
                let components = input.components(separatedBy: .whitespaces)
                let isCommand = components.count > 1 || input.hasSuffix(" ")
                
                // If it's a command with arguments, only complete the last part
                let pathToComplete: String
                let commandPart: String
                let currentDir: String
                
                if isCommand && components.count > 1 {
                    commandPart = components.dropLast().joined(separator: " ") + " "
                    pathToComplete = components.last ?? ""
                } else if isCommand {
                    commandPart = input
                    pathToComplete = ""
                } else {
                    commandPart = ""
                    pathToComplete = input
                }
                
                let currentPath = pathToComplete as NSString
                let isAbsolute = currentPath.isAbsolutePath
                let directory: String
                let prefix: String
                
                if isAbsolute {
                    directory = currentPath.deletingLastPathComponent
                    prefix = currentPath.lastPathComponent
                    currentDir = "/"
                } else {
                    currentDir = fileManager.currentDirectoryPath
                    if currentPath.length > 1 {
                        directory = (currentDir as NSString).appendingPathComponent(currentPath.deletingLastPathComponent)
                        prefix = currentPath.lastPathComponent
                    } else {
                        directory = currentDir
                        prefix = pathToComplete
                    }
                }
                
                guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else {
                    return nil
                }
                
                let matches = contents.filter { $0.hasPrefix(prefix) }
                    .sorted()
                
                if matches.isEmpty {
                    return nil
                } else if matches.count == 1 {
                    let match = matches[0]
                    let fullPath = (directory as NSString).appendingPathComponent(match)
                    var isDir: ObjCBool = false
                    _ = fileManager.fileExists(atPath: fullPath, isDirectory: &isDir)
                    let suffix = isDir.boolValue ? "/" : " "
                    
                    let completedPath: String
                    if isAbsolute {
                        completedPath = fullPath + suffix
                    } else {
                        let relativePath = (match as NSString).appendingPathComponent(suffix)
                        completedPath = (currentPath.deletingLastPathComponent as NSString).appendingPathComponent(relativePath)
                    }
                    
                    // If it was a command with arguments, prepend the command part back
                    if !commandPart.isEmpty {
                        return commandPart + completedPath
                    }
                    return completedPath
                } else {
                    var commonPrefix = matches[0]
                    for match in matches.dropFirst() {
                        commonPrefix = commonPrefix.commonPrefix(with: match)
                        if commonPrefix.isEmpty { break }
                    }
                    
                    if commonPrefix.count > prefix.count {
                        let fullPath = (directory as NSString).appendingPathComponent(commonPrefix)
                        let completedPath = isAbsolute ? 
                            fullPath : 
                            (currentPath.deletingLastPathComponent as NSString).appendingPathComponent(commonPrefix)
                        
                        // If it was a command with arguments, prepend the command part back
                        if !commandPart.isEmpty {
                            return commandPart + completedPath
                        }
                        return completedPath
                    }
                    
                    let matchesStr = matches.joined(separator: "\n")
                    DispatchQueue.main.async {
                        print("\n\(matchesStr)")
                    }
                    return nil
                }
            }
            
            func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
                if commandSelector == #selector(NSTextView.insertTab(_:)) {
                    if let textField = control as? NSTextField {
                        let currentText = textField.stringValue
                        if let completion = completePath(currentText) {
                            textField.stringValue = completion
                            parent.text = completion
                            return true
                        }
                    }
                    return true
                } else if commandSelector == #selector(NSTextView.insertNewline(_:)) {
                    isCommitting = true
                    parent.onCommit()
                    DispatchQueue.main.async {
                        self.parent.text = ""
                        (control as? NSTextField)?.stringValue = ""
                        self.isCommitting = false
                    }
                    return true
                }
                return false
            }
            
            func controlTextDidChange(_ obj: Notification) {
                if !isCommitting, let textField = obj.object as? NSTextField {
                    parent.text = textField.stringValue
                }
            }
        }
    }
}

// Custom TextField wrapper to handle appearance
struct CustomTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.focusRingType = .none
        textField.backgroundColor = .clear
        textField.textColor = .white
        textField.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        
        // Make the text field first responder when added
        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
        }
        
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: CustomTextField
        private var isCommitting = false
        private var lastCompletionPrefix: String = ""
        private var lastCompletionMatches: [String] = []
        private var lastCompletionIndex: Int = 0
        
        init(_ parent: CustomTextField) {
            self.parent = parent
        }
        
        private func completePath(_ input: String) -> String? {
            let fileManager = FileManager.default
            let currentPath = input as NSString
            let isAbsolute = currentPath.isAbsolutePath
            let directory: String
            let prefix: String
            
            // Get directory and prefix
            if isAbsolute {
                directory = currentPath.deletingLastPathComponent
                prefix = currentPath.lastPathComponent
            } else {
                let currentDir = fileManager.currentDirectoryPath
                if currentPath.length > 1 {
                    directory = (currentDir as NSString).appendingPathComponent(currentPath.deletingLastPathComponent)
                    prefix = currentPath.lastPathComponent
                } else {
                    directory = currentDir
                    prefix = input
                }
            }
            
            // Get directory contents
            guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else {
                return nil
            }
            
            // Filter and sort matches
            let matches = contents.filter { $0.hasPrefix(prefix) }
                .sorted()
            
            if matches.isEmpty {
                return nil
            } else if matches.count == 1 {
                let match = matches[0]
                let fullPath = (directory as NSString).appendingPathComponent(match)
                var isDir: ObjCBool = false
                _ = fileManager.fileExists(atPath: fullPath, isDirectory: &isDir)
                let suffix = isDir.boolValue ? "/" : " "
                
                if isAbsolute {
                    return fullPath + suffix
                } else {
                    let relativePath = (match as NSString).appendingPathComponent(suffix)
                    return (currentPath.deletingLastPathComponent as NSString).appendingPathComponent(relativePath)
                }
            } else {
                // Find common prefix
                var commonPrefix = matches[0]
                for match in matches.dropFirst() {
                    commonPrefix = commonPrefix.commonPrefix(with: match)
                    if commonPrefix.isEmpty { break }
                }
                
                // If common prefix is longer than current prefix, complete to it
                if commonPrefix.count > prefix.count {
                    let fullPath = (directory as NSString).appendingPathComponent(commonPrefix)
                    if isAbsolute {
                        return fullPath
                    } else {
                        return (currentPath.deletingLastPathComponent as NSString).appendingPathComponent(commonPrefix)
                    }
                }
                
                // Show all matches
                let matchesStr = matches.joined(separator: "\n")
                DispatchQueue.main.async {
                    print("\n\(matchesStr)")
                }
                return nil
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSTextView.insertTab(_:)) {
                if let textField = control as? NSTextField {
                    let currentText = textField.stringValue
                    if let completion = completePath(currentText) {
                        textField.stringValue = completion
                        parent.text = completion
                        return true
                    }
                }
                return true
            } else if commandSelector == #selector(NSTextView.insertNewline(_:)) {
                isCommitting = true
                parent.onCommit()
                DispatchQueue.main.async {
                    self.parent.text = ""
                    (control as? NSTextField)?.stringValue = ""
                    self.isCommitting = false
                }
                return true
            }
            return false
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if !isCommitting, let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
    }
}

struct FilePanelView: View {
    @Binding var selectedFolder: URL?
    @Binding var folderName: String
    @Binding var rootItem: FileItem?
    @Binding var selectedItem: FileItem?
    @State private var isShowingFileImporter = false
    @ObservedObject var viewModel: ContentViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
// Header is now in the parent view
            
            // File browser
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let rootItem = rootItem {
                        FileItemView(item: rootItem, selectedItem: $selectedItem, level: 0, viewModel: viewModel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer()
                            .frame(height: 125)
                        Text("No folder selected")
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .center)
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: "#1E1E1E"))
        }
        .background(Color(hex: "#1E1E1E"))
        .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
    }
    

    
    private struct FileItemView: View {
        @ObservedObject var item: FileItem
        @Binding var selectedItem: FileItem?
        let level: Int
        @State private var isHovered = false
        @State private var showingNewFileAlert = false
        @State private var showingNewFolderAlert = false
        @State private var newItemName = ""
        
        @ObservedObject var viewModel: ContentViewModel
        
        private func createNewFile() {
            guard !newItemName.isEmpty else { return }
            let fileURL = item.url.appendingPathComponent(newItemName)
            
            do {
                try "".write(to: fileURL, atomically: true, encoding: .utf8)
                let newFile = FileItem(name: newItemName, url: fileURL, isDirectory: false)
                if item.children == nil {
                    item.children = []
                }
                item.children?.append(newFile)
                item.children?.sort { $0.name < $1.name }
                newItemName = ""
            } catch {
                print("Failed to create file: \(error)")
            }
        }
        
        private func iconName(for url: URL, isDirectory: Bool) -> String {
            guard !isDirectory else { return "folder.fill" }
            
            let ext = url.pathExtension.lowercased()
            
            // Programming files
            if ["swift", "py", "js", "jsx", "ts", "tsx", "java", "c", "cpp", "h", "hpp", "m", "mm", "rb", "go", "rs", "kt", "dart"].contains(ext) {
                return "chevron.left.slash.chevron.right" // Code icon
            } 
            // Note files
            else if ["md", "markdown", "txt", "rtf", "rtfd", "pages"].contains(ext) {
                return "note.text" // Note icon
            }
            // Image files
            else if ["jpg", "jpeg", "png", "gif", "heic", "tiff", "bmp", "webp"].contains(ext) {
                return "photo" // Photo icon
            }
            // Default document icon
            return "doc.text"
        }
        
        private func iconColor(for url: URL, isDirectory: Bool) -> Color {
            if isDirectory { return .gray }
            
            let ext = url.pathExtension.lowercased()
            
            // Programming files
            if ["swift", "py", "js", "jsx", "ts", "tsx", "java", "c", "cpp", "h", "hpp", "m", "mm", "rb", "go", "rs", "kt", "dart"].contains(ext) {
                return .blue
            } 
            // Note files
            else if ["md", "markdown", "txt", "rtf", "rtfd", "pages"].contains(ext) {
                return .yellow
            }
            // Image files
            else if ["jpg", "jpeg", "png", "gif", "heic", "tiff", "bmp", "webp"].contains(ext) {
                return .green
            }
            // Default color
            return .white
        }
        
        private func createNewFolder() {
            guard !newItemName.isEmpty else { return }
            let folderURL = item.url.appendingPathComponent(newItemName, isDirectory: true)
            
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                let newFolder = FileItem(name: newItemName, url: folderURL, isDirectory: true)
                if item.children == nil {
                    item.children = []
                }
                item.children?.append(newFolder)
                item.children?.sort { $0.name < $1.name }
                item.isExpanded = true
                newItemName = ""
            } catch {
                print("Failed to create folder: \(error)")
            }
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    // Chevron for folders
                    if item.isDirectory {
                        Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    item.isExpanded.toggle()
                                    if item.isExpanded && item.children == nil {
                                        item.loadChildren()
                                    }
                                }
                            }
                    } else {
                        Spacer().frame(width: 20, height: 20)
                    }
                    
                    // File/Folder icon
                    Image(systemName: iconName(for: item.url, isDirectory: item.isDirectory))
                        .foregroundColor(iconColor(for: item.url, isDirectory: item.isDirectory))
                        .frame(width: 16, height: 16)
                    
                    // Name
                    Text(item.name)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                    
                    Spacer()
                }
                .padding(.leading, CGFloat(level * 16) + 8)
                .padding(.trailing, 8) // Add right padding to prevent highlight from extending beyond panel
                .padding(.vertical, 4)
                .background(
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
                            .frame(width: geometry.size.width - (CGFloat(level * 16) + 8) - 8) // Adjust width to account for padding
                            .offset(x: -8) // Align with the text
                    }
                )
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovered = hovering
                }
                .onTapGesture {
                    selectedItem = item
                    if item.isDirectory {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            item.isExpanded.toggle()
                            if item.isExpanded && item.children == nil {
                                item.loadChildren()
                            }
                        }
                    } else {
                        // Handle file selection
                        viewModel.loadFile(at: item.url)
                        selectedItem = item
                    }
                }
                .contextMenu {
                    Button(action: {
                        newItemName = ""
                        showingNewFileAlert = true
                    }) { Label("New File", systemImage: "doc") }

                    Button(action: {
                        newItemName = ""
                        showingNewFolderAlert = true
                    }) { Label("New Folder", systemImage: "folder.badge.plus") }
                    Divider()
                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }) { Label("Reveal in Finder", systemImage: "folder") }
                    Divider()
                    Button(action: {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(item.url.path, forType: .string)
                    }) { Label("Copy", systemImage: "doc.on.doc") }
                    Button(action: {
                        if let items = NSPasteboard.general.readObjects(forClasses: [NSString.self]) as? [String],
                           let path = items.first {
                            let sourceURL = URL(fileURLWithPath: path)
                            let destinationURL = item.url.appendingPathComponent(sourceURL.lastPathComponent)
                            try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                            item.loadChildren()
                        }
                    }) { Label("Paste", systemImage: "doc.on.clipboard") }
                    Divider()
                    Button(role: .destructive, action: {
                        do {
                            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                            if let parent = item.parent {
                                parent.children?.removeAll { $0.id == item.id }
                                parent.objectWillChange.send()
                            }
                        } catch {
                            print("Failed to delete item: \(error)")
                        }
                    }) { Label("Delete", systemImage: "trash.slash") }
                }
                .alert("New File", isPresented: $showingNewFileAlert, actions: {
                    TextField("File name", text: $newItemName)
                    Button("Create", action: createNewFile)
                    Button("Cancel", role: .cancel) {}
                }, message: {
                    Text("Enter file name:")
                })
                .alert("New Folder", isPresented: $showingNewFolderAlert, actions: {
                    TextField("Folder name", text: $newItemName)
                    Button("Create", action: createNewFolder)
                    Button("Cancel", role: .cancel) {}
                }, message: {
                    Text("Enter folder name:")
                })
                
                // Child items
                if item.isExpanded, let children = item.children, !children.isEmpty {
                    ForEach(children, id: \.id) { child in
                        FileItemView(item: child, selectedItem: $selectedItem, level: level + 1, viewModel: viewModel)
                    }
                }
            }
        }
    }
    

}

#Preview {
    ContentView()
        .environmentObject(ContentViewModel())
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
