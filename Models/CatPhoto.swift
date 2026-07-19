import Foundation

struct PixabayResponse: Decodable {
    let hits: [PixabayHit]
}

struct PixabayHit: Decodable {
    // largeImageURL(최대 1280px, 원본 사진 압축률에 따라 수백 KB~수 MB)은 화면을 꽉 채우는 배경치고
    // 과하게 무거워서 로딩이 느렸다 — webformatURL(최대 640px)로 내려받는 용량을 크게 줄인다.
    // 위에 그라디언트+텍스트가 겹쳐 보여서 해상도를 조금 낮춰도 눈에 띄게 흐려 보이지 않는다.
    let webformatURL: String
}
