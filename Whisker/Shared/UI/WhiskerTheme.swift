import SwiftUI

enum WhiskerTheme {
    static let deepOcean = Color(red: 0.03, green: 0.20, blue: 0.29)
    static let pacific = Color(red: 0.02, green: 0.48, blue: 0.68)
    static let seaGlass = Color(red: 0.53, green: 0.86, blue: 0.78)
    static let foam = Color(red: 0.92, green: 0.99, blue: 0.96)
    static let kelp = Color(red: 0.18, green: 0.48, blue: 0.36)
    static let poppy = Color(red: 0.94, green: 0.38, blue: 0.28)

    static let appBackground = LinearGradient(
        colors: [
            Color(red: 0.88, green: 0.98, blue: 0.96),
            Color(red: 0.73, green: 0.91, blue: 0.93),
            Color(red: 0.96, green: 0.95, blue: 0.87)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let aquaGradient = LinearGradient(
        colors: [seaGlass, pacific],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let sunsetGradient = LinearGradient(
        colors: [poppy, Color(red: 0.99, green: 0.70, blue: 0.42)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct WhiskerWordmark: View {
    var size: CGFloat = 34

    var body: some View {
        Text("whisker")
            .font(.custom("SnellRoundhand-Black", size: size, relativeTo: .largeTitle))
            .fontWeight(.bold)
            .foregroundStyle(WhiskerTheme.aquaGradient)
            .shadow(color: WhiskerTheme.pacific.opacity(0.18), radius: 6, y: 2)
            .accessibilityLabel("whisker")
    }
}

struct CoastalPillButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .foregroundStyle(.white)
            .background(active ? WhiskerTheme.sunsetGradient : WhiskerTheme.aquaGradient, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: WhiskerTheme.pacific.opacity(active ? 0.16 : 0.24), radius: 14, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.76), value: configuration.isPressed)
    }
}
