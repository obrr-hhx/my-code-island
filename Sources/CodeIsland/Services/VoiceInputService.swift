import AppKit
import AVFoundation
import Foundation
import Compression

/// Voice input service using Doubao Seed-ASR 2.0 (Volcengine) binary WebSocket protocol.
/// Captures microphone audio, streams to Doubao ASR, receives pure transcription.
@MainActor
@Observable
final class VoiceInputService {
    static let shared = VoiceInputService()

    var isListening = false
    var currentTranscript = ""
    var targetSession: TrackedSession?

    private var webSocketTask: URLSessionWebSocketTask?
    private var audioEngine: AVAudioEngine?
    private let inputSampleRate: Double = 16000
    private var sequenceNumber: Int32 = 1

    private init() {}

    // MARK: - Public API

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func startListening() {
        guard !isListening else { return }

        let appId = loadKey(CodeIslandConstants.doubaoAppIdPath)
        let accessToken = loadKey(CodeIslandConstants.doubaoAccessTokenPath)
        guard let appId, let accessToken, !appId.isEmpty, !accessToken.isEmpty else {
            print("[VoiceInput] Doubao App ID / Access Token not configured")
            return
        }

        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    if granted { self?.startListening() }
                    else { print("[VoiceInput] Microphone permission denied") }
                }
            }
            return
        default:
            print("[VoiceInput] Microphone permission not granted")
            return
        }

        currentTranscript = ""
        sequenceNumber = 1
        hasFinished = false
        isListening = true
        ChiptuneEngine.shared.isMuted = true

        connectDoubao(appId: appId, accessToken: accessToken)
        print("[VoiceInput] Started listening")
    }

    func stopListening() {
        guard isListening else { return }
        isListening = false

        stopAudioCapture()

        // Send final audio packet with negative sequence
        sendFinalPacket()

        ChiptuneEngine.shared.isMuted = false

        print("[VoiceInput] Stopped, waiting for final transcript...")

        // Wait up to 2 seconds for final response, then finish with what we have
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            // Only finish if we haven't already
            let transcript = self.currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcript.isEmpty {
                print("[VoiceInput] Timeout, finishing with current transcript")
                self.finishWithTranscript()
            }
        }
    }

    // MARK: - API Keys

    func loadKey(_ path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func saveKey(_ key: String, to path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? key.trimmingCharacters(in: .whitespacesAndNewlines).write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Doubao WebSocket

    private func connectDoubao(appId: String, accessToken: String) {
        let url = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel")!
        var request = URLRequest(url: url)
        request.setValue(appId, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue("volc.bigasr.sauc.duration", forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Connect-Id")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        print("[VoiceInput] Connecting to Doubao ASR...")

        // Send session init, then start receiving + audio capture
        sendSessionInit()
        receiveMessages()

        // Start audio capture after a brief delay for connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isListening else { return }
            self.startAudioCapture()
        }
    }

    // MARK: - Binary Protocol

    /// Build 4-byte protocol header
    private func buildHeader(msgType: UInt8, flags: UInt8, serialization: UInt8, compression: UInt8) -> Data {
        var header = Data(count: 4)
        header[0] = 0x11 // version=1, headerSize=1
        header[1] = (msgType << 4) | flags
        header[2] = (serialization << 4) | compression
        header[3] = 0x00
        return header
    }

    /// Send session init (CLIENT_FULL_REQUEST)
    private func sendSessionInit() {
        let payload: [String: Any] = [
            "user": ["uid": "code-island"],
            "audio": [
                "format": "pcm",
                "codec": "raw",
                "rate": 16000,
                "bits": 16,
                "channel": 1
            ],
            "request": [
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "enable_ddc": true,
                "show_utterances": true,
                "result_type": "full"
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let compressed = gzipCompress(jsonData) else {
            print("[VoiceInput] Failed to build session init")
            return
        }

        // Header: type=0x1 (full request), flags=0x1 (pos seq), serial=0x1 (JSON), compress=0x1 (gzip)
        var packet = buildHeader(msgType: 0x1, flags: 0x1, serialization: 0x1, compression: 0x1)

        // Sequence number (4 bytes, big-endian, signed)
        var seq = sequenceNumber.bigEndian
        packet.append(Data(bytes: &seq, count: 4))
        sequenceNumber += 1

        // Payload size (4 bytes, big-endian)
        var size = UInt32(compressed.count).bigEndian
        packet.append(Data(bytes: &size, count: 4))

        // Compressed payload
        packet.append(compressed)

        webSocketTask?.send(.data(packet)) { error in
            if let error { print("[VoiceInput] Init send error: \(error)") }
            else { print("[VoiceInput] Session init sent") }
        }
    }

    /// Send audio chunk (CLIENT_AUDIO_ONLY_REQUEST)
    private func sendAudioPacket(_ pcmData: Data) {
        guard let compressed = gzipCompress(pcmData) else { return }

        // Header: type=0x2 (audio only), flags=0x1 (pos seq), serial=0x0 (raw), compress=0x1 (gzip)
        var packet = buildHeader(msgType: 0x2, flags: 0x1, serialization: 0x0, compression: 0x1)

        var seq = sequenceNumber.bigEndian
        packet.append(Data(bytes: &seq, count: 4))
        sequenceNumber += 1

        var size = UInt32(compressed.count).bigEndian
        packet.append(Data(bytes: &size, count: 4))

        packet.append(compressed)

        webSocketTask?.send(.data(packet)) { _ in }
    }

    /// Send final packet with negative sequence to signal end of audio
    private func sendFinalPacket() {
        let emptyAudio = Data(count: 0)
        let compressed = gzipCompress(emptyAudio) ?? Data()

        // Header: type=0x2 (audio only), flags=0x2 (neg seq = last), serial=0x0, compress=0x1
        var packet = buildHeader(msgType: 0x2, flags: 0x2, serialization: 0x0, compression: 0x1)

        var negSeq = (-sequenceNumber).bigEndian
        packet.append(Data(bytes: &negSeq, count: 4))

        var size = UInt32(compressed.count).bigEndian
        packet.append(Data(bytes: &size, count: 4))

        packet.append(compressed)

        webSocketTask?.send(.data(packet)) { error in
            if let error { print("[VoiceInput] Final packet error: \(error)") }
            else { print("[VoiceInput] Final packet sent") }
        }
    }

    // MARK: - Receive & Parse

    private func receiveMessages() {
        guard let task = webSocketTask, task.state == .running else { return }
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.webSocketTask != nil else { return }
                switch result {
                case .success(.data(let data)):
                    self.parseResponse(data)
                    self.receiveMessages()
                case .success(.string(let text)):
                    print("[VoiceInput] Unexpected text: \(text.prefix(100))")
                    self.receiveMessages()
                case .failure(let error):
                    print("[VoiceInput] Receive error: \(error.localizedDescription)")
                @unknown default:
                    break
                }
            }
        }
    }

    private func parseResponse(_ msg: Data) {
        guard msg.count >= 4 else { print("[VoiceInput] Response too short: \(msg.count)"); return }

        let headerSize = Int(msg[0] & 0x0F) * 4
        let messageType = msg[1] >> 4
        let messageFlags = msg[1] & 0x0F
        let compression = msg[2] & 0x0F

        let isFinal = (messageFlags & 0x02) != 0
        print("[VoiceInput] Response: type=0x\(String(messageType, radix: 16)) flags=0x\(String(messageFlags, radix: 16)) compress=\(compression) final=\(isFinal) size=\(msg.count)")

        var payload = msg[headerSize...]

        // Skip sequence number if present
        if (messageFlags & 0x01) != 0 || (messageFlags & 0x02) != 0 {
            guard payload.count >= 4 else { print("[VoiceInput] No seq data"); return }
            payload = payload.dropFirst(4)
        }

        // Error response
        if messageType == 0x0F {
            guard payload.count >= 8 else { return }
            let errorCode = payload.prefix(4).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
            let payloadSize = payload.dropFirst(4).prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            payload = payload.dropFirst(8)
            if compression == 0x01, let decompressed = gzipDecompress(Data(payload)) {
                let errMsg = String(data: decompressed, encoding: .utf8) ?? "?"
                print("[VoiceInput] Server error \(errorCode): \(errMsg)")
            } else {
                print("[VoiceInput] Server error \(errorCode), size=\(payloadSize)")
            }
            disconnectWebSocket()
            return
        }

        // Full response
        if messageType == 0x09 {
            guard payload.count >= 4 else { print("[VoiceInput] No payload size"); return }
            payload = payload.dropFirst(4) // skip payload size
        }

        guard !payload.isEmpty else { print("[VoiceInput] Empty payload"); return }

        var jsonData: Data
        if compression == 0x01 {
            guard let decompressed = gzipDecompress(Data(payload)) else {
                print("[VoiceInput] Gzip decompress failed, raw \(payload.count) bytes")
                return
            }
            jsonData = decompressed
        } else {
            jsonData = Data(payload)
        }

        let jsonStr = String(data: jsonData, encoding: .utf8) ?? "?"
        print("[VoiceInput] JSON: \(jsonStr.prefix(200))")

        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("[VoiceInput] JSON parse failed")
            return
        }

        // Extract utterances from result
        if let result = json["result"] as? [String: Any],
           let utterances = result["utterances"] as? [[String: Any]] {
            var definite = ""
            var pending = ""
            for utt in utterances {
                let text = utt["text"] as? String ?? ""
                if utt["definite"] as? Bool == true {
                    definite += text
                } else {
                    pending += text
                }
            }
            currentTranscript = definite + pending

            if !currentTranscript.isEmpty {
                print("[VoiceInput] Transcript: definite=[\(definite)] pending=[\(pending)]")
            }
        }

        if isFinal {
            print("[VoiceInput] Final response received")
            finishWithTranscript()
        }
    }

    private var hasFinished = false

    private func finishWithTranscript() {
        guard !hasFinished else { return }
        hasFinished = true

        let transcript = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        disconnectWebSocket()

        if !transcript.isEmpty {
            print("[VoiceInput] Final transcript: \(transcript)")
            print("[VoiceInput] targetSession: \(targetSession?.session.sessionId ?? "nil")")
            // Re-activate the target terminal before pasting
            if let session = targetSession {
                print("[VoiceInput] Jumping to terminal for session \(session.session.projectName)")
                TerminalJumper.jump(to: session)
            } else {
                // No target session — just activate the frontmost terminal
                print("[VoiceInput] No target session, activating frontmost app")
                activateFrontmostTerminal()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                TerminalTyper.typeAndSend(transcript)
            }
        } else {
            print("[VoiceInput] No transcript received")
        }
    }

    private func disconnectWebSocket() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    // MARK: - Audio Capture

    private func startAudioCapture() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        print("[VoiceInput] Hardware format: \(hwFormat.sampleRate)Hz, \(hwFormat.channelCount)ch")

        guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: hwFormat.sampleRate, channels: 1) else {
            print("[VoiceInput] Failed to create mono format")
            return
        }

        var chunkCount = 0

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: monoFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let pcmData = self.convertToInt16PCM(buffer: buffer, targetRate: self.inputSampleRate)
            guard !pcmData.isEmpty else { return }

            chunkCount += 1
            if chunkCount <= 3 {
                var maxSample: Int16 = 0
                pcmData.withUnsafeBytes { raw in
                    let samples = raw.bindMemory(to: Int16.self)
                    for i in 0..<samples.count { maxSample = max(maxSample, abs(samples[i])) }
                }
                print("[VoiceInput] Audio #\(chunkCount): \(pcmData.count)B peak=\(String(format: "%.3f", Float(maxSample)/32767.0))")
            }

            Task { @MainActor in
                self.sendAudioPacket(pcmData)
            }
        }

        do {
            try engine.start()
            self.audioEngine = engine
            print("[VoiceInput] Audio engine started")
        } catch {
            print("[VoiceInput] Failed to start audio engine: \(error)")
        }
    }

    private nonisolated func convertToInt16PCM(buffer: AVAudioPCMBuffer, targetRate: Double) -> Data {
        guard let floatData = buffer.floatChannelData else { return Data() }
        let frameCount = Int(buffer.frameLength)
        let srcRate = buffer.format.sampleRate
        let channels = Int(buffer.format.channelCount)
        guard frameCount > 0, srcRate > 0 else { return Data() }

        let ratio = srcRate / targetRate
        let outFrames = Int(Double(frameCount) / ratio)
        guard outFrames > 0 else { return Data() }

        var pcmBytes = Data(capacity: outFrames * 2)
        for i in 0..<outFrames {
            let srcIdx = min(Int(Double(i) * ratio), frameCount - 1)
            var sample: Float = 0
            for ch in 0..<channels { sample += floatData[ch][srcIdx] }
            sample /= Float(channels)
            var int16 = Int16(max(-1, min(1, sample)) * 32767)
            pcmBytes.append(Data(bytes: &int16, count: 2))
        }
        return pcmBytes
    }

    /// Activate the most likely terminal app (iTerm2, Terminal, etc.)
    private func activateFrontmostTerminal() {
        let terminalBundleIDs = [
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "com.mitchellh.ghostty",
            "dev.warp.Warp-Stable",
        ]
        for app in NSWorkspace.shared.runningApplications {
            if let bid = app.bundleIdentifier, terminalBundleIDs.contains(bid) {
                app.activate()
                print("[VoiceInput] Activated \(bid)")
                return
            }
        }
        print("[VoiceInput] No terminal app found to activate")
    }

    private func stopAudioCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    // MARK: - Gzip

    private nonisolated func gzipCompress(_ data: Data) -> Data? {
        // Gzip header
        var compressed = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])

        // Deflate
        let bufferSize = max(data.count + 256, 1024)
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        let compressedSize = data.withUnsafeBytes { srcPtr -> Int in
            guard let src = srcPtr.baseAddress else { return 0 }
            return compression_encode_buffer(&buffer, bufferSize, src.assumingMemoryBound(to: UInt8.self), data.count, nil, COMPRESSION_ZLIB)
        }
        guard compressedSize > 0 else { return nil }
        compressed.append(Data(buffer[0..<compressedSize]))

        // Gzip footer: CRC32 + original size
        let crc = crc32(data)
        var crcLE = crc.littleEndian
        compressed.append(Data(bytes: &crcLE, count: 4))
        var sizeLE = UInt32(data.count).littleEndian
        compressed.append(Data(bytes: &sizeLE, count: 4))

        return compressed
    }

    private nonisolated func gzipDecompress(_ data: Data) -> Data? {
        // Skip gzip header (minimum 10 bytes)
        guard data.count > 18 else { return nil }
        var offset = 10
        let flags = data[3]
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= data.count else { return nil }
            let extraLen = Int(data[offset]) | (Int(data[offset+1]) << 8)
            offset += 2 + extraLen
        }
        if flags & 0x08 != 0 { // FNAME
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 } // FHCRC

        let compressedData = data[offset..<(data.count - 8)]
        guard !compressedData.isEmpty else { return nil }

        let bufferSize = 1024 * 1024 // 1MB max
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        let decompressedSize = compressedData.withUnsafeBytes { srcPtr -> Int in
            guard let src = srcPtr.baseAddress else { return 0 }
            return compression_decode_buffer(&buffer, bufferSize, src.assumingMemoryBound(to: UInt8.self), compressedData.count, nil, COMPRESSION_ZLIB)
        }
        guard decompressedSize > 0 else { return nil }
        return Data(buffer[0..<decompressedSize])
    }

    private nonisolated func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.forEach { byte in
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 != 0 ? 0xEDB88320 : 0)
            }
        }
        return ~crc
    }
}
