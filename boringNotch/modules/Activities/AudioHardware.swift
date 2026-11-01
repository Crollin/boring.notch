//
//  AudioHardware.swift
//  boringNotch
//
//  Lecture minimale des propriétés CoreAudio (périphériques, processus) pour les activités.
//

import CoreAudio
import Foundation

enum AudioHardware {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func uint(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32 {
        var a = address(sel)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr ? v : 0
    }

    static func ids(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> [AudioObjectID] {
        var a = address(sel)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &ids) == noErr ? ids : []
    }

    static func string(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = address(sel)
        var v: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr, let v else { return nil }
        return v.takeRetainedValue() as String
    }

    static func hasStreams(_ dev: AudioObjectID, input: Bool) -> Bool {
        var a = address(kAudioDevicePropertyStreams, input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(dev, &a, 0, nil, &size) == noErr && size > 0
    }

    static var devices: [AudioObjectID] { ids(system, kAudioHardwarePropertyDevices) }

    /// Un micro est en cours de capture, par n'importe quelle app.
    static var micInUse: Bool {
        devices.contains { hasStreams($0, input: true) && uint($0, kAudioDevicePropertyDeviceIsRunningSomewhere) != 0 }
    }

    /// Apps (bundle id) qui capturent le micro. Vide si le système ne l'expose pas (sandbox, ancien macOS).
    static var micApps: [String] {
        ids(system, kAudioHardwarePropertyProcessObjectList)
            .filter { uint($0, kAudioProcessPropertyIsRunningInput) != 0 }
            .compactMap { string($0, kAudioProcessPropertyBundleID) }
    }

    static func isBluetooth(_ dev: AudioObjectID) -> Bool {
        let t = uint(dev, kAudioDevicePropertyTransportType)
        return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }

    static func setDefaultOutput(_ dev: AudioObjectID) {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        var d = dev
        AudioObjectSetPropertyData(system, &a, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &d)
    }
}
