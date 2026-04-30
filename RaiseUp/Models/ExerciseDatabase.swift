import Foundation

// MARK: - 운동 정보 모델

struct ExerciseInfo: Identifiable {
    let id = UUID()
    let name: String
    let bodyPart: String            // 대분류: 하체, 가슴, 등, 팔, 어깨, 코어
    let bodyPartRegion: String?       // bodyPart 하위 중분류: "하체 전면" / "하체 후면" (하체만 해당, 나머지 nil)
    let primaryMuscles: [String]    // 주동근
    let secondaryMuscles: [String]  // 협력근
    let equipment: String           // 바벨, 덤벨, 케이블, 기구, 맨몸
    let mechanic: String?           // compound, isolation
    let aliases: [String]
    let alternatives: [String]

    /// 하위 호환용 — SessionAnalyzer 등에서 주동근 기반 그룹 조회 시 사용
    var muscleGroups: [String] { primaryMuscles }

    /// 커스텀 운동 생성 시 사용 (bodyPart 등 선택적)
    init(name: String,
         bodyPart: String = "기타",
         bodyPartRegion: String? = nil,
         primaryMuscles: [String] = [],
         secondaryMuscles: [String] = [],
         equipment: String = "맨몸",
         mechanic: String? = nil,
         aliases: [String] = [],
         alternatives: [String] = []) {
        self.name            = name
        self.bodyPart        = bodyPart
        self.bodyPartRegion    = bodyPartRegion
        self.primaryMuscles  = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment       = equipment
        self.mechanic        = mechanic
        self.aliases         = aliases
        self.alternatives    = alternatives
    }
}

// JSON 디코딩 전용 구조체 (id 자동 생성 때문에 별도 분리)
private struct ExerciseJSON: Decodable {
    let name: String
    let bodyPart: String
    let bodyPartRegion: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: String
    let mechanic: String?
    let aliases: [String]
    let alternatives: [String]?
}

// MARK: - 운동 데이터베이스

struct ExerciseDatabase {

    // exercises.json 번들 파일에서 로드 (앱 시작 시 1회)
    static let exercises: [ExerciseInfo] = {
        guard let url  = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([ExerciseJSON].self, from: data)
        else {
            assertionFailure("exercises.json 로드 실패 — 파일이 번들에 포함됐는지 확인하세요")
            return []
        }
        return list.map {
            ExerciseInfo(
                name:             $0.name,
                bodyPart:         $0.bodyPart,
                bodyPartRegion:     $0.bodyPartRegion,
                primaryMuscles:   $0.primaryMuscles,
                secondaryMuscles: $0.secondaryMuscles,
                equipment:        $0.equipment,
                mechanic:         $0.mechanic,
                aliases:          $0.aliases,
                alternatives:     $0.alternatives ?? []
            )
        }
    }()

    // MARK: - 이름 or 별명으로 운동 찾기 (fuzzy match, 커스텀 운동 포함)

    static func find(_ query: String) -> ExerciseInfo? {
        let all = allExercises
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }

        // 1. 이름 정확 일치
        if let exact = all.first(where: { $0.name.lowercased() == q }) { return exact }

        // 2. 이름 포함 ("벤치" → "벤치프레스"), 최소 2자 이상
        if q.count >= 2 {
            if let m = all.first(where: {
                $0.name.lowercased().contains(q) || q.contains($0.name.lowercased())
            }) { return m }
        }

        // 3. 별명 일치 (alias가 query와 같거나, alias가 query를 포함)
        if let alias = all.first(where: { info in
            info.aliases.contains(where: { a in
                let al = a.lowercased()
                return al == q || al.contains(q)
            })
        }) { return alias }

        // 4. Levenshtein 편집거리 퍼지 매칭 (오타·음성 인식 오류 허용)
        //    허용 편집거리: 쿼리 길이의 30%, 최소 1자
        if q.count >= 2 {
            let threshold = max(1, q.count / 3)
            let best = all.min { levenshtein($0.name.lowercased(), q) < levenshtein($1.name.lowercased(), q) }
            if let best, levenshtein(best.name.lowercased(), q) <= threshold { return best }
        }

        return nil
    }

    // MARK: - Levenshtein 편집 거리

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aArr = Array(a), bArr = Array(b)
        guard !aArr.isEmpty else { return bArr.count }
        guard !bArr.isEmpty else { return aArr.count }
        var row = Array(0...bArr.count)
        for i in 1...aArr.count {
            var prev = row[0]; row[0] = i
            for j in 1...bArr.count {
                let tmp = row[j]
                row[j] = aArr[i-1] == bArr[j-1] ? prev : min(prev, min(row[j], row[j-1])) + 1
                prev = tmp
            }
        }
        return row[bArr.count]
    }

    // MARK: - bodyPart 기준 그룹핑 (피커용)

    static var groupedByBodyPart: [(part: String, exercises: [ExerciseInfo])] {
        let order = ["하체", "가슴", "등", "어깨", "팔", "코어", "전신", "기타"]
        let dict  = Dictionary(grouping: allExercises) { $0.bodyPart }
        return order.compactMap { part in
            guard let list = dict[part], !list.isEmpty else { return nil }
            return (part, list.sorted { $0.name < $1.name })
        }
    }

    // 기본 운동 + 커스텀 운동 합산
    static var allExercises: [ExerciseInfo] {
        exercises + CustomExerciseStore.shared.toExerciseInfos()
    }

    static var allNames: [String] {
        allExercises.map { $0.name }
    }
}
