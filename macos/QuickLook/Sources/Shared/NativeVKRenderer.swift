import AppKit
import Foundation

private let vk4Magic = Data([0x56, 0x4b, 0x34, 0x5f])
private let vk6MagicPrefix = Data([0x56, 0x4b, 0x36])
private let maxEmbeddedPreviewBytes = 128 * 1024 * 1024
private let maxVK4RGBSectionBytes = 256 * 1024 * 1024

/// Image selected from a VK file before final resize/PNG encoding.
private struct NativeImageSource {
    let cgImage: CGImage
    let sourceFormat: String
    let sourceLayer: String
    let sourceLabel: String
    let widthPx: Int
    let heightPx: Int
}

/// Native renderer shared by the Quick Look extensions, CLI, and Swift tests.
///
/// This intentionally implements only the Quick Look image paths:
/// - VK6: wrapper BMP preview from the container header.
/// - VK4: 24-bit RGB sections referenced by the offset table.
///
/// It does not parse VK measurement metadata, height maps, VK6 ZIP payloads, or
/// other project formats. Keeping the parser narrow reduces sandbox risk and
/// avoids duplicating non-Quick-Look analysis code.
enum NativeVKRenderer {
    /// Render a VK4/VK6 file into a PNG asset.
    ///
    /// Finder calls this without explicit output URLs and receives a temporary
    /// PNG. The CLI passes explicit output paths and may request a JSON sidecar.
    static func render(
        mode: RenderMode,
        inputURL: URL,
        maxPixels: Int,
        outputURL requestedImageURL: URL? = nil,
        metadataURL requestedMetadataURL: URL? = nil
    ) throws -> RenderedAsset {
        let source = try loadImageSource(inputURL: inputURL, mode: mode)
        let rendered = try pngData(from: source.cgImage, maxPixels: max(16, maxPixels))
        let imageURL: URL
        if let requestedImageURL {
            imageURL = requestedImageURL
        } else {
            imageURL = try makeTemporaryRenderDirectory().appendingPathComponent("\(mode.rawValue).png")
        }
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try rendered.data.write(to: imageURL, options: .atomic)

        let output = RenderOutput(
            ok: true,
            mode: mode.rawValue,
            inputPath: inputURL.path,
            outputPath: imageURL.path,
            sourceFormat: source.sourceFormat,
            sourceLayer: source.sourceLayer,
            sourceLabel: source.sourceLabel,
            widthPx: source.widthPx,
            heightPx: source.heightPx,
            renderedWidthPx: rendered.widthPx,
            renderedHeightPx: rendered.heightPx,
            fileSizeBytes: fileSize(inputURL)
        )
        if let metadataURL = requestedMetadataURL {
            try FileManager.default.createDirectory(at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let metadata = try JSONEncoder().encode(output)
            try metadata.write(to: metadataURL, options: .atomic)
        }
        return RenderedAsset(imageURL: imageURL, output: output)
    }

    /// Dispatch to the smallest parser needed for the file format.
    private static func loadImageSource(inputURL: URL, mode: RenderMode) throws -> NativeImageSource {
        let handle = try FileHandle(forReadingFrom: inputURL)
        defer {
            try? handle.close()
        }
        let magic = try readExact(handle, count: 4)
        try handle.seek(toOffset: 0)
        if magic == vk4Magic {
            return try loadVK4ImageSource(handle: handle, inputURL: inputURL, mode: mode)
        }
        if magic.prefix(3) == vk6MagicPrefix {
            return try loadVK6BMPPreview(handle: handle, inputURL: inputURL)
        }
        let ext = inputURL.pathExtension.lowercased()
        if ext != "vk4" && ext != "vk6" {
            throw RendererError.renderFailed("Unsupported Quick Look input: \(inputURL.lastPathComponent). Expected a .vk4 or .vk6 file.")
        }
        throw RendererError.renderFailed("Invalid VK file header in \(inputURL.lastPathComponent).")
    }

    /// Read the VK6 wrapper BMP preview without opening the embedded ZIP payload.
    private static func loadVK6BMPPreview(handle: FileHandle, inputURL: URL) throws -> NativeImageSource {
        let fileSizeBytes = fileSize(inputURL)
        let header = try readExact(handle, count: 7)
        let bmpSize = Int(try uint32LE(header, at: 3))
        if bmpSize <= 0 || bmpSize > maxEmbeddedPreviewBytes {
            throw RendererError.renderFailed("Invalid VK6 embedded BMP size: \(bmpSize) bytes.")
        }
        if 7 + bmpSize > fileSizeBytes {
            throw RendererError.renderFailed("Invalid VK6 container: embedded BMP span exceeds file size.")
        }
        let bmp = try readExact(handle, count: bmpSize)
        guard bmp.count >= 2, bmp[0] == 0x42, bmp[1] == 0x4d else {
            throw RendererError.renderFailed("Invalid VK6 container: missing embedded BMP header.")
        }
        guard let representation = NSBitmapImageRep(data: bmp), let cgImage = representation.cgImage else {
            throw RendererError.renderFailed("Unable to decode embedded VK6 BMP preview.")
        }
        return NativeImageSource(
            cgImage: cgImage,
            sourceFormat: "VK6",
            sourceLayer: "vk6_bmp_preview",
            sourceLabel: "VK6 BMP preview",
            widthPx: cgImage.width,
            heightPx: cgImage.height
        )
    }

    /// Select the first usable VK4 RGB section for the requested render mode.
    private static func loadVK4ImageSource(handle: FileHandle, inputURL: URL, mode: RenderMode) throws -> NativeImageSource {
        let fileSizeBytes = fileSize(inputURL)
        if fileSizeBytes < 84 {
            throw RendererError.renderFailed("File too small to be a valid VK4 file: \(inputURL.lastPathComponent).")
        }
        let candidates = mode == .preview ? vk4PreviewPriority : vk4ThumbnailPriority
        var rejectedLayers: [String] = []
        for candidate in candidates {
            let offset = try readVK4SectionOffset(handle: handle, fileSizeBytes: fileSizeBytes, section: candidate)
            guard offset > 0 else {
                continue
            }
            do {
                let cgImage = try readVK4RGBSection(handle: handle, fileSizeBytes: fileSizeBytes, offset: offset, key: candidate.key)
                return NativeImageSource(
                    cgImage: cgImage,
                    sourceFormat: "VK4",
                    sourceLayer: candidate.key,
                    sourceLabel: candidate.label,
                    widthPx: cgImage.width,
                    heightPx: cgImage.height
                )
            } catch {
                rejectedLayers.append("\(candidate.key): \(error.localizedDescription)")
                continue
            }
        }
        if !rejectedLayers.isEmpty {
            let detail = rejectedLayers.joined(separator: "; ")
            throw RendererError.renderFailed("No usable VK4 image layer found in \(inputURL.lastPathComponent): \(detail)")
        }
        throw RendererError.renderFailed("No renderable VK4 image layer found in \(inputURL.lastPathComponent).")
    }

    /// Read one offset-table entry for a renderable VK4 image section.
    ///
    /// VK4 has an 18-entry table starting at byte 12. Quick Look only needs six
    /// RGB sections, so this reads individual entries instead of cataloging the
    /// full table and unrelated measurement/line/string sections.
    private static func readVK4SectionOffset(
        handle: FileHandle,
        fileSizeBytes: Int,
        section: VK4RenderSection
    ) throws -> UInt64 {
        try ensureSpan(fileSizeBytes: fileSizeBytes, offset: 12, size: 72, label: "VK4 offset table")
        try handle.seek(toOffset: UInt64(12 + section.offsetTableIndex * 4))
        let data = try readExact(handle, count: 4)
        let offset = UInt64(try uint32LE(data, at: 0))
        if offset != 0 {
            try ensureSpan(fileSizeBytes: fileSizeBytes, offset: offset, size: 4, label: "VK4 section \(section.key)")
        }
        return offset
    }

    /// Decode one uncompressed 24-bit RGB VK4 image section into a CGImage.
    private static func readVK4RGBSection(
        handle: FileHandle,
        fileSizeBytes: Int,
        offset: UInt64,
        key: String
    ) throws -> CGImage {
        try ensureSpan(fileSizeBytes: fileSizeBytes, offset: offset, size: 20, label: "\(key) header")
        try handle.seek(toOffset: offset)
        let header = try readExact(handle, count: 20)
        let width = Int(try uint32LE(header, at: 0))
        let height = Int(try uint32LE(header, at: 4))
        let bitDepth = Int(try uint32LE(header, at: 8))
        let compression = try uint32LE(header, at: 12)
        let dataByteSize = Int(try uint32LE(header, at: 16))
        if width <= 0 || height <= 0 {
            throw RendererError.renderFailed("Invalid \(key) dimensions: \(width)x\(height).")
        }
        if bitDepth != 24 || compression != 0 {
            throw RendererError.renderFailed("Unsupported \(key) encoding.")
        }
        // VK stores these RGB sections as tightly packed 3-byte pixels after a
        // five-word section header. Reject oversized spans before allocating.
        let pixelCount = try checkedPixelCount(width: width, height: height, bytesPerPixel: 3, key: key)
        let expectedBytes = pixelCount * 3
        if dataByteSize < expectedBytes {
            throw RendererError.renderFailed("Incomplete \(key) image data.")
        }
        if expectedBytes > maxVK4RGBSectionBytes || dataByteSize > maxVK4RGBSectionBytes {
            throw RendererError.renderFailed("Refusing oversized \(key) image data.")
        }
        try ensureSpan(fileSizeBytes: fileSizeBytes, offset: offset + 20, size: dataByteSize, label: "\(key) data")
        let rgb = try readExact(handle, count: expectedBytes)
        return try makeRGBImage(data: rgb, width: width, height: height)
    }

    /// Convert VK's packed RGB bytes into a Core Graphics-compatible RGBA image.
    private static func makeRGBImage(data: Data, width: Int, height: Int) throws -> CGImage {
        let pixelCount = try checkedPixelCount(width: width, height: height, bytesPerPixel: 4, key: "RGB image")
        var rgba = Data(count: pixelCount * 4)
        data.withUnsafeBytes { sourceBuffer in
            rgba.withUnsafeMutableBytes { destinationBuffer in
                let source = sourceBuffer.bindMemory(to: UInt8.self)
                let destination = destinationBuffer.bindMemory(to: UInt8.self)
                for pixel in 0..<pixelCount {
                    destination[pixel * 4] = source[pixel * 3]
                    destination[pixel * 4 + 1] = source[pixel * 3 + 1]
                    destination[pixel * 4 + 2] = source[pixel * 3 + 2]
                    destination[pixel * 4 + 3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: rgba as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw RendererError.renderFailed("Unable to create VK image.")
        }
        return image
    }

    /// Validate image dimensions before multiplying into byte counts.
    private static func checkedPixelCount(width: Int, height: Int, bytesPerPixel: Int, key: String) throws -> Int {
        if width <= 0 || height <= 0 || bytesPerPixel <= 0 {
            throw RendererError.renderFailed("Invalid \(key) dimensions: \(width)x\(height).")
        }
        if width > Int.max / height {
            throw RendererError.renderFailed("Invalid \(key) dimensions are too large.")
        }
        let pixelCount = width * height
        if pixelCount > Int.max / bytesPerPixel {
            throw RendererError.renderFailed("Invalid \(key) image byte size.")
        }
        return pixelCount
    }

    /// Resize and encode a CGImage as PNG for Quick Look.
    private static func pngData(from image: CGImage, maxPixels: Int) throws -> (data: Data, widthPx: Int, heightPx: Int) {
        let rendered = try resizedImage(image, maxPixels: maxPixels)
        let representation = NSBitmapImageRep(cgImage: rendered)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            throw RendererError.renderFailed("Unable to encode VK Quick Look PNG.")
        }
        return (png, rendered.width, rendered.height)
    }

    /// Scale the longest edge down to `maxPixels` while preserving aspect ratio.
    private static func resizedImage(_ image: CGImage, maxPixels: Int) throws -> CGImage {
        let maxEdge = max(image.width, image.height)
        if maxEdge <= maxPixels {
            return image
        }
        let scale = CGFloat(maxPixels) / CGFloat(maxEdge)
        let targetWidth = max(1, Int(round(CGFloat(image.width) * scale)))
        let targetHeight = max(1, Int(round(CGFloat(image.height) * scale)))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: targetWidth * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw RendererError.renderFailed("Unable to resize VK Quick Look image.")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let resized = context.makeImage() else {
            throw RendererError.renderFailed("Unable to resize VK Quick Look image.")
        }
        return resized
    }

    private static func makeTemporaryRenderDirectory() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = root.appendingPathComponent("VKQuickLook-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct VK4RenderSection {
    let offsetTableIndex: Int
    let key: String
    let label: String
}

// VK4 offset-table indices for the RGB image sections used by Quick Look.
private let vk4ThumbnailPriority = [
    VK4RenderSection(offsetTableIndex: 10, key: "clr_thumb", label: "Color thumbnail"),
    VK4RenderSection(offsetTableIndex: 9, key: "clr_peak_thumb", label: "Peak color thumbnail"),
    VK4RenderSection(offsetTableIndex: 11, key: "light_thumb", label: "Light thumbnail"),
    VK4RenderSection(offsetTableIndex: 12, key: "height_thumb", label: "Height thumbnail")
]

private let vk4PreviewPriority = [
    VK4RenderSection(offsetTableIndex: 2, key: "color_light", label: "Color light image"),
    VK4RenderSection(offsetTableIndex: 1, key: "color_peak", label: "Peak color image"),
    VK4RenderSection(offsetTableIndex: 10, key: "clr_thumb", label: "Color thumbnail"),
    VK4RenderSection(offsetTableIndex: 9, key: "clr_peak_thumb", label: "Peak color thumbnail"),
    VK4RenderSection(offsetTableIndex: 11, key: "light_thumb", label: "Light thumbnail"),
    VK4RenderSection(offsetTableIndex: 12, key: "height_thumb", label: "Height thumbnail")
]

private func fileSize(_ url: URL) -> Int {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey])
    return values?.fileSize ?? 0
}

private func readExact(_ handle: FileHandle, count: Int) throws -> Data {
    let data = try handle.read(upToCount: count) ?? Data()
    if data.count != count {
        throw RendererError.renderFailed("Unexpected end of VK file.")
    }
    return data
}

private func uint32LE(_ data: Data, at offset: Int) throws -> UInt32 {
    if offset < 0 || offset + 4 > data.count {
        throw RendererError.renderFailed("Unexpected end of VK metadata.")
    }
    return UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
}

private func ensureSpan(fileSizeBytes: Int, offset: UInt64, size: Int, label: String) throws {
    if size < 0 || offset > UInt64(Int.max) {
        throw RendererError.renderFailed("Invalid \(label) span.")
    }
    let end = offset + UInt64(size)
    if end > UInt64(fileSizeBytes) {
        throw RendererError.renderFailed("Invalid \(label) span.")
    }
}
