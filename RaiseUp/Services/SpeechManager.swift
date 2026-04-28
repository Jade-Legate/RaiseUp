import Foundation
import AVFoundation
import Speech

// MARK: - Apple SFSpeechRecognizer 기반 음성 인식 (한국어 최적화)
//
// VOSK 소형 한국어 모델 → Apple STT 교체 이유:
//  • Apple 한국어 모델이 VOSK 소형 모델 대비 인식 정확도 월등히 높음
//  • iOS 17+ on-device 인식 지원 (오프라인 가능)
//  • contextualStrings로 운동 이름 우선순위 부여 가능
//  • 아라비아 숫자 자동 변환 ("십오" → "15") 내장

class SpeechManager: NSObject {

    // MARK: - 콜백

    var onResult: ((String) -> Void)?
    var onPartialResult: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    // MARK: - 내부 상태

    private let speechRecognizer: SFSpeechRecognizer? = {
        let r = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
        r?.defaultTaskHint = .dictation
        return r
    }()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var isListening = false
    private var isPaused    = false

    /// TTS 재개 직후 일정 시간 동안 인식 결과 무시 (TTS 잔음 오인식 방지)
    private var resumeTimestamp: Date = .distantPast

    /// 자동 재시작 예약 (SFSpeechRecognizer ~1분 제한 대응)
    private var autoRestartItem: DispatchWorkItem?

    /// 연속 오류 횟수 추적 (무한 재시작 방지)
    private var consecutiveErrors = 0
    private let maxConsecutiveErrors = 5

    // MARK: - 초기화

    override init() {
        super.init()
    }

    // MARK: - VOSK 호환 API (no-op — 엔진 교체 후 불필요)

    func useExerciseMode()       { /* SFSpeech contextualStrings가 대신 처리 */ }
    func useFullMode()           { }
    func rebuildGrammarRecognizer() { }

