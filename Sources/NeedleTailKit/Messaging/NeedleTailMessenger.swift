//
//  NeedleTailMessenger.swift
//
//
//  Created by Cole M on 4/17/22.
//

import CypherMessaging
import MessagingHelpers
#if canImport(SwiftUI)
import SwiftUI
#endif
import NeedleTailHelpers
import NeedletailMediaKit
import NeedleTailCrypto
//import SpineTailedKit
//import SpineTailedProtocol
#if os(macOS)
import Cocoa
#endif
import DequeModule
#if canImport(Crypto)
@preconcurrency import Crypto
#endif
import SwiftDTF

@NeedleTailMessengerActor
public final class NeedleTailMessenger {
    
    @MainActor
    public let emitter: NeedleTailEmitter
    @MainActor
    public let contactsBundle: ContactsBundle
    public let networkMonitor: NetworkMonitor
    public typealias NTAnyChatMessage = AnyChatMessage
    public typealias NTContact = Contact
    public typealias NTPrivateChat = PrivateChat
    public var cypherTransport: NeedleTailCypherTransport?
    public var messageType: MessageType = .message {
        didSet {
            cypherTransport?.configuration.messageType = messageType
        }
    }
    
    public var multipartMessage: MultipartMessagePacket?
    var registrationApproved = false
    var registeringNewDevice = false
    var plugin: NeedleTailPlugin?
    public var store: CypherMessengerStore?
    public var cypher: CypherMessenger? {
        didSet {
            if let cypher = cypher {
                Task { @MainActor in
                    emitter.cypher = cypher
                    emitter.username = cypher.username
                    emitter.deviceId = cypher.deviceId
                }
            }
        }
    }
#if canImport(Crypto)
    public let needletailCrypto = NeedleTailCrypto()
#endif
    let consumer = NeedleTailAsyncConsumer<TargetConversation.Resolved>()
    let sortChats: @Sendable @MainActor (TargetConversation.Resolved, TargetConversation.Resolved) -> Bool
    
    let priorityActor = PriorityActor()
    @PriorityActor
    public let mediaConsumer = NeedleTailAsyncConsumer<MediaPacket>()
    public struct MediaPacket: Sendable {
        var packet: ThumbnailToMultipart
        var fileData: Data
        var thumbnailData: Data
        
        public init(packet: ThumbnailToMultipart, fileData: Data, thumbnailData: Data) {
            self.packet = packet
            self.fileData = fileData
            self.thumbnailData = thumbnailData
        }
    }
    
    public init(
        emitter: NeedleTailEmitter,
        contactsBundle: ContactsBundle,
        networkMonitor: NetworkMonitor,
        sortChats: @Sendable @MainActor @escaping (TargetConversation.Resolved, TargetConversation.Resolved) -> Bool
    ) async {
        self.emitter = emitter
        self.contactsBundle = contactsBundle
        self.networkMonitor = networkMonitor
        self.sortChats = sortChats
    }
    
    
    /// We are going to run a loop on this actor until the **Child Device** scans the **Master Device's** approval **QRCode**. We then complete the loop in **onBoardAccount()**, finish registering this device locally and then we request the **Master Device** to add the new device to the remote DB before we are allowed spool up an NTK Session.
    /// - Parameter code: The **QR Code** scanned from the **Master Device**
    public func waitForApproval(_ code: String) async throws {
        guard let transportBridge = cypherTransport?.transportBridge else { throw NeedleTailError.transportNotIntitialized }
        let approved = try await transportBridge.processApproval(code)
        registrationApproved = approved
    }
    
    // After the master scans the new device we feed it to cypher in order to add the new device locally and remotely
    public func addNewDevice(_ config: UserDeviceConfig) async throws {
        guard let cypher = cypher else { throw NeedleTailError.cypherMessengerNotSet}
        try await cypherTransport?.transportBridge?.addNewDevice(config, cypher: cypher)
    }
    
