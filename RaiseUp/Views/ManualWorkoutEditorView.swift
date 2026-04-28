import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 수동 운동 입력 / 기존 세션 편집 시트

struct ManualWorkoutEditorView: View {

    // nil → 새 세션 추가, non-nil → 기존 세션 편집
    let existingSession: WorkoutSession?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    // MARK: Draft 상태 (편집 중 임시 데이터)
    @State private var sessionDate:     Date
    @State private var drafts:          [DraftExercise]
    @State private var showPicker       = false
    @State private var isSaving         = false
    @State private var draggedDraftID:  UUID? = nil

    init(existingSession: WorkoutSession? = nil) {
        self.existingSession = existingSession
        _sessionDate = State(initialValue: existingSession?.date ?? Date())
        _drafts      = State(initialValue: existingSession.map { DraftExercise.from($0) } ?? [])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ruBackground.ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {

                            // ── 날짜·시간 ─────────────────────────────────
                            sectionCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    sectionLabel("운동 날짜 · 시간")
                                    DatePicker("",
                                               selection: $sessionDate,
                                               displayedComponents: [.date, .hourAndMinute])
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                        .tint(Color.ruGold)
                                        .colorScheme(.dark)
                                }
                            }

                            // ── 종목 목록 ─────────────────────────────────
                            VStack(spacing: 12) {
                                HStack {
                                    sectionLabel("운동 종목")
                                    Spacer()
                                    Button {
                                        showPicker = true
                                    } label: {
                                        Label("종목 추가", systemImage: "plus.circle.fill")
                                            .font(.caption.bold())
                                            .foregroundStyle(Color.ruGold)
                                    }
                                }

                                if drafts.isEmpty {
                                    emptyExercisePlaceholder
                                } else {
                                    ForEach($drafts) { $draft in
                                        ExerciseDraftCard(draft: $draft) {
                                            drafts.removeAll { $0.id == draft.id }
                                        }
                                        .id(draft.id)
                                        .onDrag {
                                            draggedDraftID = draft.id
                                            return NSItemProvider(object: draft.id.uuidString as NSString)
                                        }
                                        .onDrop(of: [.text], delegate: ExerciseDragDelegate(
                                            item: draft,
                                            drafts: $drafts,
                                            draggedID: $draggedDraftID
                                        ))
                                    }
                                }
                            }

                            Color.clear.frame(height: 1).id("editorBottom")

                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                    .onChange(of: drafts.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("editorBottom", anchor: .bottom)
                        }
                    }
                }
            }
            .navigationTitle(existingSession == nil ? "운동 직접 추가" : "운동 기록 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .foregroundStyle(Color.ruSubtext)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .foregroundStyle(drafts.isEmpty ? Color.ruSubtext : Color.ruGold)
                        .fontWeight(.bold)
                        .disabled(drafts.isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerSheet { selected in
                    drafts.append(DraftExercise(name: selected.name, info: selected))
                }
            }
        }
    }

    // MARK: - 하위 뷰

    private var emptyExercisePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell")
                .font(.system(size: 28))
                .foregroundStyle(Color.ruSubtext.opacity(0.3))
            Text("종목 추가 버튼을 눌러 운동을 추가하세요")
                .font(.caption)
                .foregroundStyle(Color.ruSubtext.opacity(0.5))
            Button {
                showPicker = true
            } label: {
                Label("+ 종목 추가", systemImage: "plus.circle")
                    .font(.caption.bold())
                    .foregroundStyle(Color.ruGold.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.ruGold.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.ruDarkCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(Color.ruDarkCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(Color.ruGold)
            .tracking(1)
    }

    // MARK: - 저장

    private func save() {
        isSaving = true

        let session: WorkoutSession
        if let existing = existingSession {
            session = existing
            // 기존 운동 기록 전부 삭제 (cascade)
            for ex in existing.exercises {
                for s in ex.sets { modelContext.delete(s) }
                modelContext.delete(ex)
            }
            session.exercises = []
        } else {
            session = WorkoutSession()
            modelContext.insert(session)
        }

        session.date      = sessionDate
        session.startTime = sessionDate
        session.endTime   = sessionDate   // 수동 입력은 시간 정보 없음

        for draft in drafts {
            let info   = draft.info ?? ExerciseDatabase.find(draft.name)
            let record = WorkoutExerciseRecord(
                exerciseName: draft.name,
                muscleGroups: info?.primaryMuscles ?? []
            )
            record.session = session
            session.exercises.append(record)

            for (i, draftSet) in draft.sets.enumerated() {
                let setRecord = WorkoutSetRecord(
                    setNumber:   i + 1,
                    actualReps:  draftSet.reps,
                    weight:      draftSet.weight.flatMap { $0 > 0 ? $0 : nil }
                )
                setRecord.exerciseRecord = record
                record.sets.append(setRecord)
            }
        }

        // 세션 분석 (직전 기록과 비교)
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let history = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { $0.id != session.id }
        let result  = SessionAnalyzer.analyze(session: session, history: history)
        session.aiAnalysis = SessionAnalyzer.format(result)

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - 드래그 재정렬 델리게이트

private struct ExerciseDragDelegate: DropDelegate {
    let item: DraftExercise
    @Binding var drafts: [DraftExercise]
    @Binding var draggedID: UUID?

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedID,
              let from = drafts.firstIndex(where: { $0.id == draggedID }),
              let to   = drafts.firstIndex(where: { $0.id == item.id }),
              from != to else { return }
        withAnimation { drafts.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - 운동 draft 카드 (종목 1개)

private struct ExerciseDraftCard: View {
    @Binding var draft:    DraftExercise
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // 헤더
            HStack {
                // 드래그 핸들
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))

                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    if let info = draft.info {
                        Text(info.primaryMuscles.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ruSubtext)
                    }
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.7))
                }
            }

            Divider().overlay(Color.ruSubtext.opacity(0.15))

            // 세트 목록
            VStack(spacing: 8) {
                // 컬럼 헤더
                HStack {
                    Text("세트").font(.system(size: 11)).foregroundStyle(Color.ruSubtext).frame(width: 30)
                    Spacer()
                    Text("횟수").font(.system(size: 11)).foregroundStyle(Color.ruSubtext).frame(width: 70)
                    Text("무게(kg)").font(.system(size: 11)).foregroundStyle(Color.ruSubtext).frame(width: 80)
                    Color.clear.frame(width: 24)
                }

                ForEach($draft.sets) { $set in
                    SetDraftRow(set: $set,
                                number: (draft.sets.firstIndex(where: { $0.id == set.id }) ?? 0) + 1) {
                        draft.sets.removeAll { $0.id == set.id }
                    }
                }
            }

            // 세트 추가 버튼
            Button {
                let prev = draft.sets.last
                draft.sets.append(DraftSet(reps: prev?.reps ?? 10, weight: prev?.weight ?? nil))
            } label: {
                Label("세트 추가", systemImage: "plus")
                    .font(.caption.bold())
                    .foregroundStyle(Color.ruGold.opacity(0.8))
            }
        }
        .padding(14)
        .background(Color.ruDarkCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 개별 세트 행

private struct SetDraftRow: View {
    @Binding var set: DraftSet
    let number: Int
    let onDelete: () -> Void

    @State private var weightText: String

    init(set: Binding<DraftSet>, number: Int, onDelete: @escaping () -> Void) {
        _set       = set
        self.number    = number
        self.onDelete  = onDelete
        _weightText = State(initialValue: set.wrappedValue.weight.map {
            $0.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int($0))" : String(format: "%.1f", $0)
        } ?? "")
    }

    var body: some View {
        HStack {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(Color.ruGold)
                .frame(width: 30)

            Spacer()

            // 횟수 스텝퍼
            HStack(spacing: 6) {
                Button { if set.reps > 1 { set.reps -= 1 } } label: {
                    Image(systemName: "minus.circle").foregroundStyle(Color.ruSubtext)
                }
                Text("\(set.reps)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 28)
                Button { set.reps += 1 } label: {
                    Image(systemName: "plus.circle").foregroundStyle(Color.ruGold)
                }
            }
            .frame(width: 90)

            // 무게 입력
            TextField("없음", text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 60)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: weightText) { _, new in
                    set.weight = Double(new)
                }

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ruSubtext.opacity(0.5))
            }
            .frame(width: 24)
        }
    }
}

