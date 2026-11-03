//
//  BluetoothBattery.swift
//  boringNotch
//
//  Batterie des accessoires Bluetooth (clavier, souris…) via le service Batterie BLE (0x180F) :
//  relevé au lancement puis toutes les 15 min, alerte dans la notch à 15 % puis à 5 %.
//  Les casques audio n'exposent en général pas ce service (macOS ne le lit pas non plus).
//

import CoreBluetooth
import Defaults
import Foundation

@MainActor
final class BluetoothBattery: NSObject {
    static let shared = BluetoothBattery()

    nonisolated(unsafe) private static let service = CBUUID(string: "180F")   // immuable après init
    nonisolated(unsafe) private static let level = CBUUID(string: "2A19")
    // ponytail: deux seuils fixes ; réglables le jour où 15/5 ne conviennent pas.
    private static let thresholds = [15, 5]

    private var central: CBCentralManager?
    private var reading: [CBPeripheral] = []       // retenus pendant la lecture
    private var alerted: [String: Int] = [:]         // dernier seuil signalé par appareil
    private var timer: Timer?

    /// Crée le gestionnaire Bluetooth (déclenche la demande d'autorisation la première fois).
    func start() {
        guard Defaults[.activityLowBattery], central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            Task { @MainActor in BluetoothBattery.shared.poll() }
        }
    }

    private func poll() {
        guard Defaults[.activityLowBattery] else { return }
        Task { for d in await OpenLogi.devices() where d.online && !d.charging { if let l = d.percentage { check(id: d.name, name: d.name, level: l) } } }
        guard let central, central.state == .poweredOn else { return }
        reading = central.retrieveConnectedPeripherals(withServices: [Self.service])
        for p in reading {
            p.delegate = self
            central.connect(p)   // le lien existe déjà (système) : ouvre seulement l'accès GATT pour l'app
        }
    }

    private func received(_ p: CBPeripheral, level: Int) {
        central?.cancelPeripheralConnection(p)
        reading.removeAll { $0 == p }
        check(id: p.identifier.uuidString, name: p.name ?? "Accessoire", level: level)
    }

    private func check(id: String, name: String, level: Int) {
        guard let threshold = Self.thresholds.last(where: { level <= $0 }) else {
            alerted[id] = nil   // rechargé : on pourra prévenir à nouveau
            return
        }
        if let last = alerted[id], last <= threshold { return }
        alerted[id] = threshold
        ActivityEvents.shared.showDevice(.init(name: name, kind: .lowBattery(level)))
    }
}

// Délégués appelés sur la file principale (queue: .main).
extension BluetoothBattery: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { if central.state == .poweredOn { poll() } }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.service])
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] where s.uuid == Self.service {
            peripheral.discoverCharacteristics([Self.level], for: s)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] where c.uuid == Self.level { peripheral.readValue(for: c) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let v = characteristic.value?.first else { return }
        MainActor.assumeIsolated { received(peripheral, level: Int(v)) }
    }
}
