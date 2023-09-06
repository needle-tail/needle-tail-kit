//
//  NeedleTailMessenger.swift
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
#if canImport(Crypto)
import Crypto
#endif
import SwiftDTF
#if os(iOS) || os(macOS)
@NeedleTailMessengerActor
public final class NeedleTailMessenger {
    
    @MainActor
    public let emitter: NeedleTailEmitter
    public let networkMonitor: NetworkMonitor
    public typealias NTAnyChatMessage = AnyChatMessage
    public typealias NTContact = Contact
    public typealias NTPrivateChat = PrivateChat
    @NeedleTailTransportActor
    public var cypherTransport: NeedleTailCypherTransport?
    @NeedleTailTransportActor
    public var messageType: MessageType = .message {
        didSet {
            cypherTransport?.configuration.messageType = messageType
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
    public var store: CypherMessengerStore?
    public var cypher: CypherMessenger? {
        didSet {
            if let cypher = cypher {
                Task { @MainActor in
                    emitter.username = cypher.username
                    emitter.deviceId = cypher.deviceId
                }
            }
        }
    }
#if canImport(Crypto)
    let needletailCrypto = NeedleTailCrypto()
#endif
    let consumer = NeedleTailAsyncConsumer<TargetConversation.Resolved>()
    let sortChats: @MainActor (TargetConversation.Resolved, TargetConversation.Resolved) -> Bool
    
    
    public init(
        emitter: NeedleTailEmitter,
        networkMonitor: NetworkMonitor,
        sortChats: @escaping @MainActor (TargetConversation.Resolved, TargetConversation.Resolved) -> Bool
    ) {
        self.emitter = emitter
        self.networkMonitor = networkMonitor
        self.sortChats = sortChats
    }
    
    
    /// We are going to run a loop on this actor until the **Child Device** scans the **Master Device's** approval **QRCode**. We then complete the loop in **onBoardAccount()**, finish registering this device locally and then we request the **Master Device** to add the new device to the remote DB before we are allowed spool up an NTK Session.
    /// - Parameter code: The **QR Code** scanned from the **Master Device**
    public func waitForApproval(_ code: String) async throws {
        guard let transportBridge = await cypherTransport?.transportBridge else { throw NeedleTailError.messengerNotIntitialized }
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
        
        let cypherTransport = try await createMessenger(
            serverInfo: serverInfo,
            plugin: plugin,
            messenger: messenger,
            nameToVerify: username
        )
        do {
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
        } catch let nterror as NeedleTailError {
            switch nterror {
            case .nilUserConfig:
                print("User Does not exist,  proceed...", nterror)
                try await self.serviceInterupted(true, cypherTransport: cypherTransport)
                await removeCypherTransport()
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
    
    @NeedleTailTransportActor
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
        messenger: NeedleTailMessenger
    ) async throws -> CypherMessenger? {
        if cypher == nil {
            //Create plugin here
            plugin = NeedleTailPlugin(messenger: self)
            guard let plugin = plugin else { return nil }
            self.cypher = try await CypherMessenger.registerMessenger(
                username: Username(username),
                appPassword: serverInfo.password,
                usingTransport: { transportRequest async throws -> NeedleTailCypherTransport in
                    return try await self.createMessenger(
                        serverInfo: serverInfo,
                        plugin: plugin,
                        messenger: messenger,
                        transportRequest: transportRequest,
                        addChildDevice: addChildDevice
                    )
                },
                p2pFactories: p2pFactories,
                database: store,
                eventHandler: eventHandler ?? makeEventHandler(plugin)
            )
        }
        return self.cypher
    }
    
    @NeedleTailTransportActor
    private func createMessenger(
        serverInfo: ClientContext.ServerClientInfo,
        plugin: NeedleTailPlugin,
        messenger: NeedleTailMessenger,
        transportRequest: TransportCreationRequest? = nil,
        nameToVerify: String = "",
        addChildDevice: Bool = false
    ) async throws -> NeedleTailCypherTransport {
        if self.cypherTransport == nil {
            //We also need to pass the plugin to our transport
            self.cypherTransport = NeedleTailCypherTransport.authenticate(
                transportRequest: transportRequest,
                serverInfo: serverInfo,
                plugin: plugin,
                messenger: messenger
            )
        }
        self.cypherTransport?.configuration.addChildDevice = addChildDevice
        guard let cypherTransport = self.cypherTransport else { throw NeedleTailError.messengerNotIntitialized }
        if !nameToVerify.isEmpty {
            cypherTransport.configuration.registrationState = .temp
        }
        Task {
            try await withThrowingTaskGroup(of: Void.self, body: { group in
                try Task.checkCancellation()
                group.addTask { [weak self] in
                    guard let self else { return }
                    //We need to make sure we have internet before we try this
                    for await status in self.networkMonitor.$currentStatus.values {
                        if status == .satisfied {
                            if cypherTransport.isConnected == false {
                                try await self.resumeService(nameToVerify)
                            }
                            return
                        }
                    }
                }
                _ = try await group.next()
                group.cancelAll()
            })
        }
        return cypherTransport
    }
    
    @discardableResult
    public func spoolService(
        appleToken: String,
        store: CypherMessengerStore,
        serverInfo: ClientContext.ServerClientInfo,
        eventHandler: PluginEventHandler? = nil,
        p2pFactories: [P2PTransportClientFactory],
        messenger: NeedleTailMessenger
    ) async throws -> CypherMessenger? {
        //Create plugin here
        self.plugin = NeedleTailPlugin(messenger: messenger)
        
        guard let plugin = self.plugin else { return nil }
        self.cypher = try await CypherMessenger.resumeMessenger(
            appPassword: serverInfo.password,
            usingTransport: { transportRequest -> NeedleTailCypherTransport in
                return try await self.createMessenger(
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
        await self.setNick()
        return self.cypher
    }
    
    @MainActor
    func setNick() async {
        emitter.needleTailNick = await cypherTransport?.configuration.needleTailNick
    }
    
    @NeedleTailTransportActor
    public func connectionAvailability() -> Bool {
        guard let cypherTransport = cypherTransport else { return false }
        if cypherTransport.authenticated == .unauthenticated && cypherTransport.isConnected == false {
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
        guard let cypherTransport = await cypherTransport else { throw NeedleTailError.messengerNotIntitialized }
        await resumeRequest(1)
        if await resumeQueue.popFirst() == 1 {
            
            totalSuspendRequests = 0
            await suspendQueue.drain()
            try await cypherTransport.createClient(nameToVerify, newHost: newHost)
            await monitorClientConnection()
        }
    }
    
    @NeedleTailTransportActor
    func monitorClientConnection() async {
        //            for await status in NeedleTailEmitter.shared.$clientIsRegistered.values {
        for await status in await emitter.$clientIsRegistered.values {
            self.cypherTransport?.isConnected = status
            self.cypherTransport?.authenticated = status ? .authenticated : .unauthenticated
            if self.cypherTransport?.isConnected == true { return }
            //                if self.messenger?.isConnected == false { return }
        }
    }
    
    private func suspendRequest(_ request: Int) async {
        totalSuspendRequests += request
        await suspendQueue.enqueue(totalSuspendRequests)
    }
    
    public func serviceInterupted(_ isSuspending: Bool = false) async throws {
        guard let cypherTransport = await cypherTransport else { throw NeedleTailError.messengerNotIntitialized }
        try await serviceInterupted(isSuspending, cypherTransport: cypherTransport)
    }
    
    internal func serviceInterupted(_ isSuspending: Bool = false, cypherTransport: NeedleTailCypherTransport) async throws {
        await suspendRequest(1)
        if await suspendQueue.popFirst() == 1 {
            totalResumeRequests = 0
            await resumeQueue.drain()
            try await cypherTransport.transportBridge?.suspendClient(isSuspending)
            await removeClient()
        }
    }
    
    @NeedleTailTransportActor
    func removeClient() async {
        cypherTransport?.configuration.client = nil
    }
    
    @NeedleTailClientActor
    func removeTransport(_ cypherTransport: NeedleTailCypherTransport) async {
        await cypherTransport.configuration.client?.teardownClient()
    }
    
    @NeedleTailTransportActor
    public func requestOfflineMessages() async throws {
        guard let cypherTransport = cypherTransport else { throw NeedleTailError.messengerNotIntitialized }
        try await cypherTransport.transportBridge?.requestOfflineMessages()
    }
    
    @NeedleTailTransportActor
    internal func deleteOfflineMessages(from contact: String) async throws {
        guard let cypherTransport = cypherTransport else { throw NeedleTailError.messengerNotIntitialized }
        try await cypherTransport.transportBridge?.deleteOfflineMessages(from: contact)
    }
    
    @NeedleTailTransportActor
    internal func notifyContactRemoved(_ contact: Username) async throws {
        guard let cypherTransport = cypherTransport else { throw NeedleTailError.messengerNotIntitialized }
        guard let username = cypherTransport.configuration.username else { throw NeedleTailError.usernameNil }
        guard let deviceId = cypherTransport.configuration.deviceId else { throw NeedleTailError.deviceIdNil }
        try await cypherTransport.transportBridge?.notifyContactRemoved(NTKUser(username: username, deviceId: deviceId), removed: contact)
    }
    
    public func registerAPN(_ token: Data) async throws {
        try await cypherTransport?.transportBridge?.registerAPNSToken(token)
    }
    
    @NeedleTailTransportActor
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
        guard var bundle = emitter.bundles.contactBundleViewModel.first(where: { $0.contact.username == contact.username }) else { return }
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
    
    @NeedleTailTransportActor
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
            //            MessageDataToFilePlugin(),
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
    
    public func requestBucketContents(_ bucket: String = "MultipartBucket") async throws {
        try await cypherTransport?.requestBucketContents(bucket)
    }
}


//SwiftUI Stuff
extension NeedleTailMessenger {
    
    public struct SkeletonView<Content>: View where Content: View {
        
        @StateObject var emitter = NeedleTailEmitter.shared
        @StateObject var networkMonitor = NetworkMonitor.shared
        
        let content: Content
        
        public init(content: Content) {
            self.content = content
        }
        
        public var body: some View {
            AsyncView(run: { () async throws -> NeedleTailMessenger in
                return await NeedleTailMessenger(
                    emitter: emitter,
                    networkMonitor: networkMonitor,
                    sortChats: sortConversations
                )
            }) { messenger in
                content
                    .environment(\.messenger, messenger)
                    .environmentObject(messenger.emitter)
                    .environmentObject(networkMonitor)
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
                        try await messenger.addContact(newContact: userHandle, nick: nick)
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
    
    public struct ThumbnailToMultipart {
        public var dtfp: DataToFilePacket
        public var symmetricKey: SymmetricKey
        public init(
            dtfp: DataToFilePacket,
            symmetricKey: SymmetricKey
        ) {
            self.dtfp = dtfp
            self.symmetricKey = symmetricKey
        }
    }
    
    //MARK: Outbound
    public func sendMessageThumbnail<Chat: AnyConversation>(
        chat: Chat,
        messageSubtype: String,
        dtfp: DataToFilePacket,
        destructionTimer: TimeInterval? = nil,
        fileURL: URL?,
        fileData: Data?,
        thumbnailData: Data
    ) async throws -> ThumbnailToMultipart? {
        guard let cypher = cypher else { return nil }
        
        //Encrypt our file for us locally
        let thumbnailBox = try cypher.encryptLocalFile(thumbnailData)
        guard let thumbnailBoxData = thumbnailBox.combined else { return nil }
        
        let thumbnailLocation = try DataToFile.shared.generateFile(
            data: thumbnailBoxData,
            fileName: dtfp.thumbnailName,
            fileType: dtfp.thumbnailType
        )
        
        var fileBlob: Data?
        if let fileURL = fileURL {
            fileBlob = try DataToFile.shared.generateData(from: fileURL.absoluteString)
            let fileName = fileURL.lastPathComponent.components(separatedBy: ".")
            try DataToFile.shared.removeItem(fileName: fileName[0], fileType: fileName[1])
        } else {
            fileBlob = fileData
        }
        guard let fileBlob = fileBlob else { return nil }
        //Encrypt our file for us locally
        let fileBox = try cypher.encryptLocalFile(fileBlob)
        guard let fileBoxData = fileBox.combined else { return nil }
        
        let fileLocation = try DataToFile.shared.generateFile(
            data: fileBoxData,
            fileName: dtfp.fileName,
            fileType: dtfp.fileType
        )
        
        // Generate the symmetric key for us and the other users to decrypt the blob later
        let symmetricKey = needletailCrypto.userInfoKey(UUID().uuidString)
        let encodedKey = try BSONEncoder().encode(symmetricKey).makeData()
        
        var dtfp = dtfp
        dtfp.fileLocation = fileLocation
        dtfp.thumbnailLocation = thumbnailLocation
        dtfp.symmetricKey = encodedKey
        
        
        let metadata = try BSONEncoder().encode(dtfp)
        
        //Save the message for ourselves and send the message to each device
        _ = try await chat.sendRawMessage(
            type: .media,
            messageSubtype: messageSubtype,
            text: "",
            metadata: metadata,
            destructionTimer: destructionTimer,
            preferredPushType: .message
        )
        return ThumbnailToMultipart(
            dtfp: dtfp,
            symmetricKey: symmetricKey
        )
    }
    
    public func sendMultipartMessage(
        dtfp: DataToFilePacket,
        conversationPartner: Username,
        symmetricKey: SymmetricKey
    ) async throws {
        guard let cypher = cypher else { return }
        //        1. Access the file locations for both blobs snd decrypt
        let fileBlob = try await needletailCrypto.decryptFile(from: dtfp.fileLocation, cypher: cypher)
        let thumbnailBlob = try await needletailCrypto.decryptFile(from: dtfp.thumbnailLocation, cypher: cypher)
        
        //        2. Encrypt with our symmetric key for share
        let sharedFileBlob = try needletailCrypto.encrypt(data: fileBlob, symmetricKey: symmetricKey)
        let sharedThumbnailBlob = try needletailCrypto.encrypt(data: thumbnailBlob, symmetricKey: symmetricKey)
        var dtfp = dtfp
        dtfp.fileBlob = sharedFileBlob
        dtfp.thumbnailBlob = sharedThumbnailBlob
        guard let cypherTransport = await cypherTransport else { return }
        let recipientsDevices = try await cypherTransport.readKeyBundle(forUsername: conversationPartner)
        guard let sender = cypherTransport.configuration.needleTailNick else { return }
        
        //For each device we need to upload an object for that device for them
        for device in try recipientsDevices.readAndValidateDevices() {
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
        
        //Send for me
        let myDevices = try await cypherTransport.readKeyBundle(forUsername: cypher.username)
        for device in try myDevices.readAndValidateDevices().filter({ $0.deviceId != cypher.deviceId }) {
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
    
    enum SampleError: Error {
        case usernameIsNil
    }
}

//LocalDB Stuff
extension NeedleTailMessenger {
    
    
    public func findMessage(by mediaId: String) async -> AnyChatMessage? {
        return await emitter.bundles.contactBundle?.messages.async.first(where: { message in
            let id = await message.message.metadata["mediaId"] as? String
            return id == mediaId
        })?.message
    }
    public func findPrivateMessage(by mediaId: String) async throws -> AnyChatMessage? {
        return try await emitter.bundles.contactBundle?.privateChat.allMessages(sortedBy: .ascending).async.first(where: { message in
            let id = await message.metadata["mediaId"] as? String
            return id == mediaId
        })
    }
    
    public func findAllMessages(with mediaId: String) async throws -> [AnyChatMessage] {
        var messages = [AnyChatMessage]()
        guard let contactBundle = await emitter.bundles.contactBundle else { return [] }
        for try await message in contactBundle.messages.async {
            let id = await message.message.metadata["mediaId"] as? String
            if id == mediaId {
                messages.append(message.message)
            }
        }
        return messages
    }
    
    //MARK: Inbound
    public func fetchConversations(_
                                   cypher: CypherMessenger
    ) async throws {
        let conversations = try await cypher.listConversations(
            includingInternalConversation: true,
            increasingOrder: sortChats
        )
        await consumer.feedConsumer(conversations)
    }
    
    public func fetchContacts(_ cypher: CypherMessenger) async throws -> [Contact] {
        try await cypher.listContacts()
    }
    
    public func fetchGroupChats(_ cypher: CypherMessenger) async throws -> [GroupChat] {
        return await emitter.groupChats
    }
    
    @MainActor
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
            try await fetchConversations(cypher)
            for try await result in NeedleTailAsyncSequence(consumer: consumer) {
                switch result {
                case .success(let result):
                    switch result {
                    case .privateChat(let privateChat):
                        
                        var messages: [NeedleTailMessage] = []
                        
                        guard let username = contact?.username else { return }
                        if privateChat.conversation.members.contains(username) {
                            let cursor = try await privateChat.cursor(sortedBy: .descending)
                            let nextBatch = try await cursor.getMore(50)
                            
                            for message in nextBatch {
                                messages.append(NeedleTailMessage(message: message))
                            }
                            
                            guard let contact = contact else { return }
                            let bundle = ContactsBundle.ContactBundle(
                                contact: contact,
                                privateChat: privateChat,
                                groupChats: [],
                                cursor: cursor,
                                messages: messages,
                                mostRecentMessage: try await MostRecentMessage(
                                    chat: privateChat
                                )
                            )
                            
                            if emitter.bundles.contactBundleViewModel.contains(where: { $0.contact.username == bundle.contact.username }) {
                                guard let index = emitter.bundles.contactBundleViewModel.firstIndex(where: { $0.contact.username == bundle.contact.username }) else { return }
                                emitter.bundles.contactBundleViewModel[index] = bundle
                            } else {
                                emitter.bundles.contactBundleViewModel.append(bundle)
                            }
                            emitter.bundles.arrangeBundle()
                        }
                    case .groupChat(let groupChat):
                        if !emitter.groupChats.contains(groupChat) {
                            emitter.groupChats.append(groupChat)
                        }
                    case .internalChat(_):
                        return
                    }
                    break
                case .finished:
                    return
                }
            }
        } catch {
            print(error)
        }
        return
    }
    
    public func removeMessages(from contact: Contact) async throws {
        guard let cypher = cypher else { return }
        let conversations = try await cypher.listConversations(
            includingInternalConversation: false,
            increasingOrder: sortChats
        )
        
        for conversation in conversations {
            
            switch conversation {
            case .privateChat(let privateChat):
                let conversationPartner = await privateChat.conversation.members.contains(contact.username)
                if await privateChat.conversation.members.contains(cypher.username) && conversationPartner {
                    for message in try await privateChat.allMessages(sortedBy: .descending) {
                        try await message.remove()
                    }
                }
            default:
                break
            }
        }
        await fetchChats(cypher: cypher, contact: contact)
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


#endif
#endif
