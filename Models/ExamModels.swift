import Foundation

struct ExamRequest: Encodable {
    let examinedAt: String
    let hospital: String?
    let memo: String?
    let mhr: Double
    let sdnn: Double
    let rmssd: Double
    let psi: Double
    let tp: Double
    let vlf: Double
    let lf: Double
    let hf: Double
    let lfNorm: Double
    let hfNorm: Double
    let lfHfRatio: Double
    let ectopicBeat: Double
    let srd: Double
    let result: String
}

struct ExamEntry: Decodable {
    let examinedAt: String
    let sdnn: Double
    let result: String
}
