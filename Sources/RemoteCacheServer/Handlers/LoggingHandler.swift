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

import NIO
import NIOHTTP1

/// Handler that logs incoming requests for the RemoteCacheServer.
class LoggingHandler: ChannelInboundHandler, ChannelOutboundHandler {
  typealias InboundIn = HTTPServerRequestPart
  typealias OutboundIn = HTTPServerResponsePart

  var requestHead: HTTPRequestHead?

  func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    switch unwrapInboundIn(data) {
    // Intercept incoming request headers.
    case .head(let requestHead):
      self.requestHead = requestHead
    default:
      break
    }
    ctx.fireChannelRead(data)
  }

  func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    // Intercept outgoing headers, and print them.
    switch unwrapOutboundIn(data) {
    case .head(let responseHead):
      if let requestHead = requestHead {
        printLog(requestHead: requestHead, responseHead: responseHead)
      }
    case .end:
      // Reset state for the logger, in case the connection is reused.
      requestHead = nil
    default:
      break
    }
    ctx.write(data, promise: promise)
  }

  private func printLog(requestHead: HTTPRequestHead, responseHead: HTTPResponseHead) {
    var log = "\(requestHead.method) \(requestHead.uri) \(responseHead.status)"
    if let contentLength = requestHead.headers["content-length"].first ?? responseHead.headers["content-length"].first {
      log += " - \(contentLength)"
    }
    print(log)
  }
}
