//
//  File.swift
//  
//
//  Created by Cole M on 9/19/21.
//

import Foundation
import NIOTransportServices

public final class IRC {
  
  let defaults = UserDefaults.standard
  
  internal var services : [ IRCClient ]
  private let passwordProvider : IRCServicePasswordProvider
  
    public init(account: IRCAccount, passwordProvider: IRCServicePasswordProvider) {

    var accounts = (try? defaults.decode([IRCAccount].self, forKey: .accounts)) ?? []
        accounts.append(account)
        self.passwordProvider = passwordProvider
        self.services         = accounts.map {
      return IRCClient(account: $0, passwordProvider: passwordProvider)
    }

    
    #if DEBUG
    if services.isEmpty {
        addAccount(IRCAccount(host: "localhost", port: 6667, nickname: "Cole"))
    }
    #endif
  }
  
  
  // MARK: - Service Lookup
  internal func serviceWithID(_ id: UUID) -> IRCClient? {
    return services.first(where: { $0.account.id == id })
  }
  internal func serviceWithID(_ id: String) -> IRCClient? {
    guard let uuid = UUID(uuidString: id) else { return nil }
    return serviceWithID(uuid)
  }
  
  public func addAccount(_ account: IRCAccount) {
    guard services.first(where: { $0.account.id == account.id }) == nil else {
      assertionFailure("duplicate ID!")
      return
    }
    
    let service = IRCClient(account: account, passwordProvider: "")
    services.append(service)
    
    persistAccounts()
  }
  public func removeAccountWithID(_ id: UUID) {
    guard let idx = services.firstIndex(where: {$0.account.id == id }) else { return }
    services.remove(at: idx)
    persistAccounts()
  }
  
  private func persistAccounts() {
    do {
      try defaults.encode(services.map(\.account), forKey: .accounts)
    }
    catch {
      assertionFailure("Could not persist accounts: \(error)")
      print("failed to persist accounts:", error)
    }
  }
  
  
  // MARK: - Lifecycle
  
  public func resume() {
    services.forEach { $0.resume() }
  }
  public func suspend() {
    services.forEach { $0.suspend() }
  }
}
