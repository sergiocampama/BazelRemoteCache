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

import Foundation
import NIO

public enum StorageType {
  case inMemory
  case filesystem(String)
}

public class RemoteCacheServer {
  private let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
  private let host: String
  private let port: Int
  private let storageType: StorageType
  private let verbose: Bool

  public init(host: String, port: Int, storageType: StorageType, verbose: Bool) {
    self.host = host
    self.port = port
    self.storageType = storageType
    self.verbose = verbose
  }

  public func start() throws {
    let storage: CacheStorage
    switch storageType {
    case .inMemory:
      storage = InMemoryStorage()
    case .filesystem(let path):
      storage = FilesystemStorage(localPath: path)
    }

    do {
      let channel = try serverBootstrap(storage: storage)
        .bind(host: host, port: port).wait()
      print("Listening on \(String(describing: channel.localAddress))...")
      try channel.closeFuture.wait()
    } catch let error {
      throw error
    }
  }

  public func stop() {
    do {
      try group.syncShutdownGracefully()
    } catch let error {
      print("Error shutting down \(error.localizedDescription)")
      exit(0)
    }
  }

  private func serverBootstrap(storage: CacheStorage) -> ServerBootstrap {
    return ServerBootstrap(group: group)
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .childChannelInitializer { channel in
        let channelFuture = channel.pipeline.add(handler: BackPressureHandler())
          .then { channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true) }
        if self.verbose {
          _ = channelFuture.then { channel.pipeline.add(handler: LoggingHandler()) }
        }
        return channelFuture.then { channel.pipeline.add(handler: RemoteCacheHandler(storage: storage)) }
      }
      .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
      .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
  }
}
