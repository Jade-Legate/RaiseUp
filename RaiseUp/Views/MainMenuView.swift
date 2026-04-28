import SwiftUI
import SwiftData

struct MainMenuView: View {
    @EnvironmentObject private var engine: WorkoutEngine
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ruBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // MARK: - 헤더
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Date().formatted(.dateTime.month().day().weekday()))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                            HStack(spacing: 6) {
                                Image(systemName: "building.columns.fill")
                                    .font(.headline)
                                    .foregroundStyle(Color.ruGold)
                                Text("RAISE UP")
                                    .font(.headline.bold())
                                    .foregroundStyle(.white)
                            }
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
                    .padding(.bottom, 28)

                    // MARK: - 메뉴 그리드
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        NavigationLink(destination: RoutinePlannerView()) {
                            MenuCard(
                                icon: "list.clipboard.fill",
                                title: "My Routine",
                                subtitle: "루틴 계획하기"
                            )
                        }
                        NavigationLink(destination: HistoryView()) {
                            MenuCard(
                                icon: "calendar",
                                title: "History",
                                subtitle: "운동 기록"
                            )
                        }
                        NavigationLink(destination: WorkoutAnalysisView()) {
                            MenuCard(
                                icon: "brain.head.profile",
                                title: "AI 분석",
                                subtitle: "운동 방향 분석",
                                isGold: true
                            )
                        }
                        NavigationLink(destination: ProfileView()) {
                            MenuCard(
                                icon: "person.fill",
                                title: "Profile",
                                subtitle: "나의 성장"
                            )
                        }
                        MenuCard(
                            icon: "mic.fill",
                            title: "음성 가이드",
                            subtitle: "명령어 보기"
                        )
                        .onTapGesture { showSettings = true }
                    }
                    .padding(.horizontal, 20)

                    Spacer()

                    // MARK: - START 버튼
                    VStack(spacing: 12) {
                        if !sessions.isEmpty {
                            Text("마지막 운동: \(sessions[0].date.formatted(.dateTime.month().day()))")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.45))
                        }

                        Button {
                            engine.startSession()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mic.fill")
                                    .font(.title3)
                                Text("START")
                                    .font(.title2.bold())
                                    .tracking(2)
                            }
                            .foregroundStyle(Color.ruDark)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .background(Color.ruGold)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .padding(.horizontal, 24)

                    }
                    .padding(.bottom, 48)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

private struct MenuCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var isGold: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isGold ? Color.ruGold : .white)
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .frame(height: 110)
        .background(Color.ruDarkCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isGold ? Color.ruGold.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
}
