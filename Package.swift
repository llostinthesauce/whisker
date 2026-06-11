// swift-tools-version: 6.0

import PackageDescription
import Foundation

// The test suite (Tests/) is kept out of the public repository. This package
// exists only to validate library-extracted sources, so when Tests/ is absent
// (a public clone) we omit the test targets and the package still resolves and
// builds. Locally, with Tests/ present, `swift test` runs the full suite.
var targets: [Target] = [
    .target(
        name: "WhiskerCleanup",
        path: "Whisker/Features/Cleanup"
    ),
    .target(
        name: "WhiskerModels",
        dependencies: ["WhiskerCleanup"],
        path: "Whisker/Shared/Models",
        sources: [
            "DictationResult.swift",
            "Transcript.swift"
        ]
    ),
    .target(
        name: "WhiskerTranscriptionCore",
        path: "Whisker/Features/Transcription",
        exclude: [
            "TranscriptionViewModel.swift"
        ],
        sources: [
            "TranscriptionEngine.swift"
        ]
    ),
    .target(
        name: "WhiskerProcessing",
        dependencies: [
            "WhiskerCleanup",
            "WhiskerModels",
            "WhiskerTranscriptionCore"
        ],
        path: "Whisker/Features/Processing",
        sources: [
            "DictationProcessor.swift"
        ]
    ),
    .target(
        name: "WhiskerRemote",
        dependencies: [
            "WhiskerCleanup",
            "WhiskerModels",
            "WhiskerProcessing",
            "WhiskerTranscriptionCore"
        ],
        path: "Whisker/Features/Remote",
        sources: [
            "RemoteMacClient.swift",
            "RemoteMacModels.swift",
            "RemoteMacProcessor.swift",
            "RemoteMacSettings.swift",
            "SegmentBoundaryDetector.swift",
            "StreamingDictationSession.swift"
        ]
    ),
    .target(
        name: "WhiskerRecorder",
        dependencies: ["WhiskerRemote"],
        path: "Whisker/Features/Recorder",
        exclude: [
            "AudioRecorder.swift",
            "RecorderView.swift",
            "RecordingLimits.swift",
            "RecordingSession.swift"
        ],
        sources: [
            "RecordingSegmenter.swift"
        ]
    ),
    .target(
        name: "WhiskerHandoff",
        path: "Whisker/Shared/Handoff",
        exclude: [
            "HandoffCommand.swift",
            "HandoffService.swift"
        ],
        sources: [
            "HandoffConstants.swift",
            "HandoffLaunchAction.swift",
            "HandoffResult.swift",
            "HandoffSignal.swift",
            "KeyboardLiveTranscriptInserter.swift",
            "KeyboardTranscriptRecovery.swift",
            "KeyboardSessionDefaults.swift"
        ]
    )
]

if FileManager.default.fileExists(atPath: "Tests") {
    targets += [
        .testTarget(
            name: "WhiskerCleanupTests",
            dependencies: ["WhiskerCleanup"],
            path: "Tests",
            exclude: [
                "Handoff",
                "Remote",
                "Recorder"
            ],
            sources: [
                "RuleBasedCleanerTests.swift"
            ]
        ),
        .testTarget(
            name: "WhiskerRemoteTests",
            dependencies: [
                "WhiskerCleanup",
                "WhiskerModels",
                "WhiskerRemote",
                "WhiskerTranscriptionCore"
            ],
            path: "Tests/Remote"
        ),
        .testTarget(
            name: "WhiskerRecorderTests",
            dependencies: ["WhiskerRecorder"],
            path: "Tests/Recorder"
        ),
        .testTarget(
            name: "WhiskerHandoffTests",
            dependencies: ["WhiskerHandoff"],
            path: "Tests/Handoff"
        )
    ]
}

let package = Package(
    name: "WhiskerValidation",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "WhiskerCleanup", targets: ["WhiskerCleanup"]),
        .library(name: "WhiskerModels", targets: ["WhiskerModels"]),
        .library(name: "WhiskerTranscriptionCore", targets: ["WhiskerTranscriptionCore"]),
        .library(name: "WhiskerProcessing", targets: ["WhiskerProcessing"]),
        .library(name: "WhiskerRemote", targets: ["WhiskerRemote"]),
        .library(name: "WhiskerRecorder", targets: ["WhiskerRecorder"]),
        .library(name: "WhiskerHandoff", targets: ["WhiskerHandoff"])
    ],
    targets: targets
)