    func onBoardAccount(
        appleToken: String,
        username: String,
        store: CypherMessengerStore,
        serverInfo: ClientContext.ServerClientInfo,
        p2pFactories: [P2PTransportClientFactory],
        eventHandler: PluginEventHandler? = nil,
        withChildDevice: Bool = false,
        messenger: NeedleTailMessenger
    ) async throws {
        self.store = store
        plugin = NeedleTailPlugin(messenger: self)
        guard let plugin = plugin else { return }
        
        let cypherTransport = try await createTransport(
            serverInfo: serverInfo,
            plugin: plugin,
            messenger: messenger,
            nameToVerify: username
        )
        let clientInfo = try await setUpClientInfo(
            cypherTransport: cypherTransport,
            nameToVerify: username,
            newHost: ""
        )
        await self.resumeService(
            cypherTransport: cypherTransport,
            clientInfo: clientInfo
        )
        do {
            if await self.emitter.channelIsActive {
                let masterKeyBundle = try await cypherTransport.readKeyBundle(forUsername: Username(username))
                for validatedMaster in try masterKeyBundle.readAndValidateDevices() {
                    guard let nick = NeedleTailNick(name: username, deviceId: validatedMaster.deviceId) else { continue }
                    try await cypherTransport.transportBridge?.requestDeviceRegistration(nick)
                }
                
                //Show the Scanner for scanning the QRCode from the Master Device which is the approval code
                await displayScanner()
                
                try await RunLoop.run(240, sleep: 1, stopRunning: { @NeedleTailMessengerActor [weak self] in
                    guard let self else { return false }
                    var running = true
                    if self.registrationApproved == true {
                        running = false
                    }
                    return running
                })
                
                guard self.registrationApproved == true else {
                    throw NeedleTailError.cannotRegisterNewDevice
                }
                
                try await serviceInterupted(true,  cypherTransport: cypherTransport)
                await removeCypherTransport()
                await setRegistrationState(.deregistered)
                
                self.cypher = try await registerNeedleTail(
                    appleToken: appleToken,
                    username: username,
                    store: store,
                    serverInfo: serverInfo,
                    p2pFactories: p2pFactories,
                    eventHandler: eventHandler,
                    addChildDevice: withChildDevice,
                    messenger: messenger
                )
                Task { @MainActor in
                    emitter.needleTailNick = cypherTransport.configuration.needleTailNick
                }
            }
        } catch let nterror as NeedleTailError {
            switch nterror {
            case .nilUserConfig:
                print("User Does not exist,  proceed...", nterror)
                try await self.serviceInterupted(true, cypherTransport: cypherTransport)
                await removeCypherTransport()
                await setRegistrationState(.deregistered)
                
                do {
                    self.cypher = try await registerNeedleTail(
                        appleToken: appleToken,
                        username: username,
                        store: store,
                        serverInfo: serverInfo,
                        p2pFactories: p2pFactories,
                        eventHandler: eventHandler,
                        messenger: messenger
                    )
                    
                    Task { @MainActor in
                        emitter.needleTailNick = cypherTransport.configuration.needleTailNick
                        dismissUI()
                    }
                } catch {
                    print("ERROR REGISTERING", error)
                }
            default:
                return
            }
        } catch {
            print(error)
            return
        }
    }
    
    func removeCypherTransport() async {
        self.cypherTransport = nil
    }
    
    @MainActor
    private func displayScanner() {
        emitter.showScanner = true
    }
    
    @MainActor
    private func dismissUI() {
#if (os(macOS) || os(iOS))
        emitter.dismissRegistration = true
        emitter.showProgress = false
        contactsBundle.contactBundle = nil
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
        messenger: NeedleTailMessenger
    ) async throws -> CypherMessenger? {
        if cypher == nil {
            //Create plugin here
            plugin = NeedleTailPlugin(messenger: self)
            guard let plugin = plugin else { return nil }
            self.cypher = try await CypherMessenger.registerMessenger(
                username: Username(username),
                appPassword: serverInfo.password,
                usingTransport: { [weak self] transportRequest async throws in
                    guard let self else { fatalError("Reference to self") }
                    let transport = try await self.createTransport(
                        serverInfo: serverInfo,
                        plugin: plugin,
                        messenger: messenger,
                        transportRequest: transportRequest,
                        addChildDevice: addChildDevice
                    )
                    await self.setTransport(transport: transport)
                    let clientInfo = try await setUpClientInfo(
                        cypherTransport: transport,
                        nameToVerify: username,
                        newHost: ""
                    )
                    await self.resumeService(
                        cypherTransport: transport,
                        clientInfo: clientInfo
                    )
                    return transport
                },
                p2pFactories: p2pFactories,
                database: store,
                eventHandler: eventHandler ?? makeEventHandler(plugin)
            )
        }
        return self.cypher
    }
    
    private func createTransport(
        serverInfo: ClientContext.ServerClientInfo,
        plugin: NeedleTailPlugin,
        messenger: NeedleTailMessenger,
        transportRequest: TransportCreationRequest? = nil,
        nameToVerify: String = "",
        addChildDevice: Bool = false
    ) async throws -> NeedleTailCypherTransport {
        let cypherTransport = NeedleTailCypherTransport.authenticate(
            transportRequest: transportRequest,
            serverInfo: serverInfo,
            plugin: plugin,
            messenger: messenger
        )
        cypherTransport.configuration.addChildDevice = addChildDevice
        if !nameToVerify.isEmpty {
            cypherTransport.configuration.registrationState = .temp
        }
        return cypherTransport
    }
    
    public func spoolService(
        appleToken: String,
        store: CypherMessengerStore,
        serverInfo: ClientContext.ServerClientInfo,
        eventHandler: PluginEventHandler? = nil,
        p2pFactories: [P2PTransportClientFactory],
        messenger: NeedleTailMessenger
    ) async throws -> CypherMessenger {
        //Create plugin here
        self.plugin = NeedleTailPlugin(messenger: messenger)
        
        guard let plugin = self.plugin else { fatalError() }
        let cypher = try await CypherMessenger.resumeMessenger(
            appPassword: serverInfo.password,
            usingTransport: { transportRequest -> NeedleTailCypherTransport in
                return try await self.createTransport(
                    serverInfo: serverInfo,
                    plugin: plugin,
                    messenger: messenger,
                    transportRequest: transportRequest
                )
            },
            p2pFactories: p2pFactories,
            database: store,
            eventHandler: eventHandler ?? self.makeEventHandler(plugin)
        )
        let cypherTransport = cypher.transport as! NeedleTailCypherTransport
        await setTransport(transport: cypherTransport)
        return cypher
    }
    
    func setTransport(transport: NeedleTailCypherTransport) async {
        self.cypherTransport = transport
    }
    
    @MainActor
    func setNick(transport: NeedleTailCypherTransport) async {
        emitter.needleTailNick = transport.configuration.needleTailNick
    }
    
    public func connectionAvailability() -> Bool {
        guard let cypherTransport = cypherTransport else { return false }
        if cypherTransport.authenticated == .unauthenticated && cypherTransport.isConnected == false {
            return false
        } else {
            return true
        }
    }
    
