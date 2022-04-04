//
//  File.swift
//  
//
//  Created by Cole M on 10/9/21.
//

import Foundation

var DefaultPort = 9888

public final class CKAccount: Codable, Identifiable {
    
    public let id               : UUID
    public var host             : String
    public var port             : Int
    public var nickname         : String
    public var videoSessions    : [ String ]?
    public var tls              : Bool
    
    public var joinedSession : [ String ]? {
        return videoSessions
    }
    
    init(
        id: UUID = UUID(),
        host: String,
        port: Int = DefaultPort,
        nickname: String,
        videoSessions: [ String ]? = nil,
        tls: Bool = false
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.nickname = nickname
        self.videoSessions = videoSessions
        self.tls = tls
    }
    
    
    enum CodingKeys: CodingKey {
        case id, host, port, nickname, videoSessions, tls
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id       = try container.decode(UUID.self,   forKey: .id)
        self.host     = try container.decode(String.self, forKey: .host)
        self.port     = try container.decode(Int.self,    forKey: .port)
        self.nickname = try container.decode(String.self, forKey: .nickname)
        self.videoSessions = try container.decode([String].self, forKey: .videoSessions)
        self.tls      = try container.decode(Bool.self, forKey: .tls)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id,               forKey: .id)
        try container.encode(host,             forKey: .host)
        try container.encode(port,             forKey: .port)
        try container.encode(nickname,         forKey: .nickname)
        try container.encode(videoSessions, forKey: .videoSessions)
        try container.encode(tls, forKey: .tls)
    }
}

extension CKAccount: CustomStringConvertible {
    public var description: String {
        var ms = "<Account: \(id) \(host):\(port) \(nickname) \(tls)"
        //      ms += " " + videoSessions.joined(separator: ",")
        ms += ">"
        return ms
    }
}
