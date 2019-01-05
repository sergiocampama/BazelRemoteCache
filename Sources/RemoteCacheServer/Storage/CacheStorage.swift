import Dispatch
import Foundation
import NIO

protocol CacheStorage {
  func contains(_ resourceURI: String) -> Bool
  func read(_ resourceURI: String) -> IOData?
  func write(_ resourceURI: String, data: Data)
}
