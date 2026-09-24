//
//  SRSCardModeViewModel.swift
//  tanngochou
//
//  Created by Jaehyun Ahn on 5/3/25.
//

// SRSCardsViewModel.swift

import Foundation
import SwiftUI
import CoreData
import Combine

class SRSCardsViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var wordsDueToday: [Word] = []
    @Published var isLoading: Bool = false
    @Published var cards: [SRSWordCard] = []
    @Published var swipedCards: [SRSWordCard] = []
    @Published var okCount: Int = 0
    @Published var noCount: Int = 0
    @Published var isRetrySession: Bool = false
    
    // MARK: - Properties
    private(set) var initialCount: Int = 0
    private var userProfile: UserProfile?
    
    // ✅ Core Data 접근을 위한 프로퍼티
    private var userSettings: UserSettings?
    private var viewContext: NSManagedObjectContext = PersistenceController.shared.viewContext
    private var hasProcessedCurrentResults = false
    
    let processingComplete = PassthroughSubject<Void, Never>()
    
    // MARK: - Data Fetching
    
    /// isRetryMode에 따라 적절한 데이터 로딩 함수를 호출하는 분기 함수
    func fetchData(isRetryMode: Bool, profile: UserProfile) {
        self.userProfile = profile
        self.isRetrySession = isRetryMode
        print("isRetryMode: \(isRetryMode)")
        
        // Core Data에서 UserSettings 객체를 가져와 프로퍼티에 저장합니다.
        let request: NSFetchRequest<UserSettings> = UserSettings.fetchRequest()
        request.fetchLimit = 1
        self.userSettings = try? viewContext.fetch(request).first

        if self.userSettings == nil {
            // UserSettings가 없으면 세션 결과 처리(processFirstSessionResults 등)가
            // 조용히 아무 일도 하지 않고 화면이 멈춘 것처럼 보이는 문제가 있었다.
            // 누락된 경우를 대비해 즉시 생성해 채워 넣는다.
            PersistenceController.shared.ensureSingleUserSettingsExists()
            self.userSettings = try? viewContext.fetch(request).first
        }

        if isRetryMode {
            fetchRetryWords()
        } else {
            fetchTodayWords()
        }
    }
    
    /// 1차 학습 단어를 가져오는 함수
    private func fetchTodayWords() {
        isLoading = true
        guard let profile = self.userProfile else {
            isLoading = false
            return
        }
        
        wordsDueToday = SRSManager.shared.fetchTodayWords(currentLearningDay: profile.currentLearningDay).shuffled()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.isLoading = false
        }
    }
    
    /// 2차 재도전 단어를 가져오는 함수
    private func fetchRetryWords() {
        isLoading = true
        
        // UserSettings에서 틀린 단어 ID 목록(JSON)을 가져와 디코딩합니다.
        guard let jsonString = userSettings?.srs_wrongAnswerWordIDs_JSON,
              let data = jsonString.data(using: .utf8),
              let wrongAnswerWordIDs = try? JSONDecoder().decode([String].self, from: data) else {
            wordsDueToday = []
            isLoading = false
            return
        }
        
        wordsDueToday = SRSManager.shared.fetchRetryWords(wordIDs: wrongAnswerWordIDs).shuffled()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.isLoading = false
        }
    }
    
    // MARK: - Card Handling
    
    func setupCards() {
        cards = wordsDueToday.compactMap { word in
            guard let wordID = word.id else { return nil }
            return SRSWordCard(
                wordID: wordID,
                kannji: word.kannji ?? "",
                hiragana: word.hiragana ?? "",
                korean: word.korean ?? "",
                example: word.example ?? "",
                exampleMean: word.mean ?? ""
            )
        }
        initialCount = cards.count
        okCount = 0
        noCount = 0
        swipedCards = []
        hasProcessedCurrentResults = false
    }
    
    func progress() -> CGFloat {
        guard initialCount > 0 else { return 0 }
        return CGFloat(initialCount - cards.count) / CGFloat(initialCount)
    }
    
    func markCard(_ card: SRSWordCard, asKnown known: Bool) {
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            var processedCard = cards[index]
            processedCard.isKnown = known
            
            if known {
                okCount += 1
            } else {
                noCount += 1
            }
            
            swipedCards.append(processedCard)
            cards.remove(at: index)
        }
    }
    
    // MARK: - Session Result Processing
    
    /// 1차 학습 결과를 처리하는 함수
    func processFirstSessionResults() {
        guard !hasProcessedCurrentResults else { return }
        guard let profile = userProfile, let settings = userSettings else { return }
        hasProcessedCurrentResults = true
        
        let currentLearningDay = Int64(profile.currentLearningDay)
        var wrongAnswerIDs: [String] = []
        
        for card in swipedCards {
            if card.isKnown == true {
                SRSManager.shared.markKnown(wordID: card.wordID, currentLearningDay: currentLearningDay)
            } else {
                SRSManager.shared.markWrong(wordID: card.wordID)
                wrongAnswerIDs.append(card.wordID.uuidString)
            }
        }
        
        if wrongAnswerIDs.isEmpty {
            // 모든 문제를 맞혔을 경우 (완벽한 학습)
            print("🎉 Perfect score on the first session! Completing the learning day now.")
            profile.currentLearningDay += 1
            profile.visitCount += 1
            
            // UserSettings의 세션 정보를 초기화합니다.
            settings.srs_sessionInProgress = false
            settings.srs_wrongAnswerWordIDs_JSON = nil
            settings.srs_firstSessionCompletionTime = nil
            
        } else {
            // 틀린 단어가 하나라도 있을 경우
            print("🤔 Some words were incorrect. Scheduling a retry session.")
            
            // UserSettings에 재도전 정보를 저장합니다.
            settings.srs_sessionInProgress = true
            settings.srs_firstSessionCompletionTime = Date()
            
            if let data = try? JSONEncoder().encode(wrongAnswerIDs) {
                settings.srs_wrongAnswerWordIDs_JSON = String(data: data, encoding: .utf8)
            }
            
            print("--- 💾 Verifying UserSettings state before saving ---")
                print("srs_sessionInProgress: \(settings.srs_sessionInProgress)")
                print("srs_firstSessionCompletionTime: \(settings.srs_firstSessionCompletionTime?.description ?? "nil")")
                print("srs_wrongAnswerWordIDs_JSON: \(settings.srs_wrongAnswerWordIDs_JSON ?? "nil")")
                print("-------------------------------------------------")
        }

        settings.srs_updatedAt = Date()
        
        print("--- 💾 Verifying UserSettings state before saving ---")
            print("srs_sessionInProgress: \(settings.srs_sessionInProgress)")
            print("srs_firstSessionCompletionTime: \(settings.srs_firstSessionCompletionTime?.description ?? "nil")")
            print("srs_wrongAnswerWordIDs_JSON: \(settings.srs_wrongAnswerWordIDs_JSON ?? "nil")")
            print("-------------------------------------------------")
            
        
        if SRSManager.shared.saveContext() {
            if !wrongAnswerIDs.isEmpty {
                NotificationManager.shared.scheduleRetryNotification()
            }
            processingComplete.send()
        } else {
            hasProcessedCurrentResults = false
        }
    }
    
    /// 2차(재도전) 학습 결과를 처리하고 세션을 완전히 종료하는 함수
    func completeRetryLearningSession() {
        guard !hasProcessedCurrentResults else { return }
        guard let profile = userProfile, let settings = userSettings else { return }
        hasProcessedCurrentResults = true
        
        let currentLearningDay = Int64(profile.currentLearningDay)
        
        for card in swipedCards {
            if card.isKnown == true {
                SRSManager.shared.retryMarkKnown(wordID: card.wordID, currentLearningDay: currentLearningDay)
            } else {
                SRSManager.shared.retryMarkWrong(wordID: card.wordID, currentLearningDay: currentLearningDay)
            }
        }
        
        profile.currentLearningDay += 1
        profile.visitCount += 1
        
        // 모든 학습이 끝났으므로 UserSettings의 세션 정보를 초기화합니다.
        settings.srs_sessionInProgress = false
        settings.srs_wrongAnswerWordIDs_JSON = nil
        settings.srs_firstSessionCompletionTime = nil
        settings.srs_updatedAt = Date()
        
        if SRSManager.shared.saveContext() {
            processingComplete.send()
        } else {
            hasProcessedCurrentResults = false
        }
    }
    
}

// MARK: - SRSWordCard Struct
struct SRSWordCard: Identifiable, Equatable {
    let id = UUID()
    let wordID: UUID
    
    let kannji: String
    let hiragana: String
    let korean: String
    var isKnown: Bool? = nil
    
    let example: String
    let exampleMean: String
}
