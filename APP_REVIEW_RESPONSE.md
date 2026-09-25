# VocaDay — App Review Guideline 2.1 Response

> Updated for version 1.2 (build 3): adds the 시험 (Exam) and 통계 (Stats) tabs, a spaced-repetition schedule shared by review cards and exams, retry reminders, and an optional user-supplied Gemini API key for exam preparation.

## Before sending

- Record the flow below on the physical iPhone 15 Pro Max running iOS 26.6.1.
- Attach the recording to the Resolution Center reply. Suggested filename: `VocaDay-App-Review-iPhone15ProMax-iOS26.6.1.mov`.
- Confirm that the iPhone and Mac tests listed below were actually completed on the submitted build.
- Replace `[ATTACHED FILE NAME]` with the actual recording filename.
- Paste the response into Resolution Center and also paste the Review Notes section into App Review Information → Notes for the submitted version.

## Resolution Center reply

Hello App Review Team,

Thank you for your review. Please find the requested information below.

### 1. Physical-device screen recording

A screen recording captured on an iPhone 15 Pro Max running iOS 26.6.1 is attached to this reply: `[ATTACHED FILE NAME]`.

The recording begins with launching VocaDay from the Home Screen and demonstrates the typical user flow through the app’s core features:

1. Completing the first-launch quick-start guide
2. Selecting a vocabulary day and adding an English word
3. Generating Korean learning information with Apple Intelligence on a supported device, or entering the information manually
4. Reviewing and editing the generated meaning, example sentences, note, and tag before saving
5. Opening the saved vocabulary day, viewing word details, and playing the English pronunciation
6. Opening Today’s Review, revealing the meaning, marking each word as “Again” or “Known,” and completing the review
7. Opening the Exam tab and completing a short exam (matching, meaning choice, and fill-in-the-blank choice; letter-tile and typing questions appear as a word’s stage rises)
8. Opening the Stats tab and a word’s study history
9. Creating and editing a private study memo
10. Viewing iCloud sync, JSON backup and restore, and privacy information in Settings

VocaDay has no account registration, login, or account-deletion flow. It has no purchases, subscriptions, advertisements, or paid content. Study memos and vocabulary are private user-created learning data; they are not published or shared with other users, so the app does not contain public user-generated content, reporting, or blocking features.

The app does not request access to location, contacts, camera, microphone, photos, or App Tracking Transparency. It asks for notification permission only to deliver the optional daily review reminder (turned on in Settings) and the retry reminder six hours after an exam with incorrect answers. Pronunciation playback uses Apple’s text-to-speech APIs and does not use the microphone. The system file picker appears only when the user explicitly chooses to import or export a backup or Markdown file. The pasteboard is read only after the user taps the Paste button in the optional JSON import flow.

### 2. Devices and operating systems tested

- iPhone 15 Pro Max — iOS 26.6.1 — physical device
- MacBook Pro with Apple M5 — macOS 26.6.2 — physical device

### 3. Purpose, target audience, and user value

VocaDay is a personal English vocabulary learning and review app primarily designed for Korean-speaking English learners, including TOEIC learners.

It solves the problem of vocabulary being scattered across notes, dictionaries, and study materials. Users can organize words into named “Days,” store Korean meanings and bilingual example sentences, listen to pronunciation, and use a spaced-review workflow to identify words they know and words they need to study again. The app also includes private study memos for grammar, dictation, and other language-learning notes.

On supported devices, Apple Intelligence can generate one to three common meanings, parts of speech, bilingual examples, a short usage note, and a learning tag. The user can review and edit all generated content before saving it.

### 4. Setup and instructions for accessing the main features

No account or login credentials are required. No subscription or purchase is required. All features are available immediately after launch.

On a fresh installation:

