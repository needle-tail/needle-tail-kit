//
//  Actors.swift
//  
//
//  Created by Cole M on 5/1/22.
//

import Foundation

@globalActor public final actor ParsingActor {
    public static let shared = ParsingActor()
    private init() {}
}

@globalActor public final actor NeedleTailActor {
    public static let shared = NeedleTailActor()
    private init() {}
}

@globalActor public final actor KeyBundleActor {
    public static let shared = KeyBundleActor()
    private init() {}
}
