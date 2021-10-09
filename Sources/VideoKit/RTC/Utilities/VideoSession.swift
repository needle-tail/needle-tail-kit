//
//  File.swift
//  
//
//  Created by Cole M on 10/9/21.
//

import Foundation


public final class VideoSession: Codable, Identifiable {
    
    public let id                : UUID
    public var host              : String
    public var port              : Int
    public var name              : String
    public var tls               : Bool
    public var videoParticipants : [ VideoParticipant ]
    
    
    init(
        id: UUID,
        host: String = "localhost",
        port: Int = 8081,
        name: String,
        tls: Bool = false,
        videoParticipants: [ VideoParticipant ]
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.name = name
        self.tls = tls
        self.videoParticipants = videoParticipants
    }
    
}
