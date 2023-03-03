//
//  NeedleTail.swift
//
//
//  Created by Cole M on 4/17/22.
//
#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS))
import CypherMessaging
import MessagingHelpers
import SwiftUI
import NeedleTailHelpers
//import SpineTailedKit
//import SpineTailedProtocol
#if os(macOS)
import Cocoa
#endif


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
    var needletailStore = NeedleTailStore()
    public var state = NetworkMonitor()
    public static let shared = NeedleTail()
    public var messageType: MessageType = .message {
        didSet {
            messenger?.messageType = messageType
        }
    }
//    @NeedleTailClientActor
    var registrationApproved = false
    var registeringNewDevice = false
//    var needleTailViewModel = NeedleTailViewModel()
    var plugin: NeedleTailPlugin?
//    @NeedleTailClientActor
    private var resumeQueue = NeedleTailStack<Int>()
//    @NeedleTailClientActor
    private var suspendQueue = NeedleTailStack<Int>()
//    @NeedleTailClientActor
    private var totalResumeRequests = 0
    private var totalSuspendRequests = 0
    private var store: CypherMessengerStore?
    

    /// We are going to run a loop on this actor until the **Child Device** scans the **Master Device's** approval **QRCode**. We then complete the loop in **onBoardAccount()**, finish registering this device locally and then we request the **Master Device** to add the new device to the remote DB before we are allowed spool up an NTK Session.
    /// - Parameter code: The **QR Code** scanned from the **Master Device**
//    @NeedleTailClientActor
    public func waitForApproval(_ code: String) async throws {
        guard let transportBridge = messenger?.transportBridge else { throw NeedleTailError.messengerNotIntitialized }
        let approved = try await transportBridge.processApproval(code)
        registrationApproved = approved
    }
    
    // After the master scans the new device we feed it to cypher in order to add the new device locally and remotely
//    @KeyBundleMechanismActor
    public func addNewDevice(_ config: UserDeviceConfig) async throws {
        guard let cypher = cypher else { throw NeedleTailError.cypherMessengerNotSet}
        try await messenger?.transportBridge?.addNewDevice(config, cypher: cypher)
    }
    
//    @NeedleTailClientActor
    func onBoardAccount(
        appleToken: String,
        username: String,
        store: CypherMessengerStore,
        clientInfo: ClientContext.ServerClientInfo,
        p2pFactories: [P2PTransportClientFactory],
        eventHandler: PluginEventHandler? = nil,
        withChildDevice: Bool = false,
        needletailStore: NeedleTailStore
    ) async throws -> CypherMessenger? {
        self.store = store
        plugin = NeedleTailPlugin(store: needletailStore)
        guard let plugin = plugin else { return nil }
        
        let messenger = try await createMessenger(
            clientInfo: clientInfo,
            plugin: plugin,
            needletailStore: needletailStore,
            nameToVerify: username
        )
        do {
            let masterKeyBundle = try await messenger.readKeyBundle(forUsername: Username(username))
            for validatedMaster in try masterKeyBundle.readAndValidateDevices() {
                guard let nick = NeedleTailNick(name: username, deviceId: validatedMaster.deviceId) else { continue }
                try await messenger.transportBridge?.requestDeviceRegistration(nick)
            }

            //Show the Scanner for scanning the QRCode from the Master Device which is the approval code
            await displayScanner()
            
            try await RunLoop.run(240, sleep: 1, stopRunning: { [weak self] in
                guard let strongSelf = self else { return false }
                var running = true
                if strongSelf.registrationApproved == true {
                    running = false
                }
                return running
            })
            
            guard self.registrationApproved == true else {
                throw NeedleTailError.cannotRegisterNewDevice
            }
            
            
            
            try await serviceInterupted(true,  messenger: messenger)
            self.messenger = nil
            let cypher = try await registerNeedleTail(
                appleToken: appleToken,
                username: username,
                store: store,
                clientInfo: clientInfo,
                p2pFactories: p2pFactories,
                eventHandler: eventHandler,
                addChildDevice: withChildDevice,
                needletailStore: needletailStore
            )
            await MainActor.run {
                needletailStore.emitter?.cypher = cypher
                needletailStore.emitter?.needleTailNick = messenger.needleTailNick
            }
            return cypher
        } catch let nterror as NeedleTailError {
            switch nterror {
            case .nilUserConfig:
                print("User Does not exist,  proceed...", nterror)
                try await self.serviceInterupted(true, messenger: messenger)
                self.messenger = nil
                do {
                    let cypher = try await registerNeedleTail(
                        appleToken: appleToken,
                        username: username,
                        store: store,
                        clientInfo: clientInfo,
                        p2pFactories: p2pFactories,
                        eventHandler: eventHandler,
                        needletailStore: needletailStore
                    )
                    await dismissUI(plugin)
                    await MainActor.run {
                        needletailStore.emitter?.cypher = cypher
                        needletailStore.emitter?.needleTailNick = messenger.needleTailNick
                    }
                } catch {
                    print("ERROR REGISTERING", error)
                }
                return self.cypher
            default:
                return nil
            }
        } catch {
            print(error)
            return nil
        }
    }
    
    @MainActor
    private func displayScanner() {
        needletailStore.emitter?.showScanner = true
    }
    
    @MainActor
    private func dismissUI(_ plugin: NeedleTailPlugin) {
//        emitter = plugin.emitter
//        needleTailViewModel.emitter = NeedleTail.shared.emitter
#if (os(macOS) || os(iOS))
        needletailStore.emitter?.dismiss = true
        needletailStore.emitter?.showProgress = false
#endif
    }
    
