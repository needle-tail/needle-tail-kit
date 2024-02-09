//
//  TransportBridge.swift
//
//
//  Created by Cole M on 2/9/23.
//

import NeedleTailHelpers
import CypherMessaging
import JWTKit
import NeedleTailProtocol
import NIOCore

protocol TransportBridge: AnyObject {
    
    func processStream(
        childChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>,
        store: TransportStore
    ) async throws
    func resumeClient(
        writer: NeedleTailWriter,
        type: RegistrationType,
        state: RegistrationState?
    ) async throws
    func suspendClient(_ isSuspending: Bool) async throws
    func sendMessage(
        message: RatchetedCypherMessage,
        toUser username: Username,
        otherUserDeviceId deviceId: DeviceId,
        pushType: PushType,
        messageId: String,
        type: ConversationType,
        readReceipt: ReadReceipt?
    ) async throws
    func sendReadReceiptMessage(
        recipient: NTKUser,
        pushType: PushType,
        type: ConversationType,
        readReceipt: ReadReceipt
    ) async throws -> (Bool, ReadReceipt.State)
    func readKeyBundle(_ username: Username) async throws -> UserConfig
    func publishKeyBundle(_
                          data: UserConfig,
                          appleToken: String,
                          nameToVerify: String,
                          recipientDeviceId: DeviceId?
    ) async throws
    func requestDeviceRegistration(_ nick: NeedleTailNick) async throws
    func requestDeviceRegistery(_ config: UserDeviceConfig, addChildDevice: Bool, appleToken: String) async throws
    func publishBlob<C>(_ blob: C) async throws -> ReferencedBlob<C> where C : Decodable, C : Encodable
    func createNeedleTailChannel(
        name: String,
        admin: NeedleTailNick,
        organizers: Set<Username>,
        members: Set<Username>,
        permissions: IRCChannelMode
    ) async throws
    func registerAPNSToken(_ token: Data) async throws
    func processApproval(_ code: String) async throws -> Bool
    func addNewDevice(_ config: UserDeviceConfig, cypher: CypherMessenger) async throws
    func requestOfflineMessages() async throws
    func deleteOfflineMessages(from contact: String) async throws
    func notifyContactRemoved(_ ntkUser: NTKUser, removed contact: Username) async throws
    func sendReadMessages(count: Int) async throws
    func downloadMultipart(_ metadata: [String]) async throws
    func uploadMultipart(_ packet: MultipartMessagePacket) async throws
    func requestBucketContents(_ bucket: String) async throws
}


extension NeedleTailClient: TransportBridge {
    
    func addNewDevice(_ config: UserDeviceConfig, cypher: CypherMessenger) async throws {
        //set the recipient Device Id so that the server knows which device is requesting this addition
        transportConfiguration.recipientDeviceId = config.deviceId
        try await cypher.addDevice(config)
    }
    
    func createNeedleTailChannel(
        name: String,
        admin: NeedleTailHelpers.NeedleTailNick,
        organizers: Set<CypherProtocol.Username>,
        members: Set<CypherProtocol.Username>,
        permissions: NeedleTailHelpers.IRCChannelMode
    ) async throws {
        try await writer?.createNeedleTailChannel(
            name: name,
            admin: admin,
            organizers: organizers,
            members: members,
            permissions: permissions
        )
    }
    
    
    func sendMessage(
        message: CypherProtocol.RatchetedCypherMessage,
        toUser username: CypherProtocol.Username,
        otherUserDeviceId deviceId: CypherProtocol.DeviceId,
        pushType: CypherMessaging.PushType,
        messageId: String,
        type: ConversationType,
        readReceipt: ReadReceipt?
    ) async throws {
        guard let writer = writer else { throw NeedleTailError.writerNotSet }
        switch type {
        case .groupMessage(let name):
            try await writer.createGroupMessage(
                messageId: messageId,
                pushType: pushType,
                message: message,
                channelName: name,
                toUser: NTKUser(
                    username: username,
                    deviceId: deviceId
                ),
                fromUser: configuration.ntkUser,
                messageType: .message,
                conversationType: type,
                readReceipt: readReceipt
            )
        case .privateMessage:
            try await writer.createPrivateMessage(
                messageId: messageId,
                pushType: pushType,
                message: message,
                toUser: NTKUser(
                    username: username,
                    deviceId: deviceId
                ),
                fromUser: configuration.ntkUser,
                messageType: .message,
                conversationType: type,
                readReceipt: readReceipt
            )
        }
    }
    
