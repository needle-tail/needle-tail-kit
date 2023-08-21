//
//  KeyBundleMechanisimDelegate.swift
//
//
//  Created by Cole M on 12/25/22.
//

import NeedleTailProtocol
import NeedleTailHelpers
import CypherMessaging
@_spi(AsyncChannel) import NIOCore

@globalActor actor KeyBundleMechanismActor {
    static let shared = KeyBundleMechanismActor()
    internal init() {}
}


//@KeyBundleMechanismActor
public protocol KeyBundleMechanisimDelegate: AnyObject {
    @KeyBundleMechanismActor
    var origin: String? { get }
    @KeyBundleMechanismActor
    @_spi(AsyncChannel)
    var asyncChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>{ get }
    func keyBundleMessage(_
                          type: TransportMessageType,
                          tags: [IRCTags]?
    ) async throws
}

@KeyBundleMechanismActor
extension KeyBundleMechanisimDelegate {
    
    public func keyBundleMessage(_
                                 type: TransportMessageType,
                                 tags: [IRCTags]? = nil
    ) async throws {
        switch type {
        case .standard(let command):
            let message = IRCMessage(command: command, tags: tags)
            try await sendAndFlushMessage(message)
        case .private(let command), .notice(let command):
            switch command {
            case .PRIVMSG(let recipients, let messageLines):
                let lines = messageLines.components(separatedBy: Constants.cLF.rawValue)
                    .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
                _ = try await lines.asyncMap {
                    let message = IRCMessage(origin: self.origin, command: .PRIVMSG(recipients, $0), tags: tags)
                    try await sendAndFlushMessage(message)
                }
            default:
                break
            }
        }
    }
    
    @KeyBundleMechanismActor
    public func sendAndFlushMessage(_ message: IRCMessage) async throws {
        let buffer = await NeedleTailEncoder.encode(value: message)
        try await asyncChannel.channel.writeAndFlush(buffer)
    }
}


@KeyBundleMechanismActor
internal final class KeyBundleMechanism: KeyBundleMechanisimDelegate {
    
    @KeyBundleMechanismActor
    var origin: String? {
        return try? BSONEncoder().encode(clientContext.nickname).makeData().base64EncodedString()
    }
    @KeyBundleMechanismActor
    var asyncChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>
    var updateKeyBundle = false
    let store: TransportStore
    let clientContext: ClientContext
    
    internal init(
        asyncChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>,
        store: TransportStore,
        clientContext: ClientContext
    ) {
        self.asyncChannel = asyncChannel
        self.store = store
        self.clientContext = clientContext
    }
    
    
    deinit {}
    
    
    func processKeyBundle(
        _ message: IRCMessage
    ) async {
        do {
            switch message.command {
            case .otherCommand(Constants.readKeyBundle.rawValue, let keyBundle):
                try await doReadKeyBundle(keyBundle)
            default:
                return
            }
        } catch {
            print(error)
        }
    }
    
    /// Request from the server a users key bundle
    /// - Parameter packet: Our Authentication Packet
    func readKeyBundle(_ packet: String) async throws {
        let type = TransportMessageType.standard(.otherCommand(Constants.readKeyBundle.rawValue, [packet]))
        try await keyBundleMessage(type)
    }
    
    func doReadKeyBundle(_ keyBundle: [String]) async throws {
        guard let keyBundle = keyBundle.first else { throw KeyBundleErrors.cannotReadKeyBundle }
        guard let data = Data(base64Encoded: keyBundle) else { throw KeyBundleErrors.cannotReadKeyBundle }
        let buffer = ByteBuffer(data: data)
        let config = try BSONDecoder().decode(UserConfig.self, from: Document(buffer: buffer))
        store.setKeyBundle(config)
    }
    
    
    enum KeyBundleErrors: Error {
        case cannotReadKeyBundle, nilData
    }
}
