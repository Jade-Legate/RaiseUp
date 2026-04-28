import SwiftUI
import SwiftData

@main
struct RaiseUpApp: App {

    @StateObject private var engine = WorkoutEngine(
        ttsService: TTSService(),
        speechManager: SpeechManager()
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .modelContainer(for: [
                    WorkoutSession.self,
                    WorkoutExerciseRecord.self,
                    WorkoutSetRecord.self,
                    PlannedWorkout.self,
                    PlannedExercise.self,
                ])
                .preferredColorScheme(.dark)
        }
    }
}
