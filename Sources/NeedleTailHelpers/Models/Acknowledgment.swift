//
//  Acknowledgment.swift
//
//
//  Created by Cole M on 3/23/22.
//

public struct Acknowledgment: Codable, Sendable {
    
    public enum AckType: Codable, Equatable, Sendable {
        case registered(String)
        case isOnline(String)
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
        case multipartUploadComplete(MultipartUploadAckPacket)
        case multipartDownloadFailed(String, String)
    }

    public var acknowledgment: AckType
    
    public init(
        acknowledgment: AckType
    ) {
        self.acknowledgment = acknowledgment
    }
}

public struct MultipartUploadAckPacket: Sendable, Codable, Equatable {
    public var name: String
    public var mediaId: String
    public var size: Int
    
    public init(
        name: String,
        mediaId: String,
        size: Int
    ) {
        self.name = name
        self.mediaId = mediaId
        self.size = size
    }
}
