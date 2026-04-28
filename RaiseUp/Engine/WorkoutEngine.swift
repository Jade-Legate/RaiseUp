import Foundation
import Combine
import SwiftData

// MARK: - 운동 단계

enum WorkoutPhase: Equatable {
    case idle
    case waitingForExercise
    case waitingForSetConfig
    case exercising
    case resting
    case waitingForNextExercise
    case sessionEnded
}

// MARK: - WorkoutEngine

final class WorkoutEngine: ObservableObject {

    // MARK: - Published 상태

    @Published var phase: WorkoutPhase = .idle {
        didSet { syncSpeechMode() }
    }
    @Published var currentExerciseName: String = ""
    @Published var displayExerciseName: String = ""
    @Published var currentSetNumber: Int = 0
    @Published var totalSets: Int = 0
    @Published var currentRep: Int = 0
    @Published var targetReps: Int = 0
    @Published var restTimeRemaining: Int = 0
    @Published var lastTranscript: String = ""
    @Published var completedSession: WorkoutSession?
    @Published var micLevel: Float = 0
    @Published var isExercisePaused: Bool = false   // 운동 일시정지 상태

    // 루틴 시작 시 세트 구성 화면에 기본값 제공
    @Published var routineDefaultReps: Int = 10
    @Published var routineDefaultSets: Int = 3
    @Published var routineDefaultWeight: Double? = nil
    /// 루틴 진행 중 여부 — WaitingForSetConfigView 힌트 표시 제어
    @Published var isFollowingRoutine: Bool = false

    // 대체 운동 추천 (음성 "기구 없어" 등 트리거 시 채워짐)
    @Published var alternativeSuggestions: [ExerciseInfo] = []
    @Published var showingAlternatives: Bool = false

    // MARK: - 내부 상태

    private var modelContext: ModelContext?
    private var routineQueue: [PlannedExercise] = []
    private let ttsService: TTSService
    private let speechManager: SpeechManager

    private var currentSession: WorkoutSession?
    private var currentExerciseRecord: WorkoutExerciseRecord?
    private var pendingExerciseName: String = ""
    private var pendingSetConfig: (sets: Int, reps: Int, weight: Double?) = (3, 10, nil)
    private var sessionStartTime: Date?

    private var repTask: Task<Void, Never>?
    private var restTask: Task<Void, Never>?
    private var waitTask: Task<Void, Never>?
    /// TTS 직렬화: 각 speak()가 이전 task가 끝난 뒤 실행되도록 체이닝
    private var ttsTask: Task<Void, Never>?

    private let repInterval: TimeInterval = 2.5

