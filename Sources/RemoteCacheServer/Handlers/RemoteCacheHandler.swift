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
import NIOHTTP1

enum CacheResponseType: Equatable {
  case iodata(IOData)
  case notFound
  case void
}

/// Handler that manages remote cache events. It only supports PUT and GET requests.
class RemoteCacheHandler {
  enum State {
    case expectingHead
    case expectingBody
    case expectingEnd
    case unsupportedMethod
  }

  private let storage: CacheStorage
  private var httpVersion = HTTPVersion(major: 1, minor: 1)

  private var state: State
  private var resourceURI: String!
  private var expectedLength = 0
  private var storedLength = 0
  private var storedData = Data()
  private var shouldStoreData = false

  private var filesToClose = [FileRegion]()

  private var requestPromise: EventLoopPromise<CacheResponseType>!

  init(storage: CacheStorage) {
    self.state = .expectingHead
    self.storage = storage
  }
}

extension RemoteCacheHandler: ChannelInboundHandler {
  typealias InboundIn = HTTPServerRequestPart
  typealias OutboundOut = HTTPServerResponsePart

  func handlerRemoved(ctx: ChannelHandlerContext) {
    do {
      for fileRegion in filesToClose {
        try fileRegion.fileHandle.close()
      }
    } catch let error {
      ctx.fireErrorCaught(error)
    }
  }

  func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    switch unwrapInboundIn(data) {
    case .head(let requestHead):
      headReceived(requestHead, ctx: ctx)
    case .body(var body):
      bodyReceived(&body)
    case .end:
      endReceived(ctx: ctx)
    }
  }

  private func headReceived(_ head: HTTPRequestHead, ctx: ChannelHandlerContext)  {
    precondition(state == .expectingHead, "expected head, was \(state)")
    precondition(requestPromise == nil, "requestPromise wasn't nil")

    requestPromise = ctx.eventLoop.newPromise(of: CacheResponseType.self)

    resourceURI = head.uri
    switch head.method {
    case .GET:
      storage.read(resourceURI, promise: requestPromise)

      requestPromise.futureResult.whenSuccess { response in
        if case .iodata(let cachedData) = response {
          if case .fileRegion(let fileRegion) = cachedData {
            self.filesToClose.append(fileRegion)
          }

          var headers = HTTPHeaders()
          headers.add(name: "content-length", value: "\(cachedData.readableBytes)")
          headers.add(name: "content-type", value: "application/octet-stream")
          ctx.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: self.httpVersion, status: .ok, headers: headers))),
                    promise: nil)
          ctx.write(self.wrapOutboundOut(.body(cachedData)), promise: nil)
        } else if case .notFound = response {
          ctx.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: self.httpVersion, status: .notFound))),
                    promise: nil)
        }
      }

      state = .expectingEnd
    case .PUT:
      if let contentLength = head.headers["content-length"].first,
         let length = Int(contentLength) {
        expectedLength = length
      }
      shouldStoreData = true
      if expectedLength == 0 {
        state = .expectingEnd
      } else {
        state = .expectingBody
      }
    default:
      ctx.write(wrapOutboundOut(.head(HTTPResponseHead(version: httpVersion, status: .methodNotAllowed))),
                promise: nil)
      state = .unsupportedMethod
    }
  }

  private func bodyReceived(_ body: inout ByteBuffer) {
    if state == .unsupportedMethod {
      // For unsupported methods, skip validation and do nothing.
      return
    }

    precondition(state == .expectingBody, "expected body, was \(state)")

    let readableBytes = body.readableBytes
    if readableBytes > 0, let availableBytes = body.readBytes(length: readableBytes) {
      storedLength += readableBytes
      storedData.append(contentsOf: availableBytes)
    }

    if storedLength == expectedLength {
      state = .expectingEnd
    }
  }

  private func endReceived(ctx: ChannelHandlerContext) {
    if state == .unsupportedMethod {
      ctx.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: httpVersion, status: .methodNotAllowed))),
                promise: nil)
      ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
      return
    }

    precondition(state == .expectingEnd, "expected end, was \(state)")
    precondition(requestPromise != nil, "expected non nil requestPromise")

    if shouldStoreData {
      storage.write(resourceURI, data: storedData, promise: requestPromise)

      requestPromise.futureResult.whenSuccess { _ in
        ctx.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: self.httpVersion, status: .ok))),
                  promise: nil)
      }
      requestPromise.futureResult.whenFailure { _ in
        ctx.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: self.httpVersion, status: .internalServerError))),
                  promise: nil)
      }
    } else {
      requestPromise.succeed(result: .void)
    }

    requestPromise.futureResult.whenComplete {
      ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
      self.reset()
    }
  }

  private func reset() {
    state = .expectingHead
    resourceURI = nil
    expectedLength = 0
    storedLength = 0
    storedData = Data()
    shouldStoreData = false
    requestPromise = nil
  }

}
