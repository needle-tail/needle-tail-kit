//
//  Actors.swift
//  
//
//  Created by Cole M on 5/1/22.
//

import Foundation

//@globalActor public final actor ParsingActor {
//    public static let shared = ParsingActor()
//    private init() {}
//}

@globalActor public actor NeedleTailTransportActor {
    public static let shared = NeedleTailTransportActor()
}

@globalActor public final actor KeyBundleActor {
    public static let shared = KeyBundleActor()
    private init() {}
}
