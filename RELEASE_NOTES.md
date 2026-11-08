# Release Notes - v0.4.0-beta

Welcome to the **MacVolumeMixer v0.4.0-beta** release! 🎚️

This release brings complete Apple-grade UI alignment, hardware-accelerated DSP audio processing with Apple Accelerate (`vDSP`), eliminated memory/CPU overhead, and native animated popovers.

---

### ✨ What's New in v0.4.0-beta

- **Apple Control Center & SoundSource Native UI**:
  - Pixel-perfect vertical column alignment across System Audio and all individual application rows.
  - Custom AppKit audio slider with unity gain tick notch at 100%, magnet snap, double-click reset, and trackpad scroll wheel support.
  - Dual-zone color tracks: Apple Accent Blue for normal range (0%–100%) and warm golden amber for boosted volume (101%–200%).
  - Monospaced percentage readouts preventing horizontal layout jitter while adjusting volume.

- **Hardware-Accelerated SIMD DSP Engine (`vDSP`)**:
  - Replaced scalar DSP sample loops with Apple Accelerate framework's vectorized `vDSP_vsmul` and hardware-clamped `vDSP_vclip`.
  - Ultra-low latency PCM attenuation and amplification with 0.0% idle CPU and ~17MB RAM footprint.

- **Refined Hover & Popover Interaction**:
  - Removed intrusive floating text tooltip bubbles in favor of subtle, responsive glass hover luminance changes.
  - Clean animated popover menus for output device selection per app and system settings.
  - Pure native app icon rendering eliminating artificial border blips and flash artifacts.

- **Designated Requirement Code Signing**:
  - Bundled with a permanent designated requirement (`com.macvolumemixer.app`) preventing macOS from resetting Screen & System Audio Recording permissions on app updates.

---

### 📦 Artifacts & Checksums

| File | Size | SHA-256 Checksum |
| :--- | :--- | :--- |
| `MacVolumeMixer-v0.4.0-beta.dmg` | ~963 KB | `d2ee4b6abcc6cc1c8fc306b5a6d7e0278f55dd73b39c393c85869f9979e4921f` |
| `MacVolumeMixer-v0.4.0-beta.zip` | ~955 KB | `93f9491a8b7d3b0787ccd19896ba7c177202a6a815b0fd67283a24ecd68e2073` |

---

### 📥 Installation

#### Via Apple Disk Image (`.dmg`):
1. Download and open `MacVolumeMixer-v0.4.0-beta.dmg`.
2. Drag `MacVolumeMixer.app` into the `Applications` folder shortcut.
3. Open `MacVolumeMixer.app` and grant audio permissions in **System Settings > Privacy & Security > Screen & System Audio Recording** when prompted.

#### Via Zip Archive:
1. Download `MacVolumeMixer-v0.4.0-beta.zip`.
2. Extract the archive and drag `MacVolumeMixer.app` into `/Applications`.