    func sendReadReceiptMessage(
        recipient: NTKUser,
        pushType: CypherMessaging.PushType,
        type: NeedleTailHelpers.ConversationType,
        readReceipt: NeedleTailHelpers.ReadReceipt
    ) async throws -> (Bool, ReadReceipt.State) {
        switch type {
        case .privateMessage:
            try await writer?.createReadReceiptMessage(
                pushType: .none,
                toUser: recipient,
                messageType: .readReceipt,
                conversationType: .privateMessage,
                readReceipt: readReceipt
            )
        default:
            break
        }
        
        //ACK
        //TODO: LETS NOT RUNLOOP
        try await RunLoop.run(20, sleep: 1, stopRunning: { [weak self] in
            guard let strongSelf = self else { return false }
            var running = true
            if await strongSelf.store?.acknowledgment == .readReceipt {
                running = false
            }
            return running
        })
        return await (store?.acknowledgment == .readReceipt ? true : false, readReceipt.state)
    }
    
    func publishBlob<C>(_ blob: C) async throws -> CypherMessaging.ReferencedBlob<C> where C : Decodable, C : Encodable, C : Sendable {
        let blobString = try BSONEncoder().encodeString(blob)
        try await writer?.publishBlob(blobString)
        guard let stream = stream else { throw NeedleTailError.streamNotSet }
        guard let channelBlob = await stream.channelBlob else { throw NeedleTailError.nilBlob }
        guard let data = Data(base64Encoded: channelBlob) else { throw NeedleTailError.nilData }
        let blob = try BSONDecoder().decodeData(NeedleTailHelpers.Blob<C>.self, from: data)
        return ReferencedBlob(id: blob._id, blob: blob.document)
    }
    
    
    func requestDeviceRegistery(_ config: CypherMessaging.UserDeviceConfig, addChildDevice: Bool, appleToken: String) async throws {
        switch await transportConfiguration.transportState.current {
        case .transportOffline:
            guard let writer = writer else { return }
            try await startSession(
                writer: writer,
                type: registrationType(appleToken),
                state: registrationState
            )
        default:
            break
        }
        
        //rebuild the device config sp we can create a master device
        let newMaster = UserDeviceConfig(
            deviceId: config.deviceId,
            identity: config.identity,
            publicKey: config.publicKey,
            isMasterDevice: false
        )
        //        logger.info("We are requesting a Device Registry with this configuration: \(newMaster)")
        
        if addChildDevice {
            let masterKeyBundle = try await readKeyBundle(configuration.ntkUser.username)
            for validatedMaster in try masterKeyBundle.readAndValidateDevices() {
                guard let nick = NeedleTailNick(name: configuration.ntkUser.username.raw, deviceId: validatedMaster.deviceId) else { continue }
                
                try await writer?.sendChildDeviceConfig(nick, config: newMaster)
            }
        } else {
            let base64String = try BSONEncoder().encodeString(newMaster)
            let data = base64String.data(using: .ascii)
#if (os(macOS) || os(iOS))
            await configuration.ntkBundle.cypherTransport.updateEmitter(data)
            try await RunLoop.run(240, sleep: 1) { @MainActor [weak self] in
                guard let self else { return false }
                var running = true
                
                if await transportConfiguration.messenger.emitter.qrCodeData == nil {
                    running = false
                }
                return running
            }
#endif
        }
    }
    
