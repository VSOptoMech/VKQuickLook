import AppKit
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let requestedEdge = max(request.maximumSize.width, request.maximumSize.height) * max(request.scale, 1.0)
        let maxPixels = max(128, Int(ceil(requestedEdge)))
        RendererService.render(mode: .thumbnail, inputURL: request.fileURL, maxPixels: maxPixels) { result in
            switch result {
            case let .success(asset):
                let reply = QLThumbnailReply(imageFileURL: asset.imageURL)
                if #available(macOS 12.0, *) {
                    reply.extensionBadge = "VK"
                }
                handler(reply, nil)
            case let .failure(error):
                handler(nil, error)
            }
        }
    }
}
