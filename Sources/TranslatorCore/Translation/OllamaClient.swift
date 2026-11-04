import Foundation

public enum BackendHealth: Sendable, Equatable {
    case ok, unreachable
    case modelMissing(String)
}

public enum BackendError: Error, Equatable {
    case unreachable
    case http(Int)
    case malformedResponse
}

public protocol TranslationBackend: Sendable {
    /// Returns translations keyed by `TranslationItem.id`. Ids may be missing
    /// if the model skipped some; callers must check.
    func translate(_ items: [TranslationItem], context: [ContextPair], hints: [ValidationIssue]) async throws -> [Int: String]
    func health() async -> BackendHealth
}

public struct OllamaClient: TranslationBackend {
    private let baseURL: URL
    private let model: String
    private let glossary: Glossary
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        model: String,
        glossary: Glossary,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.model = model
        self.glossary = glossary
        self.session = session
    }

    public func translate(_ items: [TranslationItem], context: [ContextPair], hints: [ValidationIssue]) async throws -> [Int: String] {
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "keep_alive": "2h",
            "think": false,
            "options": ["temperature": 0],
            "format": PromptBuilder.responseSchema,
            "messages": [
                ["role": "system", "content": PromptBuilder.systemPrompt(glossary: glossary)],
                ["role": "user", "content": PromptBuilder.userMessage(items: items, context: context, hints: hints)],
            ],
        ]
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"), timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        struct ChatResponse: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        struct Translations: Decodable {
            struct Item: Decodable { let id: Int; let ko: String }
            let translations: [Item]
        }
        guard let chat = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let parsed = try? JSONDecoder().decode(Translations.self, from: Data(chat.message.content.utf8))
        else { throw BackendError.malformedResponse }
        return Dictionary(parsed.translations.map { ($0.id, $0.ko) }, uniquingKeysWith: { first, _ in first })
    }

    public func health() async -> BackendHealth {
        let request = URLRequest(url: baseURL.appendingPathComponent("api/tags"), timeoutInterval: 5)
        struct Tags: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        guard let data = try? await send(request) else { return .unreachable }
        guard let tags = try? JSONDecoder().decode(Tags.self, from: data) else { return .unreachable }
        let names = Set(tags.models.map(\.name))
        let installed = names.contains(model) || (!model.contains(":") && names.contains(model + ":latest"))
        return installed ? .ok : .modelMissing(model)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendError.unreachable
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw BackendError.http(http.statusCode)
        }
        return data
    }
}
