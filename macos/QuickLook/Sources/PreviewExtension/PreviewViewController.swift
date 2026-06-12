import AppKit
import QuickLookUI

final class PreviewViewController: NSViewController, QLPreviewingController {
    private let imageView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "Rendering VK preview...")
    private let detailLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(imageView)
        rootView.addSubview(statusLabel)
        rootView.addSubview(detailLabel)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -16),
            imageView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 16),
            imageView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -12),

            statusLabel.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: detailLabel.topAnchor, constant: -4),

            detailLabel.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
            detailLabel.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -16),
            detailLabel.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -12)
        ])
        view = rootView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        title = url.lastPathComponent
        statusLabel.stringValue = "Rendering \(url.lastPathComponent)..."
        detailLabel.stringValue = ""
        imageView.image = nil

        RendererService.render(mode: .preview, inputURL: url, maxPixels: 2048) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    handler(nil)
                    return
                }
                switch result {
                case let .success(asset):
                    self.show(asset: asset, fileURL: url)
                    handler(nil)
                case let .failure(error):
                    self.show(error: error, fileURL: url)
                    handler(nil)
                }
            }
        }
    }

    private func show(asset: RenderedAsset, fileURL: URL) {
        imageView.image = NSImage(contentsOf: asset.imageURL)
        statusLabel.stringValue = fileURL.lastPathComponent
        detailLabel.stringValue = summaryLine(for: asset.output)
        let width = min(max(CGFloat(asset.output.renderedWidthPx) + 96, 640), 1400)
        let height = min(max(CGFloat(asset.output.renderedHeightPx) + 96, 480), 1000)
        preferredContentSize = NSSize(width: width, height: height)
    }

    private func show(error: Error, fileURL: URL) {
        imageView.image = nil
        statusLabel.stringValue = "Unable to preview \(fileURL.lastPathComponent)"
        detailLabel.stringValue = error.localizedDescription
        preferredContentSize = NSSize(width: 640, height: 360)
    }

    private func summaryLine(for output: RenderOutput) -> String {
        return [
            output.sourceFormat,
            output.sourceLabel,
            "\(output.widthPx)x\(output.heightPx) px",
            ByteCountFormatter.string(fromByteCount: Int64(output.fileSizeBytes), countStyle: .file)
        ].joined(separator: "   ")
    }
}
