import SwiftUI

struct PermissionsOnboardingView: View {
    @EnvironmentObject private var permissions: PermissionsService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 64))
                    .foregroundStyle(WhiskerTheme.aquaGradient)

                VStack(spacing: 12) {
                    Text("Microphone Access Required")
                        .font(.title2.bold())
                    Text("whisker records temporary audio on this iPhone, sends it to your transcription server, then deletes the temporary recording.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Required to capture temporary recordings for your server.",
                    status: permissions.mic == .granted ? .granted : (permissions.mic == .denied ? .denied : .needed)
                )
                .padding(.horizontal)

                if permissions.mic == .denied {
                    Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                        .buttonStyle(.borderedProminent)
                } else if permissions.mic != .granted {
                    Button("Grant Permission") {
                        Task { await permissions.requestMic() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button("Continue") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }

                Spacer()
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .background(WhiskerTheme.appBackground.ignoresSafeArea())
            .onChange(of: permissions.mic) { _, _ in
                if permissions.mic == .granted { dismiss() }
            }
        }
    }
}

private enum PermissionStatusDisplay { case needed, granted, denied }

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatusDisplay

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(WhiskerTheme.pacific)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            statusIcon
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .needed:
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }
}
