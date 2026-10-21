// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacVolumeMixer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MacVolumeMixer",
            targets: ["MacVolumeMixer"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacVolumeMixer",
            path: ".",
            exclude: [
                "App/Info.plist",
                "README.md",
                "bundle_app.sh"
            ],
            sources: [
                "App/MacVolumeMixerApp.swift",
                "Models/AudioProcess.swift",
                "Models/AudioDevice.swift",
                "ViewModels/MixerViewModel.swift",
                "Services/AudioEngine/AudioEngineProtocol.swift",
                "Services/AudioEngine/CoreAudioTapService.swift",
                "Services/AudioEngine/ProcessWatcher.swift",
                "Services/SystemPermissions.swift",
                "Views/MenuBar/PopoverView.swift",
                "Views/MenuBar/AppVolumeRowView.swift",
                "Views/MenuBar/MasterVolumeView.swift",
                "Views/Components/CustomSlider.swift",
                "Views/Components/AppIconView.swift"
            ]
        )
    ]
)