    @MainActor
    func setRegistrationState(_ state: ServerConnectionState) async {
#if (os(macOS) || os(iOS))
        emitter.connectionState = state
#endif
    }

    public func resumeService() async throws {
        if let cypherTransport = self.cypherTransport {
            let configuration = cypherTransport.configuration
            guard let nick = configuration.needleTailNick else { return }
            guard let username = configuration.username else { return }
            guard let deviceId = configuration.deviceId else { return }
            await networkServiceResumer(
                cypherTransport,
                clientInfo: NeedleTailCypherTransport.ClientInfo(
                    clientContext:    
                        ClientContext(
                        serverInfo: configuration.serverInfo,
                        nickname: nick
                    ),
                    username: username,
                    deviceId: deviceId
                )
            )
        }
    }

    internal func setUpClientInfo(
        cypherTransport: NeedleTailCypherTransport,
        nameToVerify: String = "",
        newHost: String = ""
    ) async throws -> NeedleTailCypherTransport.ClientInfo {
        let info = try await cypherTransport.setUpClientInfo(nameToVerify: nameToVerify, newHost: newHost)
        await setNick(transport: cypherTransport)
        return info
    }
    
    internal func resumeService(cypherTransport: NeedleTailCypherTransport, clientInfo: NeedleTailCypherTransport.ClientInfo) async {
        do {
        switch await emitter.connectionState {
        case .deregistered, .shouldRegister:
            await setRegistrationState(.registering)
            try await withThrowingTaskGroup(of: Void.self) { group in
                try Task.checkCancellation()
                group.addTask {
                    try await cypherTransport.createClient(
                        cypherTransport,
                        clientInfo: clientInfo
                    )
                }
                _ = try await group.next()
                try await self.monitorClientConnection(cypherTransport)
#if (os(macOS) || os(iOS))
                Task { @MainActor in
                    if let client = cypherTransport.configuration.client {
                        self.emitter.channelIsActive = await client.channelIsActive
                    }
                }
#endif
                group.cancelAll()
            }
        case .deregistering:
            await setRegistrationState(.shouldRegister)
            try await monitorClientConnection(cypherTransport)
        default:
            print("Trying to resume service during a \(await emitter.connectionState) state")
        }
        } catch let error as NIOCore.ChannelError {
            await setErrorReporter(error: error.description)
        } catch {
            await setErrorReporter(error: error.localizedDescription)
        }
    }
    
    private func networkServiceResumer(_
                                       cypherTransport: NeedleTailCypherTransport,
                                       clientInfo: NeedleTailCypherTransport.ClientInfo
    ) async {
        let networkServiceResumerTask = Task {
            return try await withThrowingTaskGroup(of: Void.self, body: { group in
                //We need to make sure we have internet before we try this
                for try await status in self.networkMonitor.$currentStatus.values {
                    try Task.checkCancellation()
                    group.addTask {
                        if status == .satisfied {
                            if cypherTransport.isConnected == false {
                                await self.resumeService(
                                    cypherTransport: cypherTransport,
                                    clientInfo: clientInfo
                                )
                            }
                            return
                        }
                    }
                }
                _ = try await group.next()
                group.cancelAll()
            })
        }
        
        do {
            try await networkServiceResumerTask.value
        } catch {
            if !networkServiceResumerTask.isCancelled {
                networkServiceResumerTask.cancel()
            }
        }
    }
    
