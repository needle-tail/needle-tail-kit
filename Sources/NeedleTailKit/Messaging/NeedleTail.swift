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
import NeedleTailProtocol
import SwiftUI
import NeedleTailHelpers
//import SpineTailedKit
//import SpineTailedProtocol
#if os(macOS)
import Cocoa
#endif

private func makeEventEmitter() -> NeedleTailEmitter {
    let emitter = NeedleTailEmitter(sortChats: sortConversations)
    return emitter
}

extension PublicSigningKey: Equatable {
    public static func == (lhs: CypherProtocol.PublicSigningKey, rhs: CypherProtocol.PublicSigningKey) -> Bool {
        return lhs.data == rhs.data
    }
}

public final class NeedleTail {
    
    public typealias NTAnyChatMessage = AnyChatMessage
    public typealias NTContact = Contact
    public typealias NTPrivateChat = PrivateChat
    public var messenger: NeedleTailMessenger?
    public var cypher: CypherMessenger?
    public var emitter = makeEventEmitter()
    public var state = NetworkMonitor()
    var plugin: NeedleTailPlugin?
    public var messageType: MessageType = .message {
        didSet {
            messenger?.messageType = messageType
        }
    }
    var registrationApproved = false
    var registeringNewDevice = false
    public static let shared = NeedleTail()
    var needleTailViewModel = NeedleTailViewModel()

    // We are going to run a loop on this actor until the requesting client scans the masters approval QRCode. When then complete the loop in onBoardAccount(), finish registering this device locally and then we request the master device to add the new device to the remote DB before we are allowed spool up an IRC Session.
    @NeedleTailClientActor
    public func waitForApproval(_ code: String) async throws {
        guard let messenger = messenger else { throw NeedleTailError.messengerNotIntitialized }
        registrationApproved = try await messenger.processApproval(code)
    }
    
    // After the master scans the new device we feed it to cypher in order to add the new device locally and remotely
    @NeedleTailClientActor
    public func addNewDevice(_ config: UserDeviceConfig) async throws {
        //set this to true in order to tell publishKeyBundle that we are adding a device
        messenger?.client?.transport?.updateKeyBundle = true
        //set the recipient Device Id so that the server knows which device is requesting this addition
        messenger?.recipientDeviceId = config.deviceId
        try await cypher?.addDevice(config)
    }
    
    @NeedleTailClientActor
    func onBoardAccount(
        appleToken: String,
        username: String,
        store: CypherMessengerStore,
        clientInfo: ClientContext.ServerClientInfo,
        p2pFactories: [P2PTransportClientFactory],
        eventHandler: PluginEventHandler? = nil
    ) async throws -> CypherMessenger? {
        plugin = NeedleTailPlugin(emitter: emitter)
        guard let plugin = plugin else { return nil }
        _ = try await createMessenger(
            clientInfo: clientInfo,
            plugin: plugin,
            nameToVerify: username
        )
        
        do {
            let masterKeyBundle = try await messenger?
                .readKeyBundle(forUsername: Username(username))
            
            for validatedMaster in try masterKeyBundle?.readAndValidateDevices() ?? [] {
                guard let nick = NeedleTailNick(name: username, deviceId: validatedMaster.deviceId) else { continue }
                try await messenger?.requestDeviceRegistration(nick)
            }
            
            await MainActor.run {
                emitter.showScanner = true
            }

            try await RunLoop.run(240, sleep: 1, stopRunning: {
                var running = true
                if registrationApproved == true {
                    running = false
                }
                return running
            })
            
            await messenger?.suspend(true)
            messenger = nil
            
            return try await registerNeedleTail(
                appleToken: appleToken,
                username: username,
                store: store,
                clientInfo: clientInfo,
                p2pFactories: p2pFactories,
                eventHandler: eventHandler,
                isNewDevice: true
            )
            
        } catch {
            print("User Does not exist,  proceed...")
            await self.messenger?.suspend()
            self.messenger = nil
            return try await registerNeedleTail(
                appleToken: appleToken,
                username: username,
                store: store,
                clientInfo: clientInfo,
                p2pFactories: p2pFactories,
                eventHandler: eventHandler
            )
        }
    }
    
    
    
    
    @NeedleTailClientActor
    @discardableResult
    public func registerNeedleTail(
        appleToken: String,
        username: String,
        store: CypherMessengerStore,
        clientInfo: ClientContext.ServerClientInfo,
        p2pFactories: [P2PTransportClientFactory],
        eventHandler: PluginEventHandler? = nil,
        isNewDevice: Bool = false
    ) async throws -> CypherMessenger? {
        if cypher == nil {
            //Create plugin here
            plugin = NeedleTailPlugin(emitter: emitter)
            guard let plugin = plugin else { return nil }
            
            cypher = try await CypherMessenger.registerMessenger(
                username: Username(username),
                appPassword: clientInfo.password,
                usingTransport: { transportRequest async throws -> NeedleTailMessenger in
                    if isNewDevice {
                        return try await self.createMessenger(
                            clientInfo: clientInfo,
                            plugin: plugin,
                            transportRequest: transportRequest,
                            nameToVerify: username
                        )
                    } else {
                        return try await self.createMessenger(
                            clientInfo: clientInfo,
                            plugin: plugin,
                            transportRequest: transportRequest
                        )
                    }
                },
                p2pFactories: p2pFactories,
                database: store,
                eventHandler: eventHandler ?? makeEventHandler(plugin)
            )
            messenger?.cypher = cypher
            emitter.needleTailNick = messenger?.needleTailNick
            
        }
        return cypher
    }
    
