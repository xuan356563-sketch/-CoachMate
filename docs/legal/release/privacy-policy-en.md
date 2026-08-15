# CoachMate Privacy Policy (English)

> Version: 1.0 (pre-release)
> Effective date: TBD
> Platforms: iOS / Android / Web
> This document is the official text for the App Store Connect "Privacy Policy URL" and the in-app privacy entry.
> Placeholders: `[Company Name]`, `[Contact Email]`, `[Company Address]`, `[ICP Filing Number]` must be replaced with real information before release.

---

## Introduction

[Company Name] ("we", "us") develops and operates "CoachMate" ("the App"), a local-first personalized training application that helps you log workouts, body metrics, and recovery status, and receive AI coaching suggestions after you confirm them.

We take your personal information and health data seriously. This Privacy Policy explains what information we collect, how we use, store and share it, and the rights you have. **Please read this policy in full before using the App.**

**Core principle**: Your health and body data stays on your device by default. We do not upload health data to the cloud without your separate consent; health data is never used for advertising and is never sold.

---

## 1. Information We Collect

### 1.1 Information You Provide

| Category | Details | Storage | Purpose |
| --- | --- | --- | --- |
| Account | Email address (server stores only a hash), verification code | Cloud | Sign-in and session management |
| Basic profile | Age, sex, height, weight, worker profile type, schedule type, equipment access | On-device (whitelisted fields may sync with your consent) | Personalized training suggestions |
| Body metrics | Weight, body fat, resting heart rate, HRV, sleep hours, fatigue, soreness | On-device | Trend analysis and recovery suggestions |
| Pain/rehab logs | Pain location, severity, timing | On-device | Automatic training de-escalation and safety prompts |
| Workout logs | Training logs, workout player step events, post-workout reviews (actual duration, completion, RPE, heart rate, pace, sets, weight) | On-device | Weekly reports, load trends, user insight |
| Imported files | GPX tracks or FIT summaries you import | On-device | Parse pace, heart rate, elevation; generate training effect labels |
| Race info | Race name, date, type, goal, course info (manual or photo import) | On-device | Race preparation period planning |
| Meal preference | Current dining scenario (takeout/canteen/cooking) | On-device | Daily meal instruction card |
| Feedback | Daily check-ins, workout feedback, "inaccurate" marks | On-device | Improve recommendation quality |

### 1.2 Device Permissions

| Permission | Purpose | Notes |
| --- | --- | --- |
| HealthKit | Phase-wise reading of workout records, distance, heart rate, routes, resting heart rate, HRV, VO2max, and body metrics you enable | Processed on-device only; raw HealthKit samples are never uploaded |
| Camera / Photo Library | Capture or select race posters or exercise photos | Images are analyzed on-device or sent to image recognition after your confirmation; originals are not stored server-side |
| Microphone / Speech Recognition | Transcribe your training requests on-device | Audio is not uploaded or stored; only confirmed text is sent to AI |

### 1.3 Automatically Collected Information

- Installation ID (anonymous device identifier, kept across account switches)
- Necessary crash and performance diagnostics (if enabled)

---

## 2. How We Use Information

We use your information only to the extent necessary to provide the App's features:

1. **Core features**: sign-in, training plans, workout player, exercise library, body metric logging, weekly reports, race preparation, rehab logs.
2. **AI suggestions**: after your **explicit confirmation**, we send de-identified training summaries (no personally identifiable raw health samples) to AI providers to generate structured outputs such as training plans, profile proposals, and recovery suggestions. All AI results are shown as confirm-before-apply cards; **they only affect your training after you confirm**.
3. **Security and compliance**: account verification, anomaly detection, legal compliance.

**We never**:
- use health data for ad targeting;
- sell your personal information;
- upload or store raw health data, raw prompts, images, audio, or raw HealthKit samples on servers (the server stores only validated structured AI outputs and context digests).

---

## 3. Storage and Security

- **Local-first**: body metrics, pain logs, workout logs, imported files, etc. stay on-device by default (SharedPreferences / SQLite / Keychain).
- **Cloud scope**: only when you **explicitly consent** and enable the corresponding feature in the App do the following reach the cloud:
  - account identity (email hash, session tokens);
  - subscription entitlement information;
  - confirmed structured AI outputs and context digests;
  - whitelisted cloud sync data you enabled.
- **Encryption & tokens**: access tokens live in memory only; iPhone refresh tokens are stored in Keychain; on Web you sign in again after refresh.
- **Transport security**: all network traffic uses HTTPS.
- **Retention**: on-device data is kept until you clear it; account data is handled per legal requirements after you request deletion.

---

## 4. Sharing with Third Parties

We share only what is necessary:

| Third party | Purpose | What is shared |
| --- | --- | --- |
| Cloud provider (e.g., Tencent Cloud) | Hosting backend, database, email/SMS delivery | Necessary business data (no raw health samples) |
| AI providers (DeepSeek, MiniMax, etc.) | Text AI cards, image scoring | De-identified summaries or images you confirmed |
| Apple (App Store) | Subscription purchase and entitlement verification | Purchase receipts (verified via Apple's server API) |

We do not sell your personal information. We do not share your information except for the purposes above, with your separate authorization, or as required by law.

---

## 5. Your Rights

1. **View & export**: export your cloud account data as JSON in "Profile → Data Rights".
2. **Delete account**: request account deletion in "Profile → Data Rights" (requires confirmation; cloud data is removed afterwards).
3. **Clear local data**: clear body metrics, export records, etc. on-device (independent operations).
4. **Revoke permissions**: disable HealthKit, camera, photo library, microphone, speech recognition anytime in system settings. The App degrades safely.
5. **Revoke AI consent**: turn off health summary sharing; health data then stays fully on-device.

---

## 6. Children's Privacy

The App is designed for adults and is not directed to children under 13 (or the lower age in your jurisdiction). We do not knowingly collect children's personal information.

---

## 7. Health Disclaimer

The information and suggestions provided by the App **do not constitute medical advice, diagnosis, or treatment** and do not replace a doctor, physical therapist, or other qualified medical professional. If you have a health condition, or pain persists or worsens, consult a qualified professional. In an emergency, seek immediate medical care.

---

## 8. AI-Generated Content

- The App's AI features may generate text such as training plans, meal instructions, and recovery suggestions. AI-generated content may contain errors and is provided **for your reference only**; you decide whether to adopt it.
- You can mark AI suggestions as "inaccurate" in the App to help us improve.
- If you find AI content that is unlawful, infringing, or otherwise inappropriate, you can report it via the contact information below.

---

## 9. Policy Updates

We may update this Privacy Policy from time to time. We will notify you of material changes in the App. Continued use of the App after changes constitutes acceptance.

---

## 10. Contact Us

For questions, comments, or complaints about this policy or your personal information:

- Company: [Company Name]
- Email: [Contact Email]
- Address: [Company Address]
- ICP Filing Number: [ICP Filing Number]

We will respond to your request promptly (usually within 15 business days).

---

*Last updated: [Date]*
