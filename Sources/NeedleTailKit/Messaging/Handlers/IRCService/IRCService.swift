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
    var waitCount = 0
    var logger: Logger
    var activeClientOptions: IRCClientOptions?
    var authenticated: AuthenticationState?
    public let signer: TransportCreationRequest
    public var conversations: [DecryptedModel<ConversationModel>]?
    
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
        activeClientOptions = self.clientOptionsForAccount(signer, clientOptions: clientOptions)

        guard let options = activeClientOptions else { return }
        self.client = IRCClient(options: options, userState: userState, transportDelegate: delegate)
    }
    
    
    private func clientOptionsForAccount(_ signer: TransportCreationRequest, clientOptions: ClientOptions?) -> IRCClientOptions? {
        let lowerCasedName = signer.username.raw.replacingOccurrences(of: " ", with: "").lowercased()
        guard let needletail = NeedleTailNick(lowerCasedName) else { return nil }
        return IRCClientOptions(
            port: clientOptions?.port ?? 6667,
            host: clientOptions?.host ?? "localhost",
            password: activeClientOptions?.password,
            tls: clientOptions?.tls ?? true,
            nickname: needletail.nick,
            userInfo: clientOptions?.userInfo
        )
    }

}

