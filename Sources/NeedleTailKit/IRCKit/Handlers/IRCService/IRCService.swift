import ArgumentParser
import Foundation
import NIO
import NIOTransportServices
import AsyncIRC
import CypherMessaging
import Crypto
import AsyncIRC

public final class IRCService: Identifiable, Hashable {
    
    public static func == (lhs: IRCService, rhs: IRCService) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public var id: UUID { UUID(uuidString: signer.deviceId.id)! }
    public let signer: TransportCreationRequest
    public let eventLoopGroup: EventLoopGroup
    public let passwordProvider: String
    private var activeClientOptions: IRCClientOptions?
    public var conversations: [ DecryptedModel<ConversationModel> ]?
    private var authenticated: AuthenticationState?
    public var delegate: IRCClientDelegate?
    public weak var transportDelegate: CypherTransportClientDelegate?
    
    var messenger: CypherMessenger?
    var client: IRCClient?
    internal var userState: UserState
    internal var clientOptions: ClientOptions?
    
    public init(
        signer: TransportCreationRequest,
        passwordProvider: String,
        eventLoopGroup: EventLoopGroup,
        authenticated: AuthenticationState,
        userState: UserState,
        clientOptions: ClientOptions?,
        delegate: CypherTransportClientDelegate?
    )
    async {
        self.eventLoopGroup = eventLoopGroup
        self.passwordProvider = passwordProvider
        self.signer = signer
        self.authenticated = authenticated
        self.userState = userState
        self.clientOptions = clientOptions
        self.transportDelegate = delegate
        activeClientOptions = self.clientOptionsForAccount(signer, clientOptions: clientOptions)
    }
    
    
    
    // MARK: - Connection
    private func handleAccountChange() async {
        await self.connectIfNecessary()
    }
    
    private func connectIfNecessary() async {
        guard case .offline = userState.state else { return }
        guard let options = activeClientOptions else { return }
        self.client = IRCClient(options: options)
        self.client?.delegate = self
        userState.transition(to: .connecting)
        do {
       _ = try await client?.connecting()
                self.authenticated = .authenticated
        } catch {
            self.authenticated = .authenticationFailure
            Task {
               await self.connectIfNecessary()
            }
            print(error, "OUR ERROR")
        }
        
    }
    
    private func clientOptionsForAccount(_ signer: TransportCreationRequest, clientOptions: ClientOptions?) -> IRCClientOptions? {
        guard let nick = IRCNickName(signer.username.raw) else { return nil }
//TODO: if password is not nil than we get a Crash saying PASS Command not found
        return IRCClientOptions(
            port: clientOptions?.port ?? 6667,
            host: clientOptions?.host ?? "localhost",
            password: activeClientOptions?.password,
            tls: clientOptions?.tls ?? true,
            nickname: nick,
            userInfo: clientOptions?.userInfo,
            eventLoopGroup: NIOTSEventLoopGroup()
        )
    }
    
    // MARK: - Lifecycle
    public func resume() async {
        await connectIfNecessary()
    }
    
    
    public func suspend() async {
        defer { userState.transition(to: .suspended) }
        switch userState.state {
        case .suspended, .offline:
            return
        case .connecting, .online:
            await client?.disconnect()
        }
    }
    
    public func close() async {
        await client?.disconnect()
    }
    
    
    
    // MARK: - Conversations
    @discardableResult
    public func registerPrivateChat(_ name: String) async throws -> DecryptedModel<ConversationModel>? {
        let id = name.lowercased()
        let conversation = self.conversations?.first { $0.id.uuidString == id }
        if let c = conversation { return c }
         let chat = try? await self.messenger?.createPrivateChat(with: Username(name))
        return chat?.conversation
    }
    
    @discardableResult
    public func registerGroupChat(_ name: String) async throws -> DecryptedModel<ConversationModel>? {
        let id = name.lowercased()
        let conversation = self.conversations?.first { $0.id.uuidString == id }
        if let c = conversation { return c }
         let chat = try? await self.messenger?.createGroupChat(with: [])
        return chat?.conversation
    }
    
