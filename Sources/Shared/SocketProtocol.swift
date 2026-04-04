import Foundation

/// Length-prefixed message framing over Unix domain sockets.
///
/// Wire format:
///   [4 bytes: big-endian UInt32 payload length][N bytes: UTF-8 JSON payload]
public enum SocketProtocol {

    // MARK: - Write

    /// Encode a message into length-prefixed data.
    public static func encode(_ data: Data) -> Data {
        var length = UInt32(data.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(data)
        return frame
    }

    /// Encode a Codable value into a length-prefixed frame.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let payload = try JSONEncoder().encode(value)
        return encode(payload)
    }

    // MARK: - Read

    /// Read exactly `count` bytes from a file descriptor.
    /// Returns nil if the connection is closed or an error occurs.
    public static func readExact(fd: Int32, count: Int) -> Data? {
        var buffer = [UInt8](repeating: 0, count: count)
        var totalRead = 0
        while totalRead < count {
            let n = read(fd, &buffer[totalRead], count - totalRead)
            if n <= 0 { return nil }
            totalRead += n
        }
        return Data(buffer)
    }

    /// Read one length-prefixed message from a file descriptor.
    public static func readMessage(fd: Int32) -> Data? {
        guard let header = readExact(fd: fd, count: 4) else { return nil }
        let length = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard length > 0, length < 10_000_000 else { return nil } // 10MB safety limit
        return readExact(fd: fd, count: Int(length))
    }

    /// Read and decode a Codable message from a file descriptor.
    public static func readMessage<T: Decodable>(fd: Int32, as type: T.Type) -> T? {
        guard let data = readMessage(fd: fd) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Write to FD

    /// Write all data to a file descriptor.
    public static func writeAll(fd: Int32, data: Data) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            var totalWritten = 0
            let count = rawBuffer.count
            while totalWritten < count {
                let n = write(fd, baseAddress.advanced(by: totalWritten), count - totalWritten)
                if n <= 0 { return false }
                totalWritten += n
            }
            return true
        }
    }

    /// Encode and write a length-prefixed message to a file descriptor.
    public static func writeMessage(fd: Int32, data: Data) -> Bool {
        let frame = encode(data)
        return writeAll(fd: fd, data: frame)
    }

    /// Encode a Codable value and write it to a file descriptor.
    public static func writeMessage<T: Encodable>(fd: Int32, value: T) -> Bool {
        guard let frame = try? encode(value) else { return false }
        return writeAll(fd: fd, data: frame)
    }
}

// MARK: - Message Types

/// Wrapper message sent from bridge to main app.
public struct BridgeMessage: Codable, Sendable {
    public let type: String  // "hook_event"
    public let event: HookEventPayload
    public let source: String?  // "claude" or "codex"

    public init(event: HookEventPayload, source: String? = nil) {
        self.type = "hook_event"
        self.event = event
        self.source = source
    }
}

/// Raw hook event payload from Claude Code stdin.
public struct HookEventPayload: Codable, Sendable {
    public let session_id: String?
    public let transcript_path: String?
    public let cwd: String?
    public let permission_mode: String?
    public let hook_event_name: String?
    public let tool_name: String?
    public let tool_input: JSONValue?
    public let tool_result: JSONValue?
    public let user_prompt: String?
    public let reason: String?
    public let message: String?
    public let title: String?
}

/// Response from main app to bridge.
public struct BridgeResponse: Codable, Sendable {
    public let type: String
    public let decision: String?
    public let reason: String?
    /// For AskUserQuestion: updated tool input with answers injected.
    public let updatedInput: JSONValue?

    public static func ack() -> BridgeResponse {
        BridgeResponse(type: "ack", decision: nil, reason: nil, updatedInput: nil)
    }

    public static func allow() -> BridgeResponse {
        BridgeResponse(type: "hook_response", decision: "allow", reason: nil, updatedInput: nil)
    }

    public static func deny(reason: String) -> BridgeResponse {
        BridgeResponse(type: "hook_response", decision: "deny", reason: reason, updatedInput: nil)
    }

    /// Allow with updatedInput (for AskUserQuestion answers).
    public static func allowWithInput(_ input: JSONValue) -> BridgeResponse {
        BridgeResponse(type: "hook_response", decision: "allow", reason: nil, updatedInput: input)
    }
}

/// Hook output for PreToolUse hooks.
/// Format: { hookSpecificOutput: { permissionDecision: "allow" | "deny" } }
public struct PreToolUseHookOutput: Codable, Sendable {
    public let hookSpecificOutput: PreToolUseSpecificOutput?

    public init(decision: String, reason: String? = nil, updatedInput: JSONValue? = nil) {
        self.hookSpecificOutput = PreToolUseSpecificOutput(
            hookEventName: "PreToolUse",
            permissionDecision: decision,
            permissionDecisionReason: reason,
            updatedInput: updatedInput
        )
    }
}

public struct PreToolUseSpecificOutput: Codable, Sendable {
    public let hookEventName: String
    public let permissionDecision: String?
    public let permissionDecisionReason: String?
    public let updatedInput: JSONValue?
}

/// Hook output for PermissionRequest hooks.
/// Format: { hookSpecificOutput: { decision: { behavior: "allow" | "deny" } } }
public struct PermissionRequestHookOutput: Codable, Sendable {
    public let hookSpecificOutput: PermissionRequestSpecificOutput

    public init(behavior: String, message: String? = nil) {
        self.hookSpecificOutput = PermissionRequestSpecificOutput(
            hookEventName: "PermissionRequest",
            decision: PermissionRequestDecision(behavior: behavior, message: message)
        )
    }
}

public struct PermissionRequestSpecificOutput: Codable, Sendable {
    public let hookEventName: String  // Must be "PermissionRequest"
    public let decision: PermissionRequestDecision
}

public struct PermissionRequestDecision: Codable, Sendable {
    public let behavior: String  // "allow" or "deny"
    public let message: String?
}

// MARK: - Flexible JSON Value

/// A type-erased JSON value for handling arbitrary Claude Code payloads.
public enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }

    /// Get string value from a JSON object by key.
    public func getString(_ key: String) -> String? {
        if case .object(let dict) = self, case .string(let val) = dict[key] {
            return val
        }
        return nil
    }

    /// Pretty-print the JSON value as a summary string.
    public var summary: String {
        switch self {
        case .string(let s): return s.count > 100 ? String(s.prefix(100)) + "..." : s
        case .number(let n): return String(n)
        case .bool(let b): return String(b)
        case .object(let o): return "{\(o.keys.joined(separator: ", "))}"
        case .array(let a): return "[\(a.count) items]"
        case .null: return "null"
        }
    }
}