    private var defaultRestSeconds: Int {
        let v = UserDefaults.standard.integer(forKey: "restSeconds")
        return v > 0 ? v : 60
    }
    var countingVoiceEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "countingVoiceEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "countingVoiceEnabled") }
    }

    // MARK: - 초기화

    init(ttsService: TTSService, speechManager: SpeechManager) {
        self.ttsService    = ttsService
        self.speechManager = speechManager

        speechManager.onResult = { [weak self] text in
            DispatchQueue.main.async { self?.handleVoiceInput(text) }
        }
        speechManager.onPartialResult = { [weak self] partial in
            // 이미 main에서 호출됨 (SpeechManager 내부에서 dispatch)
            self?.lastTranscript = partial
        }
        speechManager.onAudioLevel = { [weak self] level in
            self?.micLevel = level
        }
    }

    // MARK: - 설정 (ContentView.onAppear)

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        // 앱 시작 시 미리 오디오 엔진 워밍 → Start 버튼 누를 때 지연 없음
        speechManager.prewarm()
    }

    // phase가 바뀔 때마다 최적 인식 모드로 자동 전환
    private func syncSpeechMode() {
        switch phase {
        case .waitingForExercise, .waitingForNextExercise:
            speechManager.useExerciseMode()   // 문법 제한 — 운동 이름 정확도 최우선
        default:
            speechManager.useFullMode()        // 전체 어휘 — 숫자·자유 발화 허용
        }
    }

    // MARK: - 음성 입력

    /// TTS 재생 중엔 음성 결과를 무시 (pauseListening 없이 엔진 유지)
    private var isTTSSpeaking: Bool = false

    func handleVoiceInput(_ text: String) {
        lastTranscript = text
        guard !isTTSSpeaking else { return }   // TTS 중 오인식 방지
        let command = VoiceCommandParser.parse(text, phase: phase)
        handleCommand(command)
    }

    private func handleCommand(_ command: VoiceCommand) {
        switch command {
        case .startSession:    startSession()
        case .endSession:      endSession()
        case .selectExercise(let name, let info):
            guard phase == .waitingForExercise ||
                  phase == .waitingForNextExercise ||
                  phase == .waitingForSetConfig else { return }
            selectExercise(name: name, info: info)
        case .configureSet(let sets, let reps, let weight):
            guard phase == .waitingForSetConfig else { return }
            configureAndStartExercise(sets: sets, reps: reps, weight: weight)
        case .correctReps(let count):
            correctLastSet(count: count)
        case .endSet:
            guard phase == .exercising else { return }
            endCurrentSetEarly()
        case .pauseExercise:
            guard phase == .exercising, !isExercisePaused else { return }
            isExercisePaused = true
            speak("일시정지. 계속하려면 계속이라고 말하세요.")
        case .resumeExercise:
            guard phase == .exercising, isExercisePaused else { return }
            isExercisePaused = false
            speak("계속합니다.")
        case .setRestTime(let seconds):
            guard phase == .resting else { return }
            adjustRestTime(seconds)
        case .addSet:
            guard phase == .exercising || phase == .resting else { return }
            totalSets += 1
            speak("세트가 추가됐습니다. 총 \(totalSets)세트.")
        case .updateWeight(let kg):
            guard phase == .exercising || phase == .resting else { return }
            currentExerciseRecord?.plannedWeight = kg
            pendingSetConfig.weight = kg
            // 이미 기록된 세트들도 업데이트
            currentExerciseRecord?.sets.forEach { $0.weight = kg }
            try? modelContext?.save()
            speak("\(Int(kg))킬로로 기록했습니다.")
        case .requestAlternative:
            guard phase == .waitingForSetConfig else { return }
            requestAlternative()
        case .selectAlternative(let index):
            guard phase == .waitingForSetConfig, showingAlternatives else { return }
            selectAlternative(index: index)
        case .ready, .startSet:
            guard phase == .resting else { return }
            restTask?.cancel(); restTask = nil
            startNextSet()
        case .unknown: break
        }
    }

    // MARK: - 세션

    func startSession() {
        guard phase == .idle else { return }
        // prewarm()으로 이미 시작됐을 수 있음 — 안전망으로 한 번 더 시도
        speechManager.startListening()
        let session = WorkoutSession()
        currentSession   = session
        sessionStartTime = Date()
        modelContext?.insert(session)
        phase = .waitingForExercise  // didSet → useExerciseMode() 자동 호출
        speak("운동 세션을 시작합니다. 어떤 운동을 하실 건가요?")
    }

    // MARK: - 루틴으로 세션 시작

    func startSessionFromRoutine(_ routine: PlannedWorkout) {
        guard phase == .idle else { return }
        let sorted = routine.exercises.sorted(by: { $0.order < $1.order })
        routineQueue = Array(sorted.dropFirst())

        speechManager.startListening()
        let session = WorkoutSession()
        currentSession   = session
        sessionStartTime = Date()
        modelContext?.insert(session)

        if let first = sorted.first {
            pendingExerciseName  = first.exerciseName
            displayExerciseName  = first.exerciseName
            routineDefaultSets   = first.sets
            routineDefaultReps   = first.repsPerSet
            routineDefaultWeight = first.weight
            isFollowingRoutine   = true
            phase = .waitingForSetConfig
            let wText = first.weight.map { " \(Int($0))kg" } ?? ""
            speak("\(routine.name) 루틴을 시작합니다. 첫 번째 운동은 \(first.exerciseName)\(wText), \(first.repsPerSet)개씩 \(first.sets)세트입니다. 아래에서 확인 후 다음을 눌러주세요.")
        } else {
            isFollowingRoutine = false
            phase = .waitingForExercise
            speak("\(routine.name) 루틴을 시작합니다. 어떤 운동을 하실 건가요?")
        }
    }

    // 완료된 총 세트 수 (종료 시 판단 기준)
    var completedSetCount: Int {
        currentSession?.exercises.reduce(0) { $0 + $1.sets.count } ?? 0
    }

    // 0세트 → 자동 폐기 / 1세트 이상 → 저장
    func endSession() {
        guard let session = currentSession else { return }
        cancelAllTTS()
        stopAllTasks()

        if completedSetCount == 0 {
            // 아무것도 안 했으면 조용히 폐기
            modelContext?.delete(session)
            try? modelContext?.save()
            reset()   // 오디오 엔진은 유지 (reset 내부에서 stopListening 제거됨)
            return
        }

        session.endTime = Date()
        if let start = sessionStartTime {
            session.totalDuration = Date().timeIntervalSince(start)
        }
        try? modelContext?.save()
        completedSession = session
        phase = .sessionEnded
        speak("오늘의 운동을 마쳤습니다. 수고하셨습니다.")

        // 이전 세션 조회 → 규칙 기반 분석 (AI 불필요)
        let history = fetchHistory(excluding: session)
        let result  = SessionAnalyzer.analyze(session: session, history: history)
        session.aiAnalysis = SessionAnalyzer.format(result)
        try? modelContext?.save()
    }

    private func fetchHistory(excluding current: WorkoutSession) -> [WorkoutSession] {
        var descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 30   // 최근 30회면 충분
        let all = (try? modelContext?.fetch(descriptor)) ?? []
        return all.filter { $0.id != current.id }
    }

    // MARK: - 수동 입력 지원 (텍스트 필드 포커스 시 음성 충돌 방지)

    /// 텍스트 필드에 포커스가 잡혔을 때 호출 — 음성 인식 일시정지
    func pauseForManualInput() {
        speechManager.pauseListening()
    }

    /// 텍스트 필드 포커스 해제 또는 제출 후 호출 — 음성 인식 재개
    func resumeFromManualInput() {
        speechManager.resumeListening()
    }

    /// 휴식 즉시 건너뛰기 (다음 세트 시작)
    func skipRest() {
        guard phase == .resting else { return }
        restTask?.cancel()
        restTask = nil
        startNextSet()
    }

    /// 수동으로 운동 종목 제출 (텍스트 필드 → 다음 버튼)
    func submitManualExercise(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              phase == .waitingForExercise ||
              phase == .waitingForNextExercise ||
              phase == .waitingForSetConfig
        else { return }
        speechManager.resumeListening()
        let info = ExerciseDatabase.find(trimmed)
        selectExercise(name: trimmed, info: info)
    }

    /// 수동으로 세트 구성 제출 (스테퍼 → 다음 버튼)
    func submitManualSetConfig(sets: Int, reps: Int, weight: Double?) {
        guard phase == .waitingForSetConfig else { return }
        speechManager.resumeListening()
        configureAndStartExercise(sets: sets, reps: reps, weight: weight)
    }

    // MARK: - 종목 선택

    private func selectExercise(name: String, info: ExerciseInfo?) {
        waitTask?.cancel(); waitTask = nil
        let resolvedName = info?.name ?? name

        // 루틴 이탈 감지: 루틴에서 제시한 운동과 다른 운동을 선택한 경우
        let isDeviation = isFollowingRoutine &&
                          !pendingExerciseName.isEmpty &&
                          resolvedName != pendingExerciseName
        if isDeviation {
            // 이탈 운동은 루틴 기본값 없이 시작 (스텝퍼 기본값 10/3으로 초기화)
            routineDefaultReps   = 10
            routineDefaultSets   = 3
            routineDefaultWeight = nil
            isFollowingRoutine   = false
        }

        pendingExerciseName = resolvedName
        displayExerciseName = resolvedName
        phase = .waitingForSetConfig

        let message = isDeviation
            ? "\(resolvedName)으로 변경합니다. 몇 개씩 몇 세트 하실 건가요?"
            : "\(resolvedName). 몇 개씩 몇 세트 하실 건가요?"
        speak(message)
    }

    // MARK: - 세트 구성

    private func configureAndStartExercise(sets: Int, reps: Int, weight: Double?) {
        let record = WorkoutExerciseRecord(
            exerciseName: pendingExerciseName,
            muscleGroups: ExerciseDatabase.find(pendingExerciseName)?.muscleGroups ?? []
        )
        record.plannedSets   = sets
        record.plannedReps   = reps
        record.plannedWeight = weight
        currentSession?.exercises.append(record)
        currentExerciseRecord = record
        totalSets    = sets
        targetReps   = reps
        currentSetNumber = 0
        pendingSetConfig = (sets, reps, weight)
        currentExerciseName = pendingExerciseName
        let weightText = weight.map { " \(Int($0))킬로" } ?? ""
        speak("\(pendingExerciseName)\(weightText), \(reps)개씩 \(sets)세트.")
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in self?.startNextSet() }
        }
    }

    // MARK: - 세트 진행

    private func startNextSet() {
        currentSetNumber += 1
        currentRep = 0
        isExercisePaused = false
        phase = .exercising
        speak("\(currentSetNumber)세트 시작합니다.")

        repTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.repInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }

                let done: Bool = await MainActor.run { [weak self] in
                    guard let self, self.phase == .exercising else { return true }

                    // 일시정지 중: 카운트 건너뜀 (루프 유지)
                    if self.isExercisePaused { return false }

                    self.currentRep += 1
                    if self.currentRep >= self.targetReps {
                        if self.countingVoiceEnabled { self.speak("\(self.targetReps)") }
                        return true
                    }
                    if self.countingVoiceEnabled { self.speak("\(self.currentRep)") }
                    return false
                }

                if done {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { [weak self] in
                        guard let self, self.phase == .exercising else { return }
                        self.completeSet(actualReps: self.targetReps)
                    }
                    return
                }
            }
        }
    }

    private func endCurrentSetEarly() {
        repTask?.cancel(); repTask = nil
        completeSet(actualReps: currentRep)
    }

    private func completeSet(actualReps: Int) {
        let setRecord = WorkoutSetRecord(
            setNumber: currentSetNumber,
            plannedReps: targetReps,
            actualReps: actualReps,
            weight: pendingSetConfig.weight
        )
        currentExerciseRecord?.sets.append(setRecord)
        try? modelContext?.save()

        if currentSetNumber >= totalSets {
            // phase는 advanceRoutineQueue 안에서 결정 (루틴 유무에 따라 분기)
            advanceRoutineQueue(completionMsg: "\(totalSets)세트 모두 완료했습니다.")
        } else {
            phase = .resting
            restTimeRemaining = defaultRestSeconds
            speak("\(currentSetNumber)세트 완료. 휴식을 시작합니다.")
            startRestTask()
        }
    }

    private func correctLastSet(count: Int) {
        guard let lastSet = currentExerciseRecord?.sets.last else { return }
        lastSet.actualReps = count
        try? modelContext?.save()
        speak("\(currentSetNumber)세트 \(count)개로 기록했습니다.")
    }

    // MARK: - 휴식 시간 조정 (음성 명령)

    private func adjustRestTime(_ seconds: Int) {
        let clamped = max(5, min(seconds, 600)) // 5초~10분 범위 제한
        restTask?.cancel()
        restTimeRemaining = clamped
        let display = clamped >= 60 ? "\(clamped / 60)분" : "\(clamped)초"
        speak("\(display)으로 변경합니다.")
        startRestTaskWith(remaining: clamped)
    }

    // MARK: - 휴식 Task

    private func startRestTask() {
        startRestTaskWith(remaining: defaultRestSeconds)
    }

    private func startRestTaskWith(remaining startRemaining: Int) {
        var remaining = startRemaining
        restTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run { [weak self] in self?.restTimeRemaining = remaining }
            while !Task.isCancelled, remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                remaining -= 1
                await MainActor.run { [weak self] in self?.restTimeRemaining = remaining }

                if remaining == 10 {
                    await MainActor.run { [weak self] in self?.speak("10초 남았습니다.") }
                } else if remaining <= 0 {
                    await MainActor.run { [weak self] in self?.speak("다음 세트 시작합니다.") }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { [weak self] in self?.startNextSet() }
                    return
                }
            }
        }
    }

    // MARK: - 대기 Task

    private func startWaitTask() {
        waitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard self?.phase == .waitingForNextExercise else { return }
                self?.speak("다음 운동이 준비되셨나요? 운동 종목을 말씀해주세요.")
            }
        }
    }

    // MARK: - TTS (직렬화 큐)
    // • pauseListening/resumeListening을 speak() 안에서 호출하지 않음
    //   → AudioEngine이 항상 살아 있으므로 TTS 재생 중에도 TextField 즉시 활성화
    // • 대신 isTTSSpeaking 플래그로 TTS 중 음성 결과를 무시해 오인식 방지

    func speak(_ text: String) {
        let previous = ttsTask
        ttsTask = Task { [weak self] in
            _ = await previous?.value          // 이전 TTS 완료 대기
            guard let self, !Task.isCancelled else { return }
            await MainActor.run { self.isTTSSpeaking = true }
            await self.ttsService.speak(text)
            await MainActor.run { self.isTTSSpeaking = false }
        }
    }

    /// 대기 중인 TTS를 모두 취소하고 현재 재생도 즉시 중단
    func cancelAllTTS() {
        ttsTask?.cancel()
        ttsTask = nil
        ttsService.stopSpeaking()
        isTTSSpeaking = false
    }

    // MARK: - 대체 운동 추천

    private func suggestAlternatives() -> [ExerciseInfo] {
        guard let info = ExerciseDatabase.find(pendingExerciseName) else { return [] }
        return info.alternatives
            .compactMap { ExerciseDatabase.find($0) }
            .prefix(3)
            .map { $0 }
    }

    func requestAlternative() {
        let alts = suggestAlternatives()
        guard !alts.isEmpty else {
            speak("죄송합니다. 대체 운동 정보가 없습니다.")
            return
        }
        alternativeSuggestions = alts
        showingAlternatives = true
        let names = alts.enumerated()
            .map { "\($0.offset + 1)번, \($0.element.name)" }
            .joined(separator: ". ")
        speak("대체 운동을 추천해드릴게요. \(names). 번호를 말씀하거나 선택하세요.")
    }

    func selectAlternative(index: Int) {
        guard index < alternativeSuggestions.count else { return }
        let chosen = alternativeSuggestions[index]
        showingAlternatives = false
        alternativeSuggestions = []
        selectExercise(name: chosen.name, info: chosen)
    }

    /// UI 시트에서 직접 선택 시 호출 (인덱스 불필요)
    func selectAlternativeExercise(_ info: ExerciseInfo) {
        showingAlternatives = false
        alternativeSuggestions = []
        selectExercise(name: info.name, info: info)
    }

    // MARK: - 운동 이름 재선택 (이전으로 버튼)

    func goBackToExerciseSelection() {
        cancelAllTTS()
        pendingExerciseName  = ""
        displayExerciseName  = ""
        // 이전 버튼으로 돌아갈 때 루틴 기본값 초기화
        // → 새로 선택한 운동은 루틴 기본값 없이 시작
        routineDefaultReps   = 10
        routineDefaultSets   = 3
        routineDefaultWeight = nil
        isFollowingRoutine   = false
        phase = phase == .waitingForSetConfig ? .waitingForExercise : .waitingForNextExercise
        speak("어떤 운동을 하실 건가요?")
    }

    // MARK: - 현재 운동 건너뛰기

    /// saving: true  → 완료된 세트 유지 / false → 기록 전체 삭제
    func skipExercise(saving: Bool = true) {
        cancelAllTTS()
        repTask?.cancel();  repTask = nil
        restTask?.cancel(); restTask = nil
        isExercisePaused = false

        if let record = currentExerciseRecord {
            let hasSets = !record.sets.isEmpty
            if !saving || !hasSets {
                // 저장 안 함 또는 세트 없음 → 기록 제거
                currentSession?.exercises.removeAll { $0.exerciseName == record.exerciseName }
                try? modelContext?.save()
            }
            // saving && hasSets → 기존 세트 그대로 유지
        }
        currentExerciseRecord = nil

        let prefix = saving ? "운동을 저장하고 건너뛰었습니다." : "운동 기록을 삭제하고 건너뛰었습니다."
        advanceRoutineQueue(completionMsg: prefix)
    }

    // MARK: - 루틴 다음 운동 자동 로드

    private func advanceRoutineQueue(completionMsg: String) {
        if let next = routineQueue.first {
            routineQueue.removeFirst()
            pendingExerciseName  = next.exerciseName
            displayExerciseName  = next.exerciseName
            routineDefaultSets   = next.sets
            routineDefaultReps   = next.repsPerSet
            routineDefaultWeight = next.weight
            isFollowingRoutine   = true   // 루틴 힌트 표시 + 이탈 감지 활성화
            // 중간 phase 없이 바로 세트 구성 화면 → 플래시 없음
            phase = .waitingForSetConfig
            let wText = next.weight.map { " \(Int($0))kg" } ?? ""
            speak("\(completionMsg) 다음은 \(next.exerciseName)\(wText), \(next.repsPerSet)개씩 \(next.sets)세트입니다.")
        } else {
            // 루틴 큐 소진 → 일반 자유 입력 모드
            routineDefaultReps   = 10
            routineDefaultSets   = 3
            routineDefaultWeight = nil
            isFollowingRoutine   = false
            phase = .waitingForNextExercise
            speak("\(completionMsg) 다음 운동을 말씀해주세요.")
            startWaitTask()
        }
    }

    // MARK: - 리셋

    func reset() {
        cancelAllTTS()
        stopAllTasks()
        phase                = .idle
        currentSession       = nil
        currentExerciseRecord = nil
        currentExerciseName  = ""
        displayExerciseName  = ""
        currentSetNumber     = 0
        totalSets            = 0
        currentRep           = 0
        targetReps           = 0
        restTimeRemaining    = 0
        isExercisePaused     = false
        completedSession     = nil
        routineQueue         = []
        routineDefaultReps   = 10
        routineDefaultSets   = 3
        routineDefaultWeight = nil
        isFollowingRoutine   = false
        alternativeSuggestions = []
        showingAlternatives    = false
    }

    private func stopAllTasks() {
        repTask?.cancel();  restTask?.cancel();  waitTask?.cancel()
        repTask = nil;      restTask = nil;      waitTask = nil
    }
}
