# Voice Note Summarizer 🎙️⚡

**Offline, Private, On-Device AI Summary & Transcription**

**Voice Note Summarizer** is a Flutter application that uses Google's **Gemma 4 E2B** multimodal model directly on your Android device to transcribe and summarize voice notes. It operates completely offline, ensuring 100% privacy with zero data transfer to the cloud.

---

## 🚀 Key Features

*   **100% On-Device Inference:** Uses `LiteRT-LM` to run Gemma 4 E2B locally. No API keys, no cloud costs, no privacy risks.
*   **Multimodal Processing:** Processes raw audio directly (speech-to-text + summarization in one pass) without intermediate text-to-speech steps.
*   **Robust Queue System:** 
    *   **Serialized Processing:** Prevents app crashes by processing files one-by-one.
    *   **Background Execution:** Uses a Foreground Service to keep processing alive even when the screen is off.
    *   **Persistence:** Queue state is saved to disk, surviving app restarts.
*   **Share Integration:** seamlessly share audio files from WhatsApp, Telegram, or File Manager directly to the app.
*   **Dynamic Customization:**
    *   **Prompt Presets:** Save and load custom system prompts (e.g., "Romanize Urdu", "Meeting Minutes").
    *   **Dynamic Settings:** Adjust system instructions and transcription rules on the fly.

---

## 🏗️ Architecture Overview

The app is built on a **Flutter** frontend with a powerful **Native Kotlin** backend for AI inference.

### 1. Flutter Layer (`lib/`)
Handles UI, state management, and orchestration.

*   **`lib/providers/processing_state.dart`**: The "Heart" of the app.
    *   Manages the **Queue** (`QueueItem`).
    *   Handles **Audio Conversion** (`AudioConverter`).
    *   Orchestrates the **Service Bridge** (`GemmaAudioService`).
    *   Implements the **Mutex Lock** (`_isProcessingQueue`) to enforce serialized execution.
*   **`lib/services/gemma_audio_service.dart`**:
    *   Communicates with Native Android via `MethodChannel`.
    *   Exposes methods like `transcribeAndSummarize`, `copyBundledModel`, `initialize`.
*   **`lib/services/share_handler_service.dart`**:
    *   Listens for `Intent` inputs (shared files).
    *   Copies shared files to the app's local storage and adds them to the queue.
*   **`lib/services/notification_service.dart`**:
    *   Shows local notifications when summaries are ready.
    *   Enables "Tap to View" navigation via `flutter_local_notifications`.

### 2. Native Android Layer (`android/app/src/main/kotlin/`)
Handles the heavy lifting: AI model loading and inference.

*   **`GemmaAudioPlugin.kt`**:
    *   The entry point for Flutter `MethodChannel`.
    *   Receives configuration (System Prompts, Transcription Rules) from Flutter.
    *   Standardizes markdown output (TITLE, SUMMARY, KEY POINTS) for easy parsing.
*   **`GemmaRuntime.kt`**:
    *   Singleton that manages the `LiteRT-LM` engine.
    *   Implements **Single-Flight Initialization** to prevent multiple threads from loading the model simultaneously.
*   **`ModelStore.kt`**:
    *   Manages the physical model file (`.litertlm`).
    *   Handles **Atomic Copying** of the bundled 2.58GB model from APK assets -> internal storage on first run.

---

## 📂 Project Structure