    // MARK: - 권한 요청

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            print("[SpeechManager] 음성 인식 권한: \(status == .authorized ? "허용" : "거부")")
        }
        AVAudioApplication.requestRecordPermission { granted in
            print("[SpeechManager] 마이크 권한: \(granted)")
        }
    }

    // MARK: - 사전 워밍 (앱 시작 → START 버튼 지연 없앰)

    func prewarm() {
        #if targetEnvironment(simulator)
        // 시뮬레이터: 한국어 SFSpeechRecognizer = Error 300 무한루프
        // (on-device 모델 없음 + 오디오 스택 불안정)
        // → 시도 자체를 생략, 수동 입력으로 대체
        print("[SpeechManager] 시뮬레이터 환경 — 음성 인식 비활성화 (실기기에서 테스트하세요)")
        isListening = true
        return
        #endif

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                print("[SpeechManager] 음성 인식 권한 없음")
                return
            }
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                guard granted else {
                    print("[SpeechManager] 마이크 권한 없음")
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.startListening()
                }
            }
        }
    }

    // MARK: - 인식 시작

    func startListening() {
        guard !isListening else { return }

        #if targetEnvironment(simulator)
        isListening = true
        return
        #endif

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return }
        #if os(iOS)
        guard AVAudioApplication.shared.recordPermission == .granted else { return }
        #endif

        do {
            try beginRecognition()
        } catch {
            print("[SpeechManager] 시작 실패: \(error)")
        }
    }

    private func beginRecognition() throws {
        // 기존 태스크 정리
        autoRestartItem?.cancel()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        // 오디오 세션 설정
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        // 인식 요청 구성
        let request = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest = request

        // on-device 강제 안 함 — 시뮬레이터/구형 기기에서 Error 300 무한루프 방지
        // iOS가 상황에 맞게 on-device / 서버 자동 선택
        // (실기기 iOS 17+ 는 자동으로 on-device 사용)

        // 운동 이름·명령어 힌트 → 인식 정확도 대폭 향상
        request.contextualStrings = buildContextualStrings()
        request.shouldReportPartialResults = true

        // 오디오 탭 설정
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        let inputNode    = audioEngine.inputNode
        let inputFormat  = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self, !self.isPaused else { return }
            self.recognitionRequest?.append(buffer)
            self.calcAudioLevel(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        // 인식 태스크 시작
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespaces)

                // TTS 재개 직후 0.6초 이내 결과는 잔음 오인식으로 무시
                let freshEnough = Date().timeIntervalSince(self.resumeTimestamp) > 0.6

                if result.isFinal {
                    self.consecutiveErrors = 0   // 정상 결과 → 오류 카운터 리셋
                    if !text.isEmpty && freshEnough && !self.isPaused {
                        DispatchQueue.main.async { self.onResult?(text) }
                    }
                    // 발화 완료 → 즉시 재시작 (연속 인식)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                        guard let self, self.isListening else { return }
                        try? self.beginRecognition()
                    }
                } else if !text.isEmpty && freshEnough && !self.isPaused {
                    self.consecutiveErrors = 0
                    // 부분 결과 → 실시간 자막
                    DispatchQueue.main.async { self.onPartialResult?(text) }
                }
            }

            if let error = error as NSError? {
                // 정상 종료 코드들은 무시 (재시작 없이)
                let silentCodes: Set<Int> = [209, 301]   // cancelled, interrupted
                if silentCodes.contains(error.code) { return }

                // no-speech (1110), init failed (300) 등은 재시작 시도
                let normalCodes: Set<Int> = [1110, 203]
                if !normalCodes.contains(error.code) {
                    print("[SpeechManager] 인식 오류 \(error.code): \(error.localizedDescription)")
                }

                self.consecutiveErrors += 1
                if self.consecutiveErrors >= self.maxConsecutiveErrors {
                    print("[SpeechManager] 연속 오류 \(self.consecutiveErrors)회 — 음성 인식 일시 중단 (10초 후 재시도)")
                    self.consecutiveErrors = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                        guard let self, self.isListening else { return }
                        try? self.beginRecognition()
                    }
                    return
                }

                // 지수 백오프: 1s, 2s, 4s, 8s …
                let delay = min(pow(2.0, Double(self.consecutiveErrors - 1)), 8.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.isListening, !self.isPaused else { return }
                    try? self.beginRecognition()
                }
            }
        }

        // 45초마다 자동 재시작 (SFSpeechRecognizer ~1분 세션 제한 대응)
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isListening else { return }
            try? self.beginRecognition()
        }
        autoRestartItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: item)

        print("[SpeechManager] 인식 시작 (Apple STT · 한국어)")
    }

    // MARK: - 운동 이름 + 명령어 힌트 (최대 100개)

    private func buildContextualStrings() -> [String] {
        var words: [String] = []

        for info in ExerciseDatabase.allExercises {
            words.append(info.name)
            words.append(contentsOf: info.aliases.filter { !$0.isEmpty })
        }

        let commands = [
            "운동 시작", "시작", "끝", "완료", "세트 끝", "다 했어", "했어",
            "다음", "준비", "종료", "운동 종료", "오늘 끝", "고", "가자",
        ]
        words.append(contentsOf: commands)

        // 중복 제거, 100개 제한
        return Array(Set(words)).filter { !$0.isEmpty }.prefix(100).map { $0 }
    }

    // MARK: - 볼륨 레벨 계산

    private func calcAudioLevel(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        var sum: Float = 0
        for i in 0..<frames {
            let s = data[0][i]
            sum += s * s
        }
        let level = min(sqrt(sum / Float(frames)) * 15.0, 1.0)
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(level)
        }
    }

    // MARK: - 일시 정지 / 재개 (TTS 발화 중 오인식 방지)

    func pauseListening() {
        isPaused = true
    }

    func resumeListening() {
        isPaused = false
        resumeTimestamp = Date()   // 재개 시점 기록 → 잔음 필터
    }

    // MARK: - 수동 입력 지원 (텍스트 필드 포커스)

    func pauseForManualInput()  { pauseListening()  }
    func resumeFromManualInput() { resumeListening() }

    // MARK: - 완전 중지

    func stopListening() {
        isListening = false
        isPaused    = false
        autoRestartItem?.cancel()
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask    = nil
    }

    deinit { stopListening() }
}
