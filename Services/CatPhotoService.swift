import Foundation
import ImageIO

enum CatPhotoService {
    // 스플래시를 띄운 액터(MainActor)에서 곧바로 부르면 폴더 순회와 JPEG 디코딩이 메인 스레드에서
    // 동기적으로 실행돼 1.5초 스플래시 표시 시간 일부를 잡아먹는다 — 백그라운드로 넘겨서 실행한다.
    static func randomPhoto() async -> CGImage? {
        await Task.detached {
            guard let url = randomPhotoURL(),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }.value
    }

    // 카테고리 폴더 이름을 하드코딩해두면 폴더를 추가/이름 변경/삭제해도 여기 목록을 같이 바꾸지 않는
    // 이상 그 사진들이 조용히 선택 대상에서 빠진다 — CatPhotos 폴더 자체를 그때그때 실제로 순회해서
    // .jpg 파일을 찾는다.
    private static func randomPhotoURL() -> URL? {
        guard let root = Bundle.main.url(forResource: "CatPhotos", withExtension: nil) else { return nil }
        let urls = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "jpg" } ?? []
        return urls.randomElement()
    }
}
