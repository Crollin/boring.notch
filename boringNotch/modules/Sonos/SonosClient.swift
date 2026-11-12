//
//  SonosClient.swift
//  boringNotch
//
//  SOAP UPnP local (http://<ip>:1400). Aucun compte, aucun cloud.
//

import Foundation

struct SonosError: Error { let message: String }

struct SonosClient {
    private enum Service {
        case avTransport, rendering, groupRendering, topology
        var name: String {
            switch self {
            case .avTransport: "AVTransport"
            case .rendering: "RenderingControl"
            case .groupRendering: "GroupRenderingControl"
            case .topology: "ZoneGroupTopology"
            }
        }
        var path: String {
            switch self {
            case .avTransport: "MediaRenderer/AVTransport/Control"
            case .rendering: "MediaRenderer/RenderingControl/Control"
            case .groupRendering: "MediaRenderer/GroupRenderingControl/Control"
            case .topology: "ZoneGroupTopology/Control"
            }
        }
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 2
        c.timeoutIntervalForResource = 4
        return URLSession(configuration: c)
    }()

    @discardableResult
    private func call(_ host: String, _ service: Service, _ action: String, _ args: [(String, String)] = [("InstanceID", "0")]) async throws -> String {
        guard let url = URL(string: "http://\(host):1400/\(service.path)") else { throw SonosError(message: "bad host") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        req.setValue("\"urn:schemas-upnp-org:service:\(service.name):1#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        req.httpBody = Data(SonosSOAP.envelope(service: service.name, action: action, args: args).utf8)
        let (data, resp) = try await Self.session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw SonosError(message: "\(action) HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return String(decoding: data, as: UTF8.self)
    }

    func topology(host: String) async throws -> (rooms: [SonosRoom], groups: [SonosGroup]) {
        SonosParse.topology(try await call(host, .topology, "GetZoneGroupState", []))
    }

    func transportState(host: String) async throws -> String {
        SonosParse.value("CurrentTransportState", in: try await call(host, .avTransport, "GetTransportInfo")) ?? ""
    }

    func currentTrack(host: String) async throws -> SonosTrack? {
        let r = try await call(host, .avTransport, "GetPositionInfo")
        return SonosParse.value("TrackMetaData", in: r).flatMap(SonosParse.track(fromDIDL:))
    }

    func volume(host: String) async throws -> Int {
        let r = try await call(host, .rendering, "GetVolume", [("InstanceID", "0"), ("Channel", "Master")])
        return Int(SonosParse.value("CurrentVolume", in: r) ?? "") ?? 0
    }

    func setVolume(host: String, _ v: Int) async throws {
        try await call(host, .rendering, "SetVolume", [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", "\(clamp(v))")])
    }

    func groupVolume(coordinator host: String) async throws -> Int {
        Int(SonosParse.value("CurrentVolume", in: try await call(host, .groupRendering, "GetGroupVolume")) ?? "") ?? 0
    }

    func setGroupVolume(coordinator host: String, _ v: Int) async throws {
        try await call(host, .groupRendering, "SetGroupVolume", [("InstanceID", "0"), ("DesiredVolume", "\(clamp(v))")])
    }

    func groupMute(coordinator host: String) async throws -> Bool {
        SonosParse.value("CurrentMute", in: try await call(host, .groupRendering, "GetGroupMute")) == "1"
    }

    func setGroupMute(coordinator host: String, _ m: Bool) async throws {
        try await call(host, .groupRendering, "SetGroupMute", [("InstanceID", "0"), ("DesiredMute", m ? "1" : "0")])
    }

    /// La pièce `host` rejoint le groupe du coordinateur.
    func join(host: String, coordinatorID: String) async throws {
        try await call(host, .avTransport, "SetAVTransportURI",
                       [("InstanceID", "0"), ("CurrentURI", "x-rincon:\(coordinatorID)"), ("CurrentURIMetaData", "")])
    }

    /// La pièce `host` quitte son groupe.
    func leave(host: String) async throws {
        try await call(host, .avTransport, "BecomeCoordinatorOfStandaloneGroup")
    }

    /// Transfère la lecture du groupe à `newID` (l'ancien coordinateur reste membre).
    func delegate(coordinator host: String, to newID: String) async throws {
        try await call(host, .avTransport, "DelegateGroupCoordinationTo",
                       [("InstanceID", "0"), ("NewCoordinator", newID), ("RejoinGroup", "1")])
    }

    private func clamp(_ v: Int) -> Int { min(100, max(0, v)) }
}
