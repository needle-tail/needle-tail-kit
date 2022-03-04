internal enum IRCClientError: Error {
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
    case urlResponseNil
}
