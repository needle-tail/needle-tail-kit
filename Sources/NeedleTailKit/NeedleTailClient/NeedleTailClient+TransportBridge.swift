//
//  File.swift
//  
//
//  Created by Cole M on 2/9/23.
//

import NIOCore
import Logging
import NeedleTailHelpers
import CypherMessaging
import NeedleTailProtocol
import JWTKit
#if canImport(Network)
import NIOTransportServices
#endif


protocol TransportBridge: AnyObject {
    
    func startClient(_ appleToken: String) async throws
    func resumeClient(_
                      nameToVerify: String?,
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
    func receiveMessage() async
    func readKeyBundle(_ username: Username) async throws -> UserConfig
    func publishKeyBundle(_
                          data: UserConfig,
                          appleToken: String,
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
}


extension NeedleTailClient: TransportBridge {
    
    @KeyBundleMechanismActor
    func addNewDevice(_ config: UserDeviceConfig, cypher: CypherMessenger) async throws {
        guard let mechanism = mechanism else { return }
        //set this to true in order to tell publishKeyBundle that we are adding a device
        mechanism.updateKeyBundle = true
        //set the recipient Device Id so that the server knows which device is requesting this addition
        messenger.recipientDeviceId = config.deviceId
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
                fromDevice: self.deviceId,
                toUser: username,
                toDevice: deviceId,
                messageType: .message,
                conversationType: type,
                readReceipt: readReceipt)
        case .privateMessage:
            try await transport.createPrivateMessage(
                messageId: messageId,
                pushType: pushType,
                message: message,
                fromDevice: self.deviceId,
                toUser: username,
                toDevice: deviceId,
                messageType: .message,
                conversationType: type,
                readReceipt: readReceipt)
        }
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
                nil,
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
            let masterKeyBundle = try await readKeyBundle(username)
            for validatedMaster in try masterKeyBundle.readAndValidateDevices() {
                guard let nick = NeedleTailNick(name: username.raw, deviceId: validatedMaster.deviceId) else { continue }
                
                guard let transport = await transport else { return }
                try await transport.sendChildDeviceConfig(nick, config: newMaster)
            }
        } else {
            let bsonData = try BSONEncoder().encode(newMaster).makeData()
            let base64String = bsonData.base64EncodedString()
            let data = base64String.data(using: .ascii)
#if (os(macOS) || os(iOS))
            await messenger.updateEmitter(data)
            try await RunLoop.run(240, sleep: 1) { @MainActor [weak self] in
                guard let strongSelf = self else { return false }
                var running = true
                if strongSelf.messenger.plugin.emitter.qrCodeData == nil {
                    running = false
                }
                return running
            }
#endif
        }
    }
    
    func readKeyBundle(_ username: Username) async throws -> UserConfig {
        // We need to set the userConfig to nil for the next read flow
        
        guard let mechanism = await mechanism else { throw NeedleTailError.transportNotIntitialized }
        guard let store = store else { throw NeedleTailError.transportNotIntitialized }
        try await clearUserConfig()
        let jwt = try makeToken(username)
        let readBundleObject = readBundleRequest(jwt, recipient: username)
        let packet = try BSONEncoder().encode(readBundleObject).makeData()
        try await mechanism.readKeyBundle(packet.base64EncodedString())
        
        guard let userConfig = store.keyBundle else {
            throw NeedleTailError.nilUserConfig
        }
        print("FEEDING_CONFIG_TO_CTK_______", userConfig)
        return userConfig
    }
    
    
    func resumeClient(_
                      nameToVerify: String? = nil,
                      type: RegistrationType,
                      state: RegistrationState? = .full) async throws {
        try await startSession(nameToVerify, type: type, state: state)
    }
    
    
    func startClient(_ appleToken: String) async throws {
        try await attemptConnection()
        try await startSession(nil, type: registrationType(appleToken), state: registrationState)
        //        self.authenticated = .authenticated
    }
    
    
    func suspendClient(_ isSuspending: Bool = false) async {
        do {
            try await attemptDisconnect(isSuspending)
        } catch {
            await shutdownClient()
        }
        
    }
    
    
    func receiveMessage() async {
        
    }
    
    func publishKeyBundle(_
                          data: UserConfig,
                          appleToken: String,
                          recipientDeviceId: DeviceId?
    ) async throws {
        let result = try await registerForBundle(appleToken)
        try await mechanismToPublishBundle(
            data,
            contacts: result.0,
            updateKeyBundle: result.1,
            recipientDeviceId: recipientDeviceId
        )
    }
    
    public func registrationType(_ appleToken: String = "") -> RegistrationType {
        if !appleToken.isEmpty {
            return .siwa(appleToken)
        } else {
            return .plain
        }
    }
    
    
    func startSession(_
                      nameToVerify: String? = nil,
                      type: RegistrationType,
                      state: RegistrationState? = .full
    ) async throws {
        switch type {
        case .siwa(let apple):
            try await self.registerSession(apple)
        case .plain:
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
    
    func registerForBundle(_ appleToken: String) async throws -> ([NTKContact]?, Bool) {
        guard let mechanism = await mechanism else { throw NeedleTailError.transportNotIntitialized }
        guard let store = store else { throw NeedleTailError.transportNotIntitialized }
        
        // We want to set a recipient if we are adding a new device and we want to set a tag indicating we are registering a new device
        let updateKeyBundle = await mechanism.updateKeyBundle
        
        var contacts: [NTKContact]?
        if updateKeyBundle {
            contacts = [NTKContact]()
            for contact in try await cypher?.listContacts() ?? [] {
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
                nil,
                type: registrationType(appleToken),
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
            case .transportOnline(channel: _, nick: _, userInfo: _):
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
        guard let store = store else { throw NeedleTailError.transportNotIntitialized }
        
        let jwt = try makeToken(username)
        let configObject = configRequest(jwt, config: data, recipientDeviceId: recipientDeviceId)
        let bundleData = try BSONEncoder().encode(configObject).makeData()
        let keyBundle = bundleData.base64EncodedString()
        
        let recipient = try await recipient(conversationType: .privateMessage, deviceId: deviceId, name: "\(username.raw)")
        
        let packet = MessagePacket(
            id: UUID().uuidString,
            pushType: .none,
            type: .publishKeyBundle(keyBundle),
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
    
    @NeedleTailTransportActor
    public func processApproval(_ code: String) async throws -> Bool {
        guard let transport = transport else { throw NeedleTailError.transportNotIntitialized }
        return await transport.computeApproval(code)
    }
    
    @NeedleTailTransportActor
    public func registerAPNSToken(_ token: Data) async throws {
        
        let jwt = try makeToken(username)
        let apnObject = apnRequest(jwt, apnToken: token.hexString, deviceId: deviceId)
        let payload = try BSONEncoder().encode(apnObject).makeData()
        guard let transport = transport else { throw NeedleTailError.transportNotIntitialized }
        let recipient = try await recipient(conversationType: .privateMessage, deviceId: deviceId, name: "\(username.raw)")
        
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
        guard let signer = signer else { return "" }
        var signerAlgorithm: JWTAlgorithm
#if os(Linux)
        signerAlgorithm = signer as! JWTAlgorithm
#else
        signerAlgorithm = signer
#endif
        return try JWTSigner(algorithm: signerAlgorithm)
            .sign(
                Token(
                    device: UserDeviceId(user: username, device: deviceId),
                    exp: ExpirationClaim(value: Date().addingTimeInterval(3600))
                )
            )
    }
    
    func configRequest(_ jwt: String, config: UserConfig, recipientDeviceId: DeviceId? = nil) -> AuthPacket {
        return AuthPacket(
            jwt: jwt,
            username: self.username,
            deviceId: self.deviceId,
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
            username: signer?.username,
            deviceId: signer?.deviceId,
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
            username: self.username,
            deviceId: deviceId,
            tempRegister: false
        )
    }
    
    func readBundleRequest(_
                           jwt: String,
                           recipient: Username
    ) -> AuthPacket {
        AuthPacket(
            jwt: jwt,
            username: self.username,
            recipient: recipient,
            deviceId: deviceId,
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
}
