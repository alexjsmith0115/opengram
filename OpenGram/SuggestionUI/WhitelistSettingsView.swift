import SwiftUI
import AppKit

struct WhitelistSettingsView: View {
    @State private var whitelist = AppWhitelist()
    @State private var newBundleID: String = ""
    @State private var showResetConfirmation = false

    private var sortedBundleIDs: [String] {
        whitelist.bundleIDs.sorted()
    }

    private var frontmostBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("App Whitelist")
                .font(.system(size: 13, weight: .semibold))
            Text("OpenGram only activates in these apps.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer().frame(height: 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(sortedBundleIDs, id: \.self) { bundleID in
                        HStack {
                            Text(bundleID)
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Button {
                                whitelist.remove(bundleID)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 200)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            Spacer().frame(height: 12)

            if let frontmost = frontmostBundleID {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current app")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(frontmost)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    Spacer()
                    Button("Add") {
                        whitelist.add(frontmost)
                    }
                    .disabled(whitelist.isAllowed(frontmost))
                    .font(.system(size: 12))
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                Spacer().frame(height: 12)
            }

            HStack {
                TextField("com.example.app", text: $newBundleID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Button("Add") {
                    let trimmed = newBundleID.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    whitelist.add(trimmed)
                    newBundleID = ""
                }
                .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                .font(.system(size: 12))
            }

            Spacer().frame(height: 16)

            Button("Reset to Defaults") {
                showResetConfirmation = true
            }
            .font(.system(size: 12))
            .foregroundColor(.red)
            .confirmationDialog(
                "Reset whitelist to defaults?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    whitelist.resetToDefaults()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all custom entries and restore the built-in app list.")
            }
        }
        .padding(16)
        .frame(width: 400)
    }
}
