//
//  Acknowledgment.swift
//
//
//  Created by Cole M on 3/23/22.
//

public struct Acknowledgment: Codable, Sendable {
    
    public enum AckType: Codable, Equatable, Sendable {
        case registered(String)
        case registryRequestRejected(String, String)
        case registryRequestAccepted(String, String)
        case newDevice(String)
        case readKeyBundle(String)
        case apn(String)
        case none
        case messageSent
        case blocked
        case unblocked
        case quited
        case publishedKeyBundle(String)
        case readReceipt
        case multipartReceived
        case multipartUploadComplete
    }

    public var acknowledgment: AckType
    
    public init(
        acknowledgment: AckType
    ) {
        self.acknowledgment = acknowledgment
    }
}
