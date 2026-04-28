import SwiftUI
import SwiftData

// MARK: - 운동 방향 분석 뷰 (Claude AI 기반)

struct WorkoutAnalysisView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    @State private var analysisText: String = ""
    @State private var isLoading: Bool = false

    // UserDefaults 캐시 키
    private let kAnalysisText         = "aiDirectionAnalysisText"
    private let kAnalyzedSessionCount = "aiDirectionAnalyzedSessionCount"

    private var hasAPIKey: Bool {
        !(UserDefaults.standard.string(forKey: "claudeAPIKey") ?? "").isEmpty
    }

    /// 저장된 결과가 있고, 그 때와 세션 수가 같으면 → 이미 분석 완료 상태
    private var alreadyAnalyzed: Bool {
        let savedText  = UserDefaults.standard.string(forKey: kAnalysisText) ?? ""
        let savedCount = UserDefaults.standard.integer(forKey: kAnalyzedSessionCount)
        return !savedText.isEmpty && savedCount == sessions.count
    }

    var body: some View {
        ZStack {
            Color.ruBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {

                    // MARK: - 헤더
                    VStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.ruGold)
                        Text("운동 방향 분석")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("최근 운동 기록을 AI가 분석해 방향을 제시합니다")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)

                    // MARK: - 최근 운동 요약 카드
                    if !sessions.isEmpty {
                        recentSummaryCard
                    }

                    // MARK: - API 키 없음 안내
                    if !hasAPIKey {
                        VStack(spacing: 12) {
                            Image(systemName: "key.slash")
                                .font(.system(size: 32))
                                .foregroundStyle(.white.opacity(0.3))
                            Text("Claude API 키가 필요합니다")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white.opacity(0.6))
                            Text("설정 → Claude AI에 API 키를 입력하면\n맞춤 운동 방향 분석을 받을 수 있습니다.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.35))
                                .multilineTextAlignment(.center)
                            NavigationLink(destination: SettingsPlaceholderView()) {
                                Text("설정으로 이동")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(Color.ruDark)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 10)
                                    .background(Color.ruGold)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(24)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        // MARK: - 분석 버튼 (새 세션이 생겼을 때만 활성화)
                        if !alreadyAnalyzed {
                            Button {
                                Task { await runAnalysis() }
                            } label: {
                                HStack(spacing: 10) {
                                    if isLoading {
                                        ProgressView()
                                            .tint(Color.ruDark)
                                            .scaleEffect(0.9)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text(isLoading ? "분석 중..." : "AI 분석 시작")
                                        .font(.headline)
                                }
                                .foregroundStyle(isLoading ? Color.ruDark.opacity(0.6) : Color.ruDark)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(isLoading ? Color.ruGold.opacity(0.6) : Color.ruGold)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(isLoading || sessions.isEmpty)
                        } else {
                            // 이미 분석 완료 — 새 운동 기록 시 자동으로 버튼 노출
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.ruGold)
                                Text("새 운동을 기록하면 다시 분석할 수 있습니다")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        // MARK: - 분석 결과 (캐시 or 방금 받은 것)
                        if !analysisText.isEmpty {
                            analysisResultCard(analysisText)
                        } else if sessions.isEmpty {
                            Text("운동 기록이 없습니다.\n운동을 시작하면 AI가 분석해 드립니다.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.35))
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 32)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("운동 방향 분석")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { loadCachedAnalysis() }
    }

    // MARK: - 분석 결과 카드

    private func analysisResultCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.ruGold)
                Text("분석 결과")
                    .font(.caption.bold())
                    .foregroundStyle(Color.ruGold)
                    .tracking(2)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(5)
        }
        .padding(18)
        .background(Color.ruGold.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.ruGold.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - 최근 운동 요약

    private var recentSummaryCard: some View {
        let recent = Array(sessions.prefix(7))
        let uniqueMuscles = Set(recent.flatMap { $0.exercises.flatMap { $0.muscleGroups } })

        return VStack(alignment: .leading, spacing: 10) {
            Text("최근 \(recent.count)회 운동 요약")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.4))
                .tracking(2)

            HStack(spacing: 12) {
                MiniStat(label: "총 세션", value: "\(recent.count)회")
                MiniStat(label: "총 세트", value: "\(recent.reduce(0) { $0 + $1.totalSets })세트")
                MiniStat(label: "자극 부위", value: "\(uniqueMuscles.count)곳")
            }

            if !uniqueMuscles.isEmpty {
                FlowTagLayout(tags: Array(uniqueMuscles).sorted())
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 캐시 불러오기 / 저장

    private func loadCachedAnalysis() {
        analysisText = UserDefaults.standard.string(forKey: kAnalysisText) ?? ""
    }

    private func saveAnalysis(_ text: String) {
        UserDefaults.standard.set(text,           forKey: kAnalysisText)
        UserDefaults.standard.set(sessions.count, forKey: kAnalyzedSessionCount)
    }

    // MARK: - 분석 실행

    private func runAnalysis() async {
        guard !isLoading else { return }
        isLoading = true
        analysisText = ""
        let result = await AIAnalysisService.analyzeDirection(sessions: Array(sessions.prefix(10)))
        analysisText = result
        saveAnalysis(result)
        isLoading = false
    }
}

// MARK: - 보조 컴포넌트

private struct MiniStat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.subheadline.bold()).foregroundStyle(.white)
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct FlowTagLayout: View {
    let tags: [String]
    var body: some View {
        // 간단한 줄바꿈 태그
        let rows = tags.ruChunked(into: 4)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    ForEach(rows[i], id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

// Settings 딥링크용 placeholder (실제로는 시트로 열림)
private struct SettingsPlaceholderView: View {
    var body: some View { EmptyView() }
}

// Array chunked 헬퍼 (RaiseUp 전용 — 중복 방지용 네임스페이스)
private extension Array {
    func ruChunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
