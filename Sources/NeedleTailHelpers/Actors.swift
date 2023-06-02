//
//  Actors.swift
//
//
//  Created by Cole M on 5/1/22.
//


@globalActor public final actor ParsingActor {
    public static let shared = ParsingActor()
    private init() {}
}

@globalActor public final actor NeedleTailTransportActor {
    public static let shared = NeedleTailTransportActor()
}

@globalActor public final actor NeedleTailClientActor {
    public static let shared = NeedleTailClientActor()
}

@globalActor public final actor BlobActor {
    public static let shared = BlobActor()
}

@globalActor public final actor KeyBundleActor {
    public static let shared = KeyBundleActor()
    private init() {}
}

@globalActor public final actor PingPongActor {
    public static let shared = PingPongActor()
    private init() {}
}

@globalActor public final actor OfflineMessageActor {
    public static let shared = OfflineMessageActor()
    private init() {}
}

@globalActor public actor MultipartActor {
    public static let shared = MultipartActor()
    private init() {}
}
