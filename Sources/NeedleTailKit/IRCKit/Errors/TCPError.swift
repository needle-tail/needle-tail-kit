
enum TCPError: Swift.Error {
    case invalidHost
    case invalidPort
    case errorRunningProgram
}

internal enum IRCClientError : Swift.Error {
    case writeError(Swift.Error)
    case stopped
    case notImplemented
    case internalInconsistency
    case unexpectedInput
    case channelError(Swift.Error)
    case nilHostname
    case nilPort
    case nilConversation
    case nilSecureProps
    case dataGreaterThanMaxBody
    case invalidResponse
    case nilBSONResponse
    case userConfigIsNil
    case nilMessageData
    case nilUsedConfig
    case nilToken
}
