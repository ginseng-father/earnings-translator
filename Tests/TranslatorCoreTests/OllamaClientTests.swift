import Foundation
import Testing
@testable import TranslatorCore

/// Serves canned responses to URLSession requests made in these tests.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (Int, Data)
    nonisolated(unsafe) static var handler: Handler?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let (status, data) = Self.handler!(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

@Suite(.serialized)
struct OllamaClientTests {
    let items = [TranslationItem(id: 1, english: "Revenue grew.")]

    func client(model: String = "gemma4:12b") -> OllamaClient {
        OllamaClient(model: model, glossary: .standard, session: StubURLProtocol.session())
    }

    func chatReply(_ content: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["message": ["role": "assistant", "content": content]])
    }

    @Test func sendsStructuredChatRequest() async throws {
        StubURLProtocol.handler = { _ in (200, self.chatReply(#"{"translations":[{"id":1,"ko":"매출이 성장했습니다."}]}"#)) }
        _ = try await client().translate(items, context: [], hints: [])

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/chat")
        let body = try #require(JSONSerialization.jsonObject(with: StubURLProtocol.lastBody ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "gemma4:12b")
        #expect(body["stream"] as? Bool == false)
        #expect(body["keep_alive"] as? String == "2h")
        #expect(body["think"] as? Bool == false)
        #expect((body["options"] as? [String: Any])?["temperature"] as? Int == 0)
        // gemma4 on Ollama 0.40 rejects any `format` with HTTP 501.
        #expect(body["format"] == nil)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["system", "user"])
    }

    @Test func decodesTranslations() async throws {
        StubURLProtocol.handler = { _ in (200, self.chatReply(#"{"translations":[{"id":1,"ko":"매출이 성장했습니다."},{"id":2,"ko":"감사합니다."}]}"#)) }
        let result = try await client().translate(items, context: [], hints: [])
        #expect(result == [1: "매출이 성장했습니다.", 2: "감사합니다."])
    }

    @Test func decodesFencedJSONWithSurroundingText() async throws {
        let content = "다음과 같습니다:\n```json\n{\"translations\":[{\"id\":1,\"ko\":\"매출이 성장했습니다.\"}]}\n```"
        StubURLProtocol.handler = { _ in (200, self.chatReply(content)) }
        #expect(try await client().translate(items, context: [], hints: []) == [1: "매출이 성장했습니다."])
    }

    @Test func nonJSONContentIsMalformed() async {
        StubURLProtocol.handler = { _ in (200, self.chatReply("매출이 성장했습니다.")) }
        await #expect(throws: BackendError.malformedResponse) {
            try await client().translate(items, context: [], hints: [])
        }
    }

    @Test func httpErrorIsReported() async {
        StubURLProtocol.handler = { _ in (404, Data(#"{"error":"model not found"}"#.utf8)) }
        await #expect(throws: BackendError.http(404)) {
            try await client().translate(items, context: [], hints: [])
        }
    }

    @Test func connectionRefusedIsUnreachable() async {
        let client = OllamaClient(baseURL: URL(string: "http://127.0.0.1:9")!, model: "gemma4:12b", glossary: .standard)
        await #expect(throws: BackendError.unreachable) {
            try await client.translate(items, context: [], hints: [])
        }
        #expect(await client.health() == .unreachable)
    }

    @Test func healthChecksInstalledModels() async {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/tags")
            return (200, Data(#"{"models":[{"name":"gemma4:12b"},{"name":"qwen3:14b"}]}"#.utf8))
        }
        #expect(await client().health() == .ok)
        #expect(await client(model: "gemma4:26b").health() == .modelMissing("gemma4:26b"))
    }
}
