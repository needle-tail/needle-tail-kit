//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-nio-irc open source project
//
// Copyright (c) 2018-2021 ZeeZide GmbH. and the swift-nio-irc project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIOIRC project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NeedleTailHelpers

/**
 * An IRC server name.
 *
 * Maximum length is 63 characters.
 */
public struct IRCServerName: Hashable {
  
  public typealias StringLiteralType = String
  
  let storage    : String
  let normalized : String
  
  public init?(_ s: String) {
      guard NeedleTailNick.validateName(
        s, nameRules: NeedleTailNick.NameRules()
      ) == .isValidated else {
      return nil
    }
    storage    = s
    normalized = s.ircLowercased()
  }
  
  public var stringValue : String { return storage }
  
  public func hash(into hasher: inout Hasher) { normalized.hash(into: &hasher) }
  
  public static func ==(lhs: IRCServerName, rhs: IRCServerName) -> Bool {
    return lhs.normalized == rhs.normalized
  }
  
  public static func validate(string: String) -> Bool {
    guard string.count > 1 && string.count <= 63 else {
      return false
    }
    
    // TODO: RFC 2812 2.3.1
    
    return true
  }  
}
