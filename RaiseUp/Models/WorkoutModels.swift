import Foundation
import SwiftData

// MARK: - Workout Session (한 번의 운동 세션 전체)

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var date: Date = Date()
    var startTime: Date = Date()
    var endTime: Date?
    var totalDuration: TimeInterval = 0
    var aiAnalysis: String?

    @Relationship(deleteRule: .cascade)
    var exercises: [WorkoutExerciseRecord] = []

    init() {
        self.id = UUID()
        self.date = Date()
        self.startTime = Date()
    }

    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var totalReps: Int {
        exercises.reduce(0) { $0 + $1.sets.reduce(0) { $0 + $1.actualReps } }
    }

    var formattedDuration: String {
        let minutes = Int(totalDuration) / 60
        let seconds = Int(totalDuration) % 60
        if minutes == 0 { return "\(seconds)초" }
        return "\(minutes)분 \(seconds)초"
    }
}

// MARK: - 운동 세션 내 종목별 기록

@Model
final class WorkoutExerciseRecord {
    var exerciseName: String = ""
    var muscleGroups: [String] = []
    var plannedSets: Int?
    var plannedReps: Int?
    var plannedWeight: Double?
    var startedAt: Date = Date()

    @Relationship(deleteRule: .cascade)
    var sets: [WorkoutSetRecord] = []

    var session: WorkoutSession?

    init(exerciseName: String, muscleGroups: [String] = []) {
        self.exerciseName = exerciseName
        self.muscleGroups = muscleGroups
        self.startedAt = Date()
    }

    var completedSets: Int { sets.count }

    var totalVolume: Double {
        sets.reduce(0) { $0 + (Double($1.actualReps) * ($1.weight ?? 0)) }
    }
}

// MARK: - 개별 세트 기록

@Model
final class WorkoutSetRecord {
    var setNumber: Int = 1
    var plannedReps: Int?
    var actualReps: Int = 0
    var weight: Double?
    var completedAt: Date = Date()

    var exerciseRecord: WorkoutExerciseRecord?

    init(setNumber: Int, plannedReps: Int? = nil, actualReps: Int = 0, weight: Double? = nil) {
        self.setNumber = setNumber
        self.plannedReps = plannedReps
        self.actualReps = actualReps
        self.weight = weight
        self.completedAt = Date()
    }
}

// MARK: - 사전 운동 계획 (선택 사항)

@Model
final class PlannedWorkout {
    var id: UUID = UUID()
    var name: String = ""
    var date: Date = Date()
    var createdAt: Date = Date()
    var isCompleted: Bool = false

    @Relationship(deleteRule: .cascade)
    var exercises: [PlannedExercise] = []

    init() {
        self.id = UUID()
        self.date = Date()
        self.createdAt = Date()
    }
}

@Model
final class PlannedExercise {
    var exerciseName: String = ""
    var sets: Int = 3
    var repsPerSet: Int = 10
    var restSeconds: Int = 60
    var weight: Double?
    var order: Int = 0

    var plan: PlannedWorkout?

    init() {
        self.exerciseName = ""
        self.sets = 3
        self.repsPerSet = 10
        self.restSeconds = 60
        self.order = 0
    }
}
