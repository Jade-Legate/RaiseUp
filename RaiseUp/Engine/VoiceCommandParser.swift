import Foundation

// MARK: - 음성 명령 타입

enum VoiceCommand {
    case startSession
    case endSession
    case selectExercise(name: String, info: ExerciseInfo?)
    case configureSet(sets: Int, reps: Int, weight: Double?)
    case correctReps(count: Int)
    case startSet
    case endSet
    case ready
    case pauseExercise                  // "잠깐", "멈춰" → 운동 타이머 일시정지
    case resumeExercise                 // "계속" → 타이머 재개
    case setRestTime(seconds: Int)      // "2분 쉴게", "30초만" → 휴식시간 변경
    case addSet                         // "세트 하나 더" → totalSets + 1
    case updateWeight(kg: Double)       // "무게 70킬로" → 현재 운동 무게 기록
    case requestAlternative             // "기구 없어", "대체 운동" → 대체 운동 추천
    case selectAlternative(index: Int)  // "1번", "2번", "3번" → 대체 운동 선택 (0-based)
    case unknown(text: String)
}

// MARK: - 음성 명령 파서

struct VoiceCommandParser {

    static func parse(_ text: String, phase: WorkoutPhase) -> VoiceCommand {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .unknown(text: cleaned) }

        // 세션 시작
        if isStartSession(cleaned) { return .startSession }

        // "끝" — phase에 따라 세트 종료 or 세션 종료
        if isEndKeyword(cleaned) {
            switch phase {
            case .exercising:
                return .endSet
            case .waitingForExercise, .waitingForSetConfig, .waitingForNextExercise, .resting:
                return .endSession
            default:
                return .endSession
            }
        }

        // 세션 종료 (명시적 표현 — 어느 phase에서든 동작)
        if isEndSession(cleaned) { return .endSession }

        // ── 언제든 동작하는 전역 명령어 ──

        // 반복 수 수정
        if let count = parseRepCorrection(cleaned) {
            return .correctReps(count: count)
        }

        // 무게 업데이트 (exercising/resting 중)
        if [WorkoutPhase.exercising, .resting].contains(phase),
           let kg = parseWeightUpdate(cleaned) {
            return .updateWeight(kg: kg)
        }

        // 세트 추가 (exercising/resting 중)
        if [WorkoutPhase.exercising, .resting].contains(phase),
           isAddSet(cleaned) {
            return .addSet
        }

        // Phase별 명령 파싱
        switch phase {

        case .waitingForExercise, .waitingForNextExercise:
            // DB 매칭 우선 (정확한 이름 + 별명 퍼지 탐색)
            if let info = ExerciseDatabase.find(cleaned) {
                return .selectExercise(name: cleaned, info: info)
            }
            // Apple STT는 자유 형식 텍스트 반환 → DB 미등록 운동도 허용
            // 명령어가 아닌 짧은 발화(1~20자)는 운동 이름으로 처리
            let charCount = cleaned.count
            if charCount >= 1 && charCount <= 20 {
                return .selectExercise(name: cleaned, info: nil)
            }

        case .waitingForSetConfig:
            // 대체 운동 요청
            if cleaned.contains("기구 없") || cleaned.contains("대체 운동") || cleaned.contains("다른 운동") {
                return .requestAlternative
            }
            // 번호 선택 (대체 운동 목록에서)
            if cleaned.contains("1번") || cleaned.contains("첫번째") || cleaned.contains("첫 번째") {
                return .selectAlternative(index: 0)
            }
            if cleaned.contains("2번") || cleaned.contains("두번째") || cleaned.contains("두 번째") {
                return .selectAlternative(index: 1)
            }
            if cleaned.contains("3번") || cleaned.contains("세번째") || cleaned.contains("세 번째") {
                return .selectAlternative(index: 2)
            }

            // 세트 구성 먼저 시도 (한국어 숫자 정규화 포함)
            if let config = parseSetConfig(cleaned) {
                return .configureSet(sets: config.sets, reps: config.reps, weight: config.weight)
            }
            // 세트 구성 파싱 실패 → 운동 이름 수정으로 처리 (DB 우선, 없으면 raw 텍스트)
            // 숫자 발화가 운동 이름으로 오인식되지 않도록 순수 숫자 문자열은 제외
            let isNumericOnly = cleaned.allSatisfy { $0.isNumber || $0 == "." }
            if !isNumericOnly {
                let info = ExerciseDatabase.find(cleaned)
                if info != nil || (cleaned.count >= 1 && cleaned.count <= 20) {
                    return .selectExercise(name: cleaned, info: info)
                }
            }

        case .exercising:
            if isEndSet(cleaned)     { return .endSet }
            if isPause(cleaned)      { return .pauseExercise }
            if isResume(cleaned)     { return .resumeExercise }
            if isStartSet(cleaned)   { return .startSet }

        case .resting:
            if isReady(cleaned) { return .ready }
            // 휴식시간 변경
            if let secs = parseRestTime(cleaned) { return .setRestTime(seconds: secs) }
            // 휴식 중 운동 이름 → 다음 운동 선택
            if let info = ExerciseDatabase.find(cleaned) {
                return .selectExercise(name: cleaned, info: info)
            }

        default:
            break
        }

