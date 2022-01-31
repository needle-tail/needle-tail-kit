////
////  MongoStore.swift
////
////  Created by Cole M on 1/20/22.
////
////
//
//import Foundation
//import MongoKitten
//import Logging
//
//internal final class MongoStore: NeedleTailStore {
//    
//    let database: MongoDatabase
//    let logger: Logger
//    init(database: MongoDatabase) {
//        self.database = database
//        self.logger = Logger(label: "MongoStore - ")
//    }
//    func createJob(_ job: IRCJobModel) async {
//        
//    }
//    
//    func updateJob(_ job: IRCJobModel) async {
//        
//    }
//    
//    func findJobs() async throws -> [IRCJobModel] {
//            let jobDB = database["jobs"]
//            let jobDoc = try? await jobDB.find().allResults()
//            var jobs: [IRCJobModel]?
//            _ = jobDoc?.compactMap { doc in
//                do {
//                    let job = try BSONDecoder().decode(IRCJobModel.self, from: doc["body"] as! Document)
//                    jobs?.append(job)
//                    _ = jobs?.map { job -> (Date, IRCJobModel) in
//                        return (job.scheduledAt, job)
//                    }.sorted { lhs, rhs in
//                        lhs.0 < rhs.0
//                    }.map(\.1)
//                    self.logger.info("Current Jobs: - \(String(describing: jobs))")
//                } catch {
//                    self.logger.error("There was an error decoding JobModel BSON - Error: \(error)")
//                }
//            }
//            return jobs ?? []
//        }
////
////    func findOneJob(_ job: IRCJobModel) async -> IRCJobModel {
////
////    }
//
//    
//    func deleteOneJob(_ job: IRCJobModel) async {
//        
//    }
//    
//    func deleteJobs() {
//        
//    }
//}
//