    func readKeyBundle(_ username: Username) async throws -> UserConfig {
//        let task = Task {
            guard let stream = stream else { throw NeedleTailError.streamNotSet }
            let store = await stream.configuration.store
            await store.clearUserConfig()

            let jwt = try self.makeToken(configuration.ntkUser.username)
            let readBundleObject = await self.readBundleRequest(jwt, for: username)
            let packet = try BSONEncoder().encodeString(readBundleObject)
            try await stream.readKeyBundle(packet)
            
//            let result = try await withThrowingTaskGroup(of: UserConfig?.self) { group in
//                try Task.checkCancellation()
print("__________READING BUNDLE___________")
                   let result = try await RunLoop.runKeyRequestLoop(15,canRun: true, sleep: 1) {
                        var bundle: UserConfig?
                        var canRun = true
                            if let keyBundle = await store.keyBundle {
                                canRun = false
                                bundle = keyBundle
                            }
                        return (canRun, bundle)
                    }
//                }
        print("__________READ BUNDLE___________")
//        guard let result = result else { throw NeedleTailError.emitterIsNil }
            return result!
//                return try await group.next()
//            }
//        return try await task.value!
//        }
        
//        guard let unwrapedTaskValue = try await task.value else {
//            throw NeedleTailError.nilUserConfig
//        }
//        guard let userConfig = unwrapedTaskValue else {
//            throw NeedleTailError.nilUserConfig
//        }
//        return try await task.value
    }
    
    
    func resumeClient(
        writer: NeedleTailWriter,
        type: RegistrationType,
        state: RegistrationState? = .full
    ) async throws {
        try await startSession(writer: writer, type: type, state: state)
    }
    
    func suspendClient(_ isSuspending: Bool = false) async throws {
        do {
            try await attemptDisconnect(isSuspending)
        } catch {
            await transportConfiguration.transportState.transition(to: .clientOffline)
            logger.error("Could not gracefully shutdown, Forcing the exit (\(error.localizedDescription))")
            //This probably means that the server is down
            if error.localizedDescription != "alreadyClosed" {
                exit(0)
            }
        }
    }
    
    func publishKeyBundle(_
                          data: UserConfig,
                          appleToken: String,
                          nameToVerify: String,
                          recipientDeviceId: DeviceId?
    ) async throws {
        let result = try await registerForBundle(appleToken, nameToVerify: nameToVerify)
        try await mechanismToPublishBundle(
            data,
            contacts: result.0,
            updateKeyBundle: result.1,
            recipientDeviceId: recipientDeviceId
        )
    }
    
    public func registrationType(_ appleToken: String = "", nameToVerify: String = "") -> RegistrationType {
        if !appleToken.isEmpty {
            return .siwa(appleToken)
        } else {
            return .plain(nameToVerify)
        }
    }
    
    
    func startSession(
        writer: NeedleTailWriter,
        type: RegistrationType,
        state: RegistrationState? = .full
    ) async throws {
        switch type {
        case .siwa(let apple):
            try await self.registerSession(writer, appleToken: apple)
        case .plain(let nameToVerify):
            try await self.registerSession(writer, nameToVerify: nameToVerify, state: state)
        }
    }
    
    func registerSession(_
                         writer: NeedleTailWriter,
                         appleToken: String = "",
                         nameToVerify: String? = nil,
                         state: RegistrationState? = .full
    ) async throws {
        switch registrationState {
        case .full:
            let regObject = regRequest(with: appleToken)
            let packet = try BSONEncoder().encodeData(regObject)
            try await writer.registerNeedletailSession(packet)
        case .temp:
            let regObject = regRequest(true)
            let packet = try BSONEncoder().encodeData(regObject)
            try await writer.registerNeedletailSession(packet, true)
        }
    }
    
    public func registerForBundle(_ appleToken: String, nameToVerify: String) async throws -> ([NTKContact]?, Bool) {
        // We want to set a recipient if we are adding a new device and we want to set a tag indicating we are registering a new device
        guard let stream = stream else { throw NeedleTailError.streamNotSet }
        let updateKeyBundle = await stream.updateKeyBundle
        
        var contacts: [NTKContact]?
        if updateKeyBundle {
            contacts = [NTKContact]()
            for contact in try await configuration.ntkBundle.cypher?.listContacts() ?? [] {
                await contacts?.append(
                    NTKContact(
                        username: contact.username,
                        nickname: contact.nickname ?? ""
                    )
                )
            }
        }
        
        switch await transportConfiguration.transportState.current {
        case .transportOffline:
            guard let writer = writer else { throw NeedleTailError.writerNotSet }
            try await startSession(
                writer: writer,
                type: registrationType(appleToken, nameToVerify: nameToVerify),
                state: registrationState
            )
        default:
            break
        }
        
        try await RunLoop.run(20, sleep: 1, stopRunning: { [weak self] in
            guard let  self else { return false }
            var running = true
            guard let store = await store else { throw NeedleTailError.storeNotIntitialized }
            if await store.acknowledgment == .registered("true") {
                running = false
            }
            switch await transportConfiguration.transportState.current {
            case .transportOnline(clientContext: _):
                running = false
            default:
                running = true
            }
            return running
        })
        return (contacts, updateKeyBundle)
    }
    
