import SwiftUI

struct CompletionView: View {
    @EnvironmentObject private var engine: WorkoutEngine
    let session: WorkoutSession

    @State private var appear = false

    var body: some View {
        ZStack {
            Color.ruBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // 완료 헤더
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(Color.ruGold)
                            .scaleEffect(appear ? 1 : 0.5)
                            .opacity(appear ? 1 : 0)
                            .animation(.spring(duration: 0.6), value: appear)

                        Text("오늘의 운동 완료")
                            .font(.title.bold())
                            .foregroundStyle(.white)
                            .opacity(appear ? 1 : 0)
                            .animation(.easeOut(duration: 0.5).delay(0.2), value: appear)

                        Text("당신의 몸, 오늘도 성장했습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                            .opacity(appear ? 1 : 0)
                            .animation(.easeOut(duration: 0.5).delay(0.4), value: appear)
                    }
                    .padding(.top, 40)

                    // 통계
                    statsGrid
                        .opacity(appear ? 1 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.5), value: appear)

                    // 종목별 기록
                    exerciseList
                        .opacity(appear ? 1 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.6), value: appear)

                    // AI 분석
                    if let analysis = session.aiAnalysis {
                        analysisCard(text: analysis)
                            .opacity(appear ? 1 : 0)
                            .animation(.easeOut(duration: 0.5).delay(0.7), value: appear)
                    }

                    // 홈으로 버튼
                    Button { engine.reset() } label: {
                        Text("홈으로")
                            .font(.headline)
                            .foregroundStyle(Color.ruBackground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.ruGold)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .opacity(appear ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.8), value: appear)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear { appear = true }
    }

    private var statsGrid: some View {
        HStack(spacing: 12) {
            StatCard(label: "총 시간",  value: session.formattedDuration)
            StatCard(label: "종목 수",  value: "\(session.exercises.count)가지")
            StatCard(label: "총 세트", value: "\(session.totalSets)세트")
        }
    }

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("운동 기록")
                .font(.caption.bold())
                .foregroundStyle(Color.ruGold.opacity(0.8))
                .tracking(2)
                .textCase(.uppercase)

            ForEach(session.exercises, id: \.exerciseName) { record in
                ExerciseResultRow(record: record)
            }
        }
    }

    private func analysisCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "brain")
                    .foregroundStyle(Color.ruGold)
                Text("오늘의 분석")
                    .font(.caption.bold())
                    .foregroundStyle(Color.ruGold.opacity(0.8))
                    .tracking(2)
                    .textCase(.uppercase)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .lineSpacing(4)
        }
        .padding(16)
        .background(Color.ruGold.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ruGold.opacity(0.2), lineWidth: 1))
    }
}

private struct StatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ruGold.opacity(0.1), lineWidth: 1))
    }
}

private struct ExerciseResultRow: View {
    let record: WorkoutExerciseRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.exerciseName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                Text("\(record.completedSets)세트")
                    .font(.caption)
                    .foregroundStyle(Color.ruGold)
            }

            HStack(spacing: 6) {
                ForEach(Array(record.sets.enumerated()), id: \.offset) { i, set in
                    VStack(spacing: 2) {
                        Text("\(set.actualReps)")
                            .font(.caption.bold())
                            .foregroundStyle(underPerformed(set) ? .orange : .white)
                        Text("\(i + 1)")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .frame(width: 32, height: 36)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func underPerformed(_ set: WorkoutSetRecord) -> Bool {
        guard let planned = set.plannedReps else { return false }
        return set.actualReps < planned
    }
}
