//
//  SQLiteStore.swift
//  
//
//  Created by Cole M on 1/31/22.
//

import Foundation
import FluentSQLiteDriver
import FluentKit
import BSON

fileprivate final class _IRCJobModel: FluentKit.Model {
    static let schema = "a"
    
    @ID(key: .id) var id: UUID?
    @Field(key: "a") var taskKey: String
    @Field(key: "b") var task: Document
    @Field(key: "c") var delayedUntil: Date?
    @Field(key: "d") var scheduledAt: Date
    @Field(key: "e") var attempts: Int
    @Field(key: "f") var isBackgroundTask: Bool
    
    init() {}
    
    init(job: IRCJobModel, new: Bool) async {
        self.id = job.id
        self.$id.exists = !new
        self.taskKey = job.taskKey
        self.task = job.task
        self.delayedUntil = job.delayedUntil
        self.scheduledAt = job.scheduledAt
        self.attempts = job.attempts
        self.isBackgroundTask = job.isBackgroundTask
    }
    
    func makeJob() -> IRCJobModel {
        IRCJobModel(
            id: id!,
            taskKey: taskKey,
            task: task,
            delayedUntil: delayedUntil,
            scheduledAt: scheduledAt,
            attempts: attempts,
            isBackgroundTask: isBackgroundTask)
    }
}

struct IRCJobMigration: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema(_IRCJobModel.schema)
            .id()
            .field("a", .data, .required)
            .field("b", .data, .required)
            .field("c", .data, .required)
            .field("d", .data, .required)
            .field("e", .data, .required)
            .field("f", .data, .required)
            .create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema(_IRCJobModel.schema).delete()
    }
}

fileprivate func makeSQLiteURL() -> String {
    
#if os(iOS) || os(macOS)
    guard var url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
        fatalError()
    }
#else
    guard var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        fatalError()
    }
#endif
    url = url.appendingPathComponent("parseDB")
    
    if FileManager.default.fileExists(atPath: url.path) {
        var excludedFromBackup = URLResourceValues()
        excludedFromBackup.isExcludedFromBackup = true
        try! url.setResourceValues(excludedFromBackup)
    }

    return url.path
}

public class SQLiteStore: NeedleTailStore {
    let databases: Databases
    let database: Database
    var eventLoop: EventLoop { database.eventLoop }
    
    private init(databases: Databases, database: Database) {
        self.databases = databases
        self.database = database
    }
    
    static func exists() -> Bool {
        FileManager.default.fileExists(atPath: makeSQLiteURL())
    }
    
    static func destroy() {
        try? FileManager.default.removeItem(atPath:makeSQLiteURL())
    }
    
    func destroy() {
        Self.destroy()
    }
    
    public static func create(
        on eventLoop: EventLoop
    ) async throws -> SQLiteStore {
        try await self.create(withConfiguration: .file(makeSQLiteURL()), on: eventLoop).get()
    }
    
    static func create(
        withConfiguration configuration: SQLiteConfiguration,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<SQLiteStore> {
        let databases = Databases(
            threadPool: NIOThreadPool(numberOfThreads: 1),
            on: eventLoop
        )
        
        databases.use(.sqlite(configuration), as: .sqlite)
        let logger = Logger(label: "sqlite")
        
        let migrations = Migrations()
        migrations.add(IRCJobMigration())
        
        let migrator = Migrator(databases: databases, migrations: migrations, logger: logger, on: eventLoop)
        return migrator.setupIfNeeded().flatMap {
            migrator.prepareBatch()
        }.recover { _ in }.map {
            return SQLiteStore(
                databases: databases,
                database: databases.database(logger: logger, on: eventLoop)!
            )
        }.flatMapErrorThrowing { error in
            databases.shutdown()
            throw error
        }
    }
    
    
    
    
    public func createJob(_ job: IRCJobModel) async throws {
        try await _IRCJobModel(job: job, new: true).create(on: database).get()
    }
    
    public func updateJob(_ job: IRCJobModel) async throws {
        try await _IRCJobModel(job: job, new: false).update(on: database).get()
    }
    
    public func findJobs() async throws -> [IRCJobModel] {
        try await _IRCJobModel.query(on: database).all().flatMapEachThrowing {
            $0.makeJob()
        }.get()
    }
    
    public func deleteJob(_ job: IRCJobModel) async throws {
        try await _IRCJobModel(job: job, new: false).delete(on: database).get()
    }
    
    deinit {
        DispatchQueue.main.async { [databases] in
            databases.shutdown()
        }
    }
}
