////
////  File.swift
////  
////
////  Created by Cole M on 1/9/22.
////
//
//import Foundation
//
//
//public protocol NeedleTailStore: AnyObject {
//    
//    func createJob(_ job: IRCJobModel) async throws
//    func updateJob(_ job: IRCJobModel) async throws
//    func findJobs() async throws -> [IRCJobModel]
//    func deleteJob(_ job: IRCJobModel) async throws
//}
//
//
//@globalActor final actor NeedleCacheActor {
//    public static let shared = NeedleCacheActor()
//    
//    private init() {}
//}
//
//
//internal final class _NeedleTailStoreCache: NeedleTailStore {
//    
//    private weak var store: NeedleTailStore?
//    private var jobs: [IRCJobModel]?
//    
//    internal init(needleTailStore: NeedleTailStore?) {
//        self.store = needleTailStore
//    }
//    
//    @NeedleCacheActor
//    internal func createJob(_ job: IRCJobModel) async throws {
//        try await store?.createJob(job)
//    }
//    
//    @NeedleCacheActor
//    internal func updateJob(_ job: IRCJobModel) async throws {
//        try await store?.updateJob(job)
//    }
//    
//    @NeedleCacheActor
//    internal func findJobs() async throws -> [IRCJobModel] {
//        if let jobs = self.jobs {
//            return jobs
//        } else {
//            let jobs = try await self.store?.findJobs()
//            self.jobs = jobs
//            return jobs ?? []
//        }
//    }
//    
//    @NeedleCacheActor
//    internal func deleteJob(_ job: IRCJobModel) async throws {
//        try await store?.deleteJob(job)
//    }
//    
//    
//}