    public func conversationWithID(_ id: UUID) async -> DecryptedModel<ConversationModel>? {
        return try? await self.messenger?.getConversation(byId: id)?.conversation
    }
    
    public func conversationForRecipient(_ recipient: IRCMessageRecipient, create: Bool = false) async -> GroupChat? {
        return try? await self.messenger?.getGroupChat(byId: GroupChatId(recipient.stringValue))
    }
    
    // MARK: - Sending
    @discardableResult
    public func sendMessage(_ message: Data, to recipient: IRCMessageRecipient, tags: [IRCTags]?) async throws -> Bool {
//        guard case .online = userState.state else { return false }
        await client?.sendMessage(message.base64EncodedString(), to: recipient, tags: tags)
        return true
    }
}



extension IRCService: IRCClientDelegate {
    // MARK: - Messages
    public func client(_       client : IRCClient,
                       notice message : String,
                       for recipients : [ IRCMessageRecipient ]
    ) async {
        await self.updateConnectedClientState(client)
        
        // FIXME: this is not quite right, mirror what we do in message
//        self.conversationsForRecipients(recipients).forEach {
//          $0.addNotice(message)
//        }
      }
      
    public func client(_       client : IRCClient,
                       message        : String,
                       from    sender : IRCUserID,
                       for recipients : [ IRCMessageRecipient ]
    ) async {
        await self.updateConnectedClientState(client)
        
        // FIXME: We need this because for DMs we use the sender as the
        //        name
        for recipient in recipients {
          switch recipient {
            case .channel(let name):
              print(name)
//              if let c = self.registerChannel(name.stringValue) {
//                c.addMessage(message, from: sender)
//              }
              break
            case .nickname: // name should be us
              print("DATA RECEIVED: \(client)")
              print("DATA RECEIVED: \(message)")
              print("DATA RECEIVED: \(sender)")
              print("DATA RECEIVED: \(recipients)")
//              if let c = self.registerDirectMessage(sender.nick.stringValue) {
//                c.addMessage(message, from: sender)
//              }
              break
            case .everything:
break
//              self.conversations.values.forEach {
//                $0.addMessage(message, from: sender)
//              }
          }
        }
      }
    
    public func client(_ client: IRCClient, received message: IRCMessage) async {
        print("MESSAGE", message)
        print("CLIENT", client)

        struct Packet: Codable {
            let id: ObjectId
            let type: MessageType
            let body: Document
        }
        
        switch message.command {

        case .PRIVMSG(_, let data):
            Task.detached {
                print("DATA", data)
                do {
                    let buffer = ByteBuffer(data: Data(base64Encoded: data)!)
                    print("BUFFER", buffer)
                    let packet = try BSONDecoder().decode(Packet.self, from: Document(buffer: buffer))
                    print("MY PACKET", packet)
                    switch packet.type {
                        
                    case .message:
                        let dmPacket = try BSONDecoder().decode(DirectMessagePacket.self, from: packet.body)
                        print("DMPACKET", dmPacket)
                        try await self.transportDelegate?.receiveServerEvent(
                            .messageSent(
                                dmPacket.message,
                                id: dmPacket.messageId,
                                byUser: dmPacket.sender.user,
                                deviceId: dmPacket.sender.device
                            )
                        )
                    case .multiRecipientMessage:
                        break
                    case .readReceipt:
                        let receipt = try BSONDecoder().decode(ReadReceiptPacket.self, from: packet.body)
                        switch receipt.state {
                        case .displayed:
                            break
                        case .received:
                            break
                        }
                    case .ack:
                        ()
                    }
                    
                } catch {
                    print(error)
                }
            }
        default:
            break
        }
        }
    

