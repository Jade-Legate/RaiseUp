import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    @State private var selectedDate:    Date? = nil
    @State private var displayMonth:    Date = Date()
    @State private var detailSession:   WorkoutSession? = nil  // 상세 보기
    @State private var editingSession:  WorkoutSession? = nil  // 편집
    @State private var showManualEntry: Bool = false           // 수동 추가

    private var calendar: Calendar { Calendar.current }

    private var sessionsByDate: [DateComponents: [WorkoutSession]] {
        Dictionary(grouping: sessions) { session in
            calendar.dateComponents([.year, .month, .day], from: session.date)
        }
    }

    private var selectedSessions: [WorkoutSession] {
        guard let date = selectedDate else { return [] }
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return sessionsByDate[comps] ?? []
    }

    var body: some View {
        ZStack {
            Color.ruBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                CalendarGrid(
                    displayMonth: $displayMonth,
                    selectedDate: $selectedDate,
                    workoutDates: Set(sessions.map {
                        calendar.dateComponents([.year, .month, .day], from: $0.date)
                    })
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Divider()
                    .overlay(Color.white.opacity(0.1))
                    .padding(.top, 12)

                if selectedDate == nil && sessions.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.25))
                        Text("아직 운동 기록이 없습니다")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .frame(maxHeight: .infinity)
                } else if let date = selectedDate {
                    if selectedSessions.isEmpty {
                        VStack(spacing: 8) {
                            Text(date.formatted(.dateTime.month().day()))
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            Text("운동 기록 없음")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        sessionList(selectedSessions)
                    }
                } else {
                    sessionList(Array(sessions.prefix(30)))
                }
            }
        }
        .navigationTitle("History")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showManualEntry = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.ruGold)
                }
            }
        }
        .sheet(item: $detailSession) { session in
            SessionDetailSheet(session: session, onEdit: {
                detailSession = nil
                editingSession = session
            })
        }
        .sheet(isPresented: $showManualEntry) {
            ManualWorkoutEditorView()
        }
        .sheet(item: $editingSession) { session in
            ManualWorkoutEditorView(existingSession: session)
        }
    }

    @ViewBuilder
    private func sessionList(_ list: [WorkoutSession]) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(list) { session in
                    SessionCard(session: session)
                        .onTapGesture { detailSession = session }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - 세션 카드 (목록용 — 탭 가능)

private struct SessionCard: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.date.formatted(.dateTime.month().day().hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                    Text("\(session.exercises.count)가지 운동 · \(session.formattedDuration)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("\(session.totalSets)세트")
                        .font(.caption.bold())
                        .foregroundStyle(Color.ruGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.ruGold.opacity(0.15))
                        .clipShape(Capsule())
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.25))
                }
            }

            if !session.exercises.isEmpty {
                Divider().overlay(Color.white.opacity(0.1))
                // 모든 운동명 표시 (줄바꿈)
                FlowLayout(spacing: 6) {
                    ForEach(session.exercises) { ex in
                        Text(ex.exerciseName)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(14)
        .background(Color.ruDarkCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - 세션 상세 시트

struct SessionDetailSheet: View {
    let session: WorkoutSession
    let onEdit:  (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(session: WorkoutSession, onEdit: (() -> Void)? = nil) {
        self.session = session
        self.onEdit  = onEdit
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ruBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 요약 헤더
                        HStack(spacing: 12) {
                            StatPill(label: "시간",  value: session.formattedDuration)
                            StatPill(label: "종목",  value: "\(session.exercises.count)가지")
                            StatPill(label: "총세트", value: "\(session.totalSets)세트")
                            StatPill(label: "총반복", value: "\(session.totalReps)회")
                        }
                        .padding(.top, 4)

                        // 종목별 상세
                        ForEach(session.exercises) { record in
                            ExerciseDetailCard(record: record)
                        }

                        // 운동 분석
                        if let analysis = session.aiAnalysis, !analysis.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("운동 분석", systemImage: "chart.bar.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.ruGold)
                                Text(analysis)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineSpacing(4)
                            }
                            .padding(16)
                            .background(Color.ruGold.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.ruGold.opacity(0.2), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(session.date.formatted(.dateTime.month().day().weekday()))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if let onEdit {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            onEdit()
                        } label: {
                            Label("수정", systemImage: "pencil")
                                .foregroundStyle(Color.ruGold)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Color.ruGold)
                }
            }
        }
    }
}

private struct StatPill: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ExerciseDetailCard: View {
    let record: WorkoutExerciseRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.exerciseName)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    if let w = record.plannedWeight {
                        Text("\(Int(w)) kg")
                            .font(.caption)
                            .foregroundStyle(Color.ruGold)
                    }
                }
                Spacer()
                Text("\(record.completedSets)세트")
                    .font(.caption.bold())
                    .foregroundStyle(Color.ruGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.ruGold.opacity(0.12))
                    .clipShape(Capsule())
            }

            // 세트별 반복수 표시
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
                    .frame(width: 36, height: 40)
                    .background(Color.white.opacity(underPerformed(set) ? 0.08 : 0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }

            // 볼륨
            if record.totalVolume > 0 {
                Text("총 볼륨: \(Int(record.totalVolume)) kg")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
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

// MARK: - 태그 줄바꿈 레이아웃

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        y += rowHeight
        return CGSize(width: maxWidth, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - 캘린더 그리드

private struct CalendarGrid: View {
    @Binding var displayMonth: Date
    @Binding var selectedDate: Date?
    let workoutDates: Set<DateComponents>

    private var calendar: Calendar { Calendar.current }
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    private var daysInMonth: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth))
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: firstDay) - 1
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }
        return days
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    displayMonth = calendar.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
                } label: {
                    Image(systemName: "chevron.left").foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Text(displayMonth.formatted(.dateTime.year().month()))
                    .font(.subheadline.bold()).foregroundStyle(.white)
                Spacer()
                Button {
                    displayMonth = calendar.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
                } label: {
                    Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 8)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdays, id: \.self) {
                    Text($0).font(.caption2.bold()).foregroundStyle(.white.opacity(0.4)).frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<daysInMonth.count, id: \.self) { i in
                    if let date = daysInMonth[i] {
                        let comps = calendar.dateComponents([.year, .month, .day], from: date)
                        let hasWorkout = workoutDates.contains(comps)
                        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                        let isToday = calendar.isDateInToday(date)
                        Button {
                            selectedDate = isSelected ? nil : date
                        } label: {
                            ZStack {
                                if isSelected { Circle().fill(Color.ruDark) }
                                else if isToday { Circle().stroke(Color.ruGold, lineWidth: 1.5) }
                                VStack(spacing: 2) {
                                    Text("\(calendar.component(.day, from: date))")
                                        .font(.caption2)
                                        .foregroundStyle(isSelected ? .white.opacity(0.9) : .white)
                                    if hasWorkout {
                                        Circle().fill(isSelected ? Color.white.opacity(0.9) : Color.ruGold).frame(width: 4, height: 4)
                                    }
                                }
                            }
                            .frame(height: 36)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
    }
}
