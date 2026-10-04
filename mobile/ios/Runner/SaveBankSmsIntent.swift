import AppIntents
import Foundation

@available(iOS 16.0, *)
struct SaveBankSmsIntent: AppIntent {
    static var title: LocalizedStringResource = "Save data to Takings"
    static var description = IntentDescription("Files a bank SMS against the matching account.")
    static var openAppWhenRun = false

    @Parameter(title: "message", default: "")
    var message: String

    @Parameter(title: "sender", default: "")
    var sender: String

    static var parameterSummary: some ParameterSummary {
        Summary("Save data to Takings") {
            \.$message
            \.$sender
        }
    }

    func perform() async throws -> some IntentResult {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return .result()
        }
        let defaults = UserDefaults.standard
        guard let token = defaults.string(forKey: "flutter.token"), !token.isEmpty else {
            return .result()
        }
        var base = defaults.string(forKey: "flutter.baseUrl") ?? "https://api.takings.alphabet.lk"
        while base.hasSuffix("/") {
            base.removeLast()
        }
        guard let url = URL(string: base + "/sms/ingest") else {
            return .result()
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "body": text,
            "sender": sender,
            "manual": false,
        ])
        _ = try await URLSession.shared.data(for: request)
        return .result()
    }
}

@available(iOS 16.0, *)
struct TakingsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveBankSmsIntent(),
            phrases: [
                "Save a bank message in \(.applicationName)",
            ],
            shortTitle: "Save bank message",
            systemImageName: "message"
        )
    }
}
