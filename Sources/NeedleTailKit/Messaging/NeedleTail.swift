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
import DequeModule

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
    public var emitter: NeedleTailEmitter?
    public var state = NetworkMonitor()
    public static let shared = NeedleTail()
    public var messageType: MessageType = .message {
        didSet {
            messenger?.messageType = messageType
        }
    }

    public var multipartMessage: MultipartMessagePacket?
    var registrationApproved = false
    var registeringNewDevice = false
    var plugin: NeedleTailPlugin?
    private var resumeQueue = NeedleTailStack<Int>()
    private var suspendQueue = NeedleTailStack<Int>()
    private var totalResumeRequests = 0
    private var totalSuspendRequests = 0
    private var store: CypherMessengerStore?
    public var chatJobQueue = JobQueue<ChatPacketJob>()
    
    /// We are going to run a loop on this actor until the **Child Device** scans the **Master Device's** approval **QRCode**. We then complete the loop in **onBoardAccount()**, finish registering this device locally and then we request the **Master Device** to add the new device to the remote DB before we are allowed spool up an NTK Session.
    /// - Parameter code: The **QR Code** scanned from the **Master Device**
    public func waitForApproval(_ code: String) async throws {
        guard let transportBridge = messenger?.transportBridge else { throw NeedleTailError.messengerNotIntitialized }
        let approved = try await transportBridge.processApproval(code)
        registrationApproved = approved
    }
    
    // After the master scans the new device we feed it to cypher in order to add the new device locally and remotely
    public func addNewDevice(_ config: UserDeviceConfig) async throws {
        guard let cypher = cypher else { throw NeedleTailError.cypherMessengerNotSet}
        try await messenger?.transportBridge?.addNewDevice(config, cypher: cypher)
    }
    
    func onBoardAccount(
        appleToken: String,
        username: String,
        store: CypherMessengerStore,
        serverInfo: ClientContext.ServerClientInfo,
        p2pFactories: [P2PTransportClientFactory],
        eventHandler: PluginEventHandler? = nil,
        withChildDevice: Bool = false,
        emitter: NeedleTailEmitter
    ) async throws -> CypherMessenger? {
        self.store = store
        plugin = NeedleTailPlugin(emitter: emitter)
        guard let plugin = plugin else { return nil }
        
        let messenger = try await createMessenger(
            serverInfo: serverInfo,
            plugin: plugin,
            emitter: emitter,
            nameToVerify: username
        )
        do {
            let masterKeyBundle = try await messenger.readKeyBundle(forUsername: Username(username))
            for validatedMaster in try masterKeyBundle.readAndValidateDevices() {
                guard let nick = NeedleTailNick(name: username, deviceId: validatedMaster.deviceId) else { continue }
                try await messenger.transportBridge?.requestDeviceRegistration(nick)
            }
            
            //Show the Scanner for scanning the QRCode from the Master Device which is the approval code
            await displayScanner(emitter)
            
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
                serverInfo: serverInfo,
                p2pFactories: p2pFactories,
                eventHandler: eventHandler,
                addChildDevice: withChildDevice,
                emitter: emitter
            )
            Task { @MainActor in
               emitter.cypher = cypher
               emitter.needleTailNick = messenger.needleTailNick
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
                        serverInfo: serverInfo,
                        p2pFactories: p2pFactories,
                        eventHandler: eventHandler,
                        emitter: emitter
                    )
                    Task { @MainActor in
                        emitter.cypher = cypher
                        emitter.needleTailNick = messenger.needleTailNick
                        dismissUI(emitter)
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
    private func displayScanner(_ emitter: NeedleTailEmitter) {
        emitter.showScanner = true
    }
    
    @MainActor
    private func dismissUI(_ emitter: NeedleTailEmitter) {
#if (os(macOS) || os(iOS))
          emitter.dismissRegistration = true
          emitter.showProgress = false
        emitter.bundles.contactBundle = nil
#endif
    }
    
    @discardableResult
    public func registerNeedleTail(
        appleToken: String,
        username: String,
        store: CypherMessengerStore,
        serverInfo: ClientContext.ServerClientInfo,
        p2pFactories: [P2PTransportClientFactory],
        eventHandler: PluginEventHandler? = nil,
        addChildDevice: Bool = false,
        emitter: NeedleTailEmitter
    ) async throws -> CypherMessenger? {
        if cypher == nil {
            //Create plugin here
            plugin = NeedleTailPlugin(emitter: emitter)
            guard let plugin = plugin else { return nil }
            cypher = try await CypherMessenger.registerMessenger(
                username: Username(username),
                appPassword: serverInfo.password,
                usingTransport: { transportRequest async throws -> NeedleTailMessenger in
                    return try await self.createMessenger(
                        serverInfo: serverInfo,
                        plugin: plugin,
                        emitter: emitter,
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
    
    private func createMessenger(
        serverInfo: ClientContext.ServerClientInfo,
        plugin: NeedleTailPlugin,
        emitter: NeedleTailEmitter,
        transportRequest: TransportCreationRequest? = nil,
        nameToVerify: String = "",
        addChildDevice: Bool = false
    ) async throws -> NeedleTailMessenger {
        if self.messenger == nil {
            //We also need to pass the plugin to our transport
            self.messenger = try await NeedleTailMessenger.authenticate(
                transportRequest: transportRequest,
                serverInfo: serverInfo,
                plugin: plugin,
                emitter: emitter
            )
        }
        self.messenger?.addChildDevice = addChildDevice
        guard let messenger = self.messenger else { throw NeedleTailError.messengerNotIntitialized }
        if !nameToVerify.isEmpty {
            messenger.registrationState = .temp
        }
        //We need to make sure we have internet before we try this
        for status in await NeedleTail.shared.state.receiver.statusArray {
            if status == .satisfied {
                if messenger.isConnected == false {
                    try await resumeService(nameToVerify)
                }
            }
        }
        return messenger
    }
    
    @discardableResult
    public func spoolService(
        appleToken: String,
        store: CypherMessengerStore,
        serverInfo: ClientContext.ServerClientInfo,
        eventHandler: PluginEventHandler? = nil,
        p2pFactories: [P2PTransportClientFactory],
        emitter: NeedleTailEmitter
    ) async throws -> CypherMessenger? {
        //Create plugin here
        plugin = NeedleTailPlugin(emitter: emitter)
        guard let plugin = plugin else { return nil }
        cypher = try await CypherMessenger.resumeMessenger(
            appPassword: serverInfo.password,
            usingTransport: { transportRequest -> NeedleTailMessenger in

                return try await self.createMessenger(
                    serverInfo: serverInfo,
                    plugin: plugin,
                    emitter: emitter,
                    transportRequest: transportRequest
                )
                
            },
            p2pFactories: p2pFactories,
            database: store,
            eventHandler: eventHandler ?? makeEventHandler(plugin)
        )
        
        await MainActor.run {
              emitter.needleTailNick = messenger?.needleTailNick
        }
        return self.cypher
    }
    
    public func connectionAvailability() -> Bool {
        guard let messenger = messenger else { return false }
        if messenger.authenticated == .unauthenticated && messenger.isConnected == false {
            return false
        } else {
            return true
        }
    }
    
    private func resumeRequest(_ request: Int) async {
        totalResumeRequests += request
        await resumeQueue.enqueue(totalResumeRequests)
    }
    
    public func resumeService(_
                              nameToVerify: String = "",
                              appleToken: String = "",
                              newHost: String = "")
    async throws {
        guard let messenger = messenger else { throw NeedleTailError.messengerNotIntitialized }
        await resumeRequest(1)
        if await resumeQueue.popFirst() == 1 {
            
            totalSuspendRequests = 0
            await suspendQueue.drain()
            try await messenger.createClient(nameToVerify, newHost: newHost)
            await monitorClientConnection()
        }
    }
    
    func monitorClientConnection() async {
            for await status in NeedleTailEmitter.shared.$clientIsRegistered.values {
                self.messenger?.isConnected = status
                self.messenger?.authenticated = status ? .authenticated : .unauthenticated
                if self.messenger?.isConnected == true { return }
//                if self.messenger?.isConnected == false { return }
        }
    }
    
    private func suspendRequest(_ request: Int) async {
        totalSuspendRequests += request
        await suspendQueue.enqueue(totalSuspendRequests)
    }
    
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
            messenger.client = nil
        }
    }
    @NeedleTailClientActor
    func removeTransport(_ messenger: NeedleTailMessenger) async {
        await messenger.client?.teardownClient()
    }
    
    public func requestOfflineMessages() async throws {
        guard let messenger = messenger else { throw NeedleTailError.messengerNotIntitialized }
        try await messenger.transportBridge?.requestOfflineMessages()
    }
    
    internal func deleteOfflineMessages(from contact: String) async throws {
        guard let messenger = messenger else { throw NeedleTailError.messengerNotIntitialized }
        try await messenger.transportBridge?.deleteOfflineMessages(from: contact)
    }
    
    internal func notifyContactRemoved(_ contact: Username) async throws {
        guard let messenger = messenger else { throw NeedleTailError.messengerNotIntitialized }
        guard let username = messenger.username else { throw NeedleTailError.usernameNil }
        guard let deviceId = messenger.deviceId else { throw NeedleTailError.deviceIdNil }
        try await messenger.transportBridge?.notifyContactRemoved(NTKUser(username: username, deviceId: deviceId), removed: contact)
    }
    
    public func registerAPN(_ token: Data) async throws {
        try await messenger?.transportBridge?.registerAPNSToken(token)
    }
    
    public func blockUnblockUser(_ contact: Contact, emitter: NeedleTailEmitter) async throws {
        messenger?.messageType = .blockUnblock
        if await contact.isBlocked {
            try await contact.unblock()
        } else {
            try await contact.block()
        }
       Task { @MainActor in
        NeedleTail.shared.updateBundle(contact, emitter: emitter)
        }
    }
    
    @MainActor
    public func updateBundle(_ contact: Contact, emitter: NeedleTailEmitter) {
        guard var bundle = emitter.bundles.contactBundleViewModel.first(where: { $0.contact.username == contact.username }) else { return }
        bundle.contact = contact
    }
    
    public func beFriend(_ contact: Contact, emitter: NeedleTailEmitter) async throws {
        let undecided = await contact.ourFriendshipState == .undecided
        if await contact.ourFriendshipState == .notFriend || undecided {
            try await contact.befriend()
        } else {
            try await contact.unfriend()
        }
        Task { @MainActor in
         NeedleTail.shared.updateBundle(contact, emitter: emitter)
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
    
    public func removeDevice(_ id: UUID) async throws {
        let ids = try await store?.fetchDeviceIdentities()
        guard let device = ids?.first(where: { $0.id == id}) else { return }
        try await store?.removeDeviceIdentity(device)
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
            ModifyMessagePlugin(),
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
    
    public func sendMessageReadReceipt() async throws {
        try await messenger?.sendMessageReadReceipt()
    }
    
    public func sendReadMessages(count: Int) async throws {
        try await messenger?.sendReadMessages(count: count)
    }
    
    public func downloadMultipart(_ metadata: [String]) async throws {
        guard let deviceId = messenger?.deviceId else { throw NeedleTailError.deviceIdNil }
        var metadata = metadata
        metadata.append(deviceId.description)
        print("METADATA____", metadata)
        try await messenger?.downloadMultipart(metadata)
    }
}

import NIOTransportServices
//SwiftUI Stuff
extension NeedleTail {
    
    public struct SkeletonView<Content>: View where Content: View {
        
        @StateObject var emitter = NeedleTailEmitter.shared
        let content: Content
        
        public init(content: Content) {
            self.content = content
        }
        
        public var body: some View {
            AsyncView(run: { () async throws -> NeedleTailEmitter in
                return emitter
            }) { emitter in
                content
                    .environmentObject(emitter)
            }
        }
    }
    
    @MainActor
    public func spoolService(
        with serverInfo: ClientContext.ServerClientInfo,
        emitter: NeedleTailEmitter,
        store: CypherMessengerStore
    ) async throws {
        if emitter.cypher == nil {
            emitter.cypher = try await NeedleTail.shared.spoolService(
                appleToken: "",
                store: store,
                serverInfo: serverInfo,
                p2pFactories: makeP2PFactories(),
                emitter: emitter
            )
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
        public var serverInfo: ClientContext.ServerClientInfo? = nil
        public var emitter: NeedleTailEmitter
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
            serverInfo: ClientContext.ServerClientInfo? = nil,
            emitter: NeedleTailEmitter
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
            self.serverInfo = serverInfo
            self.serverInfo?.password = password
            self.emitter = emitter
        }
        
        public var body: some View {
            
            Button(buttonTitle, action: {
#if os(iOS)
                UIApplication.shared.endEditing()
#endif
              emitter.showProgress = true
                
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
                            guard let store = store else { throw NeedleTailError.storeNotIntitialized }
                            guard let serverInfo = serverInfo else { throw NeedleTailError.clientInfotNotIntitialized }
                            emitter.cypher = try await NeedleTail.shared.onBoardAccount(
                                appleToken: "",
                                username: username.raw,
                                store: store,
                                serverInfo: serverInfo,
                                p2pFactories: makeP2PFactories(),
                                eventHandler: nil,
                                emitter: emitter
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
        switch (lhs.isPinned, rhs.isPinned) {
        case (true, true), (false, false):
            ()
        case (true, false):
            return true
        case (false, true):
            return false
        }
        
        
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

extension TargetConversation.Resolved: Sendable {}


public func makeP2PFactories() -> [P2PTransportClientFactory] {
    return [
//        IPv6TCPP2PTransportClientFactory()
        //        SpineTailedTransportFactory()
    ]
}

#endif

#if os(iOS) || os(macOS)

private struct ChatMetadata: Codable {
    var isPinned: Bool?
    var isMarkedUnread: Bool?
}

struct PinnedChatsPlugin: Plugin {
    static let pluginIdentifier = "pinned-chats"
    
    func createPrivateChatMetadata(withUser otherUser: Username, messenger: CypherMessenger) async throws -> Document {
        try BSONEncoder().encode(ChatMetadata(isPinned: false, isMarkedUnread: false))
    }
}

extension AnyConversation {

    @MainActor
    public var isPinned: Bool {
        (try? self.conversation.getProp(
            ofType: ChatMetadata.self,
            forPlugin: PinnedChatsPlugin.self,
            run: \.isPinned
        )) ?? false
    }

    @MainActor
    public var isMarkedUnread: Bool {
        (try? self.conversation.getProp(
            ofType: ChatMetadata.self,
            forPlugin: PinnedChatsPlugin.self,
            run: \.isMarkedUnread
        )) ?? false
    }
    
    public func pin() async throws {
        try await modifyMetadata(
            ofType: ChatMetadata.self,
            forPlugin: PinnedChatsPlugin.self
        ) { metadata in
            metadata.isPinned = true
        }
    }
    
    public func unpin() async throws {
        try await modifyMetadata(
            ofType: ChatMetadata.self,
            forPlugin: PinnedChatsPlugin.self
        ) { metadata in
            metadata.isPinned = false
        }
    }
    
    @MainActor
    public func markUnread() async throws {
        try await modifyMetadata(
            ofType: ChatMetadata.self,
            forPlugin: PinnedChatsPlugin.self
        ) { metadata in
            metadata.isMarkedUnread = true
        }
    }
    
    @MainActor
    public func unmarkUnread() async throws {
        try await modifyMetadata(
            ofType: ChatMetadata.self,
            forPlugin: PinnedChatsPlugin.self
        ) { metadata in
            metadata.isMarkedUnread = false
        }
    }
}
public struct ModifyMessagePlugin: Plugin {
    public static let pluginIdentifier = "@/messaging/mutate-history"
    
    @MainActor public func onReceiveMessage(_ message: ReceivedMessageContext) async throws -> ProcessMessageAction? {
        guard
            message.message.messageType == .magic,
            var subType = message.message.messageSubtype,
            subType.hasPrefix("@/messaging/mutate-history/")
        else {
            return nil
        }
        
        subType.removeFirst("@/messaging/mutate-history/".count)
        let remoteId = message.message.text
        let sender = message.sender.username
        
        switch subType {
        case "revoke":
            let message = try await message.conversation.message(byRemoteId: remoteId)
            if message.sender == sender {
                // Message was sent by this user, so the action is permitted
                try await message.remove()
            }
            
            return .ignore
        default:
            return .ignore
        }
    }
    
    @CryptoActor public func onSendMessage(
        _ message: SentMessageContext
    ) async throws -> SendMessageAction? {
        guard
            message.message.messageType == .magic,
            let subType = message.message.messageSubtype,
            subType.hasPrefix("@/messaging/mutate-history/")
        else {
            return nil
        }
        
        return .send
    }
}
#endif
