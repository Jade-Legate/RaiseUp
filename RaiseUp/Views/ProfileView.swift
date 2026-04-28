import SwiftUI
import SwiftData
import Combine

struct ProfileView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    private var stats: ProfileStats { ProfileStats(sessions: sessions) }

    var body: some View {
        ZStack {
            Color.ruBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - 레벨 카드
                    LevelCard(stats: stats)
                        .padding(.horizontal, 20)

                    // MARK: - 통계
                    StatsGrid(stats: stats)
                        .padding(.horizontal, 20)

                    // MARK: - 메달
                    MedalsSection(stats: stats)
                        .padding(.horizontal, 20)

                    Spacer(minLength: 40)
                }
                .padding(.top, 16)
            }
        }
        .navigationTitle("Profile")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - 통계 모델

private struct ProfileStats {
    let sessions: [WorkoutSession]

    var totalSessions: Int { sessions.count }
    var totalSets: Int { sessions.reduce(0) { $0 + $1.totalSets } }

    var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = Date()
        let sessionDates = Set(sessions.map {
            calendar.startOfDay(for: $0.date)
        })
        while sessionDates.contains(calendar.startOfDay(for: checkDate)) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        return streak
    }

    var maxStreak: Int {
        let calendar = Calendar.current
        let sorted = sessions.map { calendar.startOfDay(for: $0.date) }.sorted()
        guard !sorted.isEmpty else { return 0 }

        var max = 1
        var current = 1
        for i in 1..<sorted.count {
            let diff = calendar.dateComponents([.day], from: sorted[i-1], to: sorted[i]).day ?? 0
            if diff == 1 { current += 1; if current > max { max = current } }
            else if diff > 1 { current = 1 }
        }
        return max
    }

    var level: Int {
        switch totalSessions {
        case 0..<5:   return 1
        case 5..<15:  return 2
        case 15..<30: return 3
        case 30..<60: return 4
        default:      return 5
        }
    }

    var levelTitle: String {
        switch level {
        case 1: return "Beginner"
        case 2: return "Trainee"
        case 3: return "Athlete"
        case 4: return "Champion"
        default: return "Legend"
        }
    }

    var progressToNextLevel: Double {
        let thresholds = [0, 5, 15, 30, 60]
        guard level < 5 else { return 1.0 }
        let start = thresholds[level - 1]
        let end   = thresholds[level]
        return Double(totalSessions - start) / Double(end - start)
    }
}

// MARK: - 레벨 카드

private struct LevelCard: View {
    let stats: ProfileStats

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LEVEL \(stats.level)")
                        .font(.caption.bold())
                        .foregroundStyle(Color.ruGold)
                        .tracking(1)
                    Text(stats.levelTitle)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.ruGold.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Circle()
                        .stroke(Color.ruGold.opacity(0.5), lineWidth: 2)
                        .frame(width: 64, height: 64)
                    Text("\(stats.level)")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(Color.ruGold)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("다음 레벨까지")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Text("\(Int(stats.progressToNextLevel * 100))%")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.ruGold)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.ruGold)
                            .frame(width: geo.size.width * min(stats.progressToNextLevel, 1.0), height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(20)
        .background(Color.ruDarkCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 통계 그리드

private struct StatsGrid: View {
    let stats: ProfileStats

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCell(value: "\(stats.totalSessions)", label: "총 운동")
            StatCell(value: "\(stats.totalSets)", label: "총 세트")
            StatCell(value: "\(stats.currentStreak)일", label: "현재 연속")
        }
    }
}

private struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.ruDarkCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 메달 섹션

private struct MedalsSection: View {
    let stats: ProfileStats

    private var medals: [Medal] {
        [
            Medal(icon: "flame.fill",
                  title: "7일 연속 운동",
                  unlocked: stats.maxStreak >= 7),
            Medal(icon: "star.fill",
                  title: "30회 달성",
                  unlocked: stats.totalSessions >= 30),
            Medal(icon: "bolt.fill",
                  title: "첫 운동 완료",
                  unlocked: stats.totalSessions >= 1),
            Medal(icon: "trophy.fill",
                  title: "100세트 돌파",
                  unlocked: stats.totalSets >= 100),
            Medal(icon: "figure.strengthtraining.traditional",
                  title: "30일 연속",
                  unlocked: stats.maxStreak >= 30),
            Medal(icon: "crown.fill",
                  title: "레전드 달성",
                  unlocked: stats.level >= 5),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("메달")
                .font(.subheadline.bold())
                .foregroundStyle(.white)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(medals) { medal in
                    MedalCell(medal: medal)
                }
            }
        }
    }
}

private struct Medal: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let unlocked: Bool
}

private struct MedalCell: View {
    let medal: Medal

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(medal.unlocked ? Color.ruGold.opacity(0.15) : Color.white.opacity(0.06))
                    .frame(width: 52, height: 52)
                Image(systemName: medal.icon)
                    .font(.title3)
                    .foregroundStyle(medal.unlocked ? Color.ruGold : Color.white.opacity(0.2))
            }
            Text(medal.title)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(medal.unlocked ? .white : .white.opacity(0.3))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(medal.unlocked ? Color.ruDarkCard : Color.ruDarkCard.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(medal.unlocked ? Color.ruGold.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}
