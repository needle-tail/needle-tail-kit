//
//  IRCCommand.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import Foundation



extension IRCCommand {
    
    var isErrorReply : Bool {
        guard case .numeric(let code, _) = self else { return false }
        return code.rawValue >= 400 // Hmmm
    }
    
    var signalsSuccessfulRegistration : Bool {
        switch self {
        case .MODE: return true // Freenode sends a MODE
        case .numeric(let code, _):
            switch code {
            case .replyWelcome, .replyYourHost, .replyMotD, .replyEndOfMotD:
                return true
            default:
                return false
            }
            
        default: return false
        }
    }
}