// MARK: - 운동 종목 피커 시트

struct ExercisePickerSheet: View {
    let onSelect: (ExerciseInfo) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var grouped: [(part: String, exercises: [ExerciseInfo])] {
        guard searchText.isEmpty else {
            let q   = searchText.lowercased()
            let hit = ExerciseDatabase.allExercises.filter {
                $0.name.lowercased().contains(q)
                || $0.aliases.contains { $0.lowercased().contains(q) }
                || $0.primaryMuscles.contains { $0.contains(q) }
            }
            return hit.isEmpty ? [] : [("검색 결과", hit.sorted { $0.name < $1.name })]
        }
        return ExerciseDatabase.groupedByBodyPart
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ruBackground.ignoresSafeArea()

                List {
                    ForEach(grouped, id: \.part) { group in
                        Section {
                            ForEach(group.exercises) { ex in
                                Button {
                                    onSelect(ex)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(ex.name)
                                                .font(.subheadline.bold())
                                                .foregroundStyle(.white)
                                            Text(ex.primaryMuscles.joined(separator: " · "))
                                                .font(.system(size: 11))
                                                .foregroundStyle(Color.ruSubtext)
                                        }
                                        Spacer()
                                        if let region = ex.bodyPartRegion {
                                            Text(region.replacingOccurrences(of: "\(ex.bodyPart) ", with: ""))
                                                .font(.system(size: 10))
                                                .foregroundStyle(Color.ruGold.opacity(0.7))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.ruGold.opacity(0.1))
                                                .clipShape(Capsule())
                                        }
                                        Image(systemName: "plus")
                                            .font(.caption)
                                            .foregroundStyle(Color.ruGold)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowBackground(Color.ruCard)
                            }
                        } header: {
                            Text(group.part)
                                .font(.caption.bold())
                                .foregroundStyle(Color.ruGold)
                                .tracking(1)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("운동 선택")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "운동 이름 / 근육 검색")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .foregroundStyle(Color.ruSubtext)
                }
            }
        }
    }
}

// MARK: - Draft 모델

struct DraftExercise: Identifiable {
    var id   = UUID()
    var name: String
    var info: ExerciseInfo?
    var sets: [DraftSet]

    init(name: String, info: ExerciseInfo? = nil) {
        self.name = name
        self.info = info ?? ExerciseDatabase.find(name)
        self.sets = [DraftSet()]
    }

    /// WorkoutSession → DraftExercise 배열
    static func from(_ session: WorkoutSession) -> [DraftExercise] {
        session.exercises.map { record in
            var d = DraftExercise(name: record.exerciseName)
            d.sets = record.sets
                .sorted { $0.setNumber < $1.setNumber }
                .map { DraftSet(reps: $0.actualReps, weight: $0.weight) }
            if d.sets.isEmpty { d.sets = [DraftSet()] }
            return d
        }
    }
}

struct DraftSet: Identifiable {
    var id     = UUID()
    var reps:   Int    = 10
    var weight: Double? = nil
}
