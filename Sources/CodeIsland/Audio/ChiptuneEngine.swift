import AVFoundation
import Foundation

/// 8-bit chiptune sound synthesizer using AVAudioEngine.
/// Generates retro game-style sound effects for app events.
@MainActor
final class ChiptuneEngine {
    static let shared = ChiptuneEngine()

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let sampleRate: Double = 44100
    private let format: AVAudioFormat

    var isMuted = false

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        setupEngine()
    }

    private func setupEngine() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.3

        do {
            try engine.start()
            self.audioEngine = engine
            self.playerNode = player
        } catch {
            print("[ChiptuneEngine] Failed to start: \(error)")
        }
    }

    // MARK: - Sound Effects

    /// Permission request alert - ascending arpeggio
    func playPermissionAlert() {
        guard !isMuted else { return }
        let notes: [(freq: Double, duration: Double)] = [
            (440, 0.08),   // A4
            (554, 0.08),   // C#5
            (659, 0.08),   // E5
            (880, 0.15),   // A5
        ]
        playArpeggio(notes, waveform: .square)
    }

    /// Permission approved - happy ascending
    func playApproved() {
        guard !isMuted else { return }
        let notes: [(freq: Double, duration: Double)] = [
            (523, 0.06),   // C5
            (659, 0.06),   // E5
            (784, 0.10),   // G5
        ]
        playArpeggio(notes, waveform: .square)
    }

    /// Permission denied - descending buzz
    func playDenied() {
        guard !isMuted else { return }
        let notes: [(freq: Double, duration: Double)] = [
            (330, 0.10),   // E4
            (247, 0.15),   // B3
        ]
        playArpeggio(notes, waveform: .square)
    }

    /// New session detected - soft ping
    func playSessionStart() {
        guard !isMuted else { return }
        let notes: [(freq: Double, duration: Double)] = [
            (880, 0.05),   // A5
            (1109, 0.10),  // C#6
        ]
        playArpeggio(notes, waveform: .triangle)
    }

    /// Session ended - descending tone
    func playSessionEnd() {
        guard !isMuted else { return }
        let notes: [(freq: Double, duration: Double)] = [
            (659, 0.06),   // E5
            (440, 0.10),   // A4
        ]
        playArpeggio(notes, waveform: .triangle)
    }

    /// Notification received - short blip
    func playNotification() {
        guard !isMuted else { return }
        let notes: [(freq: Double, duration: Double)] = [
            (1047, 0.04),  // C6
            (1319, 0.06),  // E6
        ]
        playArpeggio(notes, waveform: .square)
    }

    /// Tool use started - mechanical click
    func playToolUse() {
        guard !isMuted else { return }
        playNoise(duration: 0.02, volume: 0.15)
    }

    // MARK: - Waveform Generation

    private enum Waveform {
        case square
        case triangle
        case sawtooth
        case noise
    }

    private func generateSample(_ waveform: Waveform, phase: Double, frequency: Double) -> Float {
        switch waveform {
        case .square:
            // Square wave with slight duty cycle variation for richer tone
            let duty = 0.5
            return phase.truncatingRemainder(dividingBy: 1.0) < duty ? 0.3 : -0.3

        case .triangle:
            let p = phase.truncatingRemainder(dividingBy: 1.0)
            let v = p < 0.5 ? (p * 4.0 - 1.0) : (3.0 - p * 4.0)
            return Float(v * 0.3)

        case .sawtooth:
            let p = phase.truncatingRemainder(dividingBy: 1.0)
            return Float((p * 2.0 - 1.0) * 0.25)

        case .noise:
            return Float.random(in: -0.2...0.2)
        }
    }

    private func playArpeggio(_ notes: [(freq: Double, duration: Double)], waveform: Waveform) {
        guard let player = playerNode else { return }

        // Calculate total sample count
        let totalDuration = notes.reduce(0) { $0 + $1.duration }
        let totalSamples = Int(totalDuration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalSamples)) else { return }
        buffer.frameLength = AVAudioFrameCount(totalSamples)

        guard let channelData = buffer.floatChannelData?[0] else { return }

        var sampleIndex = 0
        var phase: Double = 0

        for note in notes {
            let noteSamples = Int(note.duration * sampleRate)
            let phaseIncrement = note.freq / sampleRate

            for i in 0..<noteSamples {
                // Volume envelope: quick attack, short decay
                let position = Double(i) / Double(noteSamples)
                let envelope: Double
                if position < 0.02 {
                    envelope = position / 0.02  // Attack
                } else if position > 0.7 {
                    envelope = (1.0 - position) / 0.3  // Release
                } else {
                    envelope = 1.0  // Sustain
                }

                let sample = generateSample(waveform, phase: phase, frequency: note.freq)
                channelData[sampleIndex] = sample * Float(envelope)

                phase += phaseIncrement
                sampleIndex += 1
            }
        }

        if !player.isPlaying {
            player.play()
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    private func playNoise(duration: Double, volume: Float) {
        guard let player = playerNode else { return }

        let totalSamples = Int(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalSamples)) else { return }
        buffer.frameLength = AVAudioFrameCount(totalSamples)

        guard let channelData = buffer.floatChannelData?[0] else { return }

        for i in 0..<totalSamples {
            let position = Double(i) / Double(totalSamples)
            let envelope = position < 0.1 ? position / 0.1 : (1.0 - position) / 0.9
            channelData[i] = Float.random(in: -1...1) * volume * Float(envelope)
        }

        if !player.isPlaying {
            player.play()
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }
}