```
.
├── lib/
│   ├── main.dart                 # App Entry point & Theme
│   ├── providers/
│   │   └── processing_state.dart # Core Logic & Queue Management
│   ├── services/
│   │   ├── gemma_audio_service.dart  # Native Bridge
│   │   ├── share_handler_service.dart# Android Intent Handler
│   │   └── notification_service.dart 
│   ├── screens/
│   │   ├── home_screen.dart      # Main Dashboard
│   │   ├── queue_screen.dart     # Queue Management UI
│   │   ├── results_screen.dart   # Transcript & Summary View
│   │   └── settings_screen.dart  # Dynamic Prompts & Presets
│   └── services/
│       └── audio_converter.dart  # FFMPEG Audio Normalization
│
├── android/app/src/main/kotlin/com/voicenotesummarizer/vm_summ/
│   ├── GemmaAudioPlugin.kt       # MethodChannel Handler
│   ├── GemmaRuntime.kt           # AI Inference Engine
│   └── ModelStore.kt             # Model File Management
│
└── assets/models/                # (Gitignored) Place .litertlm model here
```

---

## 🛠️ Setup & Installation

### Prerequisites
*   **Flutter SDK**: 3.27+
*   **Android SDK**: API 26+ (Android 8.0+)
*   **Physical Device**: 8GB+ RAM Recommended (Samsung S23/S24, Pixel 7/8/9). **Emulator will likely fail or be extremely slow.**

### 1. Model Setup
This app bundles the **Gemma 4 E2B** LiteRT-LM artifact in the APK.
The Android integration pins **LiteRT-LM 0.11.0+** for Gemma 4 speculative-decoding compatibility on supported GPU devices.
1.  Download `gemma-4-E2B-it.litertlm` from [`litert-community/gemma-4-E2B-it-litert-lm`](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm).
2.  Verify the SHA256 is `ab7838cdfc8f77e54d8ca45eadceb20452d9f01e4bfade03e5dce27911b27e42`.
3.  Place it in: `android/app/src/main/assets/gemma-4-E2B-it.litertlm`

*(Note: The bundled model is ~2.58GB and is intentionally packaged with the app.)*

### 1.1 Runtime Notes
*   **MTP readiness rollout:** The runtime probes speculative-decoding support and preloads sampler libraries on supported GPU devices.
*   **No model swap required:** The initial rollout keeps the existing bundled Gemma 4 E2B `.litertlm` artifact and does not require an app-level model family change.
*   **CPU fallback:** CPU fallback and emulator paths keep speculative decoding disabled in this version to avoid regressions on non-GPU execution paths.
*   **E4B remains optional:** Gemma 4 E4B is not bundled here. It would require a larger asset, more device-capacity validation, and a separate product decision.

### 2. Build & Run
**CRITICAL:** You must run in **Release Mode**. Debug mode adds overhead that makes the AI too slow to function.

```bash
flutter run --release
```

---

## 📝 Usage Guide

### 1. Recording
*   Tap the **Mic** button on the Home Screen.
*   Record your voice note.
*   Tap **Stop**. The app will automatically Queue -> Convert -> Process.

### 2. Sharing (WhatsApp/Telegram)
*   Select an audio file in any app.
*   Choose **Share** -> **Voice Note Summarizer**.
*   The file is added to the **Queue** instantly. You can queue multiple files back-to-back without waiting.

### 3. Customizing Prompts
*   Go to **Settings** (Gear Icon).
*   **Transcription System:** Control how the AI hears (e.g., "ROMANIZE HINDI").
*   **Transcription Prompt:** Control verbatim vs clean-up.
*   **Summarization System:** Control the output format (Bullet points, paragraphs).
*   **Presets:** Save your favorite configurations for quick switching.

---

## 🔧 Troubleshooting

*   **App Crash on First Run:** The app needs time on the *very first launch* to copy the bundled 2.58GB model into internal storage. Do not kill the app.
*   **Processing Stuck:** Force close the app. The queue system handles "Orphaned Locks" and will mark stuck items as "Failed" on next launch so you can retry.
*   **"TF_LITE_ERROR":** Ensure `android/app/src/main/assets/gemma-4-E2B-it.litertlm` is the bundled model, LiteRT-LM is at `0.11.0+`, and run on a device with GPU/NPU support.

---

## 📄 License
Apache 2.0 License.
Built with ❤️ using Flutter & Google Gemma.
