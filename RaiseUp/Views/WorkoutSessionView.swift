import SwiftUI

struct WorkoutSessionView: View {
    @EnvironmentObject private var engine: WorkoutEngine
    @State private var showEndConfirm = false

    var body: some View {
        ZStack {
            Color.ruBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                mainContent
                Spacer()
                transcriptBar
            }
        }
    }

    // MARK: - 상단 바

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if !engine.currentExerciseName.isEmpty {
                    Text(engine.currentExerciseName)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                if engine.totalSets > 0 {
                    Text("\(engine.currentSetNumber) / \(engine.totalSets) 세트")
                        .font(.subheadline)
                        .foregroundStyle(Color.ruGold)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                // 카운트 음성 토글
                Button {
                    engine.countingVoiceEnabled.toggle()
                } label: {
                    Image(systemName: engine.countingVoiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.subheadline)
                        .foregroundStyle(engine.countingVoiceEnabled ? Color.ruGold : .white.opacity(0.3))
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                Button {
                    if engine.completedSetCount > 0 {
                        showEndConfirm = true   // 세트 기록 있으면 확인
                    } else {
                        engine.endSession()     // 아무것도 안 했으면 바로 폐기
                    }
                } label: {
                    Text("종료")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .alert("운동을 종료할까요?", isPresented: $showEndConfirm) {
                    Button("저장하고 종료", role: .none) { engine.endSession() }
                    Button("취소",          role: .cancel) { }
                } message: {
                    Text("지금까지의 기록이 저장됩니다.")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Phase별 메인 콘텐츠

    @ViewBuilder
    private var mainContent: some View {
        switch engine.phase {
        case .waitingForExercise, .waitingForNextExercise:
            WaitingForExerciseView()

        case .waitingForSetConfig:
            WaitingForSetConfigView(exerciseName: engine.displayExerciseName)

        case .exercising:
            ExercisingView(currentRep: engine.currentRep, targetReps: engine.targetReps)

        case .resting:
            RestingView(
                timeRemaining: engine.restTimeRemaining,
                nextSetNumber: engine.currentSetNumber + 1,
                totalSets: engine.totalSets
            )

        default:
            EmptyView()
        }
    }

    // MARK: - 음성 인식 표시

    private var transcriptBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.08))
            HStack(spacing: 12) {
                // 볼륨 미터
                MicLevelBars(level: engine.micLevel)

                // 인식된 텍스트 (부분 결과 포함 실시간 표시)
                Text(engine.lastTranscript.isEmpty ? "듣고 있어요…" : "\"\(engine.lastTranscript)\"")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - 마이크 볼륨 바

private struct MicLevelBars: View {
    let level: Float
    private let barCount = 5
    private let barWidth: CGFloat = 3

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                let threshold = Float(i + 1) / Float(barCount)
                let active = level >= threshold
                RoundedRectangle(cornerRadius: 2)
                    .fill(active ? Color.ruGold : Color.white.opacity(0.15))
                    .frame(width: barWidth, height: barHeight(for: i))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [6, 10, 14, 10, 6]
        return heights[index]
    }
}

// MARK: - 종목 대기

private struct WaitingForExerciseView: View {
    @EnvironmentObject private var engine: WorkoutEngine
    @State private var pulse = false
    @State private var manualInput: String = ""
    @FocusState private var isTyping: Bool

    var body: some View {
        VStack(spacing: 24) {
            // 마이크 애니메이션
            ZStack {
                Circle()
                    .stroke(Color.ruGold.opacity(isTyping ? 0.04 : 0.12), lineWidth: 1)
                    .frame(width: pulse ? 130 : 110)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                Circle()
                    .fill(Color.ruGold.opacity(isTyping ? 0.03 : 0.08))
                    .frame(width: 90)
                Image(systemName: isTyping ? "keyboard" : "waveform.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(isTyping ? Color.white.opacity(0.2) : Color.ruGold)
                    .animation(.easeInOut(duration: 0.2), value: isTyping)
            }
            .onAppear { pulse = true }

            VStack(spacing: 6) {
                Text("운동 종목을 말씀해주세요")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text(isTyping ? "입력 중엔 음성 인식이 멈춥니다" : "예) \"스쿼트\", \"벤치프레스\"")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .animation(.easeInOut(duration: 0.15), value: isTyping)
            }

            // ── 직접 입력 ──
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    TextField("또는 직접 입력…", text: $manualInput)
                        .foregroundStyle(.white)
                        .tint(Color.ruGold)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(isTyping ? 0.12 : 0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isTyping ? Color.ruGold.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                        .focused($isTyping)
                        .onSubmit { submitManual() }
                        .onChange(of: isTyping) { _, focused in
                            if focused {
                                // TTS를 즉시 중단해 오디오 세션을 비워야 키보드가 뜸
                                engine.cancelAllTTS()
                                engine.pauseForManualInput()
                            } else if manualInput.isEmpty {
                                engine.resumeFromManualInput()
                            }
                        }
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("완료") { isTyping = false }
                                    .foregroundStyle(Color.ruGold)
                            }
                        }

                    // 다음 버튼
                    Button(action: submitManual) {
                        HStack(spacing: 4) {
                            Text("다음")
                                .font(.subheadline.bold())
                            Image(systemName: "arrow.right")
                                .font(.subheadline)
                        }
                        .foregroundStyle(manualInput.trimmingCharacters(in: .whitespaces).isEmpty
                                         ? Color.white.opacity(0.25) : Color.ruDark)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(manualInput.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.white.opacity(0.07) : Color.ruGold)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(manualInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func submitManual() {
        let trimmed = manualInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isTyping = false
        engine.submitManualExercise(trimmed)
        manualInput = ""
    }
}

// MARK: - 세트 구성 대기

private struct WaitingForSetConfigView: View {
    let exerciseName: String
    @EnvironmentObject private var engine: WorkoutEngine

    @State private var reps: Int = 10
    @State private var sets: Int = 3
    @State private var weightText: String = ""
    @State private var showAlternatives = false
    @FocusState private var weightFocused: Bool

    @AppStorage("weightUnit") private var weightUnit: String = "kg"

    var body: some View {
        VStack(spacing: 20) {
            // 종목명
            Text(exerciseName)
                .font(.system(size: 36, weight: .black))
                .foregroundStyle(.white)

            // 음성 힌트
            Text("음성으로 말하거나 아래에서 직접 설정하세요")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)

            // 루틴 진행 중일 때만 이탈 힌트 표시
            if engine.isFollowingRoutine {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.caption2)
                    Text("다른 운동을 하려면 종목명을 말씀하거나 '이전' 버튼을 누르세요")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.ruGold.opacity(0.55))
                .padding(.horizontal, 32)
            }

            // ── 설정 카드 ──
            VStack(spacing: 0) {
                // 반복 수
                Stepper(value: $reps, in: 1...50) {
                    HStack {
                        Text("반복 수")
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(reps)개")
                            .font(.headline)
                            .foregroundStyle(Color.ruGold)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()
                    .background(Color.white.opacity(0.1))

                // 세트 수
                Stepper(value: $sets, in: 1...20) {
                    HStack {
                        Text("세트 수")
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(sets)세트")
                            .font(.headline)
                            .foregroundStyle(Color.ruGold)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()
                    .background(Color.white.opacity(0.1))

                // 무게 (선택)
                HStack {
                    Text("무게")
                        .foregroundStyle(.white)
                    Text("(선택)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.white)
                        .tint(Color.ruGold)
                        .frame(width: 60)
                        .focused($weightFocused)
                        .onChange(of: weightFocused) { _, focused in
                            if focused {
                                engine.cancelAllTTS()
                                engine.pauseForManualInput()
                            } else {
                                engine.resumeFromManualInput()
                            }
                        }
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("완료") { weightFocused = false }
                                    .foregroundStyle(Color.ruGold)
                            }
                        }
                    Text(weightUnit)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 24)

            // ── 버튼 행 ──
            HStack(spacing: 12) {
                // 이전으로 (운동명 재선택)
                Button {
                    weightFocused = false
                    engine.goBackToExerciseSelection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left")
                        Text("이전")
                            .font(.subheadline.bold())
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                // 다음
                Button {
                    weightFocused = false
                    let weight = Double(weightText.trimmingCharacters(in: .whitespaces))
                    engine.submitManualSetConfig(sets: sets, reps: reps, weight: weight)
                } label: {
                    HStack(spacing: 6) {
                        Text("다음")
                            .font(.headline)
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(Color.ruDark)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.ruGold)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 24)

            // ── 대체 운동 버튼 ──
            Button {
                weightFocused = false
                showAlternatives = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.caption2)
                    Text("대체 운동 보기")
                        .font(.caption)
                }
                .foregroundStyle(Color.ruGold.opacity(0.65))
            }
            .padding(.bottom, 4)
        }
        .sheet(isPresented: $showAlternatives) {
            AlternativeExercisesSheet(exerciseName: engine.displayExerciseName) { chosen in
                engine.selectAlternativeExercise(chosen)
            }
        }
        .onAppear {
            // 루틴에서 시작한 경우 엔진의 기본값으로 초기화
            reps = engine.routineDefaultReps
            sets = engine.routineDefaultSets
            if let w = engine.routineDefaultWeight {
                weightText = String(Int(w))
            }
        }
    }
}

// MARK: - 운동 중 (카운팅)

private struct ExercisingView: View {
    let currentRep: Int
    let targetReps: Int
    @EnvironmentObject private var engine: WorkoutEngine
    @State private var showSkipConfirm = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 6)
                    .frame(width: 200)

                Circle()
                    .trim(from: 0, to: targetReps > 0 ? CGFloat(currentRep) / CGFloat(targetReps) : 0)
                    .stroke(
                        engine.isExercisePaused ? Color.white.opacity(0.3) : Color.ruGold,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: currentRep)

                VStack(spacing: 4) {
                    if engine.isExercisePaused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 56, weight: .black))
                            .foregroundStyle(.white.opacity(0.5))
                    } else {
                        Text("\(currentRep)")
                            .font(.system(size: 72, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.3), value: currentRep)
                    }
                    Text("/ \(targetReps)")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            // 상태 레이블
            Group {
                if engine.isExercisePaused {
                    HStack(spacing: 6) {
                        Text("일시정지")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.4))
                            .tracking(2)
                        Text("·  \"계속\" 이라고 말하세요")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.25))
                    }
                } else {
                    Text("운동 중")
                        .font(.caption.bold())
                        .foregroundStyle(Color.ruGold.opacity(0.8))
                        .tracking(3)
                        .textCase(.uppercase)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: engine.isExercisePaused)

            // 터치 대응 버튼 행
            HStack(spacing: 16) {
                // 이 운동 건너뛰기
                Button {
                    showSkipConfirm = true
                } label: {
                    Label("건너뛰기", systemImage: "forward.end.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.25))
                }
                .confirmationDialog("이 운동을 건너뛸까요?",
                                    isPresented: $showSkipConfirm,
                                    titleVisibility: .visible) {
                    Button("이 부분까지 저장하고 건너뛰기") {
                        engine.skipExercise(saving: true)
                    }
                    Button("저장 없이 건너뛰기", role: .destructive) {
                        engine.skipExercise(saving: false)
                    }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text("지금까지 완료한 세트를 저장할지 선택하세요.")
                }

                Divider()
                    .frame(height: 14)
                    .background(.white.opacity(0.15))

                // 일시정지 / 계속
                if engine.isExercisePaused {
                    Button {
                        engine.isExercisePaused = false
                        engine.speak("계속합니다.")
                    } label: {
                        Label("계속하기", systemImage: "play.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.ruGold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.ruGold.opacity(0.12))
                            .clipShape(Capsule())
                    }
                } else {
                    Button {
                        engine.isExercisePaused = true
                        engine.speak("일시정지.")
                    } label: {
                        Label("잠깐 멈추기", systemImage: "pause.circle")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
            }
        }
    }
}

// MARK: - 휴식

private struct RestingView: View {
    let timeRemaining: Int
    let nextSetNumber: Int
    let totalSets: Int
    @EnvironmentObject private var engine: WorkoutEngine

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("휴식")
                    .font(.caption.bold())
                    .foregroundStyle(Color.ruGold.opacity(0.8))
                    .tracking(3)
                    .textCase(.uppercase)

                Text("\(timeRemaining)")
                    .font(.system(size: 88, weight: .black, design: .rounded))
                    .foregroundStyle(timeRemaining <= 10 ? Color.ruGold : .white)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.4), value: timeRemaining)

                Text("초")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.4))
            }

            if nextSetNumber <= totalSets {
                Text("다음: \(nextSetNumber)세트")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }

            // 즉시 시작 버튼
            Button {
                engine.skipRest()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "forward.fill")
                    Text(nextSetNumber <= totalSets ? "\(nextSetNumber)세트 바로 시작" : "완료")
                        .font(.headline)
                }
                .foregroundStyle(Color.ruDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.ruGold)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - 대체 운동 추천 시트

