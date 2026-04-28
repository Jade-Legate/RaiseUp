import Foundation

// MARK: - 분석 결과 구조체

struct SessionAnalysisResult {
    let bodyParts:    [BodyPartVolume]       // 대분류별 세트 수 (하체/가슴/등/팔/어깨/코어)
    let muscleGroups: [MuscleGroupVolume]    // 주동근별 세트 수, 내림차순
    let totalSets:    Int
    let totalReps:    Int
    let comparisons:  [ExerciseComparison]   // 이전 대비 변화 (변화 있는 항목만)
}

/// 대분류 (하체, 가슴, 등 …)
struct BodyPartVolume {
    let name:   String           // 대분류명
    let sets:   Int
    let regions: [RegionVolume]  // 중분류 (하체만 값 있음)
}

/// 중분류 (하체 전면, 하체 후면)
struct RegionVolume {
    let name: String
    let sets: Int
}

struct MuscleGroupVolume {
    let name: String
    let sets: Int
}

struct ExerciseComparison {
    let exerciseName: String
    let weightDelta:  Double?   // nil = 무게 데이터 없음 or 첫 기록
    let repsDelta:    Int?      // nil = 반복 수 데이터 없음
    let setsDelta:    Int       // 0이면 변화 없음
    let isFirstRecord: Bool     // 이전 기록 자체가 없는 경우
}

// MARK: - 세션 분석기 (순수 함수, 외부 의존성 없음)

struct SessionAnalyzer {

    // MARK: - 메인 분석 함수

    /// - Parameters:
    ///   - session: 방금 완료한 세션
    ///   - history: 이전 세션 목록 (최신순 정렬, 현재 세션 제외)
    static func analyze(session: WorkoutSession,
                        history: [WorkoutSession]) -> SessionAnalysisResult {
        let parts       = bodyParts(from: session)
        let groups      = muscleGroups(from: session)
        let comparisons = compare(session: session, history: history)
        return SessionAnalysisResult(
            bodyParts:    parts,
            muscleGroups: groups,
            totalSets:    session.totalSets,
            totalReps:    session.totalReps,
            comparisons:  comparisons
        )
    }

    // MARK: - 대분류(bodyPart) 집계

    private static func bodyParts(from session: WorkoutSession) -> [BodyPartVolume] {
        // bodyPart → (총 세트, region → 세트)
        var partSets:   [String: Int]              = [:]
        var regionSets: [String: [String: Int]]    = [:]   // bodyPart → region → sets

        for ex in session.exercises {
            let info = ExerciseDatabase.find(ex.exerciseName)
            let n    = ex.sets.count
            guard n > 0 else { continue }

            let part   = info?.bodyPart ?? "기타"
            let region = info?.bodyPartRegion  // nil이면 중분류 없음

            partSets[part, default: 0] += n

            if let r = region {
                regionSets[part, default: [:]][r, default: 0] += n
            }
        }

        return partSets
            .map { part, sets -> BodyPartVolume in
                let regions = (regionSets[part] ?? [:])
                    .map { RegionVolume(name: $0.key, sets: $0.value) }
                    .sorted { $0.sets > $1.sets }
                return BodyPartVolume(name: part, sets: sets, regions: regions)
            }
            .sorted { $0.sets > $1.sets }
    }

    // MARK: - 주동근 집계

    private static func muscleGroups(from session: WorkoutSession) -> [MuscleGroupVolume] {
        var counts: [String: Int] = [:]

        for ex in session.exercises {
            // DB에서 주동근 조회, 없으면 세션에 저장된 값 사용
            let muscles = ExerciseDatabase.find(ex.exerciseName)?.primaryMuscles
                          ?? ex.muscleGroups

            let n = ex.sets.count
            guard n > 0 else { continue }

            for m in muscles {
                counts[m, default: 0] += n
            }
        }

        return counts
            .map { MuscleGroupVolume(name: $0.key, sets: $0.value) }
            .sorted { $0.sets > $1.sets }
    }

    // MARK: - 이전 세션 대비 변화

    private static func compare(session: WorkoutSession,
                                history: [WorkoutSession]) -> [ExerciseComparison] {
        session.exercises.compactMap { ex in
            // 이전 세션 중 같은 운동이 있는 가장 최근 기록 탐색
            let prevEx = history.lazy
                .flatMap { $0.exercises }
                .first { $0.exerciseName == ex.exerciseName }

            guard let prev = prevEx else {
                // 첫 기록 — 변화량 없음, isFirstRecord = true
                return ExerciseComparison(
                    exerciseName: ex.exerciseName,
                    weightDelta:  nil,
                    repsDelta:    nil,
                    setsDelta:    0,
                    isFirstRecord: true
                )
            }

            let weightDelta: Double? = {
                guard let cur = ex.plannedWeight, let pre = prev.plannedWeight else { return nil }
                let delta = cur - pre
                return delta == 0 ? nil : delta
            }()

            let repsDelta: Int? = {
                guard let cur = ex.plannedReps, let pre = prev.plannedReps else { return nil }
                let delta = cur - pre
                return delta == 0 ? nil : delta
            }()

            let setsDelta = ex.sets.count - prev.sets.count

            // 아무 변화도 없으면 목록에서 제외
            let hasChange = weightDelta != nil || repsDelta != nil || setsDelta != 0
            guard hasChange else { return nil }

            return ExerciseComparison(
                exerciseName: ex.exerciseName,
                weightDelta:  weightDelta,
                repsDelta:    repsDelta,
                setsDelta:    setsDelta,
                isFirstRecord: false
            )
        }
    }

    // MARK: - 텍스트 포맷

    static func format(_ result: SessionAnalysisResult) -> String {
        var lines: [String] = []

        // 대분류 (상위 2개)
        let topParts = result.bodyParts.prefix(2)
        if !topParts.isEmpty {
            let partLabels = topParts.map { part -> String in
                if part.regions.isEmpty {
                    return part.name
                } else {
                    // 하체: 하체(전면·후면) 형태로 표시
                    let regionNames = part.regions.map { r -> String in
                        r.name.replacingOccurrences(of: "\(part.name) ", with: "")
                    }.joined(separator: "·")
                    return "\(part.name)(\(regionNames))"
                }
            }
            lines.append("오늘의 주 부위  \(partLabels.joined(separator: " · "))")
        }

        // 총 세트 · 개수
        lines.append("총 \(result.totalSets)세트 · \(result.totalReps)개")

        // 변화 목록
        let changes = result.comparisons.filter { !$0.isFirstRecord }
        if !changes.isEmpty {
            lines.append("")
            for comp in changes {
                lines.append(comparisonLine(comp))
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func comparisonLine(_ comp: ExerciseComparison) -> String {
        var parts: [String] = []

        if let wd = comp.weightDelta {
            let sign = wd > 0 ? "+" : ""
            parts.append("무게 \(sign)\(formatted(wd))kg")
        }
        if let rd = comp.repsDelta {
            let sign = rd > 0 ? "+" : ""
            parts.append("횟수 \(sign)\(rd)개")
        }
        if comp.setsDelta != 0 {
            let sign = comp.setsDelta > 0 ? "+" : ""
            parts.append("세트 \(sign)\(comp.setsDelta)")
        }

        let arrow = (comp.weightDelta ?? 0) > 0 || (comp.repsDelta ?? 0) > 0 || comp.setsDelta > 0
            ? "📈" : "📉"

        return "\(arrow) \(comp.exerciseName)  \(parts.joined(separator: " · "))"
    }

    private static func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
