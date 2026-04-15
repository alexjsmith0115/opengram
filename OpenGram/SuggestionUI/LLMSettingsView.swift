import SwiftUI
import AppKit
import KeychainAccess

/// Manages the LLM Settings panel lifecycle. Call `show()` to open.
@MainActor
final class LLMSettingsPanel {
    private var panel: NSPanel?

    func show() {
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = LLMSettingsView()
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 320)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "LLM Provider"
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.contentView = hostingView
        panel.center()
        panel.isMovable = true

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }
}

/// SwiftUI view for LLM provider configuration (D-04, D-05, D-06, D-07).
/// Standalone for now; Phase 5 will embed it into a tabbed Settings window.
struct LLMSettingsView: View {

    // Non-secret config stored in UserDefaults via @AppStorage (D-05)
    @AppStorage("llmBaseURL") private var baseURL: String = "http://localhost:1234/v1"
    @AppStorage("llmEnableTone") private var enableTone: Bool = true
    @AppStorage("llmEnableClarity") private var enableClarity: Bool = true
    @AppStorage("llmEnableRephrase") private var enableRephrase: Bool = true
    @AppStorage("llmTemperature") private var temperature: Double = 0.3

    // Staged API key (committed to Keychain on Save)
    @State private var apiKeyField: String = ""

    // Connection test state
    @State private var testState: TestConnectionState = .idle
    @State private var testTask: Task<Void, Never>?

    enum TestConnectionState {
        case idle, testing, success, failure
    }

    private let keychain = Keychain(service: "com.opengram.llm")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section: LLM Provider
            Text("LLM Provider")
                .font(.system(size: 13, weight: .semibold))
            Spacer().frame(height: 8)

            Text("Endpoint URL")
                .font(.system(size: 13))
            TextField("http://localhost:1234/v1", text: $baseURL)
                .textFieldStyle(.roundedBorder)
                .onChange(of: baseURL) { _ in resetTestState() }

            Spacer().frame(height: 8)

            Text("API Key")
                .font(.system(size: 13))
            SecureField("Optional \u{2014} required for some providers", text: $apiKeyField)
                .textFieldStyle(.roundedBorder)
                .onChange(of: apiKeyField) { _ in resetTestState() }

            // Section: Check Types
            Spacer().frame(height: 24)
            Text("Check types")
                .font(.system(size: 13, weight: .semibold))
            Spacer().frame(height: 8)
            HStack(spacing: 16) {
                Toggle("Tone", isOn: $enableTone)
                    .font(.system(size: 13))
                Toggle("Clarity", isOn: $enableClarity)
                    .font(.system(size: 13))
                Toggle("Rephrase", isOn: $enableRephrase)
                    .font(.system(size: 13))
            }

            // Section: Temperature
            Spacer().frame(height: 24)
            Text("Temperature")
                .font(.system(size: 13, weight: .semibold))
            Spacer().frame(height: 8)
            Slider(value: $temperature, in: 0.0...1.0, step: 0.05)
            HStack {
                Text("Consistent")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Creative")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Buttons
            Spacer().frame(height: 24)
            HStack(spacing: 8) {
                Button("Test Connection") {
                    testConnection()
                }
                .font(.system(size: 13))

                switch testState {
                case .idle:
                    EmptyView()
                case .testing:
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                case .success:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                        Text("Connected")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                case .failure:
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 16))
                        Text("Could not connect \u{2014} check the URL and try again")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            Spacer().frame(height: 8)
            Button("Save LLM Config") {
                saveConfig()
            }
            .font(.system(size: 13))
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 400)
        .onAppear {
            loadAPIKey()
        }
    }

    // MARK: - Actions

    private func testConnection() {
        testTask?.cancel()
        testState = .testing

        testTask = Task {
            let service = LLMService()
            let config = LLMConfig(
                baseURL: baseURL,
                enabledChecks: Set(LLMCheckType.allCases),
                temperature: temperature,
                maxTokens: 1024
            )
            let key = apiKeyField.isEmpty ? nil : apiKeyField
            let result = await service.healthCheck(config: config, apiKey: key)
            guard !Task.isCancelled else { return }
            testState = result ? .success : .failure
        }
    }

    private func saveConfig() {
        // baseURL, toggles, temperature are already saved via @AppStorage
        // Only the API key needs explicit Keychain save
        Task {
            if apiKeyField.isEmpty {
                try? keychain.remove("apiKey")
            } else {
                keychain["apiKey"] = apiKeyField
            }
        }
    }

    private func loadAPIKey() {
        apiKeyField = (try? keychain.get("apiKey")) ?? ""
    }

    private func resetTestState() {
        testState = .idle
    }
}
