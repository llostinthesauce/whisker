import Foundation

struct KeyboardLiveTranscriptEdit: Equatable {
    let deleteCharacterCount: Int
    let insertText: String

    var isEmpty: Bool {
        deleteCharacterCount == 0 && insertText.isEmpty
    }
}

struct KeyboardLiveTranscriptInserter {
    private(set) var insertedText = ""

    mutating func updateLiveText(_ text: String) -> KeyboardLiveTranscriptEdit? {
        let nextText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextText.isEmpty else { return nil }

        if nextText.hasPrefix(insertedText) {
            let delta = String(nextText.dropFirst(insertedText.count))
            insertedText = nextText
            guard !delta.isEmpty else { return nil }
            return KeyboardLiveTranscriptEdit(deleteCharacterCount: 0, insertText: delta)
        }

        let edit = KeyboardLiveTranscriptEdit(
            deleteCharacterCount: insertedText.count,
            insertText: nextText
        )
        insertedText = nextText
        return edit.isEmpty ? nil : edit
    }

    mutating func finalize(with finalText: String) -> KeyboardLiveTranscriptEdit? {
        let text = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let edit = KeyboardLiveTranscriptEdit(
            deleteCharacterCount: insertedText.count,
            insertText: text
        )
        insertedText = ""
        return edit.isEmpty ? nil : edit
    }

    mutating func reset() {
        insertedText = ""
    }
}