1. Launch VocaDay and complete or skip the four-step quick-start guide.
2. The app provides a sample vocabulary group named “데이 0” so the main browsing and review flows can be tested immediately.
3. Open the “추가” (Add) tab.
4. Select an existing Day or create a new Day with the plus button beside the destination selector.
5. Enter one English word, such as `reservation`.
6. On an Apple Intelligence-supported device with the on-device model ready, tap “AI로 생성” (Generate with AI). The first use displays an on-device processing disclosure. Alternatively, press Return to create a manual entry and fill in the meaning and examples directly.
7. Review or edit the pending word and tap the bottom save button.
8. Open the “데이” (Days) tab and select the saved Day to view the word. Tap the English word to hear its pronunciation and tap the number to expand its details.
9. Open the “복습” (Review) tab. Today’s Review shows the words currently due. Open a Day, reveal each meaning, mark every word as “다시” (Again) or “알아요” (Known), and tap “복습 완료” (Complete Review).
10. Open “시험” (Exam) and tap the start button. Questions are prepared locally from each word’s meaning and example sentence; no API key is required. Answer every question to finish. Words answered incorrectly become available for a retry session six hours later.
11. Open “통계” (Stats) to see the learning schedule and tap a word to view its study history.
12. Open “학습 메모” (Study Memos) and tap the plus button to create a private study page.
13. Settings are available from the gear button on the Days screen. Settings include iCloud information, JSON backup and restore, optional JSON word import, privacy information, and a button to replay the quick-start guide.

Apple Intelligence generation requires a supported physical device, Apple Intelligence enabled in system settings, and the on-device model ready. If it is unavailable, the app clearly explains the reason and the reviewer can test the same save and review flow using manual entry. No sample file is required. The bundled sample data is sufficient to access the browsing and review features.

### 5. External services, tools, and platforms

VocaDay uses only Apple platform services for its core functionality:

- SwiftData for local persistence
- The user’s private iCloud CloudKit database for automatic synchronization between the user’s devices
- Apple Foundation Models / Apple Intelligence for optional on-device vocabulary generation
- AVSpeechSynthesizer for on-device pronunciation playback
- Apple system document pickers for user-initiated JSON backup/restore and Markdown import/export

The app does not use third-party authentication, payment processors, advertising SDKs, analytics SDKs, tracking SDKs, or third-party data providers.

**Optional Google Gemini API (user-supplied key).** In Exam settings, a user may enter their own Gemini API key. Only then does the app send each word’s English term, Korean meaning, and example sentence with its translation directly from the device to the Google Gemini API to refine exam answer choices. The request uses the user’s own key and never passes through a developer server; the developer receives no data. The key is stored only in the device Keychain and is not synced or backed up. Without a key, nothing is sent and every exam type still works. This is disclosed in Exam settings, in Settings → Privacy and Service Information, and in the privacy policy. Reviewers do not need a key to test any feature.

The optional advanced JSON import feature is not connected to an external AI provider. If a user chooses to use an external AI tool independently, the user manually copies a prompt and manually pastes the resulting JSON into VocaDay. VocaDay does not open the external service, transmit data to it, or receive data from it automatically.

### 6. Regional differences

The app functions consistently across all regions. There are no region-specific feature restrictions, catalogs, prices, accounts, or content. The current app interface and learning explanations are primarily in Korean because the target audience is Korean-speaking English learners.

### 7. Regulated industry and protected third-party material

VocaDay is an educational vocabulary tool. It does not operate in a highly regulated industry and does not provide medical, financial, legal, gambling, cryptocurrency, or government services.

The app does not distribute protected third-party courses, books, examination questions, media, or subscription content. User-entered material remains private to the user. The bundled sample vocabulary and example sentences are original learning examples supplied with the app. Therefore, no regulatory authorization or third-party content credentials are required.

We have also added this information to the App Review Information Notes field for future submissions.

Thank you.

## App Review Information — Notes

VocaDay is a personal English vocabulary learning and spaced-review app for Korean-speaking learners, including TOEIC learners. No account, login, demo credentials, purchase, subscription, advertisement, or public user-generated content is included.

