import Foundation

// MARK: - AI 분석 서비스
// 세션 완료 직후 분석 → SessionAnalyzer (규칙 기반, AI 불필요)
// 전체 운동 방향 분석    → Claude API (여러 세션 종합, AI 유의미)

struct AIAnalysisService {

    static var claudeAPIKey: String {
        UserDefaults.standard.string(forKey: "claudeAPIKey") ?? ""
    }

    // MARK: - 전체 운동 방향 분석 (여러 세션, AI 탭에서 사용)

    static func analyzeDirection(sessions: [WorkoutSession]) async -> String {
        guard !sessions.isEmpty else {
            return "아직 운동 기록이 없습니다. 운동을 시작하면 AI가 방향을 분석해 드립니다."
        }
        if !claudeAPIKey.isEmpty,
           let result = try? await callClaude(prompt: directionPrompt(sessions)) {
            return result
        }
        return "Claude API 키를 Settings에 입력하면 맞춤 분석을 받을 수 있습니다.\n\n최근 \(sessions.count)회 운동 기록이 있습니다."
    }

    // MARK: - Claude API 호출

    private static func callClaude(prompt: String) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(claudeAPIKey,       forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 800,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first,
              let text    = content["text"] as? String
        else { throw URLError(.cannotParseResponse) }
        return text
    }

    // MARK: - 운동 방향 분석 프롬프트

    private static func directionPrompt(_ sessions: [WorkoutSession]) -> String {
        let recent = Array(sessions.prefix(10))
        var lines: [String] = [
            "당신은 피트니스 코치입니다. 아래 최근 운동 기록을 분석해 한국어로 300자 이내로 작성하세요.",
            "포함할 내용:",
            "1. 자주 하는 운동 부위 / 빠진 부위",
            "2. 볼륨/빈도 추세",
            "3. 다음 2주 동안 집중할 것 1~2가지",
            "",
            "--- 최근 운동 기록 ---"
        ]
        for session in recent {
            let dateStr = session.date.formatted(.dateTime.month().day())
            let names   = session.exercises.map { $0.exerciseName }.joined(separator: ", ")
            lines.append("\(dateStr): \(names) (\(session.totalSets)세트)")
        }
        return lines.joined(separator: "\n")
    }
}
