import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var customStore = CustomExerciseStore.shared

    @State private var apiKey:      String = UserDefaults.standard.string(forKey: "elevenLabsAPIKey")  ?? ""
    @State private var voiceId:     String = UserDefaults.standard.string(forKey: "elevenLabsVoiceId") ?? "pNInz6obpgDQGcFmaJgB"
    @State private var claudeKey:   String = UserDefaults.standard.string(forKey: "claudeAPIKey") ?? ""
    @State private var restSeconds: Double = Double(UserDefaults.standard.integer(forKey: "restSeconds") > 0
                                                    ? UserDefaults.standard.integer(forKey: "restSeconds") : 60)
    @State private var countingVoice: Bool = UserDefaults.standard.object(forKey: "countingVoiceEnabled") as? Bool ?? true
    @AppStorage("weightUnit") private var weightUnit: String = "kg"

    @State private var showAddExercise = false
    @State private var editingExercise: CustomExerciseStore.CustomExercise?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ruBackground.ignoresSafeArea()

                Form {
                    // MARK: - 운동 설정
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("휴식 시간")
                                Spacer()
                                Text("\(Int(restSeconds))초")
                                    .foregroundStyle(Color.ruGold)
                                    .bold()
                            }
                            Slider(value: $restSeconds, in: 15...180, step: 5)
                                .tint(Color.ruGold)
                        }
                        .padding(.vertical, 4)

                        Toggle("카운트 음성", isOn: $countingVoice)
                            .tint(Color.ruGold)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("무게 단위")
                                .foregroundStyle(.primary)
                            Picker("무게 단위", selection: $weightUnit) {
                                Text("kg").tag("kg")
                                Text("lbs").tag("lbs")
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("운동 설정")
                    } footer: {
                        Text("카운트 음성을 끄면 세트 중 숫자를 읽지 않습니다.")
                    }

                    // MARK: - 커스텀 운동
                    Section {
                        ForEach(customStore.exercises) { exercise in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name)
                                        .font(.subheadline.bold())
                                    if !exercise.muscleGroups.isEmpty {
                                        Text(exercise.muscleGroups.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    editingExercise = exercise
                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundStyle(Color.ruGold)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            indexSet.forEach { i in
                                customStore.delete(id: customStore.exercises[i].id)
                            }
                        }

                        Button {
                            showAddExercise = true
                        } label: {
                            Label("운동 추가", systemImage: "plus")
                                .foregroundStyle(Color.ruGold)
                        }
                    } header: {
                        Text("커스텀 운동")
                    } footer: {
                        Text("추가한 운동은 음성 인식 시 자동으로 인식됩니다.")
                    }

                    // MARK: - Claude AI
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Key").font(.caption).foregroundStyle(.secondary)
                            SecureField("sk-ant-...", text: $claudeKey)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    } header: {
                        Text("Claude AI (오늘의 분석 · 운동 방향)")
                    } footer: {
                        Text("Anthropic Console에서 발급. 입력 시 AI 운동 분석이 활성화됩니다.\nconsole.anthropic.com")
                    }

                    // MARK: - ElevenLabs
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Key").font(.caption).foregroundStyle(.secondary)
                            SecureField("ElevenLabs API Key", text: $apiKey)
                                .autocorrectionDisabled()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Voice ID").font(.caption).foregroundStyle(.secondary)
                            TextField("Voice ID", text: $voiceId)
                                .autocorrectionDisabled()
                        }
                    } header: {
                        Text("ElevenLabs TTS")
                    } footer: {
                        Text("API Key를 입력하면 고품질 한국어 음성이 적용됩니다.")
                    }

                    // MARK: - 음성 명령어 안내
                    Section("기본 음성 명령어") {
                        commandRow(cmd: "운동 시작",       desc: "세션 시작")
                        commandRow(cmd: "[종목명]",         desc: "예) 스쿼트, 벤치프레스")
                        commandRow(cmd: "N킬로 N개씩 N세트", desc: "볼륨 설정")
                        commandRow(cmd: "방금 N개 했어",   desc: "반복 수 수정")
                        commandRow(cmd: "시작",            desc: "휴식 중 다음 세트")
                        commandRow(cmd: "끝",              desc: "세트 종료 / 세션 종료")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("설정")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .foregroundStyle(Color.ruGold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddExercise) {
                CustomExerciseEditor(exercise: nil)
            }
            .sheet(item: $editingExercise) { ex in
                CustomExerciseEditor(exercise: ex)
            }
        }
    }

    private func save() {
        UserDefaults.standard.set(apiKey,    forKey: "elevenLabsAPIKey")
        UserDefaults.standard.set(voiceId,   forKey: "elevenLabsVoiceId")
        UserDefaults.standard.set(claudeKey, forKey: "claudeAPIKey")
        UserDefaults.standard.set(Int(restSeconds), forKey: "restSeconds")
        UserDefaults.standard.set(countingVoice,    forKey: "countingVoiceEnabled")
        dismiss()
    }

    private func commandRow(cmd: String, desc: String) -> some View {
        HStack {
            Text(cmd).font(.subheadline.bold()).foregroundStyle(Color.ruGold)
            Spacer()
            Text(desc).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 커스텀 운동 추가/편집 시트

struct CustomExerciseEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = CustomExerciseStore.shared

    let exercise: CustomExerciseStore.CustomExercise?

    @State private var name: String = ""
    @State private var muscleGroups: String = ""
    @State private var aliases: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ruBackground.ignoresSafeArea()
                Form {
                    Section("운동 이름") {
                        TextField("예) 케틀벨스윙", text: $name)
                            .autocorrectionDisabled()
                    }
                    Section {
                        TextField("예) 전신, 하체", text: $muscleGroups)
                            .autocorrectionDisabled()
                    } header: {
                        Text("근육 그룹")
                    } footer: {
                        Text("쉼표로 구분")
                    }
                    Section {
                        TextField("예) 케틀벨, kettlebell swing", text: $aliases)
                            .autocorrectionDisabled()
                    } header: {
                        Text("별명 (음성 인식 대체어)")
                    } footer: {
                        Text("쉼표로 구분. 별명을 말해도 인식됩니다.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(exercise == nil ? "운동 추가" : "운동 편집")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .foregroundStyle(Color.ruGold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .onAppear {
                guard let ex = exercise else { return }
                name         = ex.name
                muscleGroups = ex.muscleGroups.joined(separator: ", ")
                aliases      = ex.aliases.joined(separator: ", ")
            }
        }
    }

    private func save() {
        let groups  = muscleGroups.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let aliasList = aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        if var ex = exercise {
            ex.name         = name.trimmingCharacters(in: .whitespaces)
            ex.muscleGroups = groups
            ex.aliases      = aliasList
            store.update(ex)
        } else {
            store.add(name: name.trimmingCharacters(in: .whitespaces),
                      muscleGroups: groups,
                      aliases: aliasList)
        }
        dismiss()
    }
}
