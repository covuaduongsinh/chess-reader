# Architectural Specification: Multi-Platform AI-Vision & Interactive Chess Reader
## Target Systems: iOS, Android, Windows, macOS

This document details the universal production plan for a cross-platform application built with Flutter. The app synchronizes a physical chessboard with a digital chess book (PDF and EPUB) across mobile devices and desktop computers from a unified codebase.

---

## 1. System Architecture Overview

The system utilizes a decoupled architecture split into three data pipelines: Vision, Hardware, and Document Parsing. These feed into a core FEN synchronization engine managed by a reactive state manager.

```
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                  FLUTTER UNIFIED INTERFACE (ALL OS)                     │
 └─────────────────────────────────────────────────────────────────────────┘
          │                              │                                │
 ▼ (Camera Stream)             ▼ (Bluetooth/USB)                ▼ (File Input)
 ┌─────────────────┐           ┌─────────────────┐              ┌─────────────────┐
 │ VISION PIPELINE │           │  SMART BOARD    │              │ PARSING PIPELINE│
 ├─────────────────┤           ├─────────────────┤              ├─────────────────┤
 │ 1. OpenCV C++   │           │ 1. BLE / Serial │              │ 1. PDF / EPUB   │
 │ 2. Warp & Slice │           │ 2. DGT/Chessnut │              │    Extraction   │
 │ 3. TFLite/ONNX  │           │    Protocol     │              │ 2. Font Map/OCR │
 │    Inference    │           │    Decoding     │              │ 3. RegEx/PGN    │
 └─────────────────┘           └─────────────────┘              └─────────────────┘
          │                              │                                │
          ▼ (Vision FEN)                 ▼ (Hardware FEN)                 ▼ (Target FEN)
 ┌─────────────────────────────────────────────────────────────────────────┐
 │            CORE STATE SYNCHRONIZER (Riverpod / BLoC)                    │
 ├─────────────────────────────────────────────────────────────────────────┤
 │ * Validates Move Legality via `chess.dart`                              │
 │ * Handles Stream Concurrency & Error Correction                         │
 │ * Local Stockfish WASM/FFI Engine for Position Evaluation               │
 └─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Multi-Platform Technical Stack

| Layer | Technology / Package | Implementation Detail |
| :--- | :--- | :--- |
| **UI & State** | Flutter + Riverpod | Riverpod handles the complex asynchronous streams from cameras, Bluetooth, and heavy PDF parsing isolates. |
| **Vision Core** | `opencv_dart` (C++ FFI) | Pre-compiled FFI bindings to avoid compiling OpenCV from scratch for Windows/Mac/iOS/Android. |
| **Mobile AI** | `tflite_flutter` | Hardware-accelerated inference using CoreML (Apple) and NNAPI (Android). |
| **Desktop AI** | ONNX Runtime | TFLite can struggle with Windows DirectML. ONNX provides superior GPU acceleration for desktop. |
| **Document Engine**| `syncfusion_flutter_pdf` & EPUB | Supports standard PDFs, plus native EPUB parsing (which handles reflowable text and algebraic fonts much better). |
| **Analysis** | Stockfish (FFI) | Embedded Stockfish engine binary for real-time blunder checking. |

---

## 3. Deep Dive: Architectural Improvements

### Pipeline A: AI Vision & Hardware Integration
1. **The Figurine Font Problem:** Standard PDF text extractors fail when books use specialized chess fonts (e.g., printing ♞ instead of 'N'). 
   * *Solution:* Implement a custom unicode mapping dictionary for common chess fonts (Figurine, Chess Alpha).
2. **EPUB Support Integration:** Expanding to support `.epub` files heavily reduces parsing errors compared to PDFs, as EPUB relies on standard HTML/DOM structures that are trivial to search and manipulate.
3. **Electronic Smart Board Support:** Relying solely on optical camera vision introduces lighting and occlusion errors. Adding a Bluetooth Low Energy (BLE) listener to ingest moves directly from smart boards (like Chessnut or DGT) provides 100% accurate, zero-latency physical board synchronization.

### Pipeline B: Advanced Desktop Execution
1. **Asynchronous Isolates:** Extracting full text arrays from a 300-page PDF will freeze the Flutter UI thread. The parsing engine must be wrapped in Dart `Isolates` for true background processing.
2. **Dual-Model Inference:** Use TFLite for mobile builds to save space, but utilize ONNX on Windows/Mac builds to leverage discrete desktop GPUs without native compilation headaches.

---

## 4. Phased Development Roadmap

### Phase 1: Core Parsing & Engine Setup (Weeks 1-3)
* [ ] Build the EPUB and PDF document rendering interfaces.
* [ ] Create the RegEx tokenizers and map custom figurine fonts to standard SAN notation.
* [ ] Implement Riverpod state management and connect it to `chess.dart`.

### Phase 2: Vision & FFI Implementation (Weeks 4-6)
* [ ] Integrate `opencv_dart` for cross-platform board warping.
* [ ] Train the CNN piece classifier and export to both `.tflite` and `.onnx`.
* [ ] Set up the camera streams and connect them to the inference engines using Dart isolates.

### Phase 3: Hardware & Polish (Weeks 7-8)
* [ ] Implement the `flutter_blue_plus` package to capture live FEN strings from electronic chessboards.
* [ ] Embed Stockfish via FFI to provide real-time evaluation of the physical board.
* [ ] Finalize UI/UX for automated page flipping and error highlighting.
