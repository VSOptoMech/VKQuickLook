import Foundation

/// Rendering mode requested by either Finder/Quick Look or the validation CLI.
enum RenderMode: String {
    case thumbnail
    case preview
}

/// Compact metadata describing one successful render.
///
/// The CLI writes this as JSON for diagnostics. Finder preview UI also uses it
/// directly for the single-line source summary.
struct RenderOutput: Codable {
    let ok: Bool
    let mode: String
    let inputPath: String
    let outputPath: String
    let sourceFormat: String
    let sourceLayer: String
    let sourceLabel: String
    let widthPx: Int
    let heightPx: Int
    let renderedWidthPx: Int
    let renderedHeightPx: Int
    let fileSizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case mode
        case inputPath = "input_path"
        case outputPath = "output_path"
        case sourceFormat = "source_format"
        case sourceLayer = "source_layer"
        case sourceLabel = "source_label"
        case widthPx = "width_px"
        case heightPx = "height_px"
        case renderedWidthPx = "rendered_width_px"
        case renderedHeightPx = "rendered_height_px"
        case fileSizeBytes = "file_size_bytes"
    }
}

/// Files and metadata produced by one native render request.
struct RenderedAsset {
    let imageURL: URL
    let output: RenderOutput
}

/// Domain-specific renderer failure that surfaces cleanly in Finder and CLI output.
enum RendererError: LocalizedError {
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case let .renderFailed(message):
            return message
        }
    }
}

/// Asynchronous adapter used by Quick Look extension entry points.
///
/// The renderer itself is synchronous so the CLI and tests can call it directly.
/// Quick Look providers call through this service to avoid doing file parsing and
/// image encoding on the extension callback thread.
final class RendererService {
    static func render(
        mode: RenderMode,
        inputURL: URL,
        maxPixels: Int,
        completion: @escaping (Result<RenderedAsset, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                completion(.success(try NativeVKRenderer.render(mode: mode, inputURL: inputURL, maxPixels: maxPixels)))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
