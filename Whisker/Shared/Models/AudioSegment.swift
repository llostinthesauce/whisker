import Foundation

struct AudioSegment: Equatable, Sendable {
    let fileURL: URL
    let startTime: Date
    let durationSeconds: Double

    var endTime: Date {
        startTime.addingTimeInterval(durationSeconds)
    }
}
