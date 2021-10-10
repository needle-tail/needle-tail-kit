//
//  File.swift
//  
//
//  Created by Cole M on 10/10/21.
//

import Foundation



/// A callback which defines the connect-retry strategy.
public typealias RetryStrategyCB = ( RetryInfo ) -> RetryResult


/// Object passed to the RetryStrategy callback. Contains information on the
/// number of tries etc.
public struct RetryInfo {
  
  var attempt         : Int    = 0
  var totalRetryTime  : Date   = Date()
  var timesConnected  : Int    = 0
  var lastSocketError : Swift.Error? = nil
  
  mutating func registerSuccessfulConnect() {
    self.timesConnected  += 1
    self.totalRetryTime  = Date()
    self.lastSocketError = nil
    self.attempt         = 0
  }
}

public enum RetryResult {
  case retryAfter(TimeInterval)
  case error(Swift.Error)
  case stop
}

/// This way the callback can do a simple:
///
///     return 250
///
/// instead of
///
///     return .RetryAfter(0.250)
///
/// To retry after 250ms. Makes it more similar
/// to the original API.
///
extension RetryResult : ExpressibleByIntegerLiteral {
  
  public init(integerLiteral value: Int) { // milliseconds
    self = .retryAfter(TimeInterval(value) / 1000.0)
  }
  
}

