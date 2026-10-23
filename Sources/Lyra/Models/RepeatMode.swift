import Foundation

enum RepeatMode: Int, CaseIterable, Sendable {
    case off = 0
    case all = 1
    case one = 2

    var symbolName: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    var label: String {
        switch self {
        case .off: return "Off"
        case .all: return "All"
        case .one: return "One"
        }
    }

    func next() -> RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}