    @NeedleTailClientActor
    private func createMessenger(
        clientInfo: ClientContext.ServerClientInfo,
        plugin: NeedleTailPlugin,
        transportRequest: TransportCreationRequest? = nil,
        nameToVerify: String = ""
    ) async throws -> NeedleTailMessenger {
        if self.messenger == nil {
            //We also need to pass the plugin to our transport
            self.messenger = try await NeedleTailMessenger.authenticate(
                transportRequest: transportRequest,
                clientInfo: clientInfo,
                plugin: plugin
            )
        }
        guard let messenger = self.messenger else { throw NeedleTailError.nilNTM }
        if !nameToVerify.isEmpty {
            messenger.registrationState = .temp
        }
        if messenger.client == nil {
            //We need to make sure we have internet before we try this
            for status in await NeedleTail.shared.state.receiver.statusArray {
                try await RunLoop.run(10, sleep: 1) {
                    var running = true
                    if status == .satisfied {
                        running = false
                    }
                    return running
                }
                if status == .satisfied {
                    if messenger.isConnected == false {
                        try await messenger.createClient(nameToVerify)
                    }
                }
            }
        }
        return messenger
    }
    
    @NeedleTailClientActor
    @discardableResult
    public func spoolService(
        appleToken: String,
        store: CypherMessengerStore,
        clientInfo: ClientContext.ServerClientInfo,
        eventHandler: PluginEventHandler? = nil,
        p2pFactories: [P2PTransportClientFactory]
    ) async throws -> CypherMessenger? {
        //Create plugin here
        plugin = NeedleTailPlugin(emitter: emitter)
        guard let plugin = plugin else { return nil }
        cypher = try await CypherMessenger.resumeMessenger(
            appPassword: clientInfo.password,
            usingTransport: { transportRequest -> NeedleTailMessenger in
                return try await self.createMessenger(
                    clientInfo: clientInfo,
                    plugin: plugin,
                    transportRequest: transportRequest
                )
            },
            p2pFactories: p2pFactories,
            database: store,
            eventHandler: eventHandler ?? makeEventHandler(plugin)
        )

        messenger?.cypher = self.cypher
        emitter.needleTailNick = messenger?.needleTailNick
        return self.cypher
    }

