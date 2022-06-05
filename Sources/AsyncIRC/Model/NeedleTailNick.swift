//
//  NeedleTailNick.swift
//
//
//  Created by Cole M on 4/26/22.
//

import Foundation
import CypherMessaging

public class NeedleTailNick: Codable, Hashable, Equatable, CustomStringConvertible {
    
    public var description: String {
        return "NeedleTailNick(deviceId: \(String(describing: deviceId)), name: \(name))"
    }
    public var stringValue: String {
        guard let deviceId = deviceId else { return "" }
        return "\(name):\(deviceId)"
    }
    
    public var deviceId: DeviceId?
    public var name: String

    
    public init?(
        deviceId: DeviceId?,
        name: String,
        nameRules: NameRules = NameRules()
    ) {
        self.deviceId = deviceId
        guard NeedleTailNick.validateName(name, nameRules: nameRules) == .isValidated else { return nil }
        self.name = name.ircLowercased()
    }
    
    public func hash(into hasher: inout Hasher) {
        name.hash(into: &hasher)
    }
    
    public static func ==(lhs: NeedleTailNick, rhs: NeedleTailNick) -> Bool {
        return lhs.deviceId == lhs.deviceId
    }
    
    //We want to validate our Nick
    public enum ValidatedNameStatus {
        case isValidated, failedValidation
    }
    public struct NameRules {
        public var allowsStartingDigit: Bool = true
        public var lengthLimit: Int = 1024
        
        public init() {}
    }
    
    public static func validateName(_ name: String, nameRules: NameRules) -> ValidatedNameStatus {
        guard name.count > 1, name.count >= 9, name.count <= 1024 else { return .failedValidation }
            
            var firstCharacterSet: CharacterSet
            if nameRules.allowsStartingDigit {
                firstCharacterSet = CharacterSets.letterDigitOrSpecial
            } else {
                firstCharacterSet = CharacterSets.letterOrSpecial
            }
            let rest = CharacterSets.letterDigitSpecialOrDash
            let scalars = name.unicodeScalars
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
