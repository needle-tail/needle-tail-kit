
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
}