    public func resumeService(_
                              appleToken: String = ""
    ) async throws {
        guard let messenger = messenger else { return }
        if messenger.client == nil {
            try await messenger.createClient("")
        }
        
        switch messenger.clientServeState {
        case .lockState:
            break
        case .clientConnected:
            if cypher?.authenticated != nil {
                try await messenger.startSession(messenger.registrationType(appleToken), nil, .full)
                messenger.isConnected = true
            }
        case .clientRegistered:
            messenger.clientServeState = .lockState
        }
    }
    
    public func serviceInterupted(_ isSuspending: Bool = false) async {
        guard let messenger = messenger else { return }
        await messenger.suspend(isSuspending)
        try? await RunLoop.run(5, sleep: 1) {
            var running = true
            if !messenger.isConnected {
                running = false
            }
            return running
        }
        messenger.clientServeState = .clientConnected
    }
    
    public func registerAPN(_ token: Data) async throws {
        try await messenger?.registerAPNSToken(token)
    }
    
    public func blockUnblockUser(_ contact: Contact) async throws {
        messenger?.messageType = .blockUnblock
        try await contact.block()
    }
    
    public func beFriend(_ contact: Contact) async throws {
        if await contact.ourFriendshipState == .notFriend, await contact.ourFriendshipState == .undecided {
            try await contact.befriend()
        } else {
            try await contact.unfriend()
        }
    }

