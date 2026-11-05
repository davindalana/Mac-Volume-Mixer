# MacVolumeMixer 🎚️

A native, modular macOS Volume Mixer for macOS Sonoma (14.2+) and macOS Sequoia (15.0+), built with SwiftUI and MVVM architecture.

MacVolumeMixer lives in the macOS Menu Bar (`MenuBarExtra` with `.window` style) and allows per-application volume control, mute toggling, output device switching, and real-time audio process monitoring utilizing Apple's **CoreAudio Process Audio Tap** (`AudioHardwareCreateProcessTap` / `CATapDescription`).

---

## 📁 Architecture & File Structure

```
MacVolumeMixer/
├── App/
│   ├── MacVolumeMixerApp.swift        # Application entry point (MenuBarExtra .window)
│   ├── AppIcon.icns                   # Official macOS Retina application icon
│   └── Info.plist                     # LSUIElement = true (Menu Bar only agent)
├── Models/
│   ├── AudioProcess.swift             # Process model (PID, bundleID, icon, volume, outputDeviceUID)
│   └── AudioDevice.swift              # Output device model (Internal speakers, headphones, etc.)
├── ViewModels/
│   └── MixerViewModel.swift           # Observable state, UI binding, debounced persistence
├── Services/
│   ├── AudioEngine/
│   │   ├── AudioEngineProtocol.swift  # Audio driver / tap interface contract
│   │   ├── CoreAudioTapService.swift  # CoreAudio Process Tap (macOS 14.2+) implementation
│   │   ├── RealtimeMixerEngine.swift  # Real-time DSP mixer & audio device routing
│   │   └── ProcessWatcher.swift       # Lifecycle watcher via NSWorkspace & metadata cache
│   └── SystemPermissions.swift        # Screen & Audio Capture permissions checker
└── Views/
    ├── MenuBar/
    │   ├── PopoverView.swift          # Main menu bar popover container & system volume row
    │   └── AppVolumeRowView.swift     # Individual application volume slider & device picker row
    └── Components/
        ├── CustomSlider.swift         # Modern macOS custom slider with tick marks & snap
        └── AppIconView.swift          # App icon thumbnail with rounded border & indicator
```

---

## 🚀 Getting Started

### Prerequisites
- macOS 14.2 (Sonoma) or macOS 15.0+ (Sequoia)
- Xcode 15.2+ / Swift 5.9+

### Build from Command Line
```bash
cd MacVolumeMixer
swift build
```

### Run the App
```bash
swift run MacVolumeMixer
```

### Open in Xcode
You can open `Package.swift` directly in Xcode:
```bash
open Package.swift
```

---

## 🔒 Permissions & Privacy
Tapping audio streams of other processes on macOS 14.2+ requires system audio recording permissions.
If prompted, ensure access is granted in:
**System Settings > Privacy & Security > Screen & System Audio Recording**.

---

## ✨ Features
- **Pure Menu Bar App**: Runs quietly in the status bar without cluttering the Dock (`LSUIElement = true`).
- **Real-time Per-App Volume & Mute**: Fine-grained sliders from 0% to 100% with live percentage feedback.
- **Debounced Updates**: 50ms debounce prevents flooding the CoreAudio C-API during continuous slider drags.
- **Hardware Integration**: Automatically detects default output devices (MacBook Speakers, AirPods, External Monitors) and syncs system master volume changes bi-directionally.
- **Safe Fallback**: Includes preview mocks so the interface renders seamlessly in Xcode Previews and test environments without crashing.