struct AlternativeExercisesSheet: View {
    let exerciseName: String
    let onSelect: (ExerciseInfo) -> Void
    @Environment(\.dismiss) private var dismiss

    private var alternatives: [ExerciseInfo] {
        ExerciseDatabase.find(exerciseName)?.alternatives
            .compactMap { ExerciseDatabase.find($0) }
            .prefix(3)
            .map { $0 } ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ruBackground.ignoresSafeArea()

                VStack(spacing: 16) {
                    Text("\(exerciseName) 대신 할 수 있는 운동")
                        .font(.caption)
                        .foregroundStyle(Color.ruSubtext)
                        .padding(.top, 8)

                    if alternatives.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.ruSubtext.opacity(0.4))
                            Text("대체 운동 정보가 없습니다")
                                .font(.subheadline)
                                .foregroundStyle(Color.ruSubtext)
                        }
                        Spacer()
                    } else {
                        ForEach(Array(alternatives.enumerated()), id: \.offset) { i, ex in
                            Button {
                                onSelect(ex)
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    Text("\(i + 1)")
                                        .font(.title2.bold())
                                        .foregroundStyle(Color.ruGold)
                                        .frame(width: 32, alignment: .center)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(ex.name)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                        if !ex.muscleGroups.isEmpty {
                                            Text(ex.muscleGroups.joined(separator: " · "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Color.ruGold.opacity(0.5))
                                }
                                .padding(16)
                                .background(Color.ruCard)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("대체 운동 추천")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}
