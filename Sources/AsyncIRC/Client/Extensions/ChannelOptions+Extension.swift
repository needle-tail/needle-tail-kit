//
// ChannelOptions+Extension.swift  
//
//  Created by Cole M on 3/4/22.
//

import NIO

extension ChannelOptions {
    static let reuseAddr = ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR)
}
