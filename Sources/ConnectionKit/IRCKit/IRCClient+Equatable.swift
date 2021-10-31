//
//  File.swift
//  
//
//  Created by Cole M on 9/19/21.
//

import Foundation

extension IRCClient: Equatable {
    public static func == (lhs: IRCClient, rhs: IRCClient) -> Bool {
        return lhs === rhs
    }
}
