import Foundation

struct LyricLine: Identifiable, Sendable {
    let id: UUID
    let timestamp: Double   // seconds
    let text: String

    init(timestamp: Double, text: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.text = text
    }
}
