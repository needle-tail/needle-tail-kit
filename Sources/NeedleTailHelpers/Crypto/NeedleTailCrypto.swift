//
//  NeedleTailCrypto.swift
//  Cartisim
//
//  Created by Cole M on 11/14/20.
//  Copyright © 2020 Cole M. All rights reserved.
//

import Foundation
import Crypto
import CypherMessaging
import SwiftDTF

public struct NeedleTailCrypto: Sendable {
    
    enum Errors: Error {
        case combinedDataNil
    }
    
    public init() {}
    
    //Any string we can use to generate a SymmetricKey it should be unique to a client/app
    public func userInfoKey(_ key: String) -> SymmetricKey {
        let hash = SHA256.hash(data: key.data(using: .utf8)!)
        let hashString = hash.map { String(format: "%02hhx", $0)}.joined()
        let subString = String(hashString.prefix(32))
        let keyData = subString.data(using: .utf8)!
        return SymmetricKey(data: keyData)
    }
    
    public func generatePrivateKey() -> Curve25519.KeyAgreement.PrivateKey {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        return privateKey
    }
    
    public func importPrivateKey(_ privateKey: String) throws -> Curve25519.KeyAgreement.PrivateKey {
        let privateKeyBase64 = privateKey.removingPercentEncoding!
        let rawPrivateKey = Data(base64Encoded: privateKeyBase64)!
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: rawPrivateKey)
    }
    
    public func exportPrivateKey(_ privateKey: Curve25519.KeyAgreement.PrivateKey) -> String {
        let rawPrivateKey = privateKey.rawRepresentation
        let privateKeyBase64 = rawPrivateKey.base64EncodedString()
        let percentEncodedPrivateKey = privateKeyBase64.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        return percentEncodedPrivateKey
    }
    
    public func derivedKeyLogic(
        salt: String,
        userPrivateKey: String,
        publicKey: String
    ) throws -> SymmetricKey {
            let privateKeyStringConsumption = try importPrivateKey(userPrivateKey)
            let importedPublicKey = try importPublicKey(publicKey)
            return try deriveSymmetricKey(salt: salt, privateKey: privateKeyStringConsumption, publicKey: importedPublicKey)
    }
    
    private func importPublicKey(_ publicKey: String) throws -> Curve25519.KeyAgreement.PublicKey {
        let base64PublicKey = publicKey.removingPercentEncoding!
        let rawPublicKey = Data(base64Encoded: base64PublicKey)!
        return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: rawPublicKey)
    }
    
    private func exportPublicKey(_ publicKey: Curve25519.KeyAgreement.PublicKey) -> String {
        let rawPublicKey = publicKey.rawRepresentation
        let base64PublicKey = rawPublicKey.base64EncodedString()
        return base64PublicKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    }
    
    private func deriveSymmetricKey(
        salt: String,
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        publicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> SymmetricKey {
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        return sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt.data(using: .utf8)!, sharedInfo: Data(), outputByteCount: 32)
    }
}


extension NeedleTailCrypto {
    
    public func encrypt(data: Data, symmetricKey: SymmetricKey) throws -> Data? {
        let encrypted = try AES.GCM.seal(data, using: symmetricKey)
        return encrypted.combined
    }
    
    public func decrypt(data: Data, symmetricKey: SymmetricKey) throws -> Data? {
            let sealedBox = try! AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: symmetricKey)
    }
    
    public func encryptText(text: String, symmetricKey: SymmetricKey) throws -> String {
        let textData = text.data(using: .utf8)!
        guard let encrypted = try! AES.GCM.seal(textData, using: symmetricKey).combined else { throw Errors.combinedDataNil }
        return encrypted.base64EncodedString()
    }
    
    public func decryptText(text: String, symmetricKey: SymmetricKey) throws -> String {
            guard let data = Data(base64Encoded: text) else {
                return "Could not decode text: \(text)"
            }
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
            guard let text = String(data: decryptedData, encoding: .utf8) else {
                return "Could not decode data: \(decryptedData)"
            }
            return text
    }
    
    public func encryptCodableObject<T: Codable>(_ object: T, usingKey key: SymmetricKey) throws -> Data? {
        let encoder = JSONEncoder()
        let userData = try encoder.encode(object)
        let encryptedData = try AES.GCM.seal(userData, using: key)
        return encryptedData.combined
    }
    
    public func decryptStringToCodableObject<T: Codable>(_ type: T.Type, from string: String, usingKey key: SymmetricKey) throws -> T {
        let data = Data(base64Encoded: string)!
        let box = try AES.GCM.SealedBox(combined: data)
        let decryptData = try AES.GCM.open(box, using: key)
        let decoder = JSONDecoder()
        let object = try decoder.decode(type, from: decryptData)
        return object
    }
}

extension NeedleTailCrypto {
    private func createData(message: SingleCypherMessage, cypher: CypherMessenger) async throws -> Data {
        guard let filePath = message.metadata["filePath"] as? String else { fatalError("Could not generate blob") }
        guard let blob = try DataToFile.shared.generateData(from: filePath) else { fatalError("Could not generate blob") }
        let fileComponents = filePath.components(separatedBy: ".")
        try DataToFile.shared.removeItem(fileName: fileComponents[0], fileType: fileComponents[1])
        //Decrypt
        return try cypher.decryptLocalFile(AES.GCM.SealedBox(combined: blob))
    }
    
    public func decryptFileData(_ fileData: Data, cypher: CypherMessenger) async throws -> Data {
        guard let fileName = String(data: fileData, encoding: .utf8) else { fatalError("Could not generate blob") }
        guard let blob = try DataToFile.shared.generateData(from: fileName) else { fatalError("Could not generate blob") }
        let fileComponents = fileName.components(separatedBy: ".")
        try DataToFile.shared.removeItem(fileName: fileComponents[0], fileType: fileComponents[1])
        let data = try cypher.decryptLocalFile(AES.GCM.SealedBox(combined: blob))
        return data
    }
    
    public func decryptFile(from path: String, cypher: CypherMessenger, shouldRemove: Bool = false) async throws -> Data {
        var path = path
        guard let blob = try DataToFile.shared.generateData(from: path) else { fatalError("Could not generate blob") }
        if path.contains("/") {
            path = path.components(separatedBy: "/").last ?? ""
        }
        let fileComponents = path.components(separatedBy: ".")
        if shouldRemove {
            try DataToFile.shared.removeItem(fileName: fileComponents[0], fileType: fileComponents[1])
        }
        let data = try cypher.decryptLocalFile(AES.GCM.SealedBox(combined: blob))
        return data
    }
}
