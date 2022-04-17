//
//  IRCMessenger+Entry.swift
//  
//
//  Created by Cole M on 4/17/22.
//

import Foundation
import CypherMessaging
import NIOTransportServices
import CypherMessaging
import MessagingHelpers
import AsyncIRC

public final class NeedleTail {
    
    
    public typealias NTAnyChatMessage = AnyChatMessage
    public typealias NTContact = Contact
    public typealias NTPrivateChat = PrivateChat
    
    public var irc: IRCMessenger?
    public var cypher: CypherMessenger?
    
    init() {}
    
    public static let shared = NeedleTail()

    @discardableResult
    public func registerNeedleTail(
        appleToken: String,
        username: String,
        store: CypherMessengerStore,
        clientOptions: ClientOptions,
        p2pFactories: [P2PTransportClientFactory],
        eventHandler: PluginEventHandler
    ) async throws -> CypherMessenger? {
        var type: RegistrationType?
        if !appleToken.isEmpty {
            type = .siwa
        } else {
            type = .plain
        }
        
        cypher = try await CypherMessenger.registerMessenger(
            username: Username(username),
            appPassword: clientOptions.password,
            usingTransport: { request async throws -> IRCMessenger in
                
                if self.irc == nil {
                    self.irc = try await IRCMessenger.authenticate(
                        transportRequest: request,
                        options: clientOptions
                    )
                }
                
                guard let ircMessenger = self.irc else { throw NeedleTailError.nilIRCMessenger }
                try await ircMessenger.registerBundle(type: type, options: clientOptions)
                return ircMessenger
            },
            p2pFactories: p2pFactories,
            database: store,
            eventHandler: eventHandler
        )
        return cypher
    }
    
    @discardableResult
    public func spoolService(store: CypherMessengerStore, clientOptions: ClientOptions, eventHandler: PluginEventHandler, p2pFactories: [P2PTransportClientFactory]) async throws -> CypherMessenger? {
        cypher = try await CypherMessenger.resumeMessenger(
            appPassword: clientOptions.password,
            usingTransport: { request -> IRCMessenger in
                
                self.irc = try await IRCMessenger.authenticate(
                    transportRequest: request,
                    options: clientOptions
                )
                
                guard let ircMessenger = self.irc else { throw NeedleTailError.nilIRCMessenger }
                return ircMessenger
            },
            p2pFactories: p2pFactories,
            database: store,
            eventHandler: eventHandler
        )
        
        //Start Service
        let irc = cypher?.transport as? IRCMessenger
        await irc?.startService()
        return self.cypher
    }
    
    public func resumeService() async {
        await irc?.resume()
    }
    
    public func suspendService() async {
        await irc?.suspend()
    }
    
    public func registerAPN(_ token: Data) async throws {
        try await irc?.registerAPNSToken(token)
    }
    
    public func addContact(contact: String, nick: String = "") async throws {
        let chat = try await cypher?.createPrivateChat(with: Username(contact))
        let contact = try await cypher?.createContact(byUsername: Username(contact))
            try await contact?.befriend()
            try await contact?.setNickname(to: nick)
            _ = try await chat?.sendRawMessage(
                type: .magic,
                messageSubtype: "_/ignore",
                text: "",
                preferredPushType: .contactRequest
            )
    }
    
    public func sendMessage(emitter: NeedleTailPlugin, message: String) async throws {
        _ = try await emitter.selectedChat?.sendRawMessage(
        type: .text,
        text: message,
        preferredPushType: .message
    )
    }
    
    public func fetchChats(emitter: NeedleTailPlugin, contact: Contact? = nil) async {
        guard let cypher = cypher else { return }
        await emitter.fetchChats(messenger: cypher, contact: contact)
    }
}
