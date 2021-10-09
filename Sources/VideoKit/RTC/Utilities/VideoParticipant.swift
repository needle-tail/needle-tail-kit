//
//  File.swift
//  
//
//  Created by Cole M on 10/9/21.
//

import Foundation

public final class VideoParticipant: Codable, Identifiable {
    
    public let id               : UUID
    public var name             : String
    public var videoSessions    : [ VideoSession ]
    
    
    init(
        id: UUID,
        name: String,
        videoSessions: [ VideoSession ]
    ) {
        self.id = id
        self.name = name
        self.videoSessions = videoSessions
    }
    
    
}
