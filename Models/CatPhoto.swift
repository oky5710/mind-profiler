import Foundation

struct PixabayResponse: Decodable {
    let hits: [PixabayHit]
}

struct PixabayHit: Decodable {
    let largeImageURL: String
}
