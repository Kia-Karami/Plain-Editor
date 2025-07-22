import SwiftUI
import CodeEditor
import AppKit

struct ContentView: View {
    @State private var source: String = "import SwiftUI\n\nstruct MyView: View {\n    var body: some View {\n        Text(\"Hello, World!\")\n    }\n}"
    @State private var isFilePanelOpen: Bool = false
    @State private var panelWidth: CGFloat = 180

    var body: some View {
        ZStack {
            Color(hex: "#1E1E1E").ignoresSafeArea()
            
            HStack(spacing: 0) {
                // File panel with resizing
                if isFilePanelOpen {
                    HStack(spacing: 0) {
                        FilePanelView()
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
                                        panelWidth = max(120, min(400, newWidth))
                                    }
                            )
                    }
                    .frame(width: panelWidth)
                    .transition(.move(edge: .leading))
                }
                
                // Main editor area
                VStack(spacing: 0) {
                    CodeEditor(source: $source, language: .swift, theme: .default)
                        .padding(.horizontal)
                        .padding(.top, 40)

                    HStack {
                        // Left group
                        HStack(spacing: 24) {
                            Button("Files") {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isFilePanelOpen.toggle()
                                }
                            }
                            .foregroundColor(.white)
                            .buttonStyle(PlainButtonStyle())
                            
                            Text("Terminal")
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
}

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isFolder: Bool
    var children: [FileItem]? = nil
}

class FileManagerService: ObservableObject {
    @Published var currentDirectory: URL?
    @Published var fileItems: [FileItem] = []
    
    func loadFiles(at url: URL) {
        currentDirectory = url
        fileItems = getFilesInDirectory(url: url)
    }
    
    private func getFilesInDirectory(url: URL) -> [FileItem] {
        let fileManager = FileManager.default
        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            return contents.map { url in
                var isDir: ObjCBool = false
                fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
                return FileItem(
                    name: url.lastPathComponent,
                    path: url.path,
                    isFolder: isDir.boolValue,
                    children: isDir.boolValue ? getFilesInDirectory(url: url) : nil
                )
            }.sorted { $0.name < $1.name }
        } catch {
            print("Error reading directory: \(error)")
            return []
        }
    }
}

struct FilePanelView: View {
    @StateObject private var fileManager = FileManagerService()
    @State private var selectedFile: FileItem?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Files")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding()
            .background(Color(hex: "#2D2D2D"))
            
            // VS Code-like file explorer
            VStack(spacing: 0) {
                // Toolbar with buttons
                HStack {
                    Button(action: {}) {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.medium)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                    
                    Button(action: {}) {
                        Image(systemName: "plus")
                            .imageScale(.medium)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                
                // Current path
                if let currentDir = fileManager.currentDirectory {
                    Text(currentDir.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                
                // File list with outline style
                List(fileManager.fileItems, children: \.children, rowContent: { item in
                    FileItemView(item: item, fileManager: fileManager)
                })
                .listStyle(PlainListStyle())
                .background(Color(NSColor.windowBackgroundColor))
            }
            .onAppear {
                if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    fileManager.loadFiles(at: documentsPath)
                }
            }
            
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }
}

struct FileItemView: View {
    let item: FileItem
    let fileManager: FileManagerService
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.isFolder ? "folder" : "doc.text")
                .foregroundColor(item.isFolder ? Color(NSColor.systemBlue) : Color(NSColor.secondaryLabelColor))
                .frame(width: 16, height: 16)
            
            Text(item.name)
                .foregroundColor(Color(NSColor.labelColor))
                .font(.system(size: 13))
            
            Spacer()
            
            if !item.isFolder {
                Text("􀏧")
                    .font(.system(size: 10))
                    .foregroundColor(.clear)
                    .onHover { inside in
                        NSCursor.pointingHand.set()
                    }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(isHovering ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isFolder {
                fileManager.loadFiles(at: URL(fileURLWithPath: item.path))
            } else {
                // Handle file selection
                print("Selected: \(item.path)")
            }
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

#Preview {
    let view = ContentView()
    return view
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
