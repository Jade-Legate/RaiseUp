import Foundation
import AVFoundation

// MARK: - TTS 서비스 (ElevenLabs 우선, Apple TTS fallback)

class TTSService: NSObject, AVSpeechSynthesizerDelegate {

    // MARK: - ElevenLabs 설정 (Settings에서 입력)
    var elevenLabsAPIKey: String {
        get { UserDefaults.standard.string(forKey: "elevenLabsAPIKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "elevenLabsAPIKey") }
    }
    var voiceId: String {
        get { UserDefaults.standard.string(forKey: "elevenLabsVoiceId") ?? "pNInz6obpgDQGcFmaJgB" }
        set { UserDefaults.standard.set(newValue, forKey: "elevenLabsVoiceId") }
    }

    // MARK: - 내부

    private var audioPlayer: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var appleCompletion: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - 외부 인터페이스

    /// 현재 재생 중인 오디오를 즉시 중단 (다음 speak 전 queue flush 용)
    func stopSpeaking() {
        audioPlayer?.stop()
        audioPlayer = nil
        synthesizer.stopSpeaking(at: .immediate)
        if let c = appleCompletion {
            appleCompletion = nil
            c.resume()   // continuation 정상 종료
        }
    }

    func speak(_ text: String) async {
        if !elevenLabsAPIKey.isEmpty {
            do {
                let data = try await fetchElevenLabsAudio(text: text)
                await playAudioData(data)
                return
            } catch {
                print("[TTSService] ElevenLabs 실패, Apple TTS 사용: \(error.localizedDescription)")
            }
        }
        await speakWithAppleTTS(text)
    }

    // MARK: - ElevenLabs API

    private func fetchElevenLabsAudio(text: String) async throws -> Data {
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue(elevenLabsAPIKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg",        forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": [
                "stability": 0.6,
                "similarity_boost": 0.8,
                "style": 0.2,
                "use_speaker_boost": true
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    @MainActor
    private func playAudioData(_ data: Data) async {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            while audioPlayer?.isPlaying == true {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms polling
            }
        } catch {
            print("[TTSService] 오디오 재생 실패: \(error)")
        }
    }

    // MARK: - Apple TTS (fallback)

    @MainActor
    private func speakWithAppleTTS(_ text: String) async {
        // 이전 utterance가 아직 재생 중이면 continuation을 먼저 정리
        // (두 번의 speak가 겹칠 때 continuation 누수 방지)
        if let previous = appleCompletion {
            appleCompletion = nil
            previous.resume()
        }
        synthesizer.stopSpeaking(at: .immediate)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            appleCompletion = continuation

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice              = AVSpeechSynthesisVoice(language: "ko-KR")
            utterance.rate               = AVSpeechUtteranceDefaultSpeechRate * 0.9
            utterance.pitchMultiplier    = 1.05
            utterance.volume             = 1.0
            utterance.postUtteranceDelay = 0.1

            synthesizer.speak(utterance)

            // 안전장치: delegate가 불리지 않는 경우(시뮬레이터 등) 타임아웃 후 강제 resume
            let timeout = max(Double(text.count) * 0.11 + 1.5, 2.5)
            let capturedTimeout = timeout
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(capturedTimeout * 1_000_000_000))
                guard let self else { return }
                // 아직 이 continuation이 살아있으면 resume
                if let pending = self.appleCompletion {
                    self.appleCompletion = nil
                    pending.resume()
                }
            }
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard let c = appleCompletion else { return }
        appleCompletion = nil
        c.resume()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard let c = appleCompletion else { return }
        appleCompletion = nil
        c.resume()
    }
}
