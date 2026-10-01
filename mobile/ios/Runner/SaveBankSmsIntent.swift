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
        Summary("Save data to Takings")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return .result(dialog: "That shortcut had no message to save.")
        }
        let defaults = UserDefaults.standard
        guard let token = defaults.string(forKey: "flutter.token"), !token.isEmpty else {
            return .result(dialog: "Open Takings and sign in, then run this shortcut again.")
        }
        var base = defaults.string(forKey: "flutter.baseUrl") ?? "https://api.takings.alphabet.lk"
        while base.hasSuffix("/") {
            base.removeLast()
        }
        guard let url = URL(string: base + "/sms/ingest") else {
            return .result(dialog: "Takings does not have a valid server address.")
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
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            return .result(dialog: "Sign in to Takings again, then the shortcut can save messages.")
        }
        if status >= 400 {
            return .result(dialog: "Takings could not save that message.")
        }
        let saved = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["status"] as? String
        if saved == "duplicate" {
            return .result(dialog: "That message is already in Takings.")
        }
        if saved == "ignored" {
            return .result(dialog: "Takings left that message alone. It does not look like a payment.")
        }
        return .result(dialog: "Saved to Takings.")
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
