//
//  TransportBridge.swift
//
//
//  Created by Cole M on 2/9/23.
//

import NeedleTailHelpers
import CypherMessaging
import NeedleTailProtocol
import JWTKit


protocol TransportBridge: AnyObject {
    
    func connectClient() async throws
    func resumeClient(
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
    func downloadMedia(_ metadata: [String]) async throws
    func sendMultipartToS3(_ packet: MultipartMessagePacket) async throws
}


extension NeedleTailClient: TransportBridge {
    
    
    
    @KeyBundleMechanismActor
    func addNewDevice(_ config: UserDeviceConfig, cypher: CypherMessenger) async throws {
        guard let mechanism = mechanism else { return }
        //set this to true in order to tell publishKeyBundle that we are adding a device
        mechanism.updateKeyBundle = true
        //set the recipient Device Id so that the server knows which device is requesting this addition
        ntkBundle.messenger.recipientDeviceId = config.deviceId
        try await cypher.addDevice(config)
    }
    
    func createNeedleTailChannel(
        name: String,
        admin: NeedleTailHelpers.NeedleTailNick,
        organizers: Set<CypherProtocol.Username>,
        members: Set<CypherProtocol.Username>,
        permissions: NeedleTailHelpers.IRCChannelMode
    ) async throws {
        try await transport?.createNeedleTailChannel(
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
        guard let transport = await transport else { throw NeedleTailError.transportNotIntitialized }
        switch type {
        case .groupMessage(let name):
            try await transport.createGroupMessage(
                messageId: messageId,
                pushType: pushType,
                message: message,
                channelName: name,
                toUser: NTKUser(
                    username: username,
                    deviceId: deviceId
                ),
                fromUser: self.ntkUser,
                messageType: .message,
                conversationType: type,
                readReceipt: readReceipt
            )
        case .privateMessage:
            try await transport.createPrivateMessage(
                messageId: messageId,
                pushType: pushType,
                message: message,
                toUser: NTKUser(
                    username: username,
                    deviceId: deviceId
                ),
                fromUser: self.ntkUser,
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
            try await transport?.createReadReceiptMessage(
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
        try await RunLoop.run(20, sleep: 1, stopRunning: { [weak self] in
            guard let strongSelf = self else { return false }
            var running = true
            if await strongSelf.store?.acknowledgment == .readReceipt {
                running = false
            }
            return running
        })
        return (store?.acknowledgment == .readReceipt ? true : false, readReceipt.state)
    }
    
    func publishBlob<C>(_ blob: C) async throws -> CypherMessaging.ReferencedBlob<C> where C : Decodable, C : Encodable, C : Sendable {
        guard let transport = await transport else { throw NeedleTailError.transportNotIntitialized }
        let blobString = try BSONEncoder().encode(blob).makeData()
        try await transport.publishBlob(blobString.base64EncodedString())
        
        guard let channelBlob = await transport.channelBlob else { throw NeedleTailError.nilBlob }
        guard let data = Data(base64Encoded: channelBlob) else { throw NeedleTailError.nilData }
        let blob = try BSONDecoder().decode(NeedleTailHelpers.Blob<C>.self, from: Document(data: data))
        return ReferencedBlob(id: blob._id, blob: blob.document)
    }
    
    
    func requestDeviceRegistery(_ config: CypherMessaging.UserDeviceConfig, addChildDevice: Bool, appleToken: String) async throws {
        switch await transportState.current {
        case .transportOffline:
            try await startSession(
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
            let masterKeyBundle = try await readKeyBundle(ntkUser.username)
            for validatedMaster in try masterKeyBundle.readAndValidateDevices() {
                guard let nick = NeedleTailNick(name: ntkUser.username.raw, deviceId: validatedMaster.deviceId) else { continue }
                
                guard let transport = await transport else { return }
                try await transport.sendChildDeviceConfig(nick, config: newMaster)
            }
        } else {
            let bsonData = try BSONEncoder().encode(newMaster).makeData()
            let base64String = bsonData.base64EncodedString()
            let data = base64String.data(using: .ascii)
#if (os(macOS) || os(iOS))
            await ntkBundle.messenger.updateEmitter(data)
            try await RunLoop.run(240, sleep: 1) { @MainActor [weak self] in
                guard let strongSelf = self else { return false }
                var running = true
                
                if strongSelf.ntkBundle.messenger.emitter?.qrCodeData == nil {
                    running = false
                }
                return running
            }
#endif
        }
    }
    
    func readKeyBundle(_ username: Username) async throws -> UserConfig {
        guard let mechanism = await mechanism else { throw NeedleTailError.transportNotIntitialized }
        guard let store = store else { throw NeedleTailError.transportNotIntitialized }
        try await clearUserConfig()
        
        let jwt = try makeToken(ntkUser.username)
        let readBundleObject = readBundleRequest(jwt, for: username)
        let packet = try BSONEncoder().encode(readBundleObject).makeData()
        try await mechanism.readKeyBundle(packet.base64EncodedString())
        
        guard let userConfig = store.keyBundle else {
            throw NeedleTailError.nilUserConfig
        }
        return userConfig
    }
    
    
    func resumeClient(
        type: RegistrationType,
        state: RegistrationState? = .full
    ) async throws {
        try await startSession(type: type, state: state)
    }
    
    
    func connectClient() async throws {
        try await attemptConnection()
        ntkBundle.messenger.authenticated = .authenticated
    }
    
    
    func suspendClient(_ isSuspending: Bool = false) async throws {
        do {
            try await attemptDisconnect(isSuspending)
        } catch {
            await shutdownClient()
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
        type: RegistrationType,
        state: RegistrationState? = .full
    ) async throws {
        switch type {
        case .siwa(let apple):
            try await self.registerSession(apple)
        case .plain(let nameToVerify):
            try await self.registerSession(nameToVerify: nameToVerify, state: state)
        }
    }
    
    func registerSession(_
                         appleToken: String = "",
                         nameToVerify: String? = nil,
                         state: RegistrationState? = .full
    ) async throws {
        switch registrationState {
        case .full:
            let regObject = regRequest(with: appleToken)
            let packet = try BSONEncoder().encode(regObject).makeData()
            try await transport?.registerNeedletailSession(packet)
        case .temp:
            let regObject = regRequest(true)
            let packet = try BSONEncoder().encode(regObject).makeData()
            try await transport?.registerNeedletailSession(packet, true)
        }
    }
    
    func registerForBundle(_ appleToken: String, nameToVerify: String) async throws -> ([NTKContact]?, Bool) {
        guard let mechanism = await mechanism else { throw NeedleTailError.transportNotIntitialized }
        guard let store = store else { throw NeedleTailError.transportNotIntitialized }
        
        // We want to set a recipient if we are adding a new device and we want to set a tag indicating we are registering a new device
        let updateKeyBundle = await mechanism.updateKeyBundle
        
        var contacts: [NTKContact]?
        if updateKeyBundle {
            contacts = [NTKContact]()
            for contact in try await ntkBundle.cypher?.listContacts() ?? [] {
                await contacts?.append(
                    NTKContact(
                        username: contact.username,
                        nickname: contact.nickname ?? ""
                    )
                )
            }
        }
        
        switch await transportState.current {
        case .transportOffline:
            try await startSession(
                type: registrationType(appleToken, nameToVerify: nameToVerify),
                state: registrationState
            )
        default:
            break
        }
        
        try await RunLoop.run(20, sleep: 1, stopRunning: { [weak self] in
            guard let strongSelf = self else { return false }
            var running = true
            if store.acknowledgment == .registered("true") {
                running = false
            }
            switch await strongSelf.transportState.current {
            case .transportOnline(channel: _, clientContext: _):
                running = false
            default:
                running = true
            }
            return running
        })
        return (contacts, updateKeyBundle)
    }
    
    @KeyBundleMechanismActor
    func mechanismToPublishBundle(_
                                  data: UserConfig,
                                  contacts: [NTKContact]?,
                                  updateKeyBundle: Bool,
                                  recipientDeviceId: DeviceId?
    ) async throws {
        guard let mechanism = mechanism else { throw NeedleTailError.transportNotIntitialized }
        guard let store = await store else { throw NeedleTailError.transportNotIntitialized }
        
        let jwt = try await makeToken(ntkUser.username)
        let configObject = await configRequest(jwt, config: data, recipientDeviceId: recipientDeviceId)
        let bundleData = try BSONEncoder().encode(configObject).makeData()
        let recipient = try await recipient(conversationType: .privateMessage, deviceId: ntkUser.deviceId, name: "\(ntkUser.username.raw)")
        
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
        
        let encodedData = try BSONEncoder().encode(packet).makeData()
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
        try await mechanism.keyBundleMessage(type)
        
        try await RunLoop.run(20, sleep: 1, stopRunning: { @TransportStoreActor in
            var running = true
            if store.acknowledgment == .publishedKeyBundle("true") {
                running = false
            }
            return running
        })
        
        if store.acknowledgment != .publishedKeyBundle("true") {
            throw NeedleTailError.cannotPublishKeyBundle
        }
    }
    
    
    /// Request a **QRCode** to be generated on the **Master Device** for new Device Registration
    /// - Parameter nick: The **Master Device's** **NeedleTailNick**
    @NeedleTailTransportActor
    public func requestDeviceRegistration(_ nick: NeedleTailNick) async throws {
        guard let transport = transport else { throw NeedleTailError.transportNotIntitialized }
        try await transport.sendDeviceRegistryRequest(nick)
    }
    
    public func processApproval(_ code: String) async throws -> Bool {
        guard let transport = await transport else { throw NeedleTailError.transportNotIntitialized }
        return await transport.computeApproval(code)
    }
    
    @NeedleTailTransportActor
    public func registerAPNSToken(_ token: Data) async throws {
        
        let jwt = try await makeToken(ntkUser.username)
        let apnObject = await apnRequest(jwt, apnToken: token.hexString, deviceId: ntkUser.deviceId)
        let payload = try BSONEncoder().encode(apnObject).makeData()
        guard let transport = transport else { throw NeedleTailError.transportNotIntitialized }
        let recipient = try await recipient(conversationType: .privateMessage, deviceId: ntkUser.deviceId, name: "\(ntkUser.username.raw)")
        
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
        
        let encodedData = try BSONEncoder().encode(packet).makeData()
        let encodedString = encodedData.base64EncodedString()
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
        try await transport.transportMessage(type)
    }
    
    func makeToken(_ username: Username) throws -> String {
        guard let signer = ntkBundle.signer else { return "" }
        var signerAlgorithm: JWTAlgorithm
#if os(Linux)
        signerAlgorithm = signer as! JWTAlgorithm
#else
        signerAlgorithm = signer
#endif
        return try JWTSigner(algorithm: signerAlgorithm)
            .sign(
                Token(
                    device: NTKUser(username: username, deviceId: ntkUser.deviceId),
                    exp: ExpirationClaim(value: Date().addingTimeInterval(3600))
                )
            )
    }
    
    func configRequest(_ jwt: String, config: UserConfig, recipientDeviceId: DeviceId? = nil) -> AuthPacket {
        return AuthPacket(
            jwt: jwt,
            ntkUser: NTKUser(
                username: ntkUser.username,
                deviceId: ntkUser.deviceId
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
        return AuthPacket(
            appleToken: appleToken,
            ntkUser: NTKUser(
                username: ntkBundle.signer?.username ?? ntkUser.username,
                deviceId: ntkBundle.signer?.deviceId ?? ntkUser.deviceId
            ),
            config: ntkBundle.signer?.userConfig,
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
                username: ntkUser.username,
                deviceId: deviceId
            ),
            tempRegister: false
        )
    }
    
    func readBundleRequest(_
                           jwt: String,
                           for username: Username
    ) -> AuthPacket {
        AuthPacket(
            jwt: jwt,
            ntkUser: NTKUser(
                username: self.ntkUser.username,
                deviceId: self.ntkUser.deviceId
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
    
    func clearUserConfig() async throws {
        guard let store = store else { throw NeedleTailError.transportNotIntitialized }
        store.keyBundle = nil
    }
    
    func sendReadMessages(count: Int) async throws {
        let type = TransportMessageType.standard(.otherCommand(Constants.badgeUpdate, ["\(count)"]))
        try await transport?.transportMessage(type)
    }
    
    func downloadMedia(_ metadata: [String]) async throws {
        guard !metadata[0].isEmpty else { throw NeedleTailError.mediaIdNil }
        guard !metadata[1].isEmpty else { throw NeedleTailError.totalPartsNil }
        let data = try BSONEncoder().encode(metadata).makeData()
        let type = TransportMessageType.standard(.otherCommand(Constants.multipartMediaDownload, [data.base64EncodedString()]))
        try await transport?.transportMessage(type)
    }
    
    func sendMultipartToS3(_ packet: MultipartMessagePacket) async throws {
        let messagePacket = MessagePacket(
            id: UUID().uuidString,
            pushType: .message,
            type: .multiRecipientMessage,
            createdAt: Date(),
            sender: packet.sender.deviceId,
            recipient: packet.recipient?.deviceId,
            message: packet.message,
            readReceipt: .none,
            multipartMessage: packet
        )
        
        let data = try BSONEncoder().encode(messagePacket).makeData()
        let type = TransportMessageType.standard(.otherCommand(Constants.multipartMediaUpload, [data.base64EncodedString()]))
        try await transport?.transportMessage(type)
    }
}