    func mechanismToPublishBundle(_
                                  data: UserConfig,
                                  contacts: [NTKContact]?,
                                  updateKeyBundle: Bool,
                                  recipientDeviceId: DeviceId?
    ) async throws {
        let user = configuration.ntkUser
        let jwt = try makeToken(user.username)
        let configObject = await configRequest(jwt, config: data, recipientDeviceId: recipientDeviceId)
        let bundleData = try BSONEncoder().encodeData(configObject)
        let recipient = try await recipient(conversationType: .privateMessage, deviceId: user.deviceId, name: "\(user.username.raw)")
        
        let packet = MessagePacket(
            id: UUID().uuidString,
            pushType: .none,
            type: .publishKeyBundle(bundleData),
            createdAt: Date(),
            sender: nil,
            recipient: nil,
            message: nil,
            readReceipt: .none,
            addKeyBundle: updateKeyBundle,
            contacts: contacts
        )
        
        let encodedString = try BSONEncoder().encodeString(packet)
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
        guard let writer = self.writer else { throw NeedleTailError.writerNotSet }
        guard let store = self.store else { throw NeedleTailError.storeNotIntitialized }
        
        try await writer.transportMessage(type: type)
        
        try await RunLoop.run(20, sleep: 1, stopRunning: {
            var running = true
            if await store.acknowledgment == .publishedKeyBundle("true") {
                running = false
            }
            return running
        })
        
        if await store.acknowledgment != .publishedKeyBundle("true") {
            throw NeedleTailError.cannotPublishKeyBundle
        }
    }
    
    
    /// Request a **QRCode** to be generated on the **Master Device** for new Device Registration
    /// - Parameter nick: The **Master Device's** **NeedleTailNick**
    public func requestDeviceRegistration(_ nick: NeedleTailNick) async throws {
        try await writer?.sendDeviceRegistryRequest(nick)
    }
    
    public func processApproval(_ code: String) async throws -> Bool {
        guard let stream = stream else { throw NeedleTailError.streamNotSet }
        return await stream.computeApproval(code)
    }
    
    
    public func registerAPNSToken(_ token: Data) async throws {
        let user = configuration.ntkUser
        let jwt = try makeToken(user.username)
        let apnObject = apnRequest(jwt, apnToken: token.hexString, deviceId: user.deviceId)
        let payload = try BSONEncoder().encodeData(apnObject)
        let recipient = try await recipient(conversationType: .privateMessage, deviceId: user.deviceId, name: "\(user.username.raw)")
        
        let packet = MessagePacket(
            id: UUID().uuidString,
            pushType: .none,
            type: .registerAPN(payload),
            createdAt: Date(),
            sender: nil,
            recipient: nil,
            message: nil,
            readReceipt: .none
        )
        
        let encodedString = try BSONEncoder().encodeString(packet)
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
        try await writer?.transportMessage(type: type)
    }
    

    func makeToken(_ username: Username) throws -> String {
        guard let signer = configuration.ntkBundle.signer else { return "" }
        var signerAlgorithm: JWTAlgorithm
#if os(Linux)
        signerAlgorithm = signer as! JWTAlgorithm
#else
        signerAlgorithm = signer
#endif
        return try JWTSigner(algorithm: signerAlgorithm)
            .sign(
                Token(
                    device: NTKUser(username: username, deviceId: configuration.ntkUser.deviceId),
                    exp: ExpirationClaim(value: Date().addingTimeInterval(3600))
                )
            )
    }
    
