import ArgumentParser
import Foundation
import NIO
import CypherMessaging
import Crypto
import Logging
import AsyncIRC
import NeedleTailHelpers
import MessagingHelpers
#if canImport(Network)
import NIOTransportServices
#endif

public final class IRCService {
    
    var messenger: CypherMessenger?
    var client: IRCClient?
    var userState: UserState
    var clientOptions: ClientOptions?
    var userConfig: UserConfig?
    var waitCount = 0
    var logger: Logger
    var activeClientOptions: IRCClientOptions?
    var authenticated: AuthenticationState?
    public var acknowledgment: Acknowledgment.AckType = .none
    public let signer: TransportCreationRequest
    public var conversations: [ DecryptedModel<ConversationModel> ]?
    public var transportDelegate: CypherTransportClientDelegate?
    public weak var ircDelegate: IRCClientDelegate?
    
    public init(
        signer: TransportCreationRequest,
        authenticated: AuthenticationState,
        userState: UserState,
        clientOptions: ClientOptions?,
        delegate: CypherTransportClientDelegate?
    ) async {
        self.logger = Logger(label: "IRCService - ")
        self.signer = signer
        self.authenticated = authenticated
        self.userState = userState
        self.clientOptions = clientOptions
        self.transportDelegate = delegate
        activeClientOptions = self.clientOptionsForAccount(signer, clientOptions: clientOptions)

        guard let options = activeClientOptions else { return }
        self.client = IRCClient(options: options)
        self.client?.delegate = self
    }
    
    
    private func clientOptionsForAccount(_ signer: TransportCreationRequest, clientOptions: ClientOptions?) -> IRCClientOptions? {
        guard let nick = IRCNickName(signer.username.raw) else { return nil }
        return IRCClientOptions(
            port: clientOptions?.port ?? 6667,
            host: clientOptions?.host ?? "localhost",
            password: activeClientOptions?.password,
            tls: clientOptions?.tls ?? true,
            nickname: nick,
            userInfo: clientOptions?.userInfo
        )
    }

}

