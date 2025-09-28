import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coverageSettings: ContentCoverageSettings

    var body: some View {
        Form {
            Section("Indexing") {
                HStack {
                    Text("Content coverage")
                    Spacer()
                    Text(labelText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: coverageSettings.bindingForSlider(),
                    in: coverageSettings.sliderRange,
                    step: 1
                )
                .disabled(coverageSettings.isOverrideActive)

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "Indexes the first \(headText) and the final \(tailText) of each file (\(labelText) total)."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    if coverageSettings.isOverrideActive {
                        Text("Currently overridden by the MSB_CONTENT_PERCENT environment variable.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { coverageSettings.refreshPolicy() }
    }

    private var labelText: String {
        String(format: "%.0f%%", coverageSettings.effectivePercentage)
    }

    private var headText: String {
        String(format: "%.1f%%", coverageSettings.headPercentage)
    }

    private var tailText: String {
        String(format: "%.1f%%", coverageSettings.tailPercentage)
    }
}

#Preview {
    SettingsView()
        .environmentObject(ContentCoverageSettings())
}
