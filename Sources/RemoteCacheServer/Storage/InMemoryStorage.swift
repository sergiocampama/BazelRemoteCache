// Copyright 2018 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Dispatch
import Foundation
import NIO

class InMemoryStorage: CacheStorage {
  private var memoryStorage = [String: Data]()
  private let semaphore = DispatchSemaphore(value: 1)

  func read(_ resourceURI: String, promise: EventLoopPromise<CacheResponseType>) {
    var read: Data? = nil
    semaphore.wait()
    read = memoryStorage[resourceURI]
    semaphore.signal()

    if let data = read {
      var byteBuffer = ByteBufferAllocator().buffer(capacity: data.count)
      byteBuffer.write(bytes: data)

      promise.succeed(result: .iodata(.byteBuffer(byteBuffer)))
    } else {
      promise.succeed(result: .notFound)
    }
  }

  func write(_ resourceURI: String, data: Data, promise: EventLoopPromise<CacheResponseType>?) {
    semaphore.wait()
    memoryStorage[resourceURI] = data
    semaphore.signal()
    if let promise = promise {
      promise.succeed(result: .void)
    }
  }
}
