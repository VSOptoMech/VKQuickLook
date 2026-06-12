import Foundation

/// Small command-line harness for the native renderer.
///
/// It is intended for validation and diagnostics, not as a separate rendering
/// implementation. Keeping it linked against `NativeVKRenderer` ensures CLI
/// behavior stays aligned with Finder extensions.
@main
struct VKQuickLookRender {
    static func main() {
        do {
            let arguments = try RenderArguments.parse(Array(CommandLine.arguments.dropFirst()))
            let asset = try NativeVKRenderer.render(
                mode: arguments.mode,
                inputURL: arguments.inputURL,
                maxPixels: arguments.maxPixels,
                outputURL: arguments.outputURL,
                metadataURL: arguments.metadataURL
            )
            let metadata = try JSONEncoder().encode(asset.output)
            FileHandle.standardOutput.write(metadata)
            FileHandle.standardOutput.write(Data([0x0a]))
        } catch let error as RenderCLIError {
            FileHandle.standardError.write(Data(error.message.utf8))
            FileHandle.standardError.write(Data([0x0a]))
            Foundation.exit(Int32(error.exitCode))
        } catch {
            let message = error.localizedDescription
            FileHandle.standardError.write(Data(message.utf8))
            FileHandle.standardError.write(Data([0x0a]))
            Foundation.exit(1)
        }
    }
}

/// Parsed CLI arguments after defaults and path normalization.
private struct RenderArguments {
    let mode: RenderMode
    let inputURL: URL
    let outputURL: URL
    let metadataURL: URL?
    let maxPixels: Int

    static func parse(_ rawArguments: [String]) throws -> RenderArguments {
        var arguments = rawArguments
        if arguments.first == "--help" || arguments.first == "-h" {
            throw RenderCLIError(message: usage, exitCode: 0)
        }
        guard arguments.count >= 2 else {
            throw RenderCLIError(message: usage, exitCode: 2)
        }

        let modeText = arguments.removeFirst()
        guard let mode = RenderMode(rawValue: modeText) else {
            throw RenderCLIError(message: "mode must be 'thumbnail' or 'preview'\n\n\(usage)", exitCode: 2)
        }
        let inputURL = URL(fileURLWithPath: arguments.removeFirst())

        var outputURL: URL?
        var metadataURL: URL?
        var maxPixels: Int?
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard index + 1 < arguments.count else {
                throw RenderCLIError(message: "missing value for \(option)\n\n\(usage)", exitCode: 2)
            }
            let value = arguments[index + 1]
            switch option {
            case "--output":
                outputURL = URL(fileURLWithPath: value)
            case "--metadata-json":
                metadataURL = URL(fileURLWithPath: value)
            case "--max-pixels":
                guard let parsed = Int(value), parsed >= 16 else {
                    throw RenderCLIError(message: "--max-pixels must be an integer of at least 16", exitCode: 2)
                }
                maxPixels = parsed
            default:
                throw RenderCLIError(message: "unknown option: \(option)\n\n\(usage)", exitCode: 2)
            }
            index += 2
        }

        guard let outputURL else {
            throw RenderCLIError(message: "--output is required\n\n\(usage)", exitCode: 2)
        }
        return RenderArguments(
            mode: mode,
            inputURL: inputURL,
            outputURL: normalizedPNGURL(outputURL),
            metadataURL: metadataURL,
            maxPixels: maxPixels ?? defaultMaxPixels(for: mode)
        )
    }
}

/// Usage or argument parsing error with an explicit process exit code.
private struct RenderCLIError: Error {
    let message: String
    let exitCode: Int
}

private let usage = """
Usage: VKQuickLookRender thumbnail|preview path/to/file.vk4 --output path/to/output.png [--metadata-json path/to/output.json] [--max-pixels N]
"""

private func defaultMaxPixels(for mode: RenderMode) -> Int {
    switch mode {
    case .thumbnail:
        return 512
    case .preview:
        return 2048
    }
}

private func normalizedPNGURL(_ url: URL) -> URL {
    if url.pathExtension.lowercased() == "png" {
        return url
    }
    return url.deletingPathExtension().appendingPathExtension("png")
}
