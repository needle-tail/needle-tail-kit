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
#if os(macOS)
import Cocoa
#endif

public final class NeedleTail {
    
    
    public typealias NTAnyChatMessage = AnyChatMessage
    public typealias NTContact = Contact
    public typealias NTPrivateChat = PrivateChat
    public var ntm: NeedleTailMessenger?
    public var cypher: CypherMessenger?
    public weak var delegate: AsyncIRCNotificationsDelegate?
    public var messageType: MessageType = .message {
        didSet {
            ntm?.messageType = messageType
        }
    }
    
    public static let shared = NeedleTail()
    
    @discardableResult
    public func registerNeedleTail(
        appleToken: String,
        username: String,
        store: CypherMessengerStore,
        clientInfo: ClientContext.ServerClientInfo,
        p2pFactories: [P2PTransportClientFactory],
        eventHandler: PluginEventHandler
    ) async throws -> CypherMessenger? {
        if cypher == nil {
            cypher = try await CypherMessenger.registerMessenger(
                username: Username(username),
                appPassword: clientInfo.password,
                usingTransport: { transportRequest async throws -> NeedleTailMessenger in
                    if self.ntm == nil {
                        self.ntm = try await NeedleTailMessenger.authenticate(
                            transportRequest: transportRequest,
                            clientInfo: clientInfo
                        )
                    }
                    guard let ntm = self.ntm else { throw NeedleTailError.nilNTM }
                    ntm.initalRegistration = true
                    await ntm.createClient()
                    return ntm
                },
                p2pFactories: p2pFactories,
                database: store,
                eventHandler: eventHandler
            )
        }
        return cypher
    }

    @discardableResult
    public func spoolService(
        appleToken: String,
        store: CypherMessengerStore,
        clientInfo: ClientContext.ServerClientInfo,
        eventHandler: PluginEventHandler,
        p2pFactories: [P2PTransportClientFactory]
    ) async throws -> CypherMessenger? {
        cypher = try await CypherMessenger.resumeMessenger(
            appPassword: clientInfo.password,
            usingTransport: { transportRequest -> NeedleTailMessenger in
                self.ntm = try await NeedleTailMessenger.authenticate(
                    transportRequest: transportRequest,
                    clientInfo: clientInfo
                )
                guard let ircMessenger = self.ntm else { throw NeedleTailError.nilNTM }
                return ircMessenger
            },
            p2pFactories: p2pFactories,
            database: store,
            eventHandler: eventHandler
        )
        //Start Service
#if os(macOS)
        NotificationCenter.default.addObserver(self, selector: #selector(showRegistryRequestAlert), name: .registryRequest, object: nil)
#endif
        let ntm = cypher?.transport as? NeedleTailMessenger
        try await ntm?.startSession(ntm?.registrationType(appleToken))
        self.delegate = ntm?.client
        return self.cypher
    }
    
    public func resumeService(_ appleToken: String = "") async throws {
        try await ntm?.startSession(ntm?.registrationType(appleToken))
    }
    
    public func serviceInterupted(_ isSuspending: Bool = false) async {
        await ntm?.suspend(isSuspending)
    }
    
    public func registerAPN(_ token: Data) async throws {
        try await ntm?.registerAPNSToken(token)
    }
    
    public func blockUnblockUser(_ contact: Contact) async throws {
        ntm?.messageType = .blockUnblock
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
        guard contact != self.cypher?.username.raw else { fatalError("Cannot be friends with ourself") }
        let chat = try await cypher?.createPrivateChat(with: Username(contact))
        let contact = try await cypher?.createContact(byUsername: Username(contact))
        messageType = .beFriend
        try await contact?.befriend()
        try await contact?.setNickname(to: nick)
        _ = try await chat?.sendRawMessage(
            type: .magic,
            messageSubtype: "_/ignore",
            text: "",
            preferredPushType: .contactRequest
        )
        messageType = .message
    }
    
    //We are not using CTK for groups. All messages are sent in one-on-one conversations. This includes group chat communication, that will also be routed in private chats. What we want to do is create a group. The Organizer of the group will do this. The organizer can then do the following.
    // - Name the group
    // - add initial members
    // - add other organizers to the group
    //How are we going to save groups to a device? Let's build a plug that will do the following
    //1. The admin creates the group encrypts it and saves it to disk then sends it to the NeedleTailChannel.
    //2. The Channel then is operating. it will then join the members and organizers of the Channel and emit the needed information to them if they are online, of not it will save that information until they are online and when they come online they will receive the event and be able to respond to the request. If accepted the Client will save to disk the Channel, if not it will reject it and tell the server. Either way the pending request will be deleted from the DB and all clients will be notified of the current status.
    //3. The Channel will exisit as long as the server is up. The DB will know the channel name and the Nicks assosiated with it along with their roles. The channels will be brought online when the server spools up.
    //4. The Channel acts as a passthrough of private messages and who receives them. The Logic Should be the exact same as PRIVMSG except we specify a channel recipient.
    //5. Basic Flow - DoJoin(Creates the channel if it does not exist with organizers and intial members) -> DoMessage(Sends Messages to that Channel)
    func createLocalChannel(
        name: String,
        admin: Username,
        organizers: Set<Username>,
        members: Set<Username>,
        permissions: IRCChannelMode
    ) async throws {
        
        //Set MessageType
        ntm?.type = .needleTailChannel
        guard let admin = NeedleTailNick(deviceId: ntm?.deviceId, name: admin.raw) else { return }
        //Build our server message
        ntm?.needleTailChannelMetaData = NeedleTailChannelPacket(
            name: name,
            admin: admin,
            organizers: organizers,
            members: members,
            permissions: permissions)
    
        //This will kick off a sendMessage flow
       let group = try await cypher?.createGroupChat(with: members)
        
        //Update any organizers Locally
        guard var config = await group?.getGroupConfig() else { return }
        for organizer in organizers {
            guard !config.blob.moderators.contains(organizer) else { return }
            config.blob.promoteAdmin(organizer)
        }
    }
    
#if os(macOS)
    @objc private func showRegistryRequestAlert() {
        let alert = NSAlert()
        alert.configuredCustomButtonAlert(title: "A User has requested to add their device to your account", text: "", firstButtonTitle: "Cancel", secondButtonTitle: "Add Device", thirdButtonTitle: "", switchRun: true)
        let run = alert.runModal()
        switch run {
        case .alertFirstButtonReturn:
//            logger.info("Cancel")
            break
        case .alertSecondButtonReturn:
//            logger.info("Added device")
            Task {
            await acceptRegistryRequest()
            }
        default:
            break
        }
        
    }
#endif
    
    public func acceptRegistryRequest() async {
        await delegate?.respond(to: .registryRequestAccepted)
    }
}

public class NeedleTailViewModel: ObservableObject {
    @Published public var emitter: NeedleTailEmitter?
    @Published public var cypher: CypherMessenger?
    public init() {}
}


//SwiftUI Stuff
extension NeedleTail: ObservableObject {
    
