import Testing
import Foundation
@testable import LiftoffCore

/// The config.json of a real install from before the 12-step layout (nine steps, learned devices).
let nineStepConfigFixture = #"""
{
  "displayMode" : "fullscreen",
  "duckLevel" : 0.35,
  "elevenLabsVoiceID" : "cgSgspJ2msm6clMCkdW9",
  "illustrationVariants" : {
    "dac" : 2
  },
  "learned" : {
    "cables" : [
      {
        "kind" : "display",
        "name" : "LG ULTRAFINE",
        "productID" : 23741,
        "vendorID" : 7789
      }
    ],
    "dac" : [
      {
        "kind" : "audioOutput",
        "name" : "FiiO K7 "
      }
    ],
    "dock" : [
      {
        "kind" : "usb",
        "name" : "USB 2.0 BILLBOARD",
        "productID" : 259,
        "vendorID" : 8457
      },
      {
        "kind" : "usb",
        "name" : "USB 10_100_1000 LAN",
        "productID" : 33107,
        "vendorID" : 3034
      },
      {
        "kind" : "usb",
        "name" : "USB2.0 HUB",
        "productID" : 29280,
        "vendorID" : 8523
      },
      {
        "kind" : "usb",
        "name" : "USB2.1 Hub",
        "productID" : 1552,
        "vendorID" : 1507
      },
      {
        "kind" : "usb",
        "name" : "USB3.1 Hub",
        "productID" : 1574,
        "vendorID" : 1507
      },
      {
        "kind" : "usb",
        "name" : "USB3.2 Hub",
        "productID" : 1573,
        "vendorID" : 1507
      }
    ]
  },
  "musicEnabled" : true,
  "musicVolume" : 0.6,
  "steps" : [
    {
      "gradient" : [
        "#0f5c55",
        "#0a2f3a"
      ],
      "id" : "cables",
      "instruction" : "Make sure the monitor and power cables are plugged in.",
      "rule" : {
        "devices" : {
          "_0" : "display"
        }
      },
      "symbol" : "cable.connector",
      "title" : "Check the cables"
    },
    {
      "gradient" : [
        "#5b6577",
        "#232a38"
      ],
      "id" : "dock",
      "instruction" : "Plug the USB dock into the Mac.",
      "rule" : {
        "devices" : {
          "_0" : "usb"
        }
      },
      "symbol" : "externaldrive.connected.to.line.below",
      "title" : "Connect the dock"
    },
    {
      "gradient" : [
        "#b3203a",
        "#4a0a22"
      ],
      "id" : "dac",
      "instruction" : "Turn the FiiO K7 on. I'll spot it automatically.",
      "rule" : {
        "devices" : {
          "_0" : "audioOutput",
          "hint" : "FiiO"
        }
      },
      "symbol" : "hifispeaker",
      "title" : "Power up the K7"
    },
    {
      "gradient" : [
        "#5c3bd6",
        "#1d1450"
      ],
      "id" : "agentFactory",
      "instruction" : "Launch Agent Factory.",
      "rule" : {
        "appRunning" : {
          "_0" : {
            "bundleIDs" : [
              "dev.agentfactory.desktop"
            ],
            "names" : [
              "Agent Factory"
            ]
          }
        }
      },
      "symbol" : "cpu",
      "title" : "Open Agent Factory"
    },
    {
      "gradient" : [
        "#2aa7d8",
        "#0b3c63"
      ],
      "id" : "water",
      "instruction" : "Fill your glass and tap Done.",
      "rule" : {
        "manual" : {

        }
      },
      "symbol" : "drop",
      "title" : "Pour some water"
    },
    {
      "gradient" : [
        "#3b3530",
        "#0e0c0b"
      ],
      "id" : "headphones",
      "instruction" : "Put your headphones on and tap Done.",
      "rule" : {
        "manual" : {

        }
      },
      "symbol" : "headphones",
      "title" : "Headphones on"
    },
    {
      "gradient" : [
        "#ff3b5c",
        "#7a0f3a"
      ],
      "id" : "music",
      "instruction" : "Press play in Apple Music.",
      "rule" : {
        "musicPlaying" : {

        }
      },
      "symbol" : "music.note",
      "title" : "Start the music"
    },
    {
      "gradient" : [
        "#5059c9",
        "#1f2259"
      ],
      "id" : "teams",
      "instruction" : "Bring Microsoft Teams to the front.",
      "rule" : {
        "appActivated" : {
          "_0" : {
            "bundleIDs" : [
              "com.microsoft.teams2"
            ],
            "names" : [
              "Microsoft Teams"
            ]
          }
        }
      },
      "symbol" : "person.2",
      "title" : "Open Teams"
    },
    {
      "gradient" : [
        "#ffb35c",
        "#d4466a",
        "#3a1a5c"
      ],
      "id" : "liftoff",
      "instruction" : "All systems go, Commander.",
      "rule" : {
        "final" : {

        }
      },
      "symbol" : "airplane.departure",
      "title" : "Liftoff"
    }
  ],
  "voiceEnabled" : true,
  "voiceRoomEffect" : true,
  "voiceVolume" : 1,
  "window" : {
    "endMinute" : 630,
    "startMinute" : 480,
    "weekdays" : [
      2,
      6,
      3,
      5,
      4
    ]
  }
}
"""#

@Suite struct ConfigMigrationTests {
    @Test func oldNineStepListIsReplacedKeepingEverythingElse() throws {
        let config = try JSONDecoder().decode(LiftoffConfig.self, from: Data(nineStepConfigFixture.utf8))
        #expect(config.steps == LiftoffConfig.default.steps)
        #expect(config.steps.count == 12)
        #expect(config.learned[.cables] == [DeviceSignature(kind: .display, name: "LG ULTRAFINE", vendorID: 7789, productID: 23741)])
        #expect(config.learned[.dac] == [DeviceSignature(kind: .audioOutput, name: "FiiO K7 ")])
        #expect(config.learned[.dock]?.count == 6)
        #expect(config.illustrationVariants == [.dac: 2])
        #expect(config.displayMode == .fullscreen)
        #expect(config.elevenLabsVoiceID == "cgSgspJ2msm6clMCkdW9")
        #expect(config.voiceRoomEffect)
        #expect(config.voiceVolume == 1)
        #expect(config.window == TriggerWindow())
    }

    @Test func storeLoadMigratesAndSaveWritesTheNewSteps() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("liftoff-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(nineStepConfigFixture.utf8).write(to: dir.appendingPathComponent("config.json"))
        let store = ConfigStore(directory: dir)
        let migrated = store.load()
        #expect(migrated.steps.map(\.id) == StepID.allCases)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json.bak").path))
        try store.save(migrated)
        #expect(store.load() == migrated)
    }

    @Test func handEditedStepsWithCurrentIdsAreKept() throws {
        var config = LiftoffConfig.default
        config.steps[0].title = "Hydrate"
        config.steps[4].rule = .devices(.hid, hint: "Keychron")
        let decoded = try JSONDecoder().decode(LiftoffConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.steps == config.steps)
    }

    @Test func reorderedOrPartialStepListsFallBackToDefaults() throws {
        var config = LiftoffConfig.default
        config.steps.swapAt(0, 1)
        var decoded = try JSONDecoder().decode(LiftoffConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.steps == LiftoffConfig.default.steps)
        config.steps = Array(LiftoffConfig.default.steps.dropFirst())
        decoded = try JSONDecoder().decode(LiftoffConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.steps == LiftoffConfig.default.steps)
    }
}
