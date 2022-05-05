//
//  NeedleTail.swift
//  
//
//  Created by Cole M on 4/17/22.
//
#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS))
import Foundation
import CypherMessaging
import NIOTransportServices
import CypherMessaging
import MessagingHelpers
import AsyncIRC
import SwiftUI
import NeedleTailHelpers

public final class NeedleTail {
    
    
    public typealias NTAnyChatMessage = AnyChatMessage
    public typealias NTContact = Contact
    public typealias NTPrivateChat = PrivateChat
    public var irc: IRCMessenger?
    public var cypher: CypherMessenger?
    public var messageType: MessageType = .message {
        didSet {
            irc?.messageType = messageType
        }
    }
    
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
        try await irc?.startService()
        return self.cypher
    }
    
    //IRC Becomes nil on network loss. Fix by regreistering the IRCSession with the current CypherMessenger
    public func resumeService() async {
        await irc?.resume()
    }
    
    public func serviceInterupted(_ isSuspending: Bool = false) async {
        await irc?.suspend(isSuspending)
    }
    
    public func registerAPN(_ token: Data) async throws {
        try await irc?.registerAPNSToken(token)
    }
    
    public func blockUnblockUser(_ contact: Contact) async throws {
        irc?.messageType = .blockUnblock
        try await contact.block()
    }
    
    public func beFriend(_ contact: Contact) async throws {
        if await contact.ourFriendshipState == .notFriend, await contact.ourFriendshipState == .undecided {
            try await contact.befriend()
        } else {
            try await contact.unfriend()
        }
    }
    
    public func addContact(contact: String, nick: String = "") async throws {
        let chat = try await cypher?.createPrivateChat(with: Username(contact))
        let contact = try await cypher?.createContact(byUsername: Username(contact))
        
        
        //Be Friend is not working properly, The Contact is correct be friend is reading key bundle for current nick.
        try await contact?.befriend()
        
        
        try await contact?.setNickname(to: nick)
        _ = try await chat?.sendRawMessage(
            type: .magic,
            messageSubtype: "_/ignore",
            text: "",
            preferredPushType: .contactRequest
        )
    }
}

public class NeedleTailViewModel: ObservableObject {
    @Published var emitter: NeedleTailEmitter?
    @Published var cypher: CypherMessenger?
    public init() {}
}


//SwiftUI Stuff
extension NeedleTail: ObservableObject {
    
    public struct SpoolView: View {
        public var store: CypherMessengerStore
        public var clientOptions: ClientOptions
        public var p2pFactories: [P2PTransportClientFactory]? = []
        public var eventHandler: PluginEventHandler?
        public var view: AnyView
        @StateObject var emitter = makeEventEmitter()
        @EnvironmentObject var needleTailViewModel: NeedleTailViewModel
        
        
        public init(
            _ view: AnyView,
            store: CypherMessengerStore,
            clientOptions: ClientOptions,
            p2pFactories: [P2PTransportClientFactory]? = [],
            eventHandler: PluginEventHandler? = nil
        ) {
            self.view = view
            self.store = store
            self.clientOptions = clientOptions
            self.p2pFactories = p2pFactories
            self.eventHandler = eventHandler
        }
        
        public var body: some View {
            AsyncView(run: { () async throws -> (CypherMessenger?, NeedleTailEmitter?) in
                if needleTailViewModel.cypher == nil && needleTailViewModel.emitter == nil {
                    var cypher: CypherMessenger?
                    cypher = try await NeedleTail.shared.spoolService(
                        store: store,
                        clientOptions: clientOptions,
                        eventHandler: makeEventHandler(emitter: emitter),
                        p2pFactories: makeP2PFactories()
                    )
                    return (cypher, emitter)
                } else {
                    return (needleTailViewModel.cypher,  needleTailViewModel.emitter)
                }
            }) { (cypher, emitter) in
                view
                    .environment(\._emitter, emitter)
                    .environment(\._messenger, cypher)
            }
        }
    }
    
    public struct RegisterOrAddButton: View {
        public var exists: Bool = true
        public var buttonTitle: String = ""
        public var username: String = ""
        public var nick: String = ""
        public var password: String = ""
        public var store: CypherMessengerStore
        public var options: ClientOptions
        @StateObject var emitter = makeEventEmitter()
        @Binding public var dismiss: Bool
        @Binding var showProgress: Bool
        @EnvironmentObject var needleTailViewModel: NeedleTailViewModel
        
