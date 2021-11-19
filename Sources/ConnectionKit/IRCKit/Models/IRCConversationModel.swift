//
//  ConversationModel.swift
//  
//
//  Created by Cole M on 11/2/21.
//

import Foundation
import CypherProtocol
import CypherMessaging
import Crypto
import NIOIRC

public enum ConversationType: Equatable, Codable {
    case channel
    case im
}

//Model
public final class IRCConversationModel: Model, Identifiable {
    
    public var id: UUID
    public var props: Encrypted<SecureProps>
    
    public class SecureProps: Codable, MetadataProps {
        
        public var metadata: Document
        public var type: ConversationType
        public var name: String
        public var nameID: String { return name }
        public var timeline = [ TimelineEntry ]()
        public var recipient : IRCMessageRecipient? {
            switch type {
            case .channel:
                guard let name = IRCChannelName(name) else { return nil }
                return .channel(name)
            case .im:
                guard let name = IRCNickName(name)    else { return nil }
                return .nickname(name)
            }
        }
        
        init(channel: IRCChannelName, metadata: Document) {
            self.type      = .channel
            self.name      = channel.stringValue
            self.metadata = metadata
        }
        init?(nickname: String, metadata: Document) {
            self.type      = .im
            self.name      = nickname
            self.metadata = metadata
        }
        
        convenience init?(channel: String, metadata: Document) {
            guard let name = IRCChannelName(channel) else { return nil }
            self.init(channel: name, metadata: metadata)
        }
        
    }
    
    public init (
        id: UUID,
        props: Encrypted<SecureProps>
    ) {
        self.id = id
        self.props = props
    }
    
    internal init(
        props: SecureProps,
        encryptionKey: SymmetricKey
    ) throws {
        self.id = UUID()
        self.props = try .init(props, encryptionKey: encryptionKey)
    }
}

extension DecryptedModel where M == IRCConversationModel {
    public var recipient: IRCMessageRecipient? {
        get { props.recipient! }
    }
    
    public var type: ConversationType {
        get { props.type }
    }
    
    public var name: String {
        get { props.name }
    }
    
    public var nameID: String {
        get { props.nameID }
    }
    
    public var timeline: [TimelineEntry] {
        get { props.timeline }
    }
}
