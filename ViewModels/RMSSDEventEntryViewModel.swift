import Foundation

@MainActor
@Observable
final class RMSSDEventEntryViewModel {
    let pendingEvent: RMSSDThresholdAlertCenter.PendingEvent

    var selectedEmotion: RMSSDEmotion = .calm
    var note = ""
    private(set) var isSaving = false
    var errorMessage: String?

    init(pendingEvent: RMSSDThresholdAlertCenter.PendingEvent) {
        self.pendingEvent = pendingEvent
    }

    func save() async -> Bool {
        errorMessage = nil
        isSaving = true
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = RMSSDEventRequest(
            occurredAt: DateKey.isoString(from: pendingEvent.occurredAt),
            rmssdValue: pendingEvent.rmssdValue,
            direction: pendingEvent.direction.rawValue,
            emotion: selectedEmotion.rawValue,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
        do {
            try await RMSSDEventService.logEvent(request)
            isSaving = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            return false
        }
    }
}
