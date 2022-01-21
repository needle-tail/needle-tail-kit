//
//  File.swift
//  
//
//  Created by Cole M on 1/9/22.
//

import Foundation
import MongoKitten


public protocol NeedleTailStore {
    
    func createJob(_ job: IRCJobModel) async
    func updateJob(_ job: IRCJobModel) async
    func findJobs() async throws -> [IRCJobModel]
//    func findOneJob(_ job: IRCJobModel) async -> IRCJobModel
    func deleteOneJob(_ job: IRCJobModel) async
    func deleteJobs()
}


@globalActor final actor NeedleCacheActor {
    public static let shared = NeedleCacheActor()
    
    private init() {}
}


internal final class _NeedleTailStoreCache: NeedleTailStore {
    
    internal let store: NeedleTailStore
    private var jobs: [IRCJobModel]?
    
    
    
    init(store: NeedleTailStore) {
        self.store = store
    }
    
    
    
    func createJob(_ job: IRCJobModel) async {
        
    }
    
    func updateJob(_ job: IRCJobModel) async {
        
    }
    
    @NeedleCacheActor
    func findJobs() async throws -> [IRCJobModel] {
        if let jobs = self.jobs {
            return jobs
        } else {
            let jobs = try await self.store.findJobs()
            self.jobs = jobs
            return jobs
        }
        }

    
    func deleteOneJob(_ job: IRCJobModel) async {
        
    }
    
    func deleteJobs() {
        
    }
    
    
}