//    @NeedleTailClientActor
    @discardableResult
    public func registerNeedleTail(
        appleToken: String,
        username: String,
        store: CypherMessengerStore,
        clientInfo: ClientContext.ServerClientInfo,
        p2pFactories: [P2PTransportClientFactory],
        eventHandler: PluginEventHandler? = nil,
        addChildDevice: Bool = false,
        needletailStore: NeedleTailStore
    ) async throws -> CypherMessenger? {
        if cypher == nil {
            //Create plugin here
            plugin = NeedleTailPlugin(store: needletailStore)
            guard let plugin = plugin else { return nil }
            cypher = try await CypherMessenger.registerMessenger(
                username: Username(username),
                appPassword: clientInfo.password,
                usingTransport: { transportRequest async throws -> NeedleTailMessenger in
                        return try await self.createMessenger(
                            clientInfo: clientInfo,
                            plugin: plugin,
                            needletailStore: needletailStore,
                            transportRequest: transportRequest,
                            addChildDevice: addChildDevice
                        )
                },
                p2pFactories: p2pFactories,
                database: store,
                eventHandler: eventHandler ?? makeEventHandler(plugin)
            )
        }
        return cypher
    }
    
//    @NeedleTailClientActor
    private func createMessenger(
        clientInfo: ClientContext.ServerClientInfo,
        plugin: NeedleTailPlugin,
        needletailStore: NeedleTailStore,
        transportRequest: TransportCreationRequest? = nil,
        nameToVerify: String = "",
        addChildDevice: Bool = false
    ) async throws -> NeedleTailMessenger {
        if self.messenger == nil {
            //We also need to pass the plugin to our transport
            self.messenger = try await NeedleTailMessenger.authenticate(
                transportRequest: transportRequest,
                clientInfo: clientInfo,
                needletailStore: needletailStore,
                plugin: plugin
            )
        }
        self.messenger?.addChildDevice = addChildDevice
        guard let messenger = self.messenger else { throw NeedleTailError.messengerNotIntitialized }
        if !nameToVerify.isEmpty {
            messenger.registrationState = .temp
        }
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
                        try await resumeService(nameToVerify)
                    }
                }
            }
        return messenger
    }
    
//    @NeedleTailClientActor
    @discardableResult
    public func spoolService(
        appleToken: String,
        store: CypherMessengerStore,
        clientInfo: ClientContext.ServerClientInfo,
        eventHandler: PluginEventHandler? = nil,
        p2pFactories: [P2PTransportClientFactory],
        needletailStore: NeedleTailStore
    ) async throws -> CypherMessenger? {
        //Create plugin here
        plugin = NeedleTailPlugin(store: needletailStore)
        guard let plugin = plugin else { return nil }
        cypher = try await CypherMessenger.resumeMessenger(
            appPassword: clientInfo.password,
            usingTransport: { transportRequest -> NeedleTailMessenger in
                return try await self.createMessenger(
                    clientInfo: clientInfo,
                    plugin: plugin,
                    needletailStore: needletailStore,
                    transportRequest: transportRequest
                )
            },
            p2pFactories: p2pFactories,
            database: store,
            eventHandler: eventHandler ?? makeEventHandler(plugin)
        )
        
        await MainActor.run {
            needletailStore.emitter?.needleTailNick = messenger?.needleTailNick
        }
        return self.cypher
    }
    
//    @NeedleTailClientActor
    private func resumeRequest(_ request: Int) async {
        totalResumeRequests += request
        await resumeQueue.enqueue(totalResumeRequests)
    }
    
    
//    @NeedleTailClientActor
    public func resumeService(_ nameToVerify: String = "", appleToken: String = "") async throws {
        guard let messenger = messenger else { return }
        await resumeRequest(1)
        if await resumeQueue.popFirst() == 1 {
            
            totalSuspendRequests = 0
            await suspendQueue.drain()
            try await messenger.createClient(nameToVerify)
            messenger.isConnected = true
        }
    }
    
