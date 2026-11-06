//
//  Microphones.swift
//  boringNotch
//
//  Choix du micro de la dictée, sans toucher au micro par défaut du système (musique et appels restent sur le casque).
//  Un micro Bluetooth force le casque en mode « appel » (16 kHz, bascule d'une demi-seconde) : on l'évite par défaut.
//

import AVFoundation
import CoreAudio

struct MicDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let bluetooth: Bool
    let builtIn: Bool
}

enum Microphones {
    /// Tous les périphériques qui ont au moins une entrée.
    static func all() -> [MicDevice] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap(device)
    }

    /// Micro par défaut du système.
    static func systemDefault() -> MicDevice? {
        get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, AudioDeviceID(0)).flatMap(device)
    }

    /// Micro à forcer pour ce réglage ; nil = laisser le système décider.
    /// - "auto" : micro intégré si le système a choisi un micro Bluetooth (casque, écouteurs), sinon le micro du système (Jabra USB…).
    /// - "system" : toujours le micro du système.
    /// - sinon : l'UID d'un micro précis (absent = micro du système).
    static func resolve(_ choice: String) -> MicDevice? {
        switch choice {
        case "system": return nil
        case "auto":
            guard systemDefault()?.bluetooth == true else { return nil }
            return all().first { $0.builtIn } // pas de micro intégré (Mac mini) : on garde le système
        default: return all().first { $0.uid == choice }
        }
    }

    /// Micro réellement utilisé pour ce réglage (affichage).
    static func effective(_ choice: String) -> MicDevice? { resolve(choice) ?? systemDefault() }

    // MARK: CoreAudio

    private static func device(_ id: AudioDeviceID) -> MicDevice? {
        guard id != 0, hasInput(id),
              let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName)
        else { return nil }
        let transport = get(id, kAudioDevicePropertyTransportType, UInt32(0))
        return MicDevice(id: id, uid: uid, name: name,
                         bluetooth: transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
                         builtIn: transport == kAudioDeviceTransportTypeBuiltIn)
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return false }
        return UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self)).contains { $0.mNumberChannels > 0 }
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        get(id, selector, nil as Unmanaged<CFString>?).flatMap { $0 }?.takeRetainedValue() as String?
    }

    private static func get<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }
}
