# RaiseUp

> 손을 쓰지 않아도 되는 음성 기반 헬스 트래킹 iOS 앱

운동 중 폰을 만질 필요 없이 목소리만으로 세트를 기록하고, 운동이 끝나면 자동으로 분석 결과를 보여줍니다.

---

## 주요 기능

### 음성 제어
- **"운동 시작"** — 세션 시작
- **"스쿼트"** — 종목 선택 (퍼지 매칭으로 오타·발음 오류 허용)
- **"60킬로 10개씩 3세트"** — 볼륨 설정
- **"시작 / 끝"** — 세트 시작·종료
- **"기구 없어 / 대체 운동"** — 현재 종목의 대체 운동 3개 추천
- **"1번 / 2번 / 3번"** — 음성으로 대체 운동 선택

### 운동 분석
- 세션 완료 직후 **규칙 기반 분석** (AI 불필요)
  - 오늘의 주 부위 (하체 전면/후면, 가슴, 등 …)
  - 총 세트·반복 수
  - 이전 세션 대비 무게·횟수·세트 변화량
- AI 탭에서 **Claude API 기반 다방향 분석** (최근 10회 종합, 선택 사항)

### 운동 데이터베이스
- 35개 운동, [wrkout 오픈소스](https://github.com/wrkout/exercises.json) 기반 한국어 분류
- 대분류 6종: 하체 / 가슴 / 등 / 어깨 / 팔 / 코어
- 중분류: 하체 전면 / 하체 후면
- 커스텀 운동 추가 가능 (별명 등록 → 음성 인식에 반영)

### 히스토리
- 캘린더 뷰 + 세션 상세 (종목·세트·운동 분석)
- 운동 기록 **직접 추가 / 수정** (날짜·시간 직접 입력)
- 계층형 운동 피커 (하체 → 스쿼트 선택, 오타 없음)
- 카드 드래그로 종목 순서 변경

### 루틴 플래너
- 루틴 생성·편집·삭제
- **"START"** 버튼으로 루틴 기반 음성 세션 시작

---

## 기술 스택

| 항목 | 내용 |
|---|---|
| 플랫폼 | iOS 17+ |
| 언어 | Swift 5.9 |
| UI | SwiftUI |
| 데이터 | SwiftData |
| 음성 인식 | SFSpeechRecognizer (ko-KR) |
| TTS | AVSpeechSynthesizer (기본) / ElevenLabs API (선택) |
| AI 분석 | Claude API — claude-haiku-4-5 (선택, BYOK) |

---

## 아키텍처

```
RaiseUp/
├── Engine/
│   ├── WorkoutEngine.swift       # @Observable 상태 머신 (세션 전체 흐름)
│   └── VoiceCommandParser.swift  # rule-based 의도 분류 (Intent Classification)
├── Models/
│   ├── WorkoutModels.swift       # SwiftData 모델 (Session / Exercise / Set)
│   ├── ExerciseDatabase.swift    # JSON 로더 + Levenshtein 퍼지 매칭
│   └── CustomExerciseStore.swift # UserDefaults 커스텀 운동
├── Services/
│   ├── SpeechManager.swift       # 음성 인식 (AVAudioEngine + SFSpeechRecognizer)
│   ├── TTSService.swift          # TTS (AVSpeechSynthesizer / ElevenLabs)
│   ├── SessionAnalyzer.swift     # rule-based 세션 분석 (API 불필요)
│   └── AIAnalysisService.swift   # Claude API 다방향 분석
├── Views/
│   ├── DesignSystem.swift        # 브랜드 컬러 팔레트
│   ├── WorkoutSessionView.swift  # 음성 세션 UI
│   ├── ManualWorkoutEditorView.swift # 수동 입력/편집 + 운동 피커
│   ├── HistoryView.swift
│   ├── RoutinePlannerView.swift
│   ├── WorkoutAnalysisView.swift
│   └── ProfileView.swift
└── exercises.json                # 운동 데이터 (bodyPart / 근육 분류)
```

---

## 설정 (선택 사항)

앱 내 **설정 화면**에서 입력합니다. 두 항목 모두 없어도 기본 기능은 동작합니다.

| 항목 | 용도 | 발급처 |
|---|---|---|
| Claude API Key | 운동 방향 AI 분석 | [console.anthropic.com](https://console.anthropic.com) |
| ElevenLabs API Key | 고품질 한국어 TTS | [elevenlabs.io](https://elevenlabs.io) |

---

## 실행 방법

```bash
git clone https://github.com/Jade-Legate/RaiseUp.git
cd RaiseUp
open RaiseUp.xcodeproj
```

> Xcode 16 이상 권장. 실기기 또는 시뮬레이터에서 실행.  
> 음성 인식은 실기기에서만 정상 동작합니다.

---

## 라이선스

MIT
