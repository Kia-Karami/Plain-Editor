import Foundation
import Combine

class TerminalManager: ObservableObject {
    @Published var output: String = ""
    @Published var currentDirectory: String = FileManager.default.currentDirectoryPath
    private var process: Process?
    private var outputPipe = Pipe()
    private var inputPipe = Pipe()
    
    init() {
        setupProcess()
    }
    
    private func setupProcess() {
        process = Process()
        process?.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process?.arguments = ["--no-rcs"]  // Don't load .zshrc
        
        // Minimal environment to prevent any output
        process?.environment = [
            "PS1": "",
            "TERM": "dumb",
            "CLICOLOR": "0",
            "PAGER": "cat",
            "LANG": "en_US.UTF-8"
        ]
        
        // Set up output handling
        process?.standardOutput = outputPipe
        process?.standardError = outputPipe
        process?.standardInput = inputPipe
        
        // Set up output handler
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if var output = String(data: data, encoding: .utf8) {
                // Clean up and format the output
                output = output.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Filter out unwanted messages and initial setup text
                let unwantedPatterns = [
                    "^%+$",  // Lines with only %
                    "^TERM environment variable not set.?$",
                    "^\\x1B\\[\\?1034h",  // ANSI escape sequence
                    "^\\[\\]?\\d*;?\\d*[A-Za-z]?",  // Terminal control sequences like [0;0H
                    "^\\[\\d+;?\\d*[Hf]",  // Cursor position sequences
                    "^\\[\\?\\d*[hl]?",  // Terminal mode settings
                    "^\\[\\?\\d+[hl]?",  // More terminal mode settings
                    "^\\[\\?2004[hl]?",  // Bracketed paste mode
                    "^\\[\\?1004[hl]?",  // Focus tracking
                    "^\\[\\?1006[hl]?",  // SGR mouse mode
                    "^\\x1B\\[\\?1l",  // More ANSI sequences
                    "^\\x1B\\[\\?25h"   // Show cursor
                ]
                
                for pattern in unwantedPatterns {
                    output = output.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                }
                
                output = output.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !output.isEmpty {
                    let formattedOutput = "> " + output.replacingOccurrences(of: "\n", with: "\n> ") + "\n"
                    DispatchQueue.main.async {
                        self?.output += formattedOutput
                    }
                }
            }
        }
        
        // Start the process
        do {
            try process?.run()
            // Send initial command to set the prompt
            sendCommand("export PS1='$ ' && clear")
        } catch {
            print("Failed to start terminal process: \(error)")
        }
    }
    
    func sendCommand(_ command: String) {
        guard !command.isEmpty else { return }
        
        // Add command to output with formatting
        DispatchQueue.main.async {
            self.output += "$ \(command)\n"
        }
        
        // Add newline to execute the command
        let commandWithNewline = command + "\n"
        if let data = commandWithNewline.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
            
            // Force flush the output
            do {
                try inputPipe.fileHandleForWriting.synchronize()
            } catch {
                print("Failed to flush pipe: \(error)")
            }
        }
    }
    
    func stop() {
        process?.interrupt()
        process = nil
    }
    
    deinit {
        stop()
    }
}
