import SwiftUI
import SwiftData

struct RoutinePlannerView: View {
    @EnvironmentObject private var engine: WorkoutEngine
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlannedWorkout.createdAt, order: .reverse) private var routines: [PlannedWorkout]

    @State private var showCreateSheet = false
    @State private var editingRoutine: PlannedWorkout?

    var body: some View {
        ZStack {
            Color.ruBackground.ignoresSafeArea()

            if routines.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("저장된 루틴이 없습니다")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.45))
                    Text("+ 버튼으로 루틴을 만들어보세요")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(routines) { routine in
                            RoutineCard(routine: routine) {
                                editingRoutine = routine
                            } onDelete: {
                                modelContext.delete(routine)
                                try? modelContext.save()
                            } onStart: {
                                engine.startSessionFromRoutine(routine)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("My Routine")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.ruGold)
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            RoutineEditorSheet(routine: nil)
        }
        .sheet(item: $editingRoutine) { routine in
            RoutineEditorSheet(routine: routine)
        }
    }
}

// MARK: - 루틴 카드

private struct RoutineCard: View {
    let routine: PlannedWorkout
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onStart: () -> Void

    @AppStorage("weightUnit") private var weightUnit: String = "kg"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 상단 헤더
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text("\(routine.exercises.count)가지 운동")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                HStack(spacing: 16) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }

            // 운동 목록
            if !routine.exercises.isEmpty {
                Divider().overlay(.white.opacity(0.1))
                VStack(spacing: 6) {
                    ForEach(routine.exercises.sorted(by: { $0.order < $1.order })) { ex in
                        HStack {
                            Text(ex.exerciseName)
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                            Spacer()
                            if let w = ex.weight {
                                Text("\(Int(w))\(weightUnit)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(Color.ruGold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.ruGold.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            Text("\(ex.repsPerSet)개 × \(ex.sets)세트")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
            }

            // START 버튼
            Button(action: onStart) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                    Text("START")
                        .font(.caption.bold())
                        .tracking(1.5)
                }
                .foregroundStyle(Color.ruDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.ruGold)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(Color.ruDarkCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 루틴 생성/편집 시트

struct RoutineEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let routine: PlannedWorkout?

    @State private var name: String = ""
    @State private var exercises: [ExerciseRow] = []

    @AppStorage("weightUnit") private var weightUnit: String = "kg"

    struct ExerciseRow: Identifiable {
        let id = UUID()
        var exerciseName: String = ""
        var sets: String = "3"
        var reps: String = "10"
        var weight: String = ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ruBackground.ignoresSafeArea()

                Form {
                    // MARK: 루틴 이름
                    Section {
                        TextField("예) 월요일 가슴/삼두", text: $name)
                            .foregroundStyle(Color.ruDark)
                            .autocorrectionDisabled()
                    } header: {
                        Text("루틴 이름")
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    // MARK: 운동 목록 (드래그 재정렬)
                    Section {
                        ForEach($exercises) { $row in
                            ExerciseRowEditor(row: $row, weightUnit: weightUnit)
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                .listRowBackground(Color.white.opacity(0.05))
                                .listRowSeparatorTint(.white.opacity(0.08))
                        }
                        .onMove { from, to in
                            exercises.move(fromOffsets: from, toOffset: to)
                        }
                        .onDelete { indexSet in
                            exercises.remove(atOffsets: indexSet)
                        }

                        Button {
                            exercises.append(ExerciseRow())
                        } label: {
                            Label("운동 추가", systemImage: "plus.circle.fill")
                                .foregroundStyle(Color.ruGold)
                        }
                        .listRowBackground(Color.white.opacity(0.03))
                    } header: {
                        Text("운동 목록 (길게 누르면 순서 변경)")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            }
            .navigationTitle(routine == nil ? "새 루틴" : "루틴 편집")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .foregroundStyle(Color.ruGold)
                        .bold()
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { loadExisting() }
    }

    private func loadExisting() {
        guard let routine else { return }
        name = routine.name
        exercises = routine.exercises.sorted(by: { $0.order < $1.order }).map {
            ExerciseRow(
                exerciseName: $0.exerciseName,
                sets: "\($0.sets)",
                reps: "\($0.repsPerSet)",
                weight: $0.weight.map { "\(Int($0))" } ?? ""
            )
        }
    }

    private func save() {
        let target = routine ?? PlannedWorkout()
        target.name = name.trimmingCharacters(in: .whitespaces)

        // 기존 운동 삭제
        target.exercises.forEach { modelContext.delete($0) }
        target.exercises = []

        for (i, row) in exercises.enumerated() {
            guard !row.exerciseName.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let ex = PlannedExercise()
            ex.exerciseName = row.exerciseName.trimmingCharacters(in: .whitespaces)
            ex.sets         = Int(row.sets) ?? 3
            ex.repsPerSet   = Int(row.reps) ?? 10
            ex.weight       = Double(row.weight.trimmingCharacters(in: .whitespaces))
            ex.restSeconds  = 60  // 기본 휴식 시간 유지
            ex.order        = i
            target.exercises.append(ex)
        }

        if routine == nil { modelContext.insert(target) }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - 운동 행 편집기

private struct ExerciseRowEditor: View {
    @Binding var row: RoutineEditorSheet.ExerciseRow
    let weightUnit: String

    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 운동 이름 — 탭 시 ExercisePickerSheet 열림
            Button {
                showPicker = true
            } label: {
                HStack {
                    Text(row.exerciseName.isEmpty ? "운동 선택..." : row.exerciseName)
                        .font(.subheadline.bold())
                        .foregroundStyle(row.exerciseName.isEmpty ? .white.opacity(0.35) : .white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerSheet { selected in
                    row.exerciseName = selected.name
                }
            }

            // 세트 / 개수 / 무게 필드
            HStack(spacing: 10) {
                CompactField(label: "세트", placeholder: "3", text: $row.sets)
                CompactField(label: "개수", placeholder: "10", text: $row.reps)
                CompactField(label: "무게(\(weightUnit))", placeholder: "0", text: $row.weight)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CompactField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
            TextField(placeholder, text: $text)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .font(.caption.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .frame(maxWidth: .infinity)
    }
}
