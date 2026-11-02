//
//  AppAudioTap.swift
//  boringNotch
//
//  Volume d'une app : un tap Core Audio coupe son son d'origine, un device agrégé
//  (sortie actuelle + tap) le rejoue avec le gain choisi. Pas de tap = volume natif (100 %).
//

import AudioToolbox
import CoreAudio
import Foundation

@available(macOS 14.2, *)
final class AppAudioTap {
    let processes: [AudioObjectID]
    private let gain = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    /// Lu par le thread audio sans verrou : un Float, course bénigne.
    var volume: Float {
        get { gain.pointee }
        set { gain.pointee = newValue }
    }

    init?(processes: [AudioObjectID], outputUID: String, volume: Float) {
        self.processes = processes
        gain.initialize(to: volume)

        let desc = CATapDescription(stereoMixdownOfProcesses: processes)
        desc.uuid = UUID()
        desc.muteBehavior = .mutedWhenTapped
        desc.isPrivate = true
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { stop(); return nil }

        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Boring Notch volume",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        guard AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregateID) == noErr else { stop(); return nil }

        let gain = self.gain
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
            Self.render(UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)),
                        into: UnsafeMutableAudioBufferListPointer(output), gain: gain.pointee)
        }
        guard status == noErr, AudioDeviceStart(aggregateID, procID) == noErr else { stop(); return nil }
    }

    deinit {
        stop()
        gain.deallocate()
    }

    private func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    /// Thread temps réel : pas d'allocation. Le tap est le dernier tampon d'entrée
    /// (après les éventuelles entrées du device de sortie) ; il est réparti sur les
    /// deux premiers canaux de sortie, entrelacés ou non, le reste à zéro.
    static func render(_ input: UnsafeMutableAudioBufferListPointer, into output: UnsafeMutableAudioBufferListPointer, gain: Float) {
        let src = input.count > 0 ? input[input.count - 1] : AudioBuffer()
        let srcCh = max(Int(src.mNumberChannels), 1)
        let srcFrames = Int(src.mDataByteSize) / 4 / srcCh
        let srcData = src.mData?.assumingMemoryBound(to: Float.self)

        var channelOffset = 0
        for buf in output {
            guard let data = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let ch = max(Int(buf.mNumberChannels), 1)
            let frames = Int(buf.mDataByteSize) / 4 / ch
            for f in 0..<frames {
                for k in 0..<ch {
                    let global = channelOffset + k
                    var v: Float = 0
                    if let srcData, f < srcFrames, global < 2 { v = srcData[f * srcCh + min(global, srcCh - 1)] * gain }
                    data[f * ch + k] = v
                }
            }
            channelOffset += ch
        }
    }
}
