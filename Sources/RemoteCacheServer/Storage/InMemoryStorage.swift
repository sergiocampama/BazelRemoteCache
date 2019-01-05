import Dispatch
import Foundation
import NIO

class InMemoryStorage: CacheStorage {
  private var memoryStorage = [String: Data]()
  private let semaphore = DispatchSemaphore(value: 1)

  func contains(_ resourceURI: String) -> Bool {
    var contained = false
    semaphore.wait()
    contained = memoryStorage[resourceURI] != nil
    semaphore.signal()
    return contained
  }

  func read(_ resourceURI: String) -> IOData? {
    var read: Data? = nil
    semaphore.wait()
    read = memoryStorage[resourceURI]
    semaphore.signal()

    if let data = read {
      var byteBuffer = ByteBufferAllocator().buffer(capacity: data.count)
      byteBuffer.write(bytes: data)

      return .byteBuffer(byteBuffer)
    }

    return nil
  }

  func write(_ resourceURI: String, data: Data) {
    semaphore.wait()
    memoryStorage[resourceURI] = data
    semaphore.signal()
  }
}
