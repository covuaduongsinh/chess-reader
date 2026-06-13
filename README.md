# Chess Reader

An **offline, cross‑platform interactive chess book reader** built with Flutter.
Open your own PDF/EPUB chess books, click any move in the text to follow it on a
board, analyse positions with an embedded Stockfish engine, and let a **local
vision model read printed diagrams into positions** — all with no internet
connection or server.

The Flutter app lives in [`chess_reader/`](chess_reader/).

## Features

- **Clickable moves** — tap a move in the book and the side board jumps to that
  position; step through lines and explore your own variations, then snap back
  to the book.
- **Two reading views for PDF** — the original printed pages, or a reflowed HTML
  reading view (easier on small screens). Choose at open, switch anytime; EPUB
  is always HTML.
- **Automatic diagram recognition** — every printed diagram in the book is
  detected on open, shown with its detected FEN, and **tap to load it onto the
  board**. Results are cached to disk so reopening is instant.
- **Embedded Stockfish** — analyse any position fully offline (bundled engine on
  desktop, FFI on mobile).
- **Library & export** — a home library of recent and already‑converted books,
  plus export of a converted book to standalone HTML.
- **Open in Lichess / Chess.com** — send the current position to the web for
  further analysis (optional; the app itself stays offline).
- **Comfort** — resume where you left off, bookmarks, full‑text search
  (figurine‑aware), table of contents, adaptive layout, a resizable board, and
  configurable piece set / board theme / engine depth.

## How it works

| Concern | Approach |
|---|---|
| Board & chess logic | `chessground` + `dartchess` (lichess) |
| PDF | `pdfrx` (PDFium) — text rects for tap targets, page rasters for vision |
| EPUB | zip + XHTML parsed directly, rendered via `flutter_html` |
| Engine | bundled Stockfish over UCI (desktop) / `multistockfish` FFI (mobile) |
| Vision | classical CV board locator + a small per‑square CNN exported to ONNX, run with `flutter_onnxruntime` |
| State | `flutter_riverpod` |

The vision model is a ~150k‑parameter CNN classifying each of the 64 squares
(13 classes), trained on synthetic book‑style diagrams. See
[`chess_reader/docs/`](chess_reader/docs/) for notes.

## Building

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install).

```bash
cd chess_reader
flutter pub get
flutter test          # 47 tests
flutter run -d windows # or macos / android / ios
```

Stockfish is not committed (it is large and GPL). Fetch it before a desktop
build:

```powershell
pwsh chess_reader/tool/fetch_stockfish.ps1
```

### Windows installer

```powershell
cd chess_reader
flutter build windows --release
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" windows\installer\chess_reader.iss
# → chess_reader/dist/chess_reader-setup-<version>.exe (per‑user, no admin needed)
```

## License

This program is free software, licensed under the **GNU General Public License
v3.0**. It bundles Stockfish and the lichess `chessground` / `dartchess`
libraries, which are themselves GPL/open source.

## Author

Made by **Vu‑Hung Quan**.
