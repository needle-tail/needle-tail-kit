//
//  NeedleTailMessage.swift
//  
//
//  Created by Cole M on 9/4/23.
//

import CypherMessaging

#if (os(macOS) || os(iOS))
public struct NeedleTailMessage: Equatable, Hashable, Identifiable {
    public var id = UUID()
    public var message: AnyChatMessage
    
    public init(id: UUID = UUID(), message: AnyChatMessage) {
        self.id = id
        self.message = message
    }
}
#endif
