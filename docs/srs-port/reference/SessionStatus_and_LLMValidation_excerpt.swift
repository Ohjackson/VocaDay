// 단고초 HomeViewModel — 1차/재도전 세션 상태 판정 (6시간 대기)
    enum SessionStatus {
        case readyForFirstSession
        case waitingForRetry(remainingTime: String)
        case readyForRetry
    }

    var sessionStatus: SessionStatus {
        guard let settings = userSettings else {
            return .readyForFirstSession
        }
        if !settings.srs_sessionInProgress {
            return .readyForFirstSession
        } else {
            guard let completionTime = settings.srs_firstSessionCompletionTime else {
                return .readyForRetry
            }
            guard let retryAvailableTime = Calendar.current.date(byAdding: .hour, value: 6, to: completionTime) else {
                return .readyForRetry
            }
            if sessionReferenceDate < retryAvailableTime {
                let remaining = Calendar.current.dateComponents(
                    [.hour, .minute],
                    from: sessionReferenceDate,
                    to: retryAvailableTime
                )
                let remainingTimeStr = String(format: "%02d:%02d", remaining.hour ?? 0, remaining.minute ?? 0)
                return .waitingForRetry(remainingTime: remainingTimeStr)
            } else {
                return .readyForRetry
            }
        }
    }

    var buttonStatusText: String {
        switch sessionStatus {
        case .readyForFirstSession:
            return "오늘의 학습 시작"
        case .waitingForRetry(let remainingTime):
            return "재도전까지 \(remainingTime) 남음"
        case .readyForRetry:
            return "재도전 학습 시작"
        }
    }

    var isButtonEnabled: Bool {
        switch sessionStatus {
        case .readyForFirstSession, .readyForRetry:
            return true
        case .waitingForRetry:
            return false
        }
    }


// 단고초 LLMService — 교정 재요청 + 로컬 검증 패턴
    private func requestDraftWithCorrection(
        apiKey: String,
        prompt: String,
        expectedWord: String
    ) async throws -> GeneratedWordDraft {
        do {
            return try await requestDraft(
                apiKey: apiKey,
                prompt: prompt,
                expectedWord: expectedWord
            )
        } catch {
            let errorCode = (error as NSError).code
            guard error is GeneratedWordValidationError || errorCode == -7 else {
                throw error
            }
            let correctionPrompt = """
            \(prompt)

            <correction>
            이전 응답은 다음 검증을 통과하지 못했습니다: \(error.localizedDescription)
            모든 규칙을 다시 확인하고 수정된 JSON만 반환하세요.
            </correction>
            """
            return try await requestDraft(
                apiKey: apiKey,
                prompt: correctionPrompt,
                expectedWord: expectedWord
            )
        }
    }

    struct BulkSaveResult {
        var savedWords: [String] = []
    private func validate(
        _ draft: GeneratedWordDraft,
        expectedWord: String
    ) throws -> GeneratedWordDraft {
        let values: [(String, String)] = [
            ("단어", draft.word),
            ("읽는 방법", draft.reading),
            ("한국어 뜻", draft.koreanMeaning),
            ("예문", draft.example),
            ("번역", draft.translation),
            ("시험 문장", draft.testSentence),
            ("시험 정답", draft.testAnswer)
        ]
        for (field, value) in values where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GeneratedWordValidationError.emptyField(field)
        }

        guard draft.word.trimmingCharacters(in: .whitespacesAndNewlines)
            == expectedWord.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw GeneratedWordValidationError.inputMismatch
        }
        guard draft.reading.unicodeScalars.allSatisfy({ scalar in
            (0x3040...0x309F).contains(scalar.value)
                || scalar.value == 0x30FC
                || scalar.value == 0x20
        }) else {
            throw GeneratedWordValidationError.invalidReading
        }

        let lengthLimits: [(String, String, Int)] = [
            ("단어", draft.word, 40),
            ("읽는 방법", draft.reading, 80),
            ("한국어 뜻", draft.koreanMeaning, 120),
            ("예문", draft.example, 240),
            ("번역", draft.translation, 240),
            ("시험 문장", draft.testSentence, 240),
            ("시험 정답", draft.testAnswer, 80)
        ]
        for (field, value, maximum) in lengthLimits where value.count > maximum {
            throw GeneratedWordValidationError.invalidLength(field)
        }

        let blankCount = draft.testSentence.components(separatedBy: "<>").count - 1
        let restoredSentence = draft.testSentence.replacingOccurrences(
            of: "<>",
            with: draft.testAnswer
        )
        guard blankCount == 1,
              draft.example.contains(draft.testAnswer),
              restoredSentence == draft.example else {
            throw GeneratedWordValidationError.invalidBlankSentence
        }

        var sanitizedDraft = draft
        sanitizedDraft.kanjiForm = GeneratedWordDraft.sanitizedKanjiForm(
            draft.kanjiForm,
            word: draft.word,
            reading: draft.reading
        )
        return sanitizedDraft
    }