    public func addContact(newContact: String, nick: String = "") async throws {
        let chat = try await cypher?.createPrivateChat(with: Username(newContact))
        let contact = try await cypher?.createContact(byUsername: Username(newContact))
        messageType = .message
        try await contact?.befriend()
        try await contact?.setNickname(to: nick)
        messageType = .message
        _ = try await chat?.sendRawMessage(
            type: .magic,
            messageSubtype: "_/ignore",
            text: "",
            preferredPushType: .contactRequest
        )
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
    public func createLocalChannel(
        name: String,
        admin: Username,
        organizers: Set<Username>,
        members: Set<Username>,
        permissions: IRCChannelMode
    ) async throws {
        try await messenger?.createLocalChannel(
            name: name,
            admin: admin,
            organizers: organizers,
            members: members,
            permissions: permissions
        )
    }
    
    public func makeEventHandler(_
                                 plugin: NeedleTailPlugin
    ) throws -> PluginEventHandler {
        return PluginEventHandler(plugins: [
            FriendshipPlugin(ruleset: {
                var ruleset = FriendshipRuleset()
                ruleset.ignoreWhenUndecided = true
                ruleset.preventSendingDisallowedMessages = true
                return ruleset
            }()),
            UserProfilePlugin(),
            ChatActivityPlugin(),
            plugin
        ])
    }
    
    public func startVideoChat(_ username: String, data: Data) async throws {
//        let chat = try await cypher?.createPrivateChat(with: Username(username))
//        try await chat?.buildP2PConnections()
//
//        let packet = try RTPPacket(from: data)
//        let data = try BSONEncoder().encode(packet).makeData()
//        let string = data.base64EncodedString()
//        _ = try await chat?.sendRawMessage(type: .media, text: string, preferredPushType: .call)
        
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
        
        @Environment(\.scenePhase) var scenePhase
        public var store: CypherMessengerStore
        public var clientInfo: ClientContext.ServerClientInfo
        public var p2pFactories: [P2PTransportClientFactory]? = []
        public var eventHandler: PluginEventHandler?
        public var view: AnyView
        
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
                let needleTailViewModel = NeedleTail.shared.needleTailViewModel
                if needleTailViewModel.cypher == nil && needleTailViewModel.emitter == nil {
                    needleTailViewModel.cypher = try await NeedleTail.shared.spoolService(
                        appleToken: "",
                        store: store,
                        clientInfo: clientInfo,
                        p2pFactories: makeP2PFactories()
                    )
                    needleTailViewModel.emitter = NeedleTail.shared.emitter
                }
                return (needleTailViewModel.cypher,  needleTailViewModel.emitter)
            }) { (cypher, emitter) in
                view
                    .onChange(of: scenePhase) { (phase) in
                        let task = Task {
                            switch phase {
                            case .active:
                                print("Active")
                                try? await NeedleTail.shared.resumeService()
                            case .background:
                                print("Went into Background")
                                await NeedleTail.shared.serviceInterupted(true)
                            case .inactive:
                                print("Inactive")
                            @unknown default:
                                break
                            }
                        }
                        task.cancel()
                    }
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
        public var userHandle: String = ""
        public var nick: String = ""
        public var channelName: String?
        public var admin: Username?
        public var organizers: Set<Username>?
        public var members: Set<Username>?
        public var permissions: IRCChannelMode?
        public var password: String = ""
        public var store: CypherMessengerStore? = nil
        public var clientInfo: ClientContext.ServerClientInfo? = nil
        @Binding public var dismiss: Bool
        @Binding var showProgress: Bool
        @Binding var qrCodeData: Data?
        @Binding var showScanner: Bool?
        @State var buttonTask: Task<(), Error>? = nil
        
        public init(
            exists: Bool,
            createContact: Bool,
            createChannel: Bool,
            buttonTitle: String,
            username: Username,
            password: String,
            userHandle: String,
            nick: String,
            channelName: String? = nil,
            admin: Username? = nil,
            organizers: Set<Username>? = nil,
            members: Set<Username>? = nil,
            permissions: IRCChannelMode? = nil,
            store: CypherMessengerStore? = nil,
            clientInfo: ClientContext.ServerClientInfo? = nil,
            dismiss: Binding<Bool>,
            showProgress: Binding<Bool>,
            qrCodeData: Binding<Data?>,
            showScanner: Binding<Bool?>
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
            self.userHandle = userHandle
            self.nick = nick
            self.password = password
            self.store = store
            self.clientInfo = clientInfo
            self.clientInfo?.password = password
            self._dismiss = dismiss
            self._showProgress = showProgress
            self._qrCodeData = qrCodeData
            self._showScanner = showScanner
        }
        
        public var body: some View {
            
            Button(buttonTitle, action: {
#if os(iOS)
                UIApplication.shared.endEditing()
#endif
                showProgress = true
                self.buttonTask = Task {
                    if createContact {
                        try await NeedleTail.shared.addContact(newContact: userHandle, nick: nick)
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
                        do {
                            let needleTailViewModel = NeedleTail.shared.needleTailViewModel
                            guard let store = store else { throw NeedleTailError.storeNotIntitialized }
                            guard let clientInfo = clientInfo else { throw NeedleTailError.clientInfotNotIntitialized }
                            needleTailViewModel.cypher = try await NeedleTail.shared.onBoardAccount(
                                appleToken: "",
                                username: username.raw,
                                store: store,
                                clientInfo: clientInfo,
                                p2pFactories: makeP2PFactories(),
                                eventHandler: nil
                            )
                            
                            needleTailViewModel.emitter = NeedleTail.shared.emitter
                            showProgress = false
                            dismiss = true
                        } catch let error as NeedleTailError {
                            if error == .masterDeviceReject {
                                //TODO: Send REJECTED/RETRY Notification
                            } else if error == .registrationFailure {
                                //TODO: Send RETRY with new Username Notification
                            }
                        } catch {
                            print(error)
                        }
                    }
                }
            })
            .onDisappear {
                self.buttonTask?.cancel()
            }
            .onReceive(NeedleTail.shared.emitter.$qrCodeData) { data in
                self.qrCodeData = data
                self.showProgress = false
            }
            .onReceive(NeedleTail.shared.emitter.$showScanner) { show in
                self.showScanner = show
                self.showProgress = false
            }
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
                NeedleTailProgressView()
                    .task {
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
    
    public var cypher: CypherMessenger {
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


public func makeP2PFactories() -> [P2PTransportClientFactory] {
    return [
        IPv6TCPP2PTransportClientFactory()
//        SpineTailedTransportFactory()
    ]
}

#endif
