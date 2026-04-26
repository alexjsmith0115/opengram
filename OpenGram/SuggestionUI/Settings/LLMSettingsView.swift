import SwiftUI
import AppKit
import KeychainAccess

private enum SettingsPanelLayout {
    static let size = NSSize(width: 560, height: 600)
}

/// Manages the Settings panel lifecycle. Call `show()` to open.
@MainActor
final class LLMSettingsPanel {
    private var panel: NSPanel?

    /// Test-only accessor for verifying panel configuration.
    var visiblePanel: NSPanel? { panel }

    func show() {
        if let existing = panel, existing.isVisible {
            bringToFront(existing)
            return
        }

        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(origin: .zero, size: SettingsPanelLayout.size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: SettingsPanelLayout.size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "OpenGram Settings"
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.contentView = hostingView
        panel.center()
        panel.isMovable = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // .floating keeps the panel visible in .accessory activation policy apps
        panel.level = .floating

        self.panel = panel
        bringToFront(panel)
    }

    private func bringToFront(_ panel: NSPanel) {
        // Activate the app first: .accessory apps have no foreground presence,
        // so makeKeyAndOrderFront can be ignored without this.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case llmProvider
    case clarity
    case whitelist
    case advanced
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .llmProvider: return "LLM Provider"
        case .clarity: return "Clarity"
        case .whitelist: return "Whitelisted Apps"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .llmProvider: return "brain"
        case .clarity: return "text.magnifyingglass"
        case .whitelist: return "app.badge.checkmark"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}

/// Root settings view: LLM Provider, Clarity, Whitelisted Apps, Advanced, About.
struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .llmProvider

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            selectedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: SettingsPanelLayout.size.width, height: SettingsPanelLayout.size.height)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .llmProvider:
            LLMSettingsView()
        case .clarity:
            ClaritySettingsView()
        case .whitelist:
            WhitelistSettingsView()
        case .advanced:
            AdvancedSettingsView()
        case .about:
            AboutSettingsView()
        }
    }
}

/// SwiftUI view for LLM provider configuration (D-04, D-05, D-06, D-07).
/// Standalone for now; future work will embed it into a tabbed Settings window.
struct LLMSettingsView: View {

    // Non-secret config stored in UserDefaults via @AppStorage (D-05)
    @AppStorage("llmBaseURL") private var baseURL: String = "http://localhost:1234/v1"
    @AppStorage("llmModel") private var model: String = "default"
    @AppStorage("llmEnableTone") private var enableTone: Bool = true
    @AppStorage("llmEnableRephrase") private var enableRephrase: Bool = true
    @AppStorage("llmTemperature") private var temperature: Double = 0.3
    @AppStorage("llmRequestTimeout") private var requestTimeout: Double = 60

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

            Text("Model")
                .font(.system(size: 13))
            TextField("default", text: $model)
                .textFieldStyle(.roundedBorder)

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

            // Section: Request Timeout
            Spacer().frame(height: 24)
            Text("Request Timeout")
                .font(.system(size: 13, weight: .semibold))
            Spacer().frame(height: 8)
            Slider(value: $requestTimeout, in: 15...300, step: 5)
            HStack {
                Text("\(Int(requestTimeout))s")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Local models may need 120s+")
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
        .frame(maxWidth: .infinity)
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
                model: model,
                enabledChecks: Set(LLMCheckType.allCases),
                temperature: temperature,
                maxTokens: 1024,
                requestTimeout: requestTimeout,
                confidenceThreshold: LLMConfig.defaultConfidenceThreshold
            )
            let key = apiKeyField.isEmpty ? nil : apiKeyField
            let result = await service.healthCheck(config: config, apiKey: key)
            guard !Task.isCancelled else { return }
            testState = result ? .success : .failure
        }
    }

    private func saveConfig() {
        // baseURL, toggles, temperature are already saved via @AppStorage
        // Only the API key needs explicit Keychain save (synchronous, no Task needed)
        if apiKeyField.isEmpty {
            try? keychain.remove("apiKey")
        } else {
            keychain["apiKey"] = apiKeyField
        }
    }

    private func loadAPIKey() {
        apiKeyField = (try? keychain.get("apiKey")) ?? ""
    }

    private func resetTestState() {
        testState = .idle
    }
}
