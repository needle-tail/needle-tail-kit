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
import Combine
import BSON
import CypherMessaging

@globalActor actor KeyBundleMechanismActor {
    static let shared = KeyBundleMechanismActor()
    internal init() {}
}


@KeyBundleMechanismActor
public protocol KeyBundleMechanisimDelegate: AnyObject {
    var origin: String? { get }
    var channel: Channel { get }
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
        var message: IRCMessage?
        switch type {
        case .standard(let command):
            message = IRCMessage(command: command, tags: tags)
        case .private(let command), .notice(let command):
            switch command {
            case .PRIVMSG(let recipients, let messageLines):
                let lines = messageLines.components(separatedBy: Constants.cLF)
                    .map { $0.replacingOccurrences(of: Constants.cCR, with: Constants.space) }
                _ = await lines.asyncMap {
                    message = IRCMessage(origin: self.origin, command: .PRIVMSG(recipients, $0), tags: tags)
                }
            default:
                break
            }
        }
        guard let message = message else { return }
        try await sendAndFlushMessage(message)
    }
    
    public func sendAndFlushMessage(_ message: IRCMessage) async throws {
        _ = channel.eventLoop.executeAsync { [weak self] in
            guard let strongSelf = self else { return }
            try await strongSelf.channel.writeAndFlush(message)
        }

    }
}


@KeyBundleMechanismActor
internal final class KeyBundleMechanism: KeyBundleMechanisimDelegate {
    
    var origin: String? {
        return try? BSONEncoder().encode(clientContext.nickname).makeData().base64EncodedString()
    }
    var channel: Channel
    var updateKeyBundle = false
    let store: TransportStore
    let clientContext: ClientContext
    
    internal init(
        channel: Channel,
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
            if await strongSelf.store.keyBundle != nil {
                canRun = false
            }
            return canRun
        }
        print("SENT_READ_KEY_BUNDLE REQUEST_WE FINISHED LOOPPING AND SHOULD HAVE A BUNDLE RETURNED: - BUNDLE: \(await String(describing: store.keyBundle))")
    }
    
    func doReadKeyBundle(_ keyBundle: [String]) async throws {
        print("READ_KEY_BUNDLE_REQUEST_RECEIVED_WE_SHOULD_HAVE_A_KEY_HERE_AND_NEXT_WE_SHOULD_FINISH_WITH_THE_REQUEST_METHOD: - BUNDLE: \(keyBundle)")
        guard let keyBundle = keyBundle.first else { throw KeyBundleErrors.cannotReadKeyBundle }
        guard let data = Data(base64Encoded: keyBundle) else { throw KeyBundleErrors.cannotReadKeyBundle }
        let buffer = ByteBuffer(data: data)
        let config = try BSONDecoder().decode(UserConfig.self, from: Document(buffer: buffer))
        await store.setKeyBundle(config)
    }
    
    
    enum KeyBundleErrors: Error {
        case cannotReadKeyBundle, nilData
    }
}