    public struct SpoolView: View {
        public var store: CypherMessengerStore
        public var clientInfo: ClientContext.ServerClientInfo
        public var p2pFactories: [P2PTransportClientFactory]? = []
        public var eventHandler: PluginEventHandler?
        public var view: AnyView
        @StateObject var emitter = makeEventEmitter()
        @EnvironmentObject var needleTailViewModel: NeedleTailViewModel
        
        
        public init(
            _ view: AnyView,
            store: CypherMessengerStore,
            clientInfo: ClientContext.ServerClientInfo,
            p2pFactories: [P2PTransportClientFactory]? = [],
            eventHandler: PluginEventHandler? = nil
        ) {
            self.view = view
            self.store = store
            self.clientInfo = clientInfo
            self.p2pFactories = p2pFactories
            self.eventHandler = eventHandler
        }
        
        public var body: some View {
            AsyncView(run: { () async throws -> (CypherMessenger?, NeedleTailEmitter?) in
                if needleTailViewModel.cypher == nil && needleTailViewModel.emitter == nil {
                    var cypher: CypherMessenger?
                    cypher = try await NeedleTail.shared.spoolService(
                        appleToken: "",
                        store: store,
                        clientInfo: clientInfo,
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
        public var createContact: Bool = true
        public var createChannel: Bool = true
        public var buttonTitle: String = ""
        public var username: Username = ""
        public var nick: String = ""
        public var channelName: String?
        public var admin: Username?
        public var organizers: Set<Username>?
        public var members: Set<Username>?
        public var permissions: IRCChannelMode?
        public var password: String = ""
        public var store: CypherMessengerStore
        public var clientInfo: ClientContext.ServerClientInfo
        @StateObject var emitter = makeEventEmitter()
        @Binding public var dismiss: Bool
        @Binding var showProgress: Bool
        @EnvironmentObject var needleTailViewModel: NeedleTailViewModel
        
        public init(
            exists: Bool,
            createContact: Bool,
            createChannel: Bool,
            buttonTitle: String,
            username: Username,
            password: String,
            nick: String,
            channelName: String? = nil,
            admin: Username? = nil,
            organizers: Set<Username>? = nil,
            members: Set<Username>? = nil,
            permissions: IRCChannelMode? = nil,
            store: CypherMessengerStore,
            clientInfo: ClientContext.ServerClientInfo,
            dismiss: Binding<Bool>,
            showProgress: Binding<Bool>
        ) {
            self.exists = exists
            self.createContact = createContact
            self.createChannel = createChannel
            self.channelName = channelName
            self.admin = admin
            self.organizers = organizers
            self.members = members
            self.permissions = permissions
            self.buttonTitle = buttonTitle
            self.username = username
            self.nick = nick
            self.password = password
            self.store = store
            self.clientInfo = clientInfo
            self.clientInfo.password = password
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
                    if createContact {
                        try await NeedleTail.shared.addContact(contact: username.raw, nick: nick)
                        showProgress = false
                        dismiss = true
                    } else if createChannel {
                        guard let channelName = channelName else { return }
                        guard let admin = admin else { return }
                        guard let organizers = organizers else { return }
                        guard let members = members else { return }
                        guard let permissions = permissions else { return }
                        try await NeedleTail.shared.createLocalChannel(
                            name: channelName,
                            admin: admin,
                            organizers: organizers,
                            members: members,
                            permissions: permissions
                        )
                        showProgress = false
                        dismiss = true
                    } else {
                        needleTailViewModel.cypher = try await NeedleTail.shared.registerNeedleTail(
                            appleToken: "",
                            username: username.raw,
                            store: store,
                            clientInfo: clientInfo,
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
