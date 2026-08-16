#if os(macOS)
import AppKit
import Foundation

enum CommandFlowSounds {
    private static var playing: [NSSound] = []

    static func play(_ outcome: CommandOutcome) {
        playing.removeAll { !$0.isPlaying }
        switch outcome {
        case .success:
            playTones([(frequency: 1046, duration: 0.18)])
        case .warning:
            playTones([
                (frequency: 622, duration: 0.12),
                (frequency: 466, duration: 0.16)
            ])
        case .error:
            playTones([
                (frequency: 196, duration: 0.14),
                (frequency: 165, duration: 0.14),
                (frequency: 131, duration: 0.22)
            ])
        }
    }

    private static func playTones(_ notes: [(frequency: Double, duration: TimeInterval)]) {
        guard let sound = NSSound(data: wav(notes: notes)) else {
            NSSound.beep()
            return
        }
        sound.volume = 1
        playing.append(sound)
        sound.play()
    }

    private static func wav(notes: [(frequency: Double, duration: TimeInterval)]) -> Data {
        let sampleRate = 44_100.0
        let gap = 0.06
        var samples: [Int16] = []
        for (index, note) in notes.enumerated() {
            samples.append(contentsOf: tone(frequency: note.frequency, duration: note.duration, sampleRate: sampleRate))
            if index < notes.count - 1 {
                samples.append(contentsOf: [Int16](repeating: 0, count: Int(sampleRate * gap)))
            }
        }

        let dataSize = samples.count * 2
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(littleEndian: UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        data.append(littleEndian: UInt32(16))
        data.append(littleEndian: UInt16(1))
        data.append(littleEndian: UInt16(1))
        data.append(littleEndian: UInt32(sampleRate))
        data.append(littleEndian: UInt32(sampleRate * 2))
        data.append(littleEndian: UInt16(2))
        data.append(littleEndian: UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        data.append(littleEndian: UInt32(dataSize))
        samples.withUnsafeBufferPointer { buffer in
            data.append(contentsOf: UnsafeRawBufferPointer(buffer))
        }
        return data
    }

    private static func tone(frequency: Double, duration: TimeInterval, sampleRate: Double) -> [Int16] {
        let count = Int(sampleRate * duration)
        let attack = min(800, count / 6)
        let release = min(1_600, count / 3)
        return (0..<count).map { index in
            let fadeIn = min(1, Double(index) / Double(max(attack, 1)))
            let fadeOut = min(1, Double(count - index) / Double(max(release, 1)))
            let sample = sin(2 * .pi * frequency * Double(index) / sampleRate) * fadeIn * fadeOut
            return Int16((sample * 0.9 * Double(Int16.max)).rounded())
        }
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
#endif
