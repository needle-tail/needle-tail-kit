//
//  File.swift
//  
//
//  Created by Cole M on 9/23/22.
//

import Foundation

extension IRCCommandCode {
  
  public var errorMessage: String {
    return errorMap[self] ??  "Unmapped error code \(self.rawValue)"
  }
}

fileprivate let errorMap : [ IRCCommandCode : String ] = [
  .errorUnknownCommand:    "No such command.",
  .errorNoSuchServer:      "No such server.",
  .errorNicknameInUse:     "Nickname is already in use.",
  .errorNoSuchNick:        "No such nick.",
  .errorAlreadyRegistered: "You may not reregister.",
  .errorNotRegistered:     "You have not registered",
  .errorUsersDontMatch:    "Users don't match",
  .errorNoSuchChannel:     "No such channel"
]
