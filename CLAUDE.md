# CardSnap — Claude Context

## What this is
iOS business card scanner app. Camera detects card quality (red/yellow/green), auto-captures at green, sends to Gemini API for structured extraction, stores in batches by day.

## Current Progress
- All Swift source files written ✓
- Xcode project generated via xcodegen ✓
- App icon set (black bg, white card, red laser line) ✓
- Deployed to DanPhone (iPhone 16 Pro) via Xcode ✓

## Key Files
- `CardSnap/Services/GeminiService.swift` — API key + model config
- `CardSnap/Services/CardDetector.swift` — quality scoring thresholds
- `CardSnap/ViewModels/ScannerViewModel.swift` — core scan logic
- `project.yml` — rebuild xcodeproj with `xcodegen generate`

## Next Steps
- Tune quality thresholds in CardDetector if auto-capture is too slow/fast
- Consider adding gemini-2.5-flash-image model upgrade
- Add sales-crm import integration
- App Store distribution
