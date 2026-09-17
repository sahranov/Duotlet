import Foundation

/// Serializes hardware reads off the display-link run loop. Only the result
/// returns to the main queue; a slow HID request cannot hold up a frame.
final class BackgroundLidReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Duotlet.lidReads", qos: .userInteractive)
    private let read: () -> Double?

    init(read: @escaping () -> Double?) { self.read = read }

    func sample(completion: @escaping (Double?) -> Void) {
        queue.async { [self] in
            let value = read()
            DispatchQueue.main.async { completion(value) }
        }
    }
}