    func configRequest(_ jwt: String, config: UserConfig, recipientDeviceId: DeviceId? = nil) async -> AuthPacket {
        let user = configuration.ntkUser
        return AuthPacket(
            jwt: jwt,
            ntkUser: NTKUser(
                username: user.username,
                deviceId: user.deviceId
            ),
            config: config,
            tempRegister: false,
            recipientDeviceId: recipientDeviceId
        )
    }
    
    private func regRequest(
        with appleToken: String = "",
        _ tempRegister: Bool = false
    ) -> AuthPacket {
        let user = configuration.ntkUser
        let signer = configuration.ntkBundle.signer
        return AuthPacket(
            appleToken: appleToken,
            ntkUser: NTKUser(
                username: signer?.username ?? user.username,
                deviceId: signer?.deviceId ?? user.deviceId
            ),
            config: signer?.userConfig,
            tempRegister: tempRegister
        )
    }
    
    private func apnRequest(_
                            jwt: String,
                            apnToken: String,
                            deviceId: DeviceId
    ) -> AuthPacket {
        AuthPacket(
            jwt: jwt,
            apnToken: apnToken,
            ntkUser: NTKUser(
                username: configuration.ntkUser.username,
                deviceId: deviceId
            ),
            tempRegister: false
        )
    }
    
    func readBundleRequest(_
                           jwt: String,
                           for username: Username
    ) async -> AuthPacket {
        let user = configuration.ntkUser
        return AuthPacket(
            jwt: jwt,
            ntkUser: NTKUser(
                username: user.username,
                deviceId: user.deviceId
            ),
            ntkContact: NTKContact(
                username: username,
                nickname: username.raw
            ),
            tempRegister: false
        )
    }
    
    func recipient(
        conversationType: ConversationType,
        deviceId: DeviceId?,
        name: String
    ) async throws -> IRCMessageRecipient {
        switch conversationType {
        case .groupMessage(_):
            guard let name = IRCChannelName(name) else { throw NeedleTailError.nilChannelName }
            return .channel(name)
        case .privateMessage:
            guard let validatedName = NeedleTailNick(name: name, deviceId: deviceId) else { throw NeedleTailError.nilNickName }
            return .nick(validatedName)
        }
    }
    
    public func sendReadMessages(count: Int) async throws {
        let type = TransportMessageType.standard(.otherCommand(Constants.badgeUpdate.rawValue, ["\(count)"]))
        try await writer?.transportMessage(type: type)
    }
    
    public func downloadMultipart(_ metadata: [String]) async throws {
        let encoder = BSONEncoder()
        let encodedString = try encoder.encodeString(metadata)
        let type = TransportMessageType.standard(.otherCommand(Constants.multipartMediaDownload.rawValue, [encodedString]))
        try await writer?.transportMessage(type: type)
    }
    
    public func uploadMultipart(_ packet: MultipartMessagePacket) async throws {
        let messagePacket = MessagePacket(
            id: packet.id,
            pushType: .none,
            type: .multiRecipientMessage,
            createdAt: Date(),
            sender: packet.sender.deviceId,
            recipient: packet.recipient?.deviceId,
            readReceipt: .none,
            multipartMessage: packet
        )
        let data = try BSONEncoder().encodeData(messagePacket)
        var packetCount = 0
        let chunks = data.chunks(ofCount: 10777216)
        
        for chunk in chunks {
            packetCount += 1
            self.logger.info("Uploading Multipart... Packet \(packetCount) of \(chunks.map{$0}.count)")
            let type = TransportMessageType.standard(.otherCommand(
                Constants.multipartMediaUpload.rawValue,
                [
                    packet.id,
                    String(packetCount),
                    String(chunks.map{$0}.count),
                    chunk.base64EncodedString()
                ]
            ))
            try await writer?.transportMessage(type: type)
        }
    }
    
    public func requestBucketContents(_ bucket: String) async throws {
        
        let encodedString = try BSONEncoder().encodeString([bucket])
        let type = TransportMessageType.standard(.otherCommand(
            Constants.listBucket.rawValue,
            [encodedString]
        ))
        try await writer?.transportMessage(type: type)
    }
}
