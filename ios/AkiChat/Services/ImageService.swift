import Foundation
import ImageIO
import UIKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum ImageService {
    static func validateImported(_ attachment: Attachment) throws {
        guard let source = CGImageSourceCreateWithData(attachment.jpeg as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == attachment.width, height == attachment.height,
              width > 0, height > 0, width <= 2048, height <= 2048 else {
            throw AppError.validation("导入记录含有无效图片，或图片尺寸与元数据不一致。")
        }
    }
    static func prepare(url: URL) throws -> Attachment {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw AppError.validation("无法读取图片，请选择其他图片重试。") }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048,
            kCGImageSourceShouldCacheImmediately: true]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw AppError.validation("图片解码失败，请重新选择。") }
        let image = UIImage(cgImage: cgImage)
        for quality in [0.82, 0.65, 0.45] {
            if let data = image.jpegData(compressionQuality: quality), data.count <= 4 * 1024 * 1024 {
                return Attachment(jpeg: data, width: cgImage.width, height: cgImage.height)
            }
        }
        throw AppError.validation("压缩后的图片仍超过 4 MiB，请选择较小图片重试。")
    }
}

struct PhotoPicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentation
    let completion: (Result<Attachment, Error>) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images; configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentation.wrappedValue.dismiss()
            guard let provider = results.first?.itemProvider else { return }
            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                parent.completion(.failure(AppError.validation("所选文件不是图片"))); return
            }
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [parent] url, error in
                let result: Result<Attachment, Error>
                if let url = url { result = Result { try ImageService.prepare(url: url) } }
                else { result = .failure(error ?? AppError.validation("相册图片下载失败，请重新选择以重试。")) }
                DispatchQueue.main.async { parent.completion(result) }
            }
        }
    }
}
