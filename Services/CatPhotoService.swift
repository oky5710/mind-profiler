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
        let pooled = preferredCategories().flatMap { jpegs(in: root.appendingPathComponent($0, isDirectory: true)) }
        if let photo = pooled.randomElement() {
            return photo
        }
        return randomJPEG(in: root)
    }

    private static func jpegs(in directory: URL) -> [URL] {
        FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "jpg" } ?? []
    }

    private static func randomJPEG(in directory: URL) -> URL? {
        jpegs(in: directory).randomElement()
    }

    // 회복 지수가 낮으면(RecoveryScore.label의 "회복이 필요해요" 기준과 동일하게 70 미만) funny/licking
    // 폴더에서, 그게 아니고 지금이 새벽 3~5시면 drowsy에서, 그 외 밤(22시~6시)이면 sleeping에서 고른다
    // — 아무 조건도 해당하지 않으면(또는 해당 카테고리 폴더들이 모두 비어 있으면) 전체에서 무작위로
    // 고르는 기존 동작으로 되돌아간다.
    private static func preferredCategories() -> [String] {
        if let score = RecoveryScoreCache.value, score < 70 {
            return ["funny", "licking"]
        }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 3 && hour < 5 {
            return ["drowsy"]
        }
        if hour >= 22 || hour < 6 {
            return ["sleeping"]
        }
        return []
    }
}
