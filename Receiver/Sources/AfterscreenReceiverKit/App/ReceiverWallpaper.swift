import Foundation
import AfterscreenCore

/// Files remain after disconnect; no restore or history.
enum ReceiverWallpaper {
    static func save(_ data: Data) throws -> URL {
        try WallpaperImage.validate(data)
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent("Afterscreen Receiver/Wallpapers", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("wallpaper-" + UUID().uuidString + ".jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func removeOlder(keeping url: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
        for old in files where old != url && old.lastPathComponent.hasPrefix("wallpaper-") && old.pathExtension == "jpg" {
            try? FileManager.default.removeItem(at: old)
        }
    }
}