    func fetchConversations() async {
        for chat in try! await messenger!.listConversations(
            includingInternalConversation: true,
            increasingOrder: { _, _ in return true }
        ) {
            print(chat.conversation)
        }
    }
    
    public func client(_ client: IRCClient, messageOfTheDay message: String) async {
        await self.updateConnectedClientState(client)
//        self.messageOfTheDay = message
      }
    
    
    // MARK: - Channels

    public func client(_ client: IRCClient,
                       user: IRCUserID, joined channels: [ IRCChannelName ]
    ) async {
        await self.updateConnectedClientState(client)
//        channels.forEach { self.registerChannel($0.stringValue) }
      }
    
    public func client(_ client: IRCClient,
                       user: IRCUserID, left channels: [ IRCChannelName ],
                       with message: String?
    ) async {
        await self.updateConnectedClientState(client)
//        channels.forEach { self.unregisterChannel($0.stringValue) }
      }

    public func client(_ client: IRCClient,
                       changeTopic welcome: String, of channel: IRCChannelName
    ) async {
        await self.updateConnectedClientState(client)
        // TODO: operation
    }

    private func updateConnectedClientState(_ client: IRCClient) async {
        switch self.userState.state {
        case .suspended:
            assertionFailure("not connecting, still getting connected client info")
                     return
        case .offline:
            assertionFailure("not connecting, still getting connected client info")
           //          return
        case .connecting:
                      print("going online:", client)
            self.userState.transition(to: .online)
                      let channels = await ["#NIO", "Swift"].asyncCompactMap(IRCChannelName.init)
                      client.sendMessage(.init(command: .JOIN(channels: channels, keys: nil)))
            //
        case .online:
            break
                  // TODO: update state (nick, userinfo, etc)
        }
    }
    
    // MARK: - Connection
    public func client(_ client        : IRCClient,
                       registered nick : IRCNickName,
                       with   userInfo : IRCUserInfo
    ) async {
        await self.updateConnectedClientState(client)
    }
    
    public func client(_ client: IRCClient, changedNickTo nick: IRCNickName) async {
        await self.updateConnectedClientState(client)
    }
    
    public func client(_ client: IRCClient, changedUserModeTo mode: IRCUserMode) async {
        await self.updateConnectedClientState(client)
    }

    public func clientFailedToRegister(_ newClient: IRCClient) async {
        switch self.userState.state {
            
        case .suspended, .offline:
            assertionFailure("not connecting, still get registration failure")
                       return
        case .connecting, .online:
                      print("Closing client ...")
                      client?.delegate = nil
            self.userState.transition(to: .offline)
                      await client?.disconnect()
        }
      }
    
    public func client(_ client: IRCClient, quit: String?) async {
        print("QUITING")
    }
}

extension IRCClient: Equatable {
    public static func == (lhs: IRCClient, rhs: IRCClient) -> Bool {
        return lhs === rhs
    }
}


extension IRCService {
    public struct UserProfile: Decodable {
        public let username: String
        public let config: UserConfig
    }

    enum MessageType: String, Codable {
        case message = "a"
        case multiRecipientMessage = "b"
        case readReceipt = "c"
        case ack = "d"
    }

    struct DirectMessagePacket: Codable {
        let _id: ObjectId
        let messageId: String
        let createdAt: Date
        let sender: UserDeviceId
        let recipient: UserDeviceId
        let message: RatchetedCypherMessage
    }

    struct ChatMultiRecipientMessagePacket: Codable {
        let _id: ObjectId
        let messageId: String
        let createdAt: Date
        let sender: UserDeviceId
        let recipient: UserDeviceId
        let multiRecipientMessage: MultiRecipientCypherMessage
    }

    struct ReadReceiptPacket: Codable {
        enum State: Int, Codable {
            case received = 0
            case displayed = 1
        }
        
        let _id: ObjectId
        let messageId: String
        let state: State
        let sender: UserDeviceId
        let recipient: UserDeviceId
    }
}
