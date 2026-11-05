import UIKit
import ImageIO

@MainActor enum ProfilePhotoProcessing {
    static func prepare(_ data: Data) throws -> UIImage {
        guard !data.isEmpty, data.count <= 20_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary) else { throw PhotoError.unreadable }
        return UIImage(cgImage: image)
    }
    static func rotateClockwise(_ image: UIImage) -> UIImage {
        let size = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }
    static func croppedData(_ image: UIImage, crop: ProfilePhotoCrop) throws -> Data {
        guard let rect = crop.sourceRectangle(width: image.size.width, height: image.size.height) else { throw PhotoError.unreadable }
        let scale = 512 / rect.side
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let cropped = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { _ in
            image.draw(in: CGRect(x: -rect.x * scale, y: -rect.y * scale,
                width: image.size.width * scale, height: image.size.height * scale))
        }
        guard let data = cropped.jpegData(compressionQuality: 0.9) else { throw PhotoError.unreadable }
        return data
    }
    enum PhotoError: LocalizedError {
        case unreadable
        var errorDescription: String? { "Choose a photo under 20 MB that can be opened on this device." }
    }
}

extension LedgerStore {
    @discardableResult func saveProfilePhoto(_ image: UIImage, crop: ProfilePhotoCrop, reusingOriginal: String?) -> Bool {
        var staged: [String] = []
        do {
            let crop = crop.constrained(width: image.size.width, height: image.size.height)
            let original: String
            if let saved = reusingOriginal, FileManager.default.fileExists(atPath: attachmentURL(saved).path) { original = saved }
            else {
                guard let data = image.jpegData(compressionQuality: 0.9) else { throw ProfilePhotoProcessing.PhotoError.unreadable }
                original = try attach(data, extension: "jpg"); staged.append(original)
            }
            let cropped = try attach(ProfilePhotoProcessing.croppedData(image, crop: crop), extension: "jpg"); staged.append(cropped)
            if update({ $0.profilePhoto = ProfilePhoto(originalImage: original, croppedImage: cropped, crop: crop) }) { return true }
        } catch { self.error = error.localizedDescription }
        for name in staged { try? FileManager.default.removeItem(at: attachmentURL(name)) }
        return false
    }
}
