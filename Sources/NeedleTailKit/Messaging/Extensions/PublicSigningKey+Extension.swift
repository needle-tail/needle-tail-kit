//
//  PublicSigningKey+Extension.swift
//  
//
//  Created by Cole M on 9/2/23.
//
#if (os(macOS) || os(iOS))
import CypherMessaging
import MessagingHelpers

extension PublicSigningKey: Equatable {
    public static func == (lhs: CypherProtocol.PublicSigningKey, rhs: CypherProtocol.PublicSigningKey) -> Bool {
        return lhs.data == rhs.data
    }
}
#endif
