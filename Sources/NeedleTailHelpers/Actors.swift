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

@globalActor public final actor NeedleTailClientActor {
    public static let shared = NeedleTailClientActor()
}

@globalActor public final actor NeedleTailMessengerActor {
    public static let shared = NeedleTailMessengerActor()
}

@globalActor public final actor NeedleTailChannelActor {
    public static let shared = NeedleTailChannelActor()
}

@globalActor public final actor NeedleTailInboundActor {
    public static let shared = NeedleTailInboundActor()
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

@globalActor public actor PriorityActor {
    
    public static let shared = PriorityActor()
    
    private var task = Task<Void, Never> { }
    
    /// Creates a new task group.
    public init() {}
    
    /// Queue the given `work` in the task queue, waiting for any previously queued units of work to finish before executing the `work.`
    ///
    /// - Returns: The task representing the asynchronous `work`. The execution of `work` can be prevented by cancelling the returned task before the `work` is executed.
    @discardableResult
    public func queueThrowingAction<T>(with priority: _Concurrency.TaskPriority = .medium, _ work: @Sendable @escaping () async throws -> T) -> Task<T, Error> {
        let currentTask = self.task
        let newTask = Task<T, Error>(priority: priority) {
            await currentTask.value
            try Task.checkCancellation()
            return try await work()
        }
        
        self.task = Task {
            _ = try? await newTask.value
        }
        
        return newTask
    }
}
