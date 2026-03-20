# CardSnap

Automated business card scanner for iOS. Hold up a card, it auto-captures when clear, sends to Gemini for extraction, and exports as JSON/CSV.

## Features
- Real-time red/yellow/green outline shows capture quality
- Auto-captures — no shutter button needed
- Gemini AI extracts all contact fields + handwritten notes
- Duplicate detection
- "+" note button after each scan
- History browser with edit/delete/share per batch
- Exports JSON + CSV via iOS share sheet

## Tech
- SwiftUI + AVFoundation + Vision framework
- Gemini 2.0 Flash for OCR/extraction
- Local JSON persistence
