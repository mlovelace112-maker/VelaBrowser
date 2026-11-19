import Foundation
import Security

/// The Claude models Vela can use.
enum ClaudeModel: String, CaseIterable, Identifiable, Codable {
    case haiku = "claude-haiku-5-5"
    case sonnet = "claude-sonnet-5-5"
    case opus = "claude-opus-5-5"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .haiku: "Haiku 5.5"
        case .sonnet: "Sonnet 5.5"
        case .opus: "Opus 5.5"
        }
    }

    var detail: String {
        switch self {
        case .haiku: "Fastest and cheapest"
        case .sonnet: "Fast and smart"
        case .opus: "Smartest, for harder tasks"
        }
    }
}

/// One request to Claude.
struct ClaudeRequest {
    var model: ClaudeModel
    var system: String
    /// The conversation so far, in the API's own shape:
    /// `["role": "user", "content": ...]`.
    var messages: [[String: Any]]
    var tools: [[String: Any]] = []
    var maxTokens = 32_000
    /// "low", "medium", "high"… nil uses the model's default.
    var effort: String?
}

/// What Claude sent back, rebuilt from the stream.
struct ClaudeResponse {
    /// Claude's reply exactly as sent (text, thinking and tool requests), so it
    /// can be sent back unchanged in the next request.
    var content: [[String: Any]] = []
    /// Why Claude stopped: "end_turn", "tool_use", "max_tokens", "refusal"…
    var stopReason: String?
    /// Tool requests whose input arrived damaged and must not be run.
    var invalidToolIDs: Set<String> = []

    var toolUses: [[String: Any]] {
        content.filter { $0["type"] as? String == "tool_use" }
    }

    var text: String {
        content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
    }
}

enum ClaudeError: LocalizedError {
    case noKey
    case server(status: Int, message: String)
    case stream(String)

    var errorDescription: String? {
        switch self {
        case .noKey:
            "Add your Anthropic API key in Vela ▸ Settings ▸ Claude."
        case .server(401, _):
            "Anthropic didn't accept your API key. Check it in Vela ▸ Settings ▸ Claude."
        case .server(429, _):
            "You've hit your Anthropic rate limit. Wait a moment and try again."
        case .server(529, _):
            "Claude is very busy right now. Try again in a moment, or pick another model."
        case .server(let status, let message):
            message.isEmpty ? "Claude returned an error (\(status))." : message
        case .stream(let message):
            message
        }
    }
}

/// Talks to the Claude API (api.anthropic.com).
///
/// **Why plain HTTP?** Anthropic has no official Swift library, so Vela sends
/// the same JSON a `curl` command would. Replies are *streamed*: the server
/// sends the answer a few words at a time as "server-sent events", which is
/// why text appears in Vela as Claude writes it.
///
/// Your API key lives in the macOS Keychain, never in a file.
@MainActor
enum ClaudeClient {
    static let keychain = KeychainSecret(service: "Vela Claude", account: "api-key")

    /// Sends a request and streams the reply. `onText` gets each new piece of
    /// text as it arrives.
    static func stream(
        _ request: ClaudeRequest,
        onText: @MainActor (String) -> Void
    ) async throws -> ClaudeResponse {
        guard let apiKey = keychain.read() else { throw ClaudeError.noKey }

        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")

        // Thinking is left out on purpose: these models think when it helps.
        var body: [String: Any] = [
            "model": request.model.rawValue,
            "max_tokens": request.maxTokens,
            "stream": true,
            "system": request.system,
            "messages": request.messages,
        ]
        if !request.tools.isEmpty { body["tools"] = request.tools }
        if let effort = request.effort { body["output_config"] = ["effort": effort] }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var text = ""
            for try await line in bytes.lines { text += line }
            throw ClaudeError.server(status: status, message: errorMessage(in: text))
        }

        // Rebuild each content block from the events that describe it.
        var blocks: [Int: [String: Any]] = [:]
        var toolInput: [Int: String] = [:]
        var result = ClaudeResponse()

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            let index = event["index"] as? Int ?? 0

            switch type {
            case "content_block_start":
                if let block = event["content_block"] as? [String: Any] {
                    blocks[index] = block
                    if block["type"] as? String == "tool_use" { toolInput[index] = "" }
                }

            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any], var block = blocks[index] else { continue }
                switch delta["type"] as? String {
                case "text_delta":
                    let piece = delta["text"] as? String ?? ""
                    block["text"] = (block["text"] as? String ?? "") + piece
                    onText(piece)
                case "thinking_delta":
                    block["thinking"] = (block["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
                case "signature_delta":
                    block["signature"] = delta["signature"]
                case "input_json_delta":
                    toolInput[index, default: ""] += delta["partial_json"] as? String ?? ""
                default:
                    break
                }
                blocks[index] = block

            case "content_block_stop":
                // A tool request's input arrives in pieces. Check it strictly
                // once it's complete: damaged input must never be acted on.
                guard var block = blocks[index], block["type"] as? String == "tool_use" else { continue }
                let json = toolInput[index] ?? ""
                if json.isEmpty {
                    block["input"] = [String: Any]()
                } else if let data = json.data(using: .utf8),
                          let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    block["input"] = input
                } else {
                    block["input"] = [String: Any]()
                    if let id = block["id"] as? String { result.invalidToolIDs.insert(id) }
                }
                blocks[index] = block

            case "message_delta":
                if let delta = event["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
                    result.stopReason = reason
                }

            case "error":
                let error = event["error"] as? [String: Any]
                throw ClaudeError.stream(error?["message"] as? String ?? "The connection to Claude was interrupted.")

            default:
                break
            }
        }

        result.content = blocks.keys.sorted().compactMap { blocks[$0] }
        // A tool request cut off mid-way has incomplete input too.
        if result.stopReason == "max_tokens" {
            for block in result.toolUses {
                if let id = block["id"] as? String { result.invalidToolIDs.insert(id) }
            }
        }
        return result
    }

    /// Pulls `error.message` out of an API error reply.
    private static func errorMessage(in text: String) -> String {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else { return "" }
        return message
    }
}

/// A secret (like an API key) kept in the macOS Keychain.
struct KeychainSecret {
    let service: String
    let account: String

    private var match: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() -> String? {
        var query = match
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }

    /// Saves the secret, or deletes it when `value` is empty.
    func write(_ value: String) {
        SecItemDelete(match as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var item = match
        item[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
