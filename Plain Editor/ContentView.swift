import SwiftUI
import CodeEditor

struct ContentView: View {
    @State private var source: String = "import SwiftUI\n\nstruct MyView: View {\n    var body: some View {\n        Text(\"Hello, World!\")\n    }\n}"

    var body: some View {
        ZStack {
            Color(hex: "#1E1E1E").ignoresSafeArea()
            VStack(spacing: 0) {
                CodeEditor(source: $source, language: .swift, theme: .default)
                    .padding(.horizontal)
                    .padding(.top, 40)

                HStack {
                    // Left group
                    HStack(spacing: 24) {
                        Text("Files")
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

#Preview {
    ContentView()
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var hexNumber: UInt64 = 0

        if scanner.scanHexInt64(&hexNumber) {
            let r = Double((hexNumber & 0xff0000) >> 16) / 255
            let g = Double((hexNumber & 0x00ff00) >> 8) / 255
            let b = Double(hexNumber & 0x0000ff) / 255
            self.init(red: r, green: g, blue: b)
        } else {
            self.init(red: 0, green: 0, blue: 0) // Default color
        }
    }
} 