//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-nio-irc open source project
//
// Copyright (c) 2018 ZeeZide GmbH. and the swift-nio-irc project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIOIRC project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

public protocol IRCClientMessageTarget : IRCMessageTarget {}

public extension IRCClientMessageTarget {
    func send(_ command: IRCCommand, tags: [IRCTags]? = nil) async {
            let message = IRCMessage(command: command, tags: tags)
            await sendMessage(message)
    }
}
