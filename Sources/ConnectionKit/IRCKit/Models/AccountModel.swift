//
//  AccountModel.swift
//  
//
//  Created by Cole M on 10/31/21.
//

import Foundation
import CypherProtocol
import CypherMessaging
import Crypto

public final class AccountModel: Model {
    public struct SecureProps: Codable, MetadataProps {
//        public let username: Username
        public var nickname: String
        public var activeRecipients: [ String ]
        public internal(set) var config: UserConfig
        public var metadata: Document
        public var joinedChannels: [ String ] {
          return activeRecipients.filter { $0.hasPrefix("#") }
        }

    }
    
    public let id: UUID
    public var tls: Bool
    public var host: String
    public var port: Int
    public var props: Encrypted<SecureProps>
    
    public init(
        id: UUID,
        host: String,
        port: Int,
        tls: Bool,
        props: Encrypted<SecureProps>
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.tls = tls
        self.props = props
    }
    
    internal init(
        props: SecureProps,
        encryptionKey: SymmetricKey,
        host: String,
        port: Int,
        tls: Bool
    ) throws {
        self.id = UUID()
        self.props = try .init(props, encryptionKey: encryptionKey)
        self.host = host
        self.port = port
        self.tls = tls
    }
}

extension DecryptedModel where M == AccountModel {
    public var nickname: String {
        get { props.nickname }
    }
    public var activeRecipients: [String] {
        get { props.activeRecipients }
    }
    public var joinedChannels: [String] {
        get { props.joinedChannels }
    }
    public var config: UserConfig {
        get { props.config }
    }
    public var metadata: Document {
        get { props.metadata }
    }
    func updateConfig(to newValue: UserConfig) async throws {
        try await self.setProp(at: \.config, to: newValue)
    }
}
