import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var engine: WorkoutEngine
    @Environment(\.modelContext) private var modelContext

    @State private var showSplash = true

    var body: some View {
        Group {
            if showSplash {
                SplashView(onEnter: { showSplash = false })
            } else {
                switch engine.phase {
                case .idle:
                    MainMenuView()

                case .waitingForExercise,
                     .waitingForSetConfig,
                     .exercising,
                     .resting,
                     .waitingForNextExercise:
                    WorkoutSessionView()

                case .sessionEnded:
                    if let session = engine.completedSession {
                        CompletionView(session: session)
                    } else {
                        MainMenuView()
                    }
                }
            }
        }
        .onAppear {
            engine.configure(modelContext: modelContext)
        }
    }
}
