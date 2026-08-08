import SwiftUI

// 식약처 낱알식별정보 검색으로 약을 찾아 등록한다 — mind-record 웹의 MedicinePage.tsx
// DrugSearchSheet와 동일한 2단계 흐름(검색·목록 → 선택한 약의 복용 시간대 선택 → 등록).
// 이름을 직접 입력해 등록하는 수단은 웹에도 없어서 iOS도 검색 결과 선택만 지원한다.
struct DrugSearchSheet: View {
    let existingItemSeqs: Set<String>
    var onRegistered: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchInput = ""
    @State private var searchTerm = ""
    @State private var results: [DrugItem] = []
    @State private var isSearching = false
    @State private var searchErrorMessage: String?

    @State private var selectedDrug: DrugItem?
    @State private var selectedTimings: Set<MedicationTiming> = []
    @State private var isRegistering = false
    @State private var registerErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let selectedDrug {
                    timingPicker(for: selectedDrug)
                } else {
                    searchView
                }
            }
            .navigationTitle(selectedDrug == nil ? "복용약 추가" : "복용 시간 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedDrug != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            self.selectedDrug = nil
                            selectedTimings = []
                            registerErrorMessage = nil
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private var searchView: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("약 이름 검색", text: $searchInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await search() } }
                Button("검색") { Task { await search() } }
                    .disabled(searchInput.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }
            .padding(.horizontal)

            if isSearching {
                ProgressView()
            } else if let searchErrorMessage {
                Text(searchErrorMessage).font(Typography.caption).foregroundStyle(.red)
            } else if !searchTerm.isEmpty && results.isEmpty {
                Text("검색 결과가 없어요").font(Typography.caption).foregroundStyle(.secondary)
            }

            List(results) { item in
                let isActive = existingItemSeqs.contains(item.itemSeq)
                Button {
                    guard !isActive else { return }
                    selectedDrug = item
                    selectedTimings = []
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.itemName).font(Typography.secondary)
                            Text(item.entpName).font(Typography.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(isActive ? "복용 중" : "선택 ›")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isActive)
            }
            .listStyle(.plain)
        }
        .padding(.top)
    }

    private func timingPicker(for drug: DrugItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(drug.itemName).font(Typography.secondary.bold()).lineLimit(1)
                    Text(drug.entpName).font(Typography.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                ForEach(MedicationTiming.allCases) { timing in
                    Toggle(timing.label, isOn: timingBinding(timing))
                }
            }

            if let registerErrorMessage {
                Text(registerErrorMessage).font(Typography.caption).foregroundStyle(.red)
            }

            Button {
                Task { await register(drug) }
            } label: {
                if isRegistering {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("등록").font(Typography.button).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRegistering || selectedTimings.isEmpty)

            Spacer()
        }
        .padding()
    }

    private func timingBinding(_ timing: MedicationTiming) -> Binding<Bool> {
        Binding(
            get: { selectedTimings.contains(timing) },
            set: { isOn in
                if isOn { selectedTimings.insert(timing) } else { selectedTimings.remove(timing) }
            }
        )
    }

    private func search() async {
        let trimmed = searchInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchTerm = trimmed
        isSearching = true
        searchErrorMessage = nil
        do {
            results = try await MedicationService.searchDrugs(name: trimmed).items
        } catch {
            searchErrorMessage = error.localizedDescription
        }
        isSearching = false
    }

    private func register(_ drug: DrugItem) async {
        registerErrorMessage = nil
        isRegistering = true
        do {
            try await MedicationService.addMedication(
                name: drug.itemName,
                timings: Array(selectedTimings),
                itemSeq: drug.itemSeq,
                entpName: drug.entpName,
                itemImage: drug.itemImage,
                drugShape: drug.drugShape,
                colorClass: drug.colorClass,
                chart: drug.chart
            )
            await onRegistered()
            dismiss()
        } catch {
            registerErrorMessage = error.localizedDescription
        }
        isRegistering = false
    }
}
