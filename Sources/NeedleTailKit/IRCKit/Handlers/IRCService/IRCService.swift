import ArgumentParser
import Foundation
import NIO
import AsyncIRC
import CypherMessaging
import Crypto
#if canImport(Network)
import NIOTransportServices
import MessagingHelpers
#endif

public final class IRCService {
    
    public let signer: TransportCreationRequest
    internal var activeClientOptions: IRCClientOptions?
    public var conversations: [ DecryptedModel<ConversationModel> ]?
    internal var authenticated: AuthenticationState?
    public weak var ircDelegate: IRCClientDelegate?
    public var transportDelegate: CypherTransportClientDelegate?
    public weak var store: NeedleTailStore?
    internal var messenger: CypherMessenger?
    internal var client: IRCClient?
    internal var userState: UserState
    internal var clientOptions: ClientOptions?
    internal var userConfig: UserConfig?
    var stream: KeyBundleIterator?
    public var acknowledgment: Acknowledgment.AckType = .none
    
    
    public init(
        signer: TransportCreationRequest,
        authenticated: AuthenticationState,
        userState: UserState,
        clientOptions: ClientOptions?,
        delegate: CypherTransportClientDelegate?,
        store: NeedleTailStore
    ) async {
        self.signer = signer
        self.authenticated = authenticated
        self.userState = userState
        self.clientOptions = clientOptions
        self.transportDelegate = delegate
        self.store = store
        activeClientOptions = self.clientOptionsForAccount(signer, clientOptions: clientOptions)
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

