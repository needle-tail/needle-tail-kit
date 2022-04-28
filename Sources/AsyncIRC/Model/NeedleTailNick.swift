//
//  NeedleTailNick.swift
//
//
//  Created by Cole M on 4/26/22.
//

import Foundation
import CypherMessaging

public struct NeedleTailNick: Codable, Hashable, Equatable, CustomStringConvertible {
    public var description: String {
        return nick
    }
    public var stringValue: String {
        return nick
    }
    
    public var deviceId: DeviceId?
    public var nick: String

    
    public init(
        deviceId: DeviceId?,
        nick: String
    ) {
        self.deviceId = deviceId
        self.nick = nick
    }
    
    public init?(_ nick: String, nickRules: NickRules = NickRules()) {
        guard NeedleTailNick.validateNick(nick, nickRules: nickRules) == .isValidated else { return nil }
        self.nick = nick.ircLowercased()
    }
    
    
    public func hash(into hasher: inout Hasher) {
        nick.hash(into: &hasher)
    }
    
    public static func ==(lhs: NeedleTailNick, rhs: NeedleTailNick) -> Bool {
        return lhs.deviceId == lhs.deviceId
    }
    
    //We want to validate our Nick
    public enum ValidatedNickStatus {
        case isValidated, failedValidation
    }
    public struct NickRules {
        public var allowsStartingDigit: Bool = true
        public var lengthLimit: Int = 1024
        
        public init() {}
    }
    
    public static func validateNick(_ nick: String, nickRules: NickRules) -> ValidatedNickStatus {
        guard nick.count > 1, nick.count >= 9, nick.count <= 1024 else { return .failedValidation }
            
            var firstCharacterSet: CharacterSet
            if nickRules.allowsStartingDigit {
                firstCharacterSet = CharacterSets.letterDigitOrSpecial
            } else {
                firstCharacterSet = CharacterSets.letterOrSpecial
            }
            let rest = CharacterSets.letterDigitSpecialOrDash
            let scalars = nick.unicodeScalars
            guard firstCharacterSet.contains(scalars[scalars.startIndex]) else { return .failedValidation }
            for scalar in scalars.dropFirst() {
                guard rest.contains(scalar) else { return .failedValidation }
            }
        return .isValidated
    }
}


import struct Foundation.CharacterSet

fileprivate enum CharacterSets {
  static let letter                   = CharacterSet.letters
  static let digit                    = CharacterSet.decimalDigits
  static let special                  = CharacterSet(charactersIn: "[]\\`_^{|}")
  static let letterOrSpecial          = letter.union(special)
  static let letterDigitOrSpecial     = letter.union(digit).union(special)
  static let letterDigitSpecialOrDash = letterDigitOrSpecial
                                        .union(CharacterSet(charactersIn: "-"))
}
