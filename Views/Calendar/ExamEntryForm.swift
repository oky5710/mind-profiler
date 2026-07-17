import SwiftUI

struct ExamEntryForm: View {
    let date: Date
    var onSaved: () async -> Void

    @State private var time = Date()
    @State private var hospital = ""
    @State private var memo = ""
    @State private var result = ""

    @State private var mhr = ""
    @State private var sdnn = ""
    @State private var rmssd = ""
    @State private var psi = ""
    @State private var tp = ""
    @State private var vlf = ""
    @State private var lf = ""
    @State private var hf = ""
    @State private var lfNorm = ""
    @State private var hfNorm = ""
    @State private var lfHfRatio = ""
    @State private var ectopicBeat = ""
    @State private var srd = ""

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Time Domain Analysis") {
                numberField("MHR", $mhr)
                numberField("SDNN", $sdnn)
                numberField("RMSSD", $rmssd)
                numberField("PSI", $psi)
            }

            Section("Frequency Domain Analysis") {
                numberField("TP", $tp)
                numberField("VLF", $vlf)
                numberField("LF", $lf)
                numberField("HF", $hf)
                numberField("LF Norm", $lfNorm)
                numberField("HF Norm", $hfNorm)
                numberField("LF/HF Ratio", $lfHfRatio)
                numberField("Ectopic Beat", $ectopicBeat)
            }

            Section("Other") {
                numberField("SRD", $srd)
                TextField("Result", text: $result)
            }

            Section("검사 정보") {
                DatePicker("검사 시간", selection: $time, displayedComponents: .hourAndMinute)
                TextField("병원 (선택)", text: $hospital)
                TextField("메모 (선택)", text: $memo)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Text("저장")
                }
            }
            .disabled(isSaving)
        }
    }

    private func numberField(_ label: String, _ binding: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", text: binding)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
    }

    private func save() async {
        errorMessage = nil

        guard
            let mhrValue = Double(mhr), let sdnnValue = Double(sdnn), let rmssdValue = Double(rmssd),
            let psiValue = Double(psi), let tpValue = Double(tp), let vlfValue = Double(vlf),
            let lfValue = Double(lf), let hfValue = Double(hf), let lfNormValue = Double(lfNorm),
            let hfNormValue = Double(hfNorm), let lfHfRatioValue = Double(lfHfRatio),
            let ectopicBeatValue = Double(ectopicBeat), let srdValue = Double(srd),
            !result.isEmpty
        else {
            errorMessage = "모든 값을 올바르게 입력해주세요."
            return
        }

        isSaving = true
        let examinedAt = DateKey.combine(date: date, time: time)
        let request = ExamRequest(
            examinedAt: ISO8601DateFormatter().string(from: examinedAt),
            hospital: hospital.isEmpty ? nil : hospital,
            memo: memo.isEmpty ? nil : memo,
            mhr: mhrValue,
            sdnn: sdnnValue,
            rmssd: rmssdValue,
            psi: psiValue,
            tp: tpValue,
            vlf: vlfValue,
            lf: lfValue,
            hf: hfValue,
            lfNorm: lfNormValue,
            hfNorm: hfNormValue,
            lfHfRatio: lfHfRatioValue,
            ectopicBeat: ectopicBeatValue,
            srd: srdValue,
            result: result
        )

        do {
            try await ExamService.createExam(request)
            await onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
