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

class FilesystemStorage: CacheStorage {
  private let localPath: String
  private let concurrentFileQueue = DispatchQueue(label: "com.google.remote_cache.file",
                                                  attributes: .concurrent)

  init(localPath: String) {
    self.localPath = localPath
  }

  func read(_ resourceURI: String, promise: EventLoopPromise<CacheResponseType>) {
    let url = URL(fileURLWithPath: localPath).appendingPathComponent(resourceURI)
    if FileManager.default.fileExists(atPath: url.path) {
      if let fileHandle = try? FileHandle(path: url.path),
        let fileRegion = try? FileRegion(fileHandle: fileHandle) {
        promise.succeed(result: .iodata(.fileRegion(fileRegion)))
        return
      }
    }
    promise.succeed(result: .notFound)
  }

  func write(_ resourceURI: String, data: Data, promise: EventLoopPromise<CacheResponseType>?) {
    let url = URL(fileURLWithPath: localPath).appendingPathComponent(resourceURI)
    let parent = url.deletingLastPathComponent()

    // Check once to schedule a directory creation task...
    if !FileManager.default.fileExists(atPath: parent.path) {
      concurrentFileQueue.async(flags: .barrier) {
        // ... and check again in case it was alredy created by another task.
        if !FileManager.default.fileExists(atPath: parent.path) {
          do {
            try FileManager.default.createDirectory(at: parent,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
          } catch let error {
            if let promise = promise {
              promise.fail(error: error)
            }
          }
        }
      }
    }
    concurrentFileQueue.async {
      do {
        try data.write(to: url, options: [.atomic])
      } catch let error {
        if let promise = promise {
          promise.fail(error: error)
        }
      }
      if let promise = promise {
        promise.succeed(result: .void)
      }
    }
  }
}
