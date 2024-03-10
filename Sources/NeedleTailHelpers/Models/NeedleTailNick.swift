//
//  NeedleTailNick.swift
//
//
//  Created by Cole M on 4/26/22.
//

import CypherMessaging
import NIOConcurrencyHelpers

/// We are using classes because we want a reference to the object on the server, in order to use ObjectIdentifier to Cache the Object.
/// This class can be Sendable because we are using a lock to protect any mutated state
public final class NeedleTailNick: Codable, Hashable, Equatable, CustomStringConvertible, @unchecked Sendable {
    
    private let lock = NIOLock()
    private static let staticLock = NIOLock()
    public var description: String {
        lock.withSendableLock { [weak self] in
            guard let self else { return "" }
            let did = self.deviceId ?? DeviceId("")
            return "NeedleTailNick(name: \(self.name), deviceId: \(did))"
        }
    }
    
    public var stringValue: String {
        lock.withSendableLock { [weak self] in
            guard let self else { return "" }
            guard let deviceId = deviceId else { return "" }
            return "\(name)_\(deviceId)"
        }
    }
    public let name: String
    public let deviceId: DeviceId?
    
    
    public init?(
        name: String,
        deviceId: DeviceId?,
        nameRules: NameRules = NameRules()
    ) {
        lock.lock()
        self.deviceId = deviceId
        self.name = name.ircLowercased()
        lock.unlock()
        guard NeedleTailNick.validateName(name, nameRules: nameRules) == .isValidated else { return nil }
    }
    
    public func hash(into hasher: inout Hasher) {
        deviceId.hash(into: &hasher)
    }
    
    public static func ==(lhs: NeedleTailNick, rhs: NeedleTailNick) -> Bool {
        return lhs.deviceId == lhs.deviceId
    }
    
    //We want to validate our Nick
    public enum ValidatedNameStatus {
        case isValidated, failedValidation
    }
    public struct NameRules: Sendable {
        public var allowsStartingDigit: Bool = true
        public var disallowsUnderScore: Bool = true
        public var lengthLimit: Int = 1024
        public init() {}
    }
    
    public static func validateName(_ name: String, nameRules: NameRules) -> ValidatedNameStatus {
        guard name.count > 1, name.count >= 1, name.count <= 1024 else { return .failedValidation }
        
        if nameRules.disallowsUnderScore && name.contains("_") {
            return .isValidated
        }
        
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
    
    public enum CodingKeys: CodingKey, Sendable {
        case name, deviceId
    }
    
    // MARK: - Codable
    public init(from decoder: Decoder) async throws {
        lock.lock()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.deviceId = try container.decode(DeviceId.self, forKey: .deviceId)
        lock.unlock()
    }
    
    public func encode(to encoder: Encoder) throws {
        lock.lock()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(deviceId, forKey: .deviceId)
        lock.unlock()
    }
}


import struct Foundation.CharacterSet

fileprivate enum CharacterSets: Sendable {
    static let letter                   = CharacterSet.letters
    static let digit                    = CharacterSet.decimalDigits
    static let special                  = CharacterSet(charactersIn: "[]\\`_^{|}")
    static let letterOrSpecial          = letter.union(special)
    static let letterDigitOrSpecial     = letter.union(digit).union(special)
    static let letterDigitSpecialOrDash = letterDigitOrSpecial
        .union(CharacterSet(charactersIn: "-"))
}
