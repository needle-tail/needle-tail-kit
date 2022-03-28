import CypherProtocol
import CypherMessaging
import Foundation
import BSON
import NIO
import Logging


extension StoredTask {
    func execute(on messenger: CypherMessenger) async throws {}
    func onDelayed(on messenger: CypherMessenger) async throws {}
}

enum _IRCTaskKey: String, Codable {
    case parseMessage = "a"
    case parseMessageDeliveryStateChangeTask = "b"
}

struct ParseMessageTask: Codable {
    private enum CodingKeys: String, CodingKey {
        case message = "a"
    }
    
    let message: String
}

@available(macOS 12, iOS 15, *)
struct ParseMessageDeliveryStateChangeTask: Codable {
    private enum CodingKeys: String, CodingKey {
        case localId = "a"
        case messageId = "b"
        case newState = "e"
    }
    
    let localId: UUID
    let messageId: String
    let newState: ChatMessageModel.DeliveryState
}

public enum _IRCTaskConfig {
    public static var sendMessageRetryMode: IRCTaskRetryMode? = nil
}

@available(macOS 12, iOS 15, *)
enum IRCTask: Codable, IRCStoredTask {
    
    
    private enum CodingKeys: String, CodingKey {
        case key = "a"
        case document = "b"
    }
    
    case parseMessage(ParseMessageTask)
    case parseMessageDeliveryStateChangeTask(ParseMessageDeliveryStateChangeTask)
    
    
    var retryMode: IRCTaskRetryMode {
        switch self {
        case .parseMessage, .parseMessageDeliveryStateChangeTask(_):
            if let mode = _IRCTaskConfig.sendMessageRetryMode {
                return mode
            }
            return .retryAfter(30, maxAttempts: 3)
        }
    }
    
    var requiresConnectivity: Bool {
        switch self {
        case .parseMessage:
            return true
        case .parseMessageDeliveryStateChangeTask(_):
            return false
        }
    }
    
    var priority: IRCTaskPriority {
        switch self {
        case .parseMessage:
            // These need to be fast, but are not urgent per-say
            return .higher
        case .parseMessageDeliveryStateChangeTask:
            // A conversation can continue without these, but it's preferred to be done sooner rather than later
            return .lower
        }
    }
    
    var isBackgroundTask: Bool {
        switch self {
        case .parseMessage:
            return false
        case .parseMessageDeliveryStateChangeTask:
            // Both tasks can temporarily fail due to network or user delay
            return true
        }
    }
    
    var key: IRCTaskKey {
        IRCTaskKey(stringLiteral: _key.rawValue)
    }
    
    var _key: _IRCTaskKey {
        switch self {
        case .parseMessage:
            return .parseMessage
        case .parseMessageDeliveryStateChangeTask:
            return .parseMessageDeliveryStateChangeTask
        }
    }
    
    func makeDocument() throws -> Document {
        switch self {
        case .parseMessage(let message):
            return try BSONEncoder().encode(message)
        case .parseMessageDeliveryStateChangeTask(let message):
            return try BSONEncoder().encode(message)
        }
    }
    var logger: Logger {
        Logger(label: "IRCTask - ")
    }
    
    init(key: _IRCTaskKey, document: Document) throws {
        let decoder = BSONDecoder()
        switch key {
        case .parseMessage:
            self = try .parseMessage(decoder.decode(ParseMessageTask.self, from: document))
        case .parseMessageDeliveryStateChangeTask:
            self = try .parseMessageDeliveryStateChangeTask(decoder.decode(ParseMessageDeliveryStateChangeTask.self, from: document))
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        try self.init(
            key: container.decode(_IRCTaskKey.self, forKey: .key),
            document: container.decode(Document.self, forKey: .document)
        )
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(_key, forKey: .key)
        try container.encode(makeDocument(), forKey: .document)
    }
    
    func onDelayed() async throws {
        switch self {
        case .parseMessage(let task):
//            print(task)
            break
//            _ = try await messenger._markMessage(byId: task.localId, as: .undelivered)
        case .parseMessageDeliveryStateChangeTask:
            ()
        }
    }
    
    func execute() async throws -> IRCMessage? {
        switch self {
        case .parseMessage(let message):
//            debugLog("Sending message to \(message.recipient)")
//            return try await TaskHelpers.writeMessageTask(task: message, messenger: messenger)
            return try await IRCTaskHelpers.parseMessageTask(task: message, ircMessageParser: IRCMessageParser(logger: self.logger))
        case .parseMessageDeliveryStateChangeTask(let task):
//            let result = try await messenger._markMessage(byId: task.localId, as: task.newState)
//            switch result {
//            case .error:
//                return
//            case .success:
//                ()
//            case .notModified:
//                () // Still emit the notification to the other side
//            }
            
            switch task.newState {
            case .none, .undelivered:
                return nil
            case .read: break
//                return try await messenger.transport.sendMessageReadReceipt(
//                    byRemoteId: task.messageId,
//                    to: task.recipient
//                )
            case .received: break
//                return try await messenger.transport.sendMessageReceivedReceipt(
//                    byRemoteId: task.messageId,
//                    to: task.recipient
//                )
            case .revoked:
                fatalError("TODO")
            }
        }
        return nil
    }
}

@available(macOS 12, iOS 15, *)
enum IRCTaskHelpers {

    fileprivate static func parseMessageTask(task: ParseMessageTask, ircMessageParser: IRCMessageParser) async throws -> IRCMessage {
        //Parse
        Logger(label: "IRCTaskHelpers - ").info("Parsing has begun")
            return try await ircMessageParser.parseMessage(task.message)
    }
    
    fileprivate static func writeMessageTask(
        task: ParseMessageTask
    ) async throws {
//    messenger: CypherMessenger
//        guard messenger.authenticated == .authenticated else {
//            debugLog("Not connected with the server")
//            _ = try await messenger._markMessage(byId: task.localId, as: .undelivered)
//            throw CypherSDKError.offline
//        }
//
//        // Fetch the identity
//        debugLog("Executing task: Send message")
//
//        if let p2pTransport = try await messenger.getEstablishedP2PConnection(with: task.recipient, deviceId: task.recipientDeviceId) {
//            do {
//                try await p2pTransport.sendMessage(
//                    task.message,
//                    messageId: task.messageId
//                )
//
//                // Message may be a magic packet
//                _ = try? await messenger._markMessage(byId: task.localId, as: .none)
//
//                return
//            } catch {
//                debugLog("P2P Connection failed to communicate")
//            }
//        }
//
//        try await messenger._writeWithRatchetEngine(ofUser: task.recipient, deviceId: task.recipientDeviceId) { ratchetEngine, rekeyState in
//            let encodedMessage = try BSONEncoder().encode(task.message).makeData()
//            let ratchetMessage = try ratchetEngine.ratchetEncrypt(encodedMessage)
//
//            let encryptedMessage = try await messenger._signRatchetMessage(ratchetMessage, rekey: rekeyState)
//            try await messenger.transport.sendMessage(
//                encryptedMessage,
//                toUser: task.recipient,
//                otherUserDeviceId: task.recipientDeviceId,
//                pushType: task.pushType,
//                messageId: task.messageId
//            )
//        }
//
//        // Message may be a magic packet
//        _ = try? await messenger._markMessage(byId: task.localId, as: .none)
    }
}
