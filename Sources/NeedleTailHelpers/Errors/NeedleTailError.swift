public enum NeedleTailError: String, Error {
    case invalidResponse
    case nilBSONResponse
    case nilUserConfig
    case nilToken
    case urlResponseNil
    case nilClient
    case nilChannelName
    case nilNickName
    case nilNTM
    case nilData
    case nilChannelData
    case nilBlob
    case invalidUserId
    case membersCountInsufficient = "Insufficient members. You are trying to create a group chat with only 1 member."
    case nilElG
    case transportNotIntitialized
    case messengerNotIntitialized
    case masterDeviceReject = "The Master Device rejected the request to add a new device"
    case registrationFailure
    case storeNotIntitialized = "You must initialize a store"
    case clientInfotNotIntitialized = "You must initialize client info"
}
