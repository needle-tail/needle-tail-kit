//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-nio-irc open source project
//
// Copyright (c) 2018-2021 ZeeZide GmbH. and the swift-nio-irc project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIOIRC project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import _AtomicsShims


extension ByteBuffer {
    
    mutating func writeCSVArgument<T: Sequence>(_ args: T)
    where T.Element == String
    {
        let cSpace : UInt8 = 32
        let cComma : UInt8 = 44
        
        writeInteger(cSpace)
        
        var isFirst = true
        for arg in args {
            if isFirst { isFirst = false }
            else { writeInteger(cComma) }
            writeString(arg)
        }
    }
    
    mutating func writeArguments<T: Sequence>(_ args: T)
    where T.Element == String
    {
        let cSpace : UInt8 = 32
        
        for arg in args {
            writeInteger(cSpace)
            writeString(arg)
        }
    }
    
    mutating func writeArguments<T: Collection>(_ args: T, useLast: Bool = false)
    where T.Element == String
    {
        let cSpace : UInt8 = 32
        
        guard !args.isEmpty else { return }
        
        for arg in args.dropLast() {
            writeInteger(cSpace)
            writeString(arg)
        }
        
        let lastIdx = args.index(args.startIndex, offsetBy: args.count - 1)
        return writeLastArgument(args[lastIdx])
    }
    
    mutating func writeLastArgument(_ s: String) {
        let cSpace : UInt8 = 32
        let cColon : UInt8 = 58
        
        writeInteger(cSpace)
        writeInteger(cColon)
        writeString(s)
    }
}
