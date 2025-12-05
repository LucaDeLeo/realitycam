//
//  DebugEnvironmentView.swift
//  Rial
//
//  Debug-only view for switching API environments at runtime.
//  Eliminates need to rebuild when switching between local/production APIs.
//

import SwiftUI

#if DEBUG

/// Debug settings view for switching API environments.
///
/// ## Usage
/// Present as a sheet from CaptureView's debug button:
/// ```swift
/// .sheet(isPresented: $showDebugSettings) {
///     DebugEnvironmentView()
/// }
/// ```
///
/// ## Features
/// - Select between Local (Simulator), Local (Device), and Production
/// - Custom IP field for physical device testing
/// - Live URL preview
/// - Settings persist across app launches
struct DebugEnvironmentView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = EnvironmentStore.shared

    var body: some View {
        NavigationView {
            Form {
                // Current Status Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: store.isOverrideActive ? "bolt.fill" : "bolt.slash")
                                .foregroundColor(store.isOverrideActive ? .green : .secondary)
                            Text(store.isOverrideActive ? "Override Active" : "Using Default")
                                .font(.headline)
                        }

                        Text(store.apiBaseURL.absoluteString)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Current API")
                }

                // Environment Picker Section
                Section {
                    ForEach(APIEnvironment.allCases) { env in
                        EnvironmentRow(
                            environment: env,
                            isSelected: store.currentEnvironment == env && store.isOverrideActive,
                            customIP: store.customIP
                        ) {
                            store.activate(environment: env)
                        }
                    }
                } header: {
                    Text("Select Environment")
                } footer: {
                    Text("Changes take effect immediately. No rebuild required.")
                }

                // Custom IP Section (only for localDevice)
                if store.currentEnvironment == .localDevice && store.isOverrideActive {
                    Section {
                        HStack {
                            Text("http://")
                                .foregroundColor(.secondary)
                            TextField("192.168.1.x", text: $store.customIP)
                                .keyboardType(.decimalPad)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            Text(":8080")
                                .foregroundColor(.secondary)
                        }
                        .font(.system(.body, design: .monospaced))
                    } header: {
                        Text("Device IP Address")
                    } footer: {
                        Text("Your Mac's local IP. Find it in System Settings → Network.")
                    }
                }

                // Reset Section
                Section {
                    Button(role: .destructive) {
                        store.reset()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Default")
                        }
                    }
                    .disabled(!store.isOverrideActive)
                }

                // Help Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        helpRow(
                            icon: "laptopcomputer",
                            title: "Simulator",
                            description: "Use \"Local (Simulator)\" - connects to localhost"
                        )
                        helpRow(
                            icon: "iphone",
                            title: "Physical Device",
                            description: "Use \"Local (Device)\" and enter your Mac's IP"
                        )
                        helpRow(
                            icon: "cloud",
                            title: "Production",
                            description: "Use \"Production\" to test against live API"
                        )
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Quick Guide")
                }
            }
            .navigationTitle("Debug Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func helpRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Row for each environment option
private struct EnvironmentRow: View {
    let environment: APIEnvironment
    let isSelected: Bool
    let customIP: String
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(environment.displayName)
                        .foregroundColor(.primary)
                    Text(urlPreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var urlPreview: String {
        environment.defaultURL(customIP: customIP.isEmpty ? nil : customIP).absoluteString
    }
}

// MARK: - Preview

struct DebugEnvironmentView_Previews: PreviewProvider {
    static var previews: some View {
        DebugEnvironmentView()
    }
}

#endif
