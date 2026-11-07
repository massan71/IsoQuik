import Foundation

struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { status == 0 }

    var combined: String {
        [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum Shell {
    /// Runs a short command and returns stdout, stderr and the exit status.
    static func run(_ executable: String, _ arguments: [String]) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(
                        returning: CommandResult(
                            status: -1,
                            stdout: "",
                            stderr: error.localizedDescription
                        )
                    )
                    return
                }

                // Read both pipes in parallel to avoid a buffer deadlock.
                final class Box: @unchecked Sendable {
                    var output = Data()
                    var error = Data()
                }
                let box = Box()
                let group = DispatchGroup()

                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    box.output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    box.error = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                process.waitUntilExit()
                group.wait()

                continuation.resume(
                    returning: CommandResult(
                        status: process.terminationStatus,
                        stdout: String(data: box.output, encoding: .utf8) ?? "",
                        stderr: String(data: box.error, encoding: .utf8) ?? ""
                    )
                )
            }
        }
    }
}

enum StreamReader {
    /// Turns a pipe into a sequence of lines delivered to the handler.
    static func lines(
        from handle: FileHandle,
        isError: Bool,
        handler: @escaping @Sendable (String, Bool) -> Void
    ) async {
        do {
            for try await line in handle.bytes.lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    handler(trimmed, isError)
                }
            }
        } catch {
            // EOF or closed pipe: nothing to do.
        }
    }
}
