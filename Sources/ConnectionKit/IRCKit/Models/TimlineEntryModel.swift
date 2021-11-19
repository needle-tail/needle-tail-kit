//
//  TimelineEntry.swift
//  
//
//  Created by Cole M on 11/2/21.
//

import Foundation
import CypherProtocol
import CypherMessaging
import Crypto
import NIOIRC

//Model
import struct Foundation.Date

public enum Payload: Codable, Equatable {
  case ownMessage(String)
  case message(String, IRCUserID)
  case notice (String)

  case disconnect
  case reconnect
}

extension IRCUserID: Codable {
    public func encode(to encoder: Encoder) throws {
        
    }
    
    public init(from decoder: Decoder) throws {
        try! self.init(from: decoder)
    }
}

public struct TimelineEntryModel: Codable, Model, Equatable {
    
    
    public struct SecureProps: Codable, MetadataProps {
        public var metadata: Document
        
        public let date    : Date
        public let payload : Payload
        
        init(date: Date = Date(), payload: Payload, metadata: Document) {
          self.date    = date
          self.payload = payload
            self.metadata = metadata
        }
        
    }
  
    public let id: UUID
    public var props: Encrypted<SecureProps>
    
    init(
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
    
    public static func == (lhs: TimelineEntryModel, rhs: TimelineEntryModel) -> Bool {
        return lhs.id == rhs.id
    }
}

extension DecryptedModel: Codable {
    public func encode(to encoder: Encoder) throws {
        
    }
    
    public convenience init(from decoder: Decoder) throws {
        try! self.init(from: decoder)
    }

}

extension DecryptedModel where M == TimelineEntryModel {
    public var date: Date {
        get { props.date }
    }
    
    public var payload: Payload {
        get { props.payload }
    }

    public var metadata: Document {
        get { props.metadata }
    }
    
}


public struct TimelineEntry:  Codable, Identifiable, Hashable {
    
    public var id: UUID
    
    public static func == (lhs: TimelineEntry, rhs: TimelineEntry) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    public let model: DecryptedModel<TimelineEntryModel>

}
