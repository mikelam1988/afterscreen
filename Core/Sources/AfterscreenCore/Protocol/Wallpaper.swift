import Foundation
import ImageIO

public struct WallpaperTransfer: Codable {
    public var id: UUID
    public var image: Data
    public init(id: UUID = UUID(), image: Data) { self.id = id; self.image = image }
}

public struct WallpaperResult: Codable {
    public var id: UUID
    /// nil means the receiver successfully applied the wallpaper.
    public var error: String?
    public init(id: UUID, error: String?) { self.id = id; self.error = error }
}

public enum WallpaperImage {
    public static let maxBytes = 16 << 20
    public enum Failure: LocalizedError {
        case invalid
        public var errorDescription: String? { L10n.t("Cannot read this static wallpaper (maximum 16 MB, 8192 pixels per side).", "이 정적 배경화면을 읽을 수 없습니다 (최대 16 MB, 각 변 8192 픽셀).") }
    }

    public static func validate(_ data: Data) throws {
        guard !data.isEmpty, data.count <= maxBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.jpeg",
              CGImageSourceGetCount(source) == 1,
              let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= 8192, h <= 8192,
              CGImageSourceGetStatus(source) == .statusComplete else { throw Failure.invalid }
    }

    /// Convert a local static image to a bounded JPEG, without sending file paths.
    public static func prepare(url: URL) throws -> Data {
        guard url.isFileURL, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 8192
              ] as CFDictionary) else { throw Failure.invalid }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { throw Failure.invalid }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.invalid }
        try validate(data as Data)
        return data as Data
    }
}