    private func setCanRegister(canRegister: Bool) async {
        self.canReregister = canRegister
    }
    var canReregister = false
    func monitorClientConnection(_ cypherTransport: NeedleTailCypherTransport) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for await state in await self.emitter.$connectionState.values {
                try Task.checkCancellation()
                group.addTask {
                    switch state {
                    case .shouldRegister:
                        await self.setCanRegister(canRegister: true)
                    case .registered:
                        await self.setNick(transport: cypherTransport)
                        cypherTransport.isConnected = true
                        cypherTransport.authenticated = .authenticated
                        if await self.cypherTransport?.isConnected == true { return }
                    case .deregistered:
                        cypherTransport.isConnected = false
                        cypherTransport.authenticated = .unauthenticated
                        if await self.canReregister {
                            let clientInfo = try await self.setUpClientInfo(
                                cypherTransport: cypherTransport,
                                nameToVerify: cypherTransport.configuration.username?.raw ?? "",
                                newHost: ""
                            )
                            await self.resumeService(
                                cypherTransport: cypherTransport,
                                clientInfo: clientInfo
                            )
                        }
                    default:
                        ()
                    }
                }
                _ = try await group.next()
                group.cancelAll()
            }
        }
    }
    
    public func serviceInterupted(_ isSuspending: Bool = false) async throws {
        guard let cypherTransport = cypherTransport else { throw NeedleTailError.messengerNotIntitialized }
        try await serviceInterupted(isSuspending, cypherTransport: cypherTransport)
    }
    
    internal func serviceInterupted(_ isSuspending: Bool = false, cypherTransport: NeedleTailCypherTransport) async throws {
        switch await emitter.connectionState {
        case .registered:
            await setRegistrationState(.deregistering)
            try await cypherTransport.transportBridge?.suspendClient(isSuspending)
            await removeClient()
        default:
            break
        }
    }
    
    func removeClient() async {
        cypherTransport?.configuration.client = nil
    }
    
    func removeTransport(_ cypherTransport: NeedleTailCypherTransport) async {
        await cypherTransport.configuration.client?.teardownClient()
    }
    
    public func requestOfflineMessages() async throws {
        guard let cypherTransport = cypherTransport else { throw NeedleTailError.messengerNotIntitialized }
        try await cypherTransport.transportBridge?.requestOfflineMessages()
    }
    
    internal func deleteOfflineMessages(from contact: String) async throws {
        guard let cypherTransport = cypherTransport else { throw NeedleTailError.messengerNotIntitialized }
        try await cypherTransport.transportBridge?.deleteOfflineMessages(from: contact)
    }
    
    internal func notifyContactRemoved(_ contact: Username) async throws {
        guard let cypherTransport = cypherTransport else { throw NeedleTailError.messengerNotIntitialized }
        guard let username = cypherTransport.configuration.username else { throw NeedleTailError.usernameNil }
        guard let deviceId = cypherTransport.configuration.deviceId else { throw NeedleTailError.deviceIdNil }
        try await cypherTransport.transportBridge?.notifyContactRemoved(NTKUser(username: username, deviceId: deviceId), removed: contact)
    }
    
    public func registerAPN(_ token: Data) async throws {
        try await cypherTransport?.transportBridge?.registerAPNSToken(token)
    }
    
    public func blockUnblockUser(_ contact: Contact) async throws {
        cypherTransport?.configuration.messageType = .blockUnblock
        if await contact.isBlocked {
            try await contact.unblock()
        } else {
            try await contact.block()
        }
        await self.updateBundle(contact)
    }
    
    @MainActor
    public func updateBundle(_ contact: Contact) {
        guard var bundle = contactsBundle.contactBundleViewModel.first(where: { $0.contact?.username == contact.username }) else { return }
        bundle.contact = contact
    }
    
    public func beFriend(_ contact: Contact) async throws {
        let undecided = await contact.ourFriendshipState == .undecided
        if await contact.ourFriendshipState == .notFriend || undecided {
            try await contact.befriend()
        } else {
            try await contact.unfriend()
        }
        await updateBundle(contact)
    }
    
    public func addContact(newContact: String, nick: String = "") async throws {
        let username = Username(newContact)
        let chat = try await cypher?.createPrivateChat(with: username)
        let contact = try await cypher?.createContact(byUsername: username)
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
        try await cypherTransport?.createLocalChannel(
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
        try await cypherTransport?.sendMessageReadReceipt()
    }
    
    public func sendReadMessages(count: Int) async throws {
        try await cypherTransport?.sendReadMessages(count: count)
    }
    
    public func downloadMultipart(_ metadata: [String]) async throws {
        try await cypherTransport?.downloadMultipart(metadata)
    }
    
    public func requestBucketContents(_ bucket: String = "MediaBucket") async throws {
        try await cypherTransport?.requestBucketContents(bucket)
    }
}


//SwiftUI Stuff
extension NeedleTailMessenger {
    
    public struct SkeletonView<Content>: View where Content: View {
        
        @StateObject var emitter = NeedleTailEmitter.shared
        @StateObject var contactsBundle = ContactsBundle.shared
        @StateObject var networkMonitor = NetworkMonitor.shared
        
        let content: Content
        
        public init(content: Content) {
            self.content = content
        }
        
        public var body: some View {
            AsyncView(run: { () async throws -> NeedleTailMessenger in
                return await NeedleTailMessenger(
                    emitter: emitter,
                    contactsBundle: contactsBundle,
                    networkMonitor: networkMonitor,
                    sortChats: sortConversations
                )
            }) { messenger in
                content
                    .environment(\.messenger, messenger)
                    .environmentObject(messenger.emitter)
                    .environmentObject(networkMonitor)
                    .environmentObject(contactsBundle)
            }
        }
    }
    
    
    public func spoolService(
        with serverInfo: ClientContext.ServerClientInfo,
        messenger: NeedleTailMessenger,
        store: CypherMessengerStore
    ) async throws {
        if messenger.cypher == nil {
            self.cypher = try await spoolService(
                appleToken: "",
                store: store,
                serverInfo: serverInfo,
                p2pFactories: makeP2PFactories(),
                messenger: messenger
            )
            guard let cypherTransport = cypherTransport else { return }
            let clientInfo = try await self.setUpClientInfo(
                cypherTransport: cypherTransport,
                nameToVerify: cypherTransport.configuration.username?.raw ?? "",
                newHost: ""
            )
                await self.resumeService(
                    cypherTransport: cypherTransport,
                    clientInfo: clientInfo
                )
        }
    }
    
    @MainActor
    private func setErrorReporter(error description: String) {
        emitter.errorReporter = ErrorReporter(status: true, error: description)
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
        @State var buttonTask: Task<(), Error>? = nil
        @Environment(\.messenger) var messenger
        @EnvironmentObject var emitter: NeedleTailEmitter
        
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
            serverInfo: ClientContext.ServerClientInfo? = nil
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
        }
        
