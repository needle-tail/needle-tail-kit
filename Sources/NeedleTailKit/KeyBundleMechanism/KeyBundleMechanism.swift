//
//  KeyBundleMechanisimDelegate.swift
//  
//
//  Created by Cole M on 12/25/22.
//

import Foundation
import NeedleTailProtocol
import NeedleTailHelpers
import NIOCore
#if canImport(Combine)
import Combine
#endif
import BSON
import CypherMessaging

@globalActor actor KeyBundleMechanismActor {
    static let shared = KeyBundleMechanismActor()
    internal init() {}
}


//@KeyBundleMechanismActor
public protocol KeyBundleMechanisimDelegate: AnyObject {
    var origin: String? { get }
    var channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>{ get }
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
                let lines = messageLines.components(separatedBy: Constants.cLF)
                    .map { $0.replacingOccurrences(of: Constants.cCR, with: Constants.space) }
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
        //THIS IS ANNOYING BUT WORKS
        try await RunLoop.run(5, sleep: 1, stopRunning: {
            var canRun = true
            if self.channel.channel.isActive  {
                canRun = false
            }
            return canRun
        })
        let encoded = await NeedleTailEncoder.encode(value: message)
        try await channel.writeAndFlush(encoded)
    }
}


@KeyBundleMechanismActor
internal final class KeyBundleMechanism: KeyBundleMechanisimDelegate {
    
    var origin: String? {
        return try? BSONEncoder().encode(clientContext.nickname).makeData().base64EncodedString()
    }
    var channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>
    var updateKeyBundle = false
    let store: TransportStore
    let clientContext: ClientContext
    
    internal init(
        channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>,
        store: TransportStore,
        clientContext: ClientContext
    ) {
        self.channel = channel
        self.store = store
        self.clientContext = clientContext
    }
    
    
    deinit {}
    
    
    
    func processKeyBundle(
        _ message: IRCMessage
    ) async throws {
        switch message.command {
        case .otherCommand("READKEYBNDL", let keyBundle):
            try await doReadKeyBundle(keyBundle)
        default:
            return
        }
    }
    
    /// Request from the server a users key bundle
    /// - Parameter packet: Our Authentication Packet
    func readKeyBundle(_ packet: String) async throws {
        let type = TransportMessageType.standard(.otherCommand("READKEYBNDL", [packet]))
        try await keyBundleMessage(type)
        try await RunLoop.run(30, sleep: 1) { [weak self] in
            guard let strongSelf = self else { return false }
            var canRun = true
            if strongSelf.store.keyBundle != nil {
                canRun = false
            }
            return canRun
        }
        print("SENT_READ_KEY_BUNDLE REQUEST_WE FINISHED LOOPPING AND SHOULD HAVE A BUNDLE RETURNED: - BUNDLE: \(String(describing: store.keyBundle))")
    }
    
    func doReadKeyBundle(_ keyBundle: [String]) async throws {
        print("READ_KEY_BUNDLE_REQUEST_RECEIVED_WE_SHOULD_HAVE_A_KEY_HERE_AND_NEXT_WE_SHOULD_FINISH_WITH_THE_REQUEST_METHOD: - BUNDLE: \(keyBundle)")
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