MAIN TEST FLOW: Launch the app → complete or skip the four-step quick-start guide → open 추가 (Add) → select 데이 0 or create a Day → enter `reservation` → tap AI로 생성 (Generate with AI) on a supported Apple Intelligence device, or press Return for manual entry → review/edit the pending content → tap the bottom save button → open 데이 (Days) and the saved Day → tap the English word for pronunciation and its number for details → open 복습 (Review) → open Today’s Review → reveal meanings → mark every word 다시 (Again) or 알아요 (Known) → complete the review → open 시험 (Exam) → start and finish the exam (no API key needed) → open 통계 (Stats) → open 학습 메모 (Study Memos) to create a private note. Settings are available through the gear button on the Days screen.

The app includes sample data named 데이 0, so no sample file is required. Apple Intelligence generation requires a supported physical device with Apple Intelligence enabled and its on-device model ready. Manual word entry provides the same save and review workflow when the model is unavailable.

CORE APPLE SERVICES: SwiftData local storage; the user’s private iCloud CloudKit database for sync; Apple Foundation Models for optional on-device generation; AVSpeechSynthesizer for pronunciation; system document pickers for user-initiated JSON backup/restore and Markdown import/export. OPTIONAL: if the user enters their own Gemini API key in Exam settings, word data is sent directly to the Google Gemini API to refine exam choices; without a key nothing is sent and all features work. There are no third-party authentication services, payments, ads, analytics, tracking, or third-party data providers. Optional external-AI JSON use is entirely manual copy/paste and is not an integration.

PERMISSIONS: Notifications only, for the optional daily review reminder and the exam retry reminder. The app does not request location, contacts, camera, microphone, photos, or tracking access. Text-to-speech does not use the microphone. File and paste access occur only after an explicit user action.

REGIONS AND CONTENT: Functionality is consistent across all regions. The interface is primarily Korean for Korean-speaking English learners. The app is not a regulated service and does not distribute protected third-party material.

TESTED DEVICES: iPhone 15 Pro Max with iOS 26.6.1; MacBook Pro with Apple M5 and macOS 26.6.2.

## Physical-device screen recording plan

Use the submitted TestFlight/App Store build. Enable Do Not Disturb and avoid showing notifications or personal data.

### 0:00–0:15 — Launch

- Begin on the physical iPhone Home Screen so the device launch is clear.
- Open VocaDay.
- Show the app version/build in TestFlight first if practical, then return to the Home Screen and launch VocaDay.

### 0:15–0:40 — First-launch guide

- Move through all four quick-start screens.
- Show the Day, Add, Save, and Review explanations.
- Tap Start and show that the Add tab opens.

### 0:40–1:20 — Add and save a word

- Keep 데이 0 selected or create a new Day named `Review Demo`.
- Enter `reservation`.
- Tap AI로 생성 on the iPhone 15 Pro Max.
- If the Apple Intelligence disclosure appears, show and accept it.
- Wait for the meaning and example sentences to appear.
- Briefly edit one field to demonstrate user control over generated content.
- Tap the bottom save button.

If the on-device model is unavailable, demonstrate manual entry instead and make that visible in the recording.

### 1:20–1:45 — Browse and pronunciation

- Open Days and select the destination Day.
- Show the saved word in the mobile card layout.
- Tap the English word to play pronunciation.
- Tap the number to expand the English example, Korean translation, note, and tag.

### 1:45–2:25 — Review

- Open Review and show the Today’s Review count.
- Open a Day.
- Show that Complete Review remains disabled until all words are assessed.
- Reveal the Korean meaning.
- Mark at least one word Again and the remaining words Known.
- Complete the review and show that words marked Again move to a retry session available six hours later.

### 2:25–3:00 — Exam and stats

- Open Exam and start today’s exam (no Gemini key).
- Answer a matching question and multiple-choice questions (new words start with recognition types; typing types appear from stage 2).
- Finish the exam and show the result screen.
- Open Stats and tap one word to show its study history.

### 3:00–3:20 — Study memo

- Open Study Memos.
- Create a new page, enter a title and a short note, and return to the list.

### 3:20–3:45 — Settings and privacy

- Open Settings from the Days screen.
- Show iCloud sync information.
- Open JSON Backup and Restore briefly.
- Open Privacy and Service Information and show that there is no login, payment, advertising, or tracking.
- End the recording.
