import AppKit
import Foundation

/// Self-contained renderer regression tests.
///
/// The tests generate minimal synthetic VK4/VK6 files so the repository can
/// validate the Swift renderer without private sample data or a Python reference
/// parser. They cover the supported image paths and key malformed-file failures.
@main
struct VKQuickLookRendererTests {
    static func main() {
        do {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("VKQuickLookRendererTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: root)
            }

            try testVK4Thumbnail(root: root)
            try testVK4Preview(root: root)
            try testVK6Thumbnail(root: root)
            try testVK6Preview(root: root)
            try testUnsupportedInput(root: root)
            try testTruncatedVK4(root: root)
            try testCorruptVK4Section(root: root)
            print("Swift renderer self-tests passed")
        } catch {
            fputs("Swift renderer self-tests failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func testVK4Thumbnail(root: URL) throws {
        let source = root.appendingPathComponent("synthetic-thumbnail.vk4")
        let output = root.appendingPathComponent("thumbnail.png")
        try writeSyntheticVK4(source)

        let asset = try NativeVKRenderer.render(mode: .thumbnail, inputURL: source, maxPixels: 512, outputURL: output)

        try expect(asset.output.sourceFormat == "VK4", "VK4 thumbnail source format")
        try expect(asset.output.sourceLayer == "clr_thumb", "VK4 thumbnail source layer")
        try expect(asset.output.widthPx == 2, "VK4 thumbnail width")
        try expect(asset.output.heightPx == 2, "VK4 thumbnail height")
        try expect(FileManager.default.fileExists(atPath: output.path), "VK4 thumbnail output file")
    }

    private static func testVK4Preview(root: URL) throws {
        let source = root.appendingPathComponent("synthetic-preview.vk4")
        let output = root.appendingPathComponent("preview.png")
        try writeSyntheticVK4(source)

        let asset = try NativeVKRenderer.render(mode: .preview, inputURL: source, maxPixels: 512, outputURL: output)

        try expect(asset.output.sourceFormat == "VK4", "VK4 preview source format")
        try expect(asset.output.sourceLayer == "color_light", "VK4 preview source layer")
        try expect(asset.output.widthPx == 3, "VK4 preview width")
        try expect(asset.output.heightPx == 2, "VK4 preview height")
        try expect(FileManager.default.fileExists(atPath: output.path), "VK4 preview output file")
    }

    private static func testVK6Thumbnail(root: URL) throws {
        let source = root.appendingPathComponent("synthetic-thumbnail.vk6")
        let output = root.appendingPathComponent("vk6-thumbnail.png")
        try writeSyntheticVK6(source)

        let asset = try NativeVKRenderer.render(mode: .thumbnail, inputURL: source, maxPixels: 512, outputURL: output)

        try expect(asset.output.sourceFormat == "VK6", "VK6 thumbnail source format")
        try expect(asset.output.sourceLayer == "vk6_bmp_preview", "VK6 thumbnail source layer")
        try expect(asset.output.widthPx == 2, "VK6 thumbnail width")
        try expect(asset.output.heightPx == 2, "VK6 thumbnail height")
        try expect(FileManager.default.fileExists(atPath: output.path), "VK6 thumbnail output file")
    }

    private static func testVK6Preview(root: URL) throws {
        let source = root.appendingPathComponent("synthetic-preview.vk6")
        let output = root.appendingPathComponent("vk6-preview.png")
        try writeSyntheticVK6(source)

        let asset = try NativeVKRenderer.render(mode: .preview, inputURL: source, maxPixels: 512, outputURL: output)

        try expect(asset.output.sourceFormat == "VK6", "VK6 preview source format")
        try expect(asset.output.sourceLayer == "vk6_bmp_preview", "VK6 preview source layer")
        try expect(asset.output.widthPx == 2, "VK6 preview width")
        try expect(asset.output.heightPx == 2, "VK6 preview height")
        try expect(FileManager.default.fileExists(atPath: output.path), "VK6 preview output file")
    }

    private static func testUnsupportedInput(root: URL) throws {
        let source = root.appendingPathComponent("not-vk.h5")
        try Data("placeholder".utf8).write(to: source)

        try expectRenderFailure(source, mode: .thumbnail, contains: "Expected a .vk4 or .vk6")
    }

    private static func testTruncatedVK4(root: URL) throws {
        let source = root.appendingPathComponent("truncated.vk4")
        try Data("VK4_".utf8).write(to: source)

        try expectRenderFailure(source, mode: .thumbnail, contains: "File too small")
    }

    private static func testCorruptVK4Section(root: URL) throws {
        let source = root.appendingPathComponent("corrupt.vk4")
        try writeCorruptVK4(source)

        try expectRenderFailure(source, mode: .thumbnail, contains: "Incomplete clr_thumb image data")
    }

    private static func expectRenderFailure(_ source: URL, mode: RenderMode, contains expectedText: String) throws {
        do {
            _ = try NativeVKRenderer.render(mode: mode, inputURL: source, maxPixels: 512)
        } catch {
            try expect(error.localizedDescription.contains(expectedText), "error should contain \(expectedText)")
            return
        }
        throw TestFailure("expected render failure for \(source.lastPathComponent)")
    }

    private static func writeSyntheticVK4(_ url: URL) throws {
        var sections: [(slot: Int, data: Data)] = []
        sections.append((2, rgbSection(width: 3, height: 2, pixels: [
            255, 0, 0, 0, 255, 0, 0, 0, 255,
            255, 255, 0, 0, 255, 255, 255, 0, 255,
        ])))
        sections.append((10, rgbSection(width: 2, height: 2, pixels: [
            10, 20, 30, 40, 50, 60,
            70, 80, 90, 100, 110, 120,
        ])))

        var header = Data(repeating: 0, count: 84)
        header.replaceSubrange(0..<4, with: Data("VK4_".utf8))
        var body = Data()
        for section in sections {
            let offset = UInt32(84 + body.count)
            header.writeUInt32LE(offset, at: 12 + section.slot * 4)
            body.append(section.data)
        }
        var file = Data()
        file.append(header)
        file.append(body)
        try file.write(to: url)
    }

    private static func writeCorruptVK4(_ url: URL) throws {
        var header = Data(repeating: 0, count: 84)
        header.replaceSubrange(0..<4, with: Data("VK4_".utf8))
        header.writeUInt32LE(84, at: 12 + 10 * 4)
        var file = Data()
        file.append(header)
        file.append(rgbSectionHeader(width: 8, height: 8, dataByteSize: 3))
        file.append(Data([0, 1, 2]))
        try file.write(to: url)
    }

    private static func writeSyntheticVK6(_ url: URL) throws {
        // VK6 files start with "VK6", then a little-endian BMP byte count,
        // followed by the BMP preview. The renderer intentionally stops there.
        let bmp = bmp32(width: 2, height: 2, bgraPixelsBottomUp: [
            70, 80, 90, 255, 100, 110, 120, 255,
            10, 20, 30, 255, 40, 50, 60, 255,
        ])
        var file = Data("VK6".utf8)
        file.appendUInt32LE(UInt32(bmp.count))
        file.append(bmp)
        try file.write(to: url)
    }

    private static func rgbSection(width: UInt32, height: UInt32, pixels: [UInt8]) -> Data {
        var section = rgbSectionHeader(width: width, height: height, dataByteSize: UInt32(pixels.count))
        section.append(contentsOf: pixels)
        return section
    }

    private static func rgbSectionHeader(width: UInt32, height: UInt32, dataByteSize: UInt32) -> Data {
        var section = Data()
        section.appendUInt32LE(width)
        section.appendUInt32LE(height)
        section.appendUInt32LE(24)
        section.appendUInt32LE(0)
        section.appendUInt32LE(dataByteSize)
        return section
    }

    private static func bmp32(width: UInt32, height: UInt32, bgraPixelsBottomUp: [UInt8]) -> Data {
        // Minimal uncompressed BMP v3 header. Positive height means pixel rows
        // are stored bottom-up, matching the supplied fixture data.
        let pixelDataSize = UInt32(bgraPixelsBottomUp.count)
        let fileSize = UInt32(14 + 40) + pixelDataSize
        var bmp = Data("BM".utf8)
        bmp.appendUInt32LE(fileSize)
        bmp.appendUInt16LE(0)
        bmp.appendUInt16LE(0)
        bmp.appendUInt32LE(54)
        bmp.appendUInt32LE(40)
        bmp.appendInt32LE(Int32(width))
        bmp.appendInt32LE(Int32(height))
        bmp.appendUInt16LE(1)
        bmp.appendUInt16LE(32)
        bmp.appendUInt32LE(0)
        bmp.appendUInt32LE(pixelDataSize)
        bmp.appendInt32LE(2_835)
        bmp.appendInt32LE(2_835)
        bmp.appendUInt32LE(0)
        bmp.appendUInt32LE(0)
        bmp.append(contentsOf: bgraPixelsBottomUp)
        return bmp
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw TestFailure(message)
        }
    }
}

private struct TestFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }

    mutating func appendInt32LE(_ value: Int32) {
        appendUInt32LE(UInt32(bitPattern: value))
    }

    mutating func writeUInt32LE(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(value & 0xff)
        self[offset + 1] = UInt8((value >> 8) & 0xff)
        self[offset + 2] = UInt8((value >> 16) & 0xff)
        self[offset + 3] = UInt8((value >> 24) & 0xff)
    }
}