        public init(
            exists: Bool,
            buttonTitle: String,
            username: String,
            password: String,
            nick: String,
            store: CypherMessengerStore,
            options: ClientOptions,
            dismiss: Binding<Bool>,
            showProgress: Binding<Bool>
        ) {
            self.exists = exists
            self.buttonTitle = buttonTitle
            self.username = username
            self.nick = nick
            self.password = password
            self.store = store
            self.options = options
            self.options.password = password
            self._dismiss = dismiss
            self._showProgress = showProgress
        }
        
        public var body: some View {
            
            Button(buttonTitle, action: {
                #if os(iOS)
                UIApplication.shared.endEditing()
                #endif
                showProgress = true
                Task {
                    if exists {
                        try await NeedleTail.shared.addContact(contact: username, nick: nick)
                        showProgress = false
                        dismiss = true
                    } else {
                        needleTailViewModel.cypher = try await NeedleTail.shared.registerNeedleTail(
                            appleToken: "",
                            username: username,
                            store: store,
                            clientOptions: options,
                            p2pFactories: makeP2PFactories(),
                            eventHandler: makeEventHandler(emitter: emitter)
                        )
                        
                        needleTailViewModel.emitter = emitter
                        showProgress = false
                        dismiss = true
                    }
                }
            })
        }
    }
    
    
    enum SampleError: Error {
        case usernameIsNil
    }
}

public struct AsyncView<T, V: View>: View {
    @State var result: Result<T, Error>?
    let run: () async throws -> T
    let build: (T) -> V
    
    public init(run: @escaping () async throws -> T, @ViewBuilder build: @escaping (T) -> V) {
        self.run = run
        self.build = build
    }
    
    public var body: some View {
        ZStack {
            switch result {
            case .some(.success(let value)):
                build(value)
            case .some(.failure(let error)):
                ErrorView(error: error)
            case .none:
                NeedleTailProgressView().task {
                    do {
                        self.result = .success(try await run())
                    } catch {
                        self.result = .failure(error)
                    }
                }
            }
        }.id(result.debugDescription)
    }
}


extension EnvironmentValues {
    
    private struct CypherMessengerKey: EnvironmentKey {
        typealias Value = CypherMessenger?
        
        static let defaultValue: CypherMessenger? = nil
    }
    
    public var _messenger: CypherMessenger? {
        get {
            self[CypherMessengerKey.self]
        }
        set {
            self[CypherMessengerKey.self] = newValue
        }
    }
    
    public var messenger: CypherMessenger {
        get {
            self[CypherMessengerKey.self]!
        }
        set {
            self[CypherMessengerKey.self] = newValue
        }
    }
    
    private struct EventEmitterKey2: EnvironmentKey {
        typealias Value = NeedleTailEmitter?
        static let defaultValue: NeedleTailEmitter? = nil
    }
    
    public var _emitter: NeedleTailEmitter? {
        get {
            self[EventEmitterKey2.self]
        }
        set {
            self[EventEmitterKey2.self] = newValue
        }
    }
    
    public var emitter: NeedleTailEmitter {
        get {
            self[EventEmitterKey2.self]!
        }
        set {
            self[EventEmitterKey2.self] = newValue
        }
    }
}

@Sendable
@MainActor
func sortConversations(lhs: TargetConversation.Resolved, rhs: TargetConversation.Resolved) -> Bool {
    switch (lhs.lastActivity, rhs.lastActivity) {
    case (.some(let lhs), .some(let rhs)):
        return lhs > rhs
    case (.some, .none):
        return true
    case (.none, .some):
        return false
    case (.none, .none):
        return true
    }
}

public func makeEventEmitter() -> NeedleTailEmitter {
    NeedleTailEmitter(sortChats: sortConversations)
}


public func makeEventHandler(emitter: NeedleTailEmitter) -> PluginEventHandler {
    PluginEventHandler(plugins: [
        FriendshipPlugin(ruleset: {
            var ruleset = FriendshipRuleset()
            ruleset.ignoreWhenUndecided = true
            ruleset.preventSendingDisallowedMessages = true
            return ruleset
        }()),
        UserProfilePlugin(),
        ChatActivityPlugin(),
        NeedleTailPlugin(emitter: emitter)
    ])
}


public func makeP2PFactories() -> [P2PTransportClientFactory] {
    return [
        IPv6TCPP2PTransportClientFactory(),
    ]
}

#endif
