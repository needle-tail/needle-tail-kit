//
//  File.swift
//  
//
//  Created by Cole M on 9/19/21.
//

import Foundation

public protocol IRCServicePasswordProvider {
    func passwordForAccount(_ account: IRCAccount, yield: @escaping ( IRCAccount, String ) -> Void)
}