//    @NeedleTailClientActor
    private func suspendRequest(_ request: Int) async {
        totalSuspendRequests += request
        await suspendQueue.enqueue(totalSuspendRequests)
    }
    
    
//    @NeedleTailClientActor
    public func serviceInterupted(_ isSuspending: Bool = false) async throws {
        guard let messenger = messenger else { throw NeedleTailError.messengerNotIntitialized }
        try await serviceInterupted(isSuspending, messenger: messenger)
    }
    
    internal func serviceInterupted(_ isSuspending: Bool = false, messenger: NeedleTailMessenger) async throws {
        await suspendRequest(1)
        if await suspendQueue.popFirst() == 1 {
                totalResumeRequests = 0
                await resumeQueue.drain()
            try await messenger.transportBridge?.suspendClient(isSuspending)
            await removeTransport(messenger)
            messenger.client = nil
        }
    }
    @NeedleTailClientActor
    func removeTransport(_ messenger: NeedleTailMessenger) async {
        await messenger.client?.teardownClient()
    }
    
    public func registerAPN(_ token: Data) async throws {
        try await messenger?.transportBridge?.registerAPNSToken(token)
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


//SwiftUI Stuff
extension NeedleTail {
    
    public struct SkeletonView: View {
        
        @StateObject public var emitter = NeedleTailEmitter(sortChats: sortConversations)
        public var view: AnyView
        
        public init(
            _ view: AnyView
        ) {
            self.view = view
        }
        
        public var body: some View {
            AsyncView(run: { () async throws -> NeedleTailEmitter in
                let vm = NeedleTail.shared.needletailStore
                vm.emitter = self.emitter
                return vm.emitter!
            }) { emitter in
                view
                    .environmentObject(emitter)
            }
        }
    }
    
    public struct SpoolView: View {
        

        @EnvironmentObject public var emitter: NeedleTailEmitter        
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
            AsyncView(run: { () async throws -> NeedleTailEmitter in
                let needletailStore = NeedleTail.shared.needletailStore
                needletailStore.emitter = self.emitter
                if needletailStore.emitter?.cypher == nil {
                    needletailStore.emitter?.cypher = try await NeedleTail.shared.spoolService(
                        appleToken: "",
                        store: store,
                        clientInfo: clientInfo,
                        p2pFactories: makeP2PFactories(),
                        needletailStore: needletailStore
                    )
                }
                return needletailStore.emitter!
            }) { emitter in
                view
//                    .environmentObject(emitter)
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
            clientInfo: ClientContext.ServerClientInfo? = nil
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
        }
        
        public var body: some View {
            
            Button(buttonTitle, action: {
#if os(iOS)
                UIApplication.shared.endEditing()
#endif
                NeedleTail.shared.needletailStore.emitter?.showProgress = true
                self.buttonTask = Task {
                    if createContact {
                        try await NeedleTail.shared.addContact(newContact: userHandle, nick: nick)
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
                    } else {
                        do {
                            let needletail = NeedleTail.shared
                            guard let store = store else { throw NeedleTailError.storeNotIntitialized }
                            guard let clientInfo = clientInfo else { throw NeedleTailError.clientInfotNotIntitialized }
                            needletail.needletailStore.emitter?.cypher = try await NeedleTail.shared.onBoardAccount(
                                appleToken: "",
                                username: username.raw,
                                store: store,
                                clientInfo: clientInfo,
                                p2pFactories: makeP2PFactories(),
                                eventHandler: nil,
                                needletailStore: NeedleTail.shared.needletailStore
                            )
                        } catch let error as NeedleTailError {
                            if error == .masterDeviceReject {
                                //TODO: Send REJECTED/RETRY Notification
                                print("MASTER_DEVICE_REJECTED_REGISTRATION", error)
                            } else if error == .registrationFailure {
                                //TODO: Send RETRY with new Username Notification
                                print("REGISTRATION_FAILED", error)
                            } else {
                                print(error)
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
        }
        .id(result.debugDescription)
    }
}

@MainActor public func sortConversations(lhs: TargetConversation.Resolved, rhs: TargetConversation.Resolved) -> Bool {
//    let task = Task { @Sendable @MainActor in
        
//        switch (lhs.isPinned, rhs.isPinned) {
//        case (true, true), (false, false):
//            ()
//        case (true, false):
//            return true
//        case (false, true):
//            return false
//        }
        
        
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
//    }
//    return await task.value
}

extension TargetConversation.Resolved: Sendable {}


public func makeP2PFactories() -> [P2PTransportClientFactory] {
    return [
//        IPv6TCPP2PTransportClientFactory()
        //        SpineTailedTransportFactory()
    ]
}

#endif

public class NeedleTailStore {
#if os(iOS) || os(macOS)
    @Published public var emitter: NeedleTailEmitter?
#endif
    public init() {}
}

#if os(iOS) || os(macOS)
extension NeedleTailStore: ObservableObject {}
#endif