        return .unknown(text: cleaned)
    }

    // MARK: - 세션 명령

    private static func isStartSession(_ text: String) -> Bool {
        ["운동 시작", "운동시작", "시작할게", "시작하자"].contains(where: { text.contains($0) })
    }

    // "끝" 단독 키워드 (phase-aware로 처리)
    private static func isEndKeyword(_ text: String) -> Bool {
        ["끝", "완료", "다 끝"].contains(where: { text == $0 })
    }

    private static func isEndSession(_ text: String) -> Bool {
        ["운동 끝", "운동끝", "운동 종료", "운동종료", "오늘 끝", "다 끝났어", "끝났어", "종료"].contains(where: { text.contains($0) })
    }

    private static func isStartSet(_ text: String) -> Bool {
        ["시작", "고", "가자"].contains(where: { text == $0 })
    }

    private static func isEndSet(_ text: String) -> Bool {
        ["세트 끝", "세트끝", "다 했어", "했어"].contains(where: { text.contains($0) })
    }

    private static func isPause(_ text: String) -> Bool {
        ["잠깐", "멈춰", "스탑", "일시정지", "정지", "멈추"].contains(where: { text.contains($0) })
    }

    private static func isResume(_ text: String) -> Bool {
        ["계속", "다시", "재개", "계속해", "계속하자"].contains(where: { text.contains($0) })
    }

    private static func isAddSet(_ text: String) -> Bool {
        ["세트 추가", "세트 더", "세트 하나 더", "한 세트 더"].contains(where: { text.contains($0) })
    }

    // MARK: - 휴식시간 파서 ("2분 쉴게", "1분만", "30초")

    static func parseRestTime(_ text: String) -> Int? {
        let n = normalizeKoreanNumbers(text)

        // 분 단위
        let minPatterns = ["([0-9]+)\\s*분", "([0-9]+)\\s*분만", "([0-9]+)\\s*분\\s*쉴"]
        for p in minPatterns {
            if let v = firstInt(n, pattern: p) { return v * 60 }
        }
        // 초 단위
        let secPatterns = ["([0-9]+)\\s*초", "([0-9]+)\\s*초만", "([0-9]+)\\s*초\\s*쉴"]
        for p in secPatterns {
            if let v = firstInt(n, pattern: p) { return v }
        }
        return nil
    }

    // MARK: - 무게 업데이트 파서 ("무게 70킬로", "70kg으로")

    static func parseWeightUpdate(_ text: String) -> Double? {
        let triggers = ["무게", "kg으로", "킬로로", "킬로그램으로"]
        guard triggers.contains(where: { text.contains($0) }) else { return nil }
        return parseWeight(text)
    }

    private static func firstInt(_ text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let v = Int(text[range]) else { return nil }
        return v
    }

    private static func isReady(_ text: String) -> Bool {
        ["준비 완료", "준비완료", "준비됐어", "준비", "시작", "다음"].contains(where: { text.contains($0) })
    }

    // MARK: - 세트 구성 파서

    struct SetConfig {
        let sets: Int
        let reps: Int
        let weight: Double?
    }

    static func parseSetConfig(_ text: String) -> SetConfig? {
        // 한국어 숫자 표현을 아라비아 숫자로 변환 후 파싱
        let normalized = normalizeKoreanNumbers(text)

        let patterns: [(pattern: String, setsIsFirst: Bool)] = [
            ("([0-9]+)\\s*개씩?\\s*([0-9]+)\\s*세트", false),
            ("([0-9]+)\\s*세트\\s*([0-9]+)\\s*[개회]",  true),
            ("([0-9]+)\\s*[개회]\\s*([0-9]+)\\s*세트",  false),
        ]

        for (pattern, setsIsFirst) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
                  let r1 = Range(match.range(at: 1), in: normalized),
                  let r2 = Range(match.range(at: 2), in: normalized),
                  let v1 = Int(normalized[r1]),
                  let v2 = Int(normalized[r2])
            else { continue }

            let (sets, reps) = setsIsFirst ? (v1, v2) : (v2, v1)
            return SetConfig(sets: sets, reps: reps, weight: parseWeight(normalized))
        }
        return nil
    }

    // MARK: - 한국어 숫자 → 아라비아 숫자 변환 (세트 구성 파싱용)

    static func normalizeKoreanNumbers(_ text: String) -> String {
        var s = text

        // 1. 고유어 숫자 (긴 것 먼저)
        let nativeMap: [(String, String)] = [
            ("스물다섯", "25"), ("스물넷", "24"), ("스물셋", "23"),
            ("스물둘", "22"), ("스물하나", "21"), ("스물", "20"),
            ("열아홉", "19"), ("열여덟", "18"), ("열일곱", "17"),
            ("열여섯", "16"), ("열다섯", "15"), ("열넷", "14"),
            ("열셋", "13"), ("열둘", "12"), ("열하나", "11"),
            ("열", "10"),
            ("아홉", "9"), ("여덟", "8"), ("일곱", "7"),
            ("여섯", "6"), ("다섯", "5"), ("넷", "4"),
            ("셋", "3"), ("둘", "2"), ("하나", "1"),
        ]
        for (k, v) in nativeMap { s = s.replacingOccurrences(of: k, with: v) }

        // 2. 한자어 숫자 복합 (긴 것 먼저)
        let sinoCompound: [(String, String)] = [
            ("삼십", "30"), ("이십오", "25"), ("이십사", "24"),
            ("이십삼", "23"), ("이십이", "22"), ("이십일", "21"),
            ("이십", "20"), ("십구", "19"), ("십팔", "18"),
            ("십칠", "17"), ("십육", "16"), ("십오", "15"),
            ("십사", "14"), ("십삼", "13"), ("십이", "12"),
            ("십일", "11"), ("십", "10"),
        ]
        for (k, v) in sinoCompound { s = s.replacingOccurrences(of: k, with: v) }

        // 3. 단일 한자어 숫자는 세트/개/회 앞에서만 안전하게 교체 (오인식 방지)
        let sinoSingle: [(String, String)] = [
            ("구", "9"), ("팔", "8"), ("칠", "7"), ("육", "6"),
            ("오", "5"), ("사", "4"), ("삼", "3"), ("이", "2"), ("일", "1"),
        ]
        for (k, v) in sinoSingle {
            for suffix in ["세트", " 세트", "개", " 개", "회", " 회"] {
                s = s.replacingOccurrences(of: k + suffix, with: v + suffix)
            }
        }

        return s
    }

    // MARK: - 반복 수 수정 파서

    static func parseRepCorrection(_ text: String) -> Int? {
        let patterns = [
            "방금\\s*(?:세트\\s*)?([0-9]+)\\s*[개회]",
            "([0-9]+)\\s*[개회]\\s*만?\\s*(?:했어|했음|함|했습니다|밖에)",
            "사실\\s*([0-9]+)\\s*[개회]",
            "([0-9]+)\\s*[개회]\\s*(?:했어|했음|함)",
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text),
                  let count = Int(text[range])
            else { continue }
            return count
        }
        return nil
    }

    // MARK: - 무게 파서

    private static func parseWeight(_ text: String) -> Double? {
        let pattern = "([0-9]+(?:\\.[0-9]+)?)\\s*(?:kg|킬로|킬로그램)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range])
        else { return nil }
        return value
    }

}
