import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject private var engine: WorkoutEngine
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    @State private var showSettings = false
    @State private var micPulse = false

    var body: some View {
        ZStack {
            Color.ruBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 헤더
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Date().formatted(.dateTime.month().day().weekday()))
                            .font(.caption)
                            .foregroundStyle(Color.ruGold.opacity(0.8))
                        Text("RaiseUp")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .foregroundStyle(Color.ruGold)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)

                // MARK: - 음성 트리거 영역
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.ruGold.opacity(0.15), lineWidth: 1)
                            .frame(width: micPulse ? 160 : 140)
                            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: micPulse)

                        Circle()
                            .stroke(Color.ruGold.opacity(0.08), lineWidth: 1)
                            .frame(width: micPulse ? 200 : 180)
                            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true).delay(0.2), value: micPulse)

                        Circle()
                            .fill(Color.ruGold.opacity(0.1))
                            .frame(width: 120)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.ruGold)
                    }
                    .onAppear { micPulse = true }

                    VStack(spacing: 8) {
                        Text("\"운동 시작\"")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                        Text("이라고 말하면 시작됩니다")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(maxHeight: .infinity)

                // MARK: - 최근 기록
                if !sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("최근 운동")
                            .font(.caption.bold())
                            .foregroundStyle(Color.ruGold.opacity(0.8))
                            .padding(.horizontal, 24)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(sessions.prefix(5)) { session in
                                    SessionCard(session: session)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

private struct SessionCard: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.date.formatted(.dateTime.month().day()))
                .font(.caption2)
                .foregroundStyle(Color.ruGold.opacity(0.8))
            Text("\(session.exercises.count)가지 운동")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            Text("\(session.totalSets)세트 · \(session.formattedDuration)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ruGold.opacity(0.15), lineWidth: 1))
        .frame(width: 130)
    }
}
