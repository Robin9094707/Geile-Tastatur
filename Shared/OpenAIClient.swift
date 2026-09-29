import Foundation

enum OpenAIClientError: LocalizedError {
    case missingKey
    case invalidResponse
    case requestFailed(Int, String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Bitte zuerst einen OpenAI API-Key in der App hinterlegen."
        case .invalidResponse:
            return "Die OpenAI-Antwort konnte nicht verarbeitet werden."
        case let .requestFailed(code, message):
            return "OpenAI-Fehler \(code): \(message)"
        case .emptyResult:
            return "OpenAI hat keinen Text zurückgegeben."
        }
    }
}

struct OpenAIClient {
    static let shared = OpenAIClient()

    func transcribe(fileURL: URL, apiKey: String, model: String = "gpt-transcribe") async throws -> String {
        guard !apiKey.isEmpty else { throw OpenAIClientError.missingKey }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let audioData = try Data(contentsOf: fileURL)
        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        append("\r\n--\(boundary)--\r\n")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        try validate(response: response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw OpenAIClientError.invalidResponse
        }

        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw OpenAIClientError.emptyResult }
        return clean
    }

    func cleanTranscript(_ transcript: String, apiKey: String, model: String) async throws -> String {
        let instructions = """
        Du bist ein extrem präziser Diktat-Editor. Gib ausschließlich den finalen Text zurück.
        Entferne Versprecher, Füllwörter und abgebrochene Formulierungen nur dann, wenn die Korrektur aus dem Gesagten eindeutig hervorgeht.
        Wenn der Sprecher sich selbst korrigiert (z. B. „nein, ich meinte ...“), behalte nur die korrigierte Fassung.
        Setze natürliche deutsche Zeichensetzung, Groß-/Kleinschreibung und Absätze.
        Erfinde niemals neue Fakten oder Inhalte und ändere nicht die Bedeutung.
        """
        return try await responsesText(
            input: transcript,
            instructions: instructions,
            apiKey: apiKey,
            model: model,
            maxOutputTokens: 1200
        )
    }

    func suggestions(context: String, apiKey: String, model: String) async throws -> [String] {
        let instructions = """
        Erzeuge genau drei sehr kurze, natürliche Schreibvorschläge, die zum bisherigen Text passen.
        Keine Erklärungen. Trenne die drei Vorschläge ausschließlich mit |||.
        Schreibe in derselben Sprache wie der Kontext.
        """
        let result = try await responsesText(
            input: context,
            instructions: instructions,
            apiKey: apiKey,
            model: model,
            maxOutputTokens: 160
        )

        return result
            .components(separatedBy: "|||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { $0 }
    }

    private func responsesText(
        input: String,
        instructions: String,
        apiKey: String,
        model: String,
        maxOutputTokens: Int
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw OpenAIClientError.missingKey }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let payload: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": input,
            "max_output_tokens": maxOutputTokens
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [[String: Any]] else {
            throw OpenAIClientError.invalidResponse
        }

        var pieces: [String] = []
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content where (part["type"] as? String) == "output_text" {
                if let text = part["text"] as? String {
                    pieces.append(text)
                }
            }
        }

        let result = pieces.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw OpenAIClientError.emptyResult }
        return result
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message: String
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let value = error["message"] as? String {
                message = value
            } else {
                message = String(data: data, encoding: .utf8) ?? "Unbekannter Fehler"
            }
            throw OpenAIClientError.requestFailed(http.statusCode, message)
        }
    }
}
