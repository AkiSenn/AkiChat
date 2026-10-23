import SwiftUI
import ImageIO

final class ThumbnailLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private static let cache: NSCache<NSString, UIImage> = {
        let value = NSCache<NSString, UIImage>(); value.totalCostLimit = 32 * 1024 * 1024; return value
    }()
    private static let queue = DispatchQueue(label: "com.akisenn.akichat.thumbnails", qos: .userInitiated)
    private var request = UUID()
    func load(_ attachment: Attachment, maxPixel: Int) {
        let token = UUID(); request = token
        Self.queue.async { [weak self] in
            let key = "\(attachment.id)-\(attachment.jpeg.hashValue)-\(maxPixel)" as NSString
            var image = Self.cache.object(forKey: key)
            if image == nil, let source = CGImageSourceCreateWithData(attachment.jpeg as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
               let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary) {
                image = UIImage(cgImage: cg)
                if let image = image { Self.cache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height) }
            }
            DispatchQueue.main.async { [weak self] in if self?.request == token { self?.image = image } }
        }
    }
}
struct AttachmentThumbnail: View {
    let attachment: Attachment
    var maxPixel = 800
    @StateObject private var loader = ThumbnailLoader()
    var body: some View {
        Group {
            if let image = loader.image { Image(uiImage: image).resizable().scaledToFit() }
            else { RoundedRectangle(cornerRadius: 10).fill(Theme.card).aspectRatio(CGFloat(max(1, attachment.width)) / CGFloat(max(1, attachment.height)), contentMode: .fit).overlay(ProgressView()) }
        }.onAppear { loader.load(attachment, maxPixel: maxPixel) }
            .onChange(of: attachment.id) { _ in loader.load(attachment, maxPixel: maxPixel) }
    }
}
