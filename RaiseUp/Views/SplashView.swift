import SwiftUI

struct SplashView: View {
    let onEnter: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.ruBackground.ignoresSafeArea()

            VStack(spacing: 48) {
                Spacer()

                // 로고
                VStack(spacing: 16) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.ruGold)
                        .scaleEffect(appeared ? 1 : 0.7)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(duration: 0.8), value: appeared)

                    VStack(spacing: 2) {
                        Text("RAISE")
                            .font(.system(size: 40, weight: .black, design: .serif))
                            .foregroundStyle(.white)
                        Text("UP")
                            .font(.system(size: 40, weight: .black, design: .serif))
                            .foregroundStyle(Color.ruGold)
                    }
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.3), value: appeared)

                    Text("Raise your body. Raise your self.")
                        .font(.caption)
                        .foregroundStyle(Color.ruGold.opacity(0.6))
                        .tracking(1)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(0.5), value: appeared)
                }

                Spacer()

                // Enter App 버튼
                Button(action: onEnter) {
                    Text("Enter App")
                        .font(.headline)
                        .foregroundStyle(Color.ruBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.ruGold)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.7), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}