        public var body: some View {
            
            Button(buttonTitle, action: {
#if os(iOS)
                UIApplication.shared.endEditing()
#endif
                emitter.showProgress = true
                
                self.buttonTask = Task {
                    if createContact {
                        let newContact = userHandle.lowercased().trimmingCharacters(in: .whitespaces)
                        try await messenger.addContact(newContact: newContact, nick: nick)
                    } else if createChannel {
                        guard let channelName = channelName else { return }
                        guard let admin = admin else { return }
                        guard let organizers = organizers else { return }
                        guard let members = members else { return }
                        guard let permissions = permissions else { return }
                        try await messenger.createLocalChannel(
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
                            
                            try await messenger.onBoardAccount(
                                appleToken: "",
                                username: username.raw,
                                store: store,
                                serverInfo: serverInfo,
                                p2pFactories: makeP2PFactories(),
                                eventHandler: nil,
                                messenger: messenger
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
    
    public struct ThumbnailToMultipart: Sendable {
        public var dtfp: DataToFilePacket
        public var metadata: Document?
        public var symmetricKey: SymmetricKey
        
        public init(
            dtfp: DataToFilePacket,
            metadata: Document?,
            symmetricKey: SymmetricKey
        ) {
            self.dtfp = dtfp
            self.metadata = metadata
            self.symmetricKey = symmetricKey
        }
    }
    
    
    public func encodeDTFP(dtfp: DataToFilePacket) async throws -> ThumbnailToMultipart {
        // Generate the symmetric key for us and the other users to decrypt the blob later
        let symmetricKey = try await needletailCrypto.userInfoKey(UUID().uuidString)
        let encodedKey = try BSONEncoder().encodeData(symmetricKey)
        
        var dtfp = dtfp
        dtfp.symmetricKey = encodedKey
        
        let metadata = try BSONEncoder().encode(dtfp)
        
        return ThumbnailToMultipart(
            dtfp: dtfp,
            metadata: metadata,
            symmetricKey: symmetricKey
        )
    }
    
    //MARK: Outbound
    public func sendMessageThumbnail<Chat: AnyConversation>(
        chat: Chat,
        messageSubtype: String,
        metadata: Document,
        destructionTimer: TimeInterval? = nil
    ) async throws {
        //Save the message for ourselves and send the message to each device
        _ = try await chat.sendRawMessage(
            type: .media,
            messageSubtype: messageSubtype,
            text: "",
            metadata: metadata,
            destructionTimer: destructionTimer,
            preferredPushType: .message
        )
    }
    
    public func sendMultipartMessage(
        dtfp: DataToFilePacket,
        conversationPartner: Username,
        symmetricKey: SymmetricKey
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { @NeedleTailMessengerActor group in
            try Task.checkCancellation()
            guard let cypher = cypher else { return }
            //        1. Access the file locations for both blobs snd decrypt
            let fileBlob = try await needletailCrypto.decryptFile(from: dtfp.fileLocation, cypher: cypher)
            let thumbnailBlob = try await needletailCrypto.decryptFile(from: dtfp.thumbnailLocation, cypher: cypher)
            
            //        2. Encrypt with our symmetric key for share
            let sharedFileBlob = try await needletailCrypto.encrypt(data: fileBlob, symmetricKey: symmetricKey)
            let sharedThumbnailBlob = try await needletailCrypto.encrypt(data: thumbnailBlob, symmetricKey: symmetricKey)
            var dtfp = dtfp
            dtfp.fileBlob = sharedFileBlob
            dtfp.thumbnailBlob = sharedThumbnailBlob
            guard let cypherTransport = cypherTransport else { return }
            let recipientsDevices = try await cypherTransport.readKeyBundle(forUsername: conversationPartner)
            guard let sender = cypherTransport.configuration.needleTailNick else { return }
            
            //For each device we need to upload an object for that device for them
            for device in try recipientsDevices.readAndValidateDevices() {
                group.addTask { @NeedleTailMessengerActor in
                    //create multipart message
                    let packet = MultipartMessagePacket(
                        id: dtfp.mediaId,
                        sender: sender,
                        recipient: NeedleTailNick(
                            name: conversationPartner.raw,
                            deviceId: device.deviceId
                        ),
                        dtfp: dtfp,
                        usersFileName: "\(dtfp.fileName)_\(device.deviceId.raw).\(dtfp.fileType)",
                        usersThumbnailName: "\(dtfp.thumbnailName)_\(device.deviceId.raw).\(dtfp.thumbnailType)"
                    )
                    
                    dtfp.symmetricKey = nil
                    dtfp.fileLocation = ""
                    dtfp.thumbnailLocation = ""
                    try await cypherTransport.uploadMultipart(packet)
                }
            }
            
            //Send for me
            let myDevices = try await cypherTransport.readKeyBundle(forUsername: cypher.username)
            for device in try myDevices.readAndValidateDevices().filter({ $0.deviceId != cypher.deviceId }) {
                group.addTask { @NeedleTailMessengerActor in
                    //create multipart message
                    let packet = MultipartMessagePacket(
                        id: dtfp.mediaId,
                        sender: sender,
                        recipient: NeedleTailNick(
                            name: cypher.username.raw,
                            deviceId: device.deviceId
                        ),
                        dtfp: dtfp,
                        usersFileName: "\(dtfp.fileName)_\(device.deviceId.raw).\(dtfp.fileType)",
                        usersThumbnailName: "\(dtfp.thumbnailName)_\(device.deviceId.raw).\(dtfp.thumbnailType)"
                    )
                    
                    dtfp.symmetricKey = nil
                    dtfp.fileLocation = ""
                    dtfp.thumbnailLocation = ""
                    try await cypherTransport.uploadMultipart(packet)
                }
            }
        }
    }
}

//LocalDB Stuff
extension NeedleTailMessenger {
    
    public func findMessage(from mediaId: String, cypher: CypherMessenger) async throws -> AnyChatMessage? {
        let conversations = try await cypher.listConversations(
            includingInternalConversation: true,
            increasingOrder: sortChats
        )
        for conversation in conversations {
            switch conversation {
            case .privateChat(let privateChat):
                let allMessages = try await privateChat.allMessages(sortedBy: .ascending)
                for message in allMessages {
                    if await message.metadata["mediaId"] as? String == mediaId {
                        return message
                    }
                }
                break
            case .groupChat(_):
                return nil
            case .internalChat(_):
                return nil
            }
        }
        return nil
    }
    
    public func findMessage(by mediaId: String) async -> AnyChatMessage? {
        return await contactsBundle.contactBundle?.messages.async.first(where: { message in
            let id = await message.message.metadata["mediaId"] as? String
            return id == mediaId
        })?.message
    }
    public func findPrivateMessage(by mediaId: String) async throws -> AnyChatMessage? {
        return try await contactsBundle.contactBundle?.chat.allMessages(sortedBy: .ascending).async.first(where: { message in
            let id = await message.metadata["mediaId"] as? String
            return id == mediaId
        })
    }
    public func findMessage(with messageId: UUID) async throws -> AnyChatMessage? {
        return try await contactsBundle.contactBundle?.chat.allMessages(sortedBy: .ascending).async.first(where: { $0.id == messageId })
    }
    
    public func findAllMessages(with mediaId: String) async throws -> [AnyChatMessage] {
        var messages = [AnyChatMessage]()
        guard let contactBundle = contactsBundle.contactBundle else { return [] }
        for try await message in contactBundle.messages.async {
            let id = await message.message.metadata["mediaId"] as? String
            if id == mediaId {
                messages.append(message.message)
            }
        }
        return messages
    }
    
    public func recreateOrRemoveFile(from mediaId: String) async throws {
        if let privateMessage = try await findPrivateMessage(by: mediaId) {
            do {
                guard let thumbnailLocation = await privateMessage.metadata["thumbnailLocation"] as? String else { return }
                guard let keyBinary = await privateMessage.metadata["symmetricKey"] as? Binary else { return }
                let symmetricKey = try BSONDecoder().decodeData(SymmetricKey.self, from: keyBinary.data)
                guard let cypher = cypher else { return }
                let thumbnailBlob = try await needletailCrypto.decryptFile(from: thumbnailLocation, cypher: cypher)
                let newSize = try await ImageProcessor.getNewSize(data: thumbnailBlob, desiredSize: CGSize(width: 600, height: 600), isThumbnail: false)
                let newImage: CGImage = try await ImageProcessor.resize(thumbnailBlob, to: newSize, isThumbnail: false)
                var data: Data?
#if os(iOS)
                data = UIImage(cgImage: newImage).jpegData(compressionQuality: 1.0)
                
#elseif os(macOS)
                data = NSImage(cgImage: newImage, size: newSize).jpegData(size: newSize)
#endif
                guard let data = data else { return }
                guard let sharedFileBlob = try await needletailCrypto.encrypt(data: data, symmetricKey: symmetricKey) else { return }
                let fileType = thumbnailLocation.components(separatedBy: ".").first ?? "jpg"
                
                let fileLocation = try DataToFile.shared.generateFile(
                    data: sharedFileBlob,
                    fileName: "\(UUID().uuidString)_\(cypher.deviceId.raw)",
                    fileType: fileType
                )
                
                let document = await privateMessage.metadata
                var dtfp = try BSONDecoder().decode(DataToFilePacket.self, from: document)
                try await privateMessage.setMetadata(
                    cypher,
                    emitter: emitter,
                    sortChats: sortConversations,
                    run: { props in
                        dtfp.fileLocation = fileLocation
                        return try BSONEncoder().encode(dtfp)
                    })
                
            } catch {
                try await privateMessage.remove()
            }
        } else {
            for message in try await findAllMessages(with: mediaId) {
                try await message.remove()
            }
        }
    }
    
    //MARK: Inbound
    public func fetchConversations(_
                                   cypher: CypherMessenger
    ) async throws -> [TargetConversation.Resolved] {
        let conversations = try await cypher.listConversations(
            includingInternalConversation: true,
            increasingOrder: sortChats
        )
        return conversations
    }
    
    public func fetchContacts(_ cypher: CypherMessenger) async throws -> [Contact] {
        try await cypher.listContacts()
    }
    
    public func fetchGroupChats(_ cypher: CypherMessenger) async throws -> [GroupChat] {
        return await emitter.groupChats
    }
    
    /// `fetchChats()` will fetch all CTK/NTK chats/chat types. That means when this method is called we will get all private chats for the CTK Instance which means all chats on our localDB
    /// that this device has knowledge of. We then can use them in our NeedleTailKit Transport Mechanism.
    /// - Parameters:
    ///   - cypher: **CTK**'s `CypherMessenger` for this Device.
    ///   - contact: The opitional `Contact` we want to use to filter private chats on.
    /// - Returns: An `AnyChatMessageCursor` which references a point in memory of `CypherMessenger`'s `AnyChatMessage`
    public func fetchChats(
        cypher: CypherMessenger,
        contact: Contact? = nil
    ) async {
        do {
            let results = try await fetchConversations(cypher)
            for result in results {
                switch result {
                case .privateChat(let chat):
                    try await getChats(chat: chat, contact: contact)
                case .groupChat(let groupChat):
                    if await !emitter.groupChats.contains(groupChat) {
                    }
                case .internalChat(let chat):
                    try await getChats(chat: chat)
                }
            }
        } catch {
            print(error)
        }
    }
    
    @MainActor
    func getChats<Chat: AnyConversation>(chat: Chat, contact: Contact? = nil) async throws {
        var messages: [NeedleTailMessage] = []
        let username = contact?.username
        
        let cursor = try await chat.cursor(sortedBy: .descending)
        let nextBatch = try await cursor.getMore(50)
        
        for message in nextBatch {
            messages.append(NeedleTailMessage(message: message))
        }
        //maps chat to contact that is in the chat
        if chat is PrivateChat, let contact = contact {
            guard let username = username else { return }
            guard chat.conversation.members.contains(username) else { return }
            
            if let index = contactsBundle.contactBundleViewModel.firstIndex(where: { $0.chat.conversation.id == chat.conversation.id } ) {
                contactsBundle.contactBundleViewModel[index].id = UUID()
                contactsBundle.contactBundleViewModel[index].contact = contact
                contactsBundle.contactBundleViewModel[index].chat = chat
                contactsBundle.contactBundleViewModel[index].messages = messages
                contactsBundle.contactBundleViewModel[index].mostRecentMessage = try await MostRecentMessage(
                    chat: chat as! PrivateChat
                )
                await contactsBundle.arrangeBundle()
            } else {
                let bundle = ContactsBundle.ContactBundle(
                    contact: contact,
                    chat: chat,
                    groupChats: [],
                    cursor: cursor,
                    messages: messages,
                    mostRecentMessage: try await MostRecentMessage(
                        chat: chat as! PrivateChat
                    )
                )
                contactsBundle.contactBundleViewModel.append(bundle)
                await contactsBundle.arrangeBundle()
            }
            
        } else {
            if let index = contactsBundle.contactBundleViewModel.firstIndex(where: { $0.chat.conversation.id == chat.conversation.id } ) {
                contactsBundle.contactBundleViewModel[index].id = UUID()
                contactsBundle.contactBundleViewModel[index].chat = chat
                contactsBundle.contactBundleViewModel[index].messages = messages
                await contactsBundle.arrangeBundle()
            } else {
                let bundle = ContactsBundle.ContactBundle(
                    chat: chat,
                    groupChats: [],
                    cursor: cursor,
                    messages: messages,
                    mostRecentMessage: nil
                )
                contactsBundle.contactBundleViewModel.append(bundle)
                await contactsBundle.arrangeBundle()
            }
        }
    }
    
    @MainActor
    func containsUsername(bundle: ContactsBundle.ContactBundle) async -> Bool {
        contactsBundle.contactBundleViewModel.contains(where: { $0.contact?.username == bundle.contact?.username })
    }
    
    @MainActor
    func firstIndex(bundle: ContactsBundle.ContactBundle) async -> Array.Index {
        guard let index = contactsBundle.contactBundleViewModel.firstIndex(where: { $0.contact?.username == bundle.contact?.username }) else { return 0 }
        return index
    }
    
    public func removeMessages(from contact: Contact, shouldRevoke: Bool = false) async throws {
        guard let cypher = cypher else { return }
        let conversations = try await cypher.listConversations(
            includingInternalConversation: false,
            increasingOrder: sortChats
        )
        
        for conversation in conversations {
            print("START LOOP")
            switch conversation {
            case .privateChat(let privateChat):
                let conversationPartner = await privateChat.conversation.members.contains(contact.username)
                if await privateChat.conversation.members.contains(cypher.username) && conversationPartner {
                    for message in try await privateChat.allMessages(sortedBy: .descending) {
                        let fileLocation = await message.metadata["fileLocation"] as? String
                        let thumbnailLocation = await message.metadata["thumbnailLocation"] as? String
                        
                        if let seperatedFileLocation = fileLocation?.components(separatedBy: "/").last {
                            guard let fileName = seperatedFileLocation.components(separatedBy: ".").first else { fatalError() }
                            guard let fileNameType = seperatedFileLocation.components(separatedBy: ".").last else { fatalError() }
                            try DataToFile.shared.removeItem(fileName: fileName, fileType: fileNameType)
                        }
                        if let seperatedThumbnailLocation = thumbnailLocation?.components(separatedBy: "/").last {
                            guard let thumbnailName = seperatedThumbnailLocation.components(separatedBy: ".").first else { fatalError() }
                            guard let thumbnailNameType = seperatedThumbnailLocation.components(separatedBy: ".").last else { fatalError() }
                            try DataToFile.shared.removeItem(fileName: thumbnailName, fileType: thumbnailNameType)
                        }
                        
                        if shouldRevoke {
                            try await message.revoke()
                        } else {
                            try await message.remove()
                        }
                    }
                }
            default:
                break
            }
        }
        await fetchChats(cypher: cypher, contact: contact)
        await fetchChats(cypher: cypher, contact: contact)
    }
    
    public func removeMessages(
        from conversation: TargetConversation.Resolved,
        contact: Contact? = nil,
        shouldRevoke: Bool
    ) async throws {
        guard let cypher = cypher else { return }
        switch conversation {
        case .privateChat(let privateChat):
            guard let contact = contact else { return }
            let conversationPartner = await privateChat.conversation.members.contains(contact.username)
            if await privateChat.conversation.members.contains(cypher.username) && conversationPartner {
                for message in try await privateChat.allMessages(sortedBy: .descending) {
                    if shouldRevoke {
                        try await message.revoke()
                    } else {
                        try await message.remove()
                    }
                }
            }
        case .internalChat(let internalConversation):
            for message in try await internalConversation.allMessages(sortedBy: .descending) {
                if shouldRevoke {
                    try await message.revoke()
                } else {
                    try await message.remove()
                }
            }
        default:
            break
        }
        
        await fetchChats(cypher: cypher)
    }
    
    
    
    //MARK: Outbound
    public func sendMessage<Chat: AnyConversation>(
        chat: Chat,
        type: CypherMessageType,
        messageSubtype: String? = nil,
        text: String = "",
        dtfp: DataToFilePacket? = nil,
        destructionTimer: TimeInterval? = nil,
        pushType: PushType = .message,
        conversationType: ConversationType,
        mediaId: String = "",
        sender: NeedleTailNick,
        dataCount: Int = 0
    ) async throws {
        
        //Send Message
        _ = try await chat.sendRawMessage(
            type: type,
            messageSubtype: messageSubtype,
            text: text,
            //            metadata: metadata,
            destructionTimer: destructionTimer,
            preferredPushType: pushType
        )
    }
    
    public func sendGroupMessage(message: String) async throws {
        
    }
    
    public func processMediaPacket(message: AnyChatMessage, chat: AnyConversation) async throws {
        await priorityActor.queueThrowingAction(with: .background) {
            for try await result in NeedleTailAsyncSequence(consumer: self.mediaConsumer) {
                switch result {
                case .success(var packet):
                    packet.packet.metadata = nil
                    let thumbnailBox = try await self.emitter.cypher?.encryptLocalFile(packet.thumbnailData)
                    guard let thumbnailBoxData = thumbnailBox?.combined else { return }
                    var dtfp = packet.packet.dtfp
                    let thumbnailLocation = try DataToFile.shared.generateFile(
                        data: thumbnailBoxData,
                        fileName: dtfp.thumbnailName,
                        fileType: dtfp.thumbnailType
                    )
                    
                    let fileBlob = packet.fileData
                    //Encrypt our file for us locally
                    guard let cypher = await self.emitter.cypher else { return }
                    let fileBox = try cypher.encryptLocalFile(fileBlob)
                    guard let fileBoxData = fileBox.combined else { return }
                    
                    let fileLocation = try DataToFile.shared.generateFile(
                        data: fileBoxData,
                        fileName: dtfp.fileName,
                        fileType: dtfp.fileType
                    )
                    guard let mediaId = await message.metadata["mediaId"] as? String else { return }
                    if mediaId == dtfp.mediaId {
                        guard let message = try await chat.allMessages(sortedBy: .descending).async.first(where: { await $0.metadata["mediaId"] as! String == mediaId }) else { throw NeedleTailError.cannotFindChat }
                        
                        try await message.setMetadata(
                            cypher,
                            emitter: self.emitter,
                            sortChats: sortConversations,
                            run: { props in
                                dtfp.fileLocation = fileLocation
                                dtfp.thumbnailLocation = thumbnailLocation
                                return try BSONEncoder().encode(dtfp)
                            })
                        var packet = packet
                        packet.packet.dtfp.fileLocation = await message.metadata["fileLocation"] as! String
                        packet.packet.dtfp.thumbnailLocation = await message.metadata["thumbnailLocation"] as! String
                        
                        guard let privateChat = chat as? PrivateChat else { throw NeedleTailError.cannotFindChat }
                        let symmetricKey = packet.packet.symmetricKey
                        try await self.sendMultipartMessage(
                            dtfp: packet.packet.dtfp,
                            conversationPartner: privateChat.conversationPartner,
                            symmetricKey: symmetricKey
                        )
                    }
                case .consumed:
                    print("PACKET_CONSUMED")
                    return
                }
            }
        }
    }
}

@MainActor
public func sortConversations(lhs: TargetConversation.Resolved, rhs: TargetConversation.Resolved) -> Bool {
    switch (lhs.isPinned(), rhs.isPinned()) {
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

extension EnvironmentValues {
    private struct NeedleTailMessengerKey: EnvironmentKey {
        typealias Value = NeedleTailMessenger?
        
        static let defaultValue: NeedleTailMessenger? = nil
    }
    public var _messenger: NeedleTailMessenger? {
        get {
            self[NeedleTailMessengerKey.self]
        }
        set {
            self[NeedleTailMessengerKey.self] = newValue
        }
    }
    
    public var messenger: NeedleTailMessenger {
        get {
            self[NeedleTailMessengerKey.self]!
        }
        set {
            self[NeedleTailMessengerKey.self] = newValue
        }
    }
    
}

extension NIOCore.ChannelError {
    
    var description: String {
        switch self {
        case .connectPending:
            return "connectPending"
        case .connectTimeout(let timeout):
            return "connectTimeout: \(timeout)"
        case .operationUnsupported:
            return "operationUnsupported"
        case .ioOnClosedChannel:
            return "ioOnClosedChannel"
        case .alreadyClosed:
            return "alreadyClosed"
        case .outputClosed:
            return "outputClosed"
        case .inputClosed:
            return "inputClosed"
        case .eof:
            return "eof"
        case .writeMessageTooLarge:
            return "writeMessageTooLarge"
        case .writeHostUnreachable:
            return "writeHostUnreachable"
        case .unknownLocalAddress:
            return "unknownLocalAddress"
        case .badMulticastGroupAddressFamily:
            return "badMulticastGroupAddressFamily"
        case .badInterfaceAddressFamily:
            return "badInterfaceAddressFamily"
        case .illegalMulticastAddress(let address):
            return "illegalMulticastAddress: \(address)"
        case .multicastNotSupported(let interface):
            return "multicastNotSupported, Interface is: \(interface)"
        case .inappropriateOperationForState:
            return "inappropriateOperationForState"
        case .unremovableHandler:
            return "unremovableHandler"
        }
    }
}
