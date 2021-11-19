////
////  AccountModel.swift
////  
////
////  Created by Cole M on 10/31/21.
////
//
//import Foundation
//import CypherProtocol
//import CypherMessaging
//import Crypto
//
//
//public final class IRCAccountModel: Codable, Model {
//    
//    public struct SecureProps: Codable, MetadataProps {
//        public var nickname: String
//        public var activeRecipients: [ String ]
//        public internal(set) var config: UserConfig
//        public var metadata: Document
//        public var joinedChannels: [ String ] {
//            return activeRecipients.filter { $0.hasPrefix("#") }
//        }
//        
//    }
//    
//    public let id: UUID
//    public var props: Encrypted<SecureProps>
//    
//    public init(
//        id: UUID,
//        props: Encrypted<SecureProps>
//    ) {
//        self.id = id
//        self.props = props
//    }
//    
//    internal init(
//        props: SecureProps,
//        encryptionKey: SymmetricKey
//    ) throws {
//        self.id = UUID()
//        self.props = try .init(props, encryptionKey: encryptionKey)
//    }
//}
//
//extension DecryptedModel where M == IRCAccountModel {
//    public var nickname: String {
//        get { props.nickname }
//    }
//    public var activeRecipients: [String] {
//        get { props.activeRecipients }
//    }
//    public var joinedChannels: [String] {
//        get { props.joinedChannels }
//    }
//    public var config: UserConfig {
//        get { props.config }
//    }
//    public var metadata: Document {
//        get { props.metadata }
//    }
//    func updateConfig(to newValue: UserConfig) async throws {
//        try await self.setProp(at: \.config, to: newValue)
//    }
//}
//
//
//public final class IRCAccount: Identifiable, Hashable {
//    public var id: UUID { model.id }
//    public var port: Int
//    public var host: String
//    public var tls: Bool
//    internal let databaseEncryptionKey: SymmetricKey
//    public let model: DecryptedModel<IRCAccountModel>
//    public var joinedChannels : [ String ] {
//        return model.activeRecipients.filter { $0.hasPrefix("#") }
//    }
//    
//    public static func == (lhs: IRCAccount, rhs: IRCAccount) -> Bool {
//        return lhs.id == rhs.id
//    }
//    
//    public func hash(into hasher: inout Hasher) {
//        hasher.combine(id)
//    }
//    
//    
//    public init(
//        databaseEncryptionKey: SymmetricKey,
//        model: DecryptedModel<IRCAccountModel>,
//        port: Int = 6667,
//        host: String = "localhost",
//        tls: Bool = false
//    ) {
//        self.databaseEncryptionKey = databaseEncryptionKey
//        self.model = model
//        self.port = port
//        self.host = host
//        self.tls = tls
//    }
//}
//
////extension IRCAccount: CustomStringConvertible {
////  public var description: String {
////    var ms = "<Account: \(id) \(host):\(port) \(nickname)"
////    ms += " " + activeRecipients.joined(separator: ",")
////    ms += ">"
////    return ms
////  }
////}
