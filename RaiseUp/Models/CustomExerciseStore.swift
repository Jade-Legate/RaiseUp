import Foundation
import Combine

// MARK: - 사용자 커스텀 운동 저장소 (UserDefaults 기반)

class CustomExerciseStore: ObservableObject {
    static let shared = CustomExerciseStore()

    private let key = "customExercises"

    struct CustomExercise: Codable, Identifiable {
        var id: String = UUID().uuidString
        var name: String
        var muscleGroups: [String]
        var aliases: [String]
    }

    @Published private(set) var exercises: [CustomExercise] = []

    private init() {
        load()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CustomExercise].self, from: data)
        else { return }
        exercises = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(exercises) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func add(name: String, muscleGroups: [String] = [], aliases: [String] = []) {
        let ex = CustomExercise(name: name, muscleGroups: muscleGroups, aliases: aliases)
        exercises.append(ex)
        save()
    }

    func update(_ exercise: CustomExercise) {
        guard let i = exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        exercises[i] = exercise
        save()
    }

    func delete(id: String) {
        exercises.removeAll { $0.id == id }
        save()
    }

    // ExerciseInfo로 변환
    func toExerciseInfos() -> [ExerciseInfo] {
        exercises.map {
            ExerciseInfo(
                name:           $0.name,
                primaryMuscles: $0.muscleGroups,   // 기존 필드 → primaryMuscles로 매핑
                aliases:        $0.aliases
            )
        }
    }
}
