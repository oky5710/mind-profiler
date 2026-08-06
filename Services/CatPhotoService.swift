import Foundation
import ImageIO

enum CatPhotoService {
    private static let categories = [
        "angry", "cheesy", "confident", "curious", "cute", "drowsy", "funny", "licking",
        "polite", "sad", "sleeping", "staring", "surprised", "warm",
        "what_are_you_looking_at", "wistful",
    ]

    static func randomPhoto() -> CGImage? {
        let urls = categories.flatMap { category in
            let subdirectory = "CatPhotos/\(category)"
            return Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: subdirectory) ?? []
        }
        guard let url = urls.randomElement(),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
