# MacVolumeMixer 🎚️

[![Release](https://img.shields.io/badge/release-v0.4.0--beta-blue.svg)](https://github.com/davindalana/Mac-Volume-Mixer/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014.2%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A high-performance, native macOS Volume Mixer inspired by Apple Control Center and SoundSource. Built with **SwiftUI**, **CoreAudio Process Audio Tap** (`CATapDescription`), and hardware-accelerated **Apple Accelerate SIMD DSP (`vDSP`)** for macOS Sonoma (14.2+) and macOS Sequoia (15.0+).

MacVolumeMixer runs quietly in the macOS Menu Bar (`MenuBarExtra`) providing real-time per-app volume management, hardware mute toggling, output device routing, and seamless volume boost up to 200%.

---

## 📸 Overview & Design Highlights

- **Native Liquid Glass UI**: Modern macOS Sonoma & Sequoia frosted glass styling (`ultraThinMaterial`) with pixel-perfect column alignment.
- **Hardware-Accelerated DSP**: Uses Apple's Accelerate framework (`vDSP`) for vectorized PCM volume attenuation and amplification without CPU latency.
- **Clean Hover Feedback**: Pure Apple-style button transitions without intrusive floating tooltip bubbles.
- **Ultra-low Resource Footprint**: Idle CPU usage is ~0.0% and memory footprint is ~17MB with event-driven lifecycle observation.

---

## ✨ Key Features

- **Per-Application Volume**: Control audio output volume per process independently from 0% to 200%.
- **Unity Gain & Boost Zones**: Standard 0%–100% audio range with Apple Accent Blue, and smooth warm gold/amber boost range above 100%.
- **Audio Output Routing**: Route individual app audio to specific output devices (Internal Speakers, Headphones, AirPods, External Monitors) via native animated popovers.
- **Custom Hardware Slider**: Custom-built AppKit slider featuring double-click reset to 100%, magnet snap at unity gain, and trackpad scroll wheel support.
- **Pinned Applications**: Pin favorite apps (Finder, Music, Safari, WhatsApp, Spotify, etc.) or add any running app or disk binary with one click.
- **Designated Requirement Code Signing**: Packaged with a permanent Designated Requirement signature so Screen & Audio Recording permissions remain intact across restarts and updates.

---

## 📦 Installation & Download

### Option 1: Apple Disk Image (.dmg) (Recommended)
1. Download the latest `MacVolumeMixer-v0.4.0-beta.dmg` from the [GitHub Releases](https://github.com/davindalana/Mac-Volume-Mixer/releases) page.
2. Double-click the `.dmg` file to mount it.
3. Drag and drop **MacVolumeMixer** into the **Applications** folder shortcut.
4. Launch **MacVolumeMixer** from Applications or Spotlight.

### Option 2: Zip Archive
1. Download `MacVolumeMixer-v0.4.0-beta.zip` from [GitHub Releases](https://github.com/davindalana/Mac-Volume-Mixer/releases).
2. Extract the archive and move `MacVolumeMixer.app` to `/Applications`.

### Option 3: Build from Source
Ensure you have Xcode 15.2+ and Swift 5.9+ installed:
```bash
git clone https://github.com/davindalana/Mac-Volume-Mixer.git
cd Mac-Volume-Mixer
./bundle_app.sh
```
This automatically compiles the optimized release binary, packages the bundle, signs it with the permanent designated requirement, and installs it into `/Applications/MacVolumeMixer.app`.

---

## 🔒 Permissions & Security

On macOS 14.2+, intercepting audio output streams of third-party processes requires macOS Audio Recording authorization:
1. When launched, grant permissions under **System Settings > Privacy & Security > Screen & System Audio Recording**.
2. If prompted, restart the app or click **Restart** inside the app's permission banner.

---

## 📁 Architecture

```
MacVolumeMixer/
├── App/
│   ├── MacVolumeMixerApp.swift        # App entry point (MenuBarExtra .window)
│   ├── AppIcon.icns                   # macOS Retina application icon
│   ├── Info.plist                     # LSUIElement = true (Menu Bar only agent)
│   └── designated_requirement.txt     # Permanent code signing requirement
├── Models/
│   ├── AudioProcess.swift             # Process model (PID, bundleID, icon, volume, outputDeviceUID)
│   └── AudioDevice.swift              # Output device model (AirPods, Speakers, HDMI, etc.)
├── ViewModels/
│   └── MixerViewModel.swift           # Observable state, UI binding, debounced persistence
├── Services/
│   ├── AudioEngine/
│   │   ├── AudioEngineProtocol.swift  # Audio driver / tap interface contract
│   │   ├── CoreAudioTapService.swift  # CoreAudio Process Tap (macOS 14.2+) implementation
│   │   ├── RealtimeMixerEngine.swift  # Hardware-accelerated SIMD (vDSP) DSP mixer engine
│   │   └── ProcessWatcher.swift       # Lifecycle watcher via NSWorkspace & metadata cache
│   └── SystemPermissions.swift        # Audio Capture permissions manager
└── Views/
    ├── MenuBar/
    │   ├── PopoverView.swift          # Main menu bar popover container & system volume row
    │   └── AppVolumeRowView.swift     # Individual application volume slider & device picker row
    └── Components/
        ├── CustomSlider.swift         # Modern macOS custom slider with tick marks & snap
        ├── AppIconView.swift          # Clean native app icon viewer
        ├── MixerPopovers.swift        # Native device picker & settings popovers
        └── ViewExtensions.swift       # Pointing hand cursor modifiers
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
