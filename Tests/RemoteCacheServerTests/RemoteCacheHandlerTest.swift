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

@testable import NIO
import NIOFoundationCompat
import NIOHTTP1
@testable import RemoteCacheServer
import XCTest

class RemoteCacheOutboundTestHandler: ChannelOutboundHandler {
  typealias OutboundIn = HTTPServerResponsePart
  
  var responseParts = [HTTPServerResponsePart]()
  
  func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    responseParts.append(unwrapOutboundIn(data))
  }
  
  func assertPartReceived(_ expectedPart: HTTPServerResponsePart) {
    XCTAssertEqual(responseParts.removeFirst(), expectedPart)
  }

  func assertNoParts() {
    XCTAssertEqual(responseParts.count, 0)
  }
}

class RemoteCacheHandlerTest: XCTestCase {
  var serverChannel: EmbeddedChannel!
  let httpVersion = HTTPVersion(major: 1, minor: 1)
  var outboundTestHandler: RemoteCacheOutboundTestHandler!

  override func setUp() {
    serverChannel = EmbeddedChannel()
    outboundTestHandler = RemoteCacheOutboundTestHandler()
  }

  override func tearDown() {
    serverChannel = nil
  }

  func setupServerChannel() throws {
    XCTAssertNoThrow(
      try serverChannel.pipeline.add(handler: outboundTestHandler)
        .then { self.serverChannel.pipeline.add(handler: RemoteCacheHandler(storage: InMemoryStorage())) }
        .wait()
    )
  }

  func testGetNotFound() throws {
    try setupServerChannel()

    let requestHead = HTTPRequestHead(version: httpVersion, method: .GET, uri: "/fake/path")

    try serverChannel.writeInbound(HTTPServerRequestPart.head(requestHead))
    try serverChannel.writeInbound(HTTPServerRequestPart.end(nil))

    outboundTestHandler.assertPartReceived(
      HTTPServerResponsePart.head(HTTPResponseHead(version: httpVersion, status: .notFound))
    )
    outboundTestHandler.assertPartReceived(HTTPServerResponsePart.end(nil))
    outboundTestHandler.assertNoParts()
  }
  
  func testPutFile() throws {
    try setupServerChannel()
    
    let data = "my contents".data(using: .utf8)!
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.write(bytes: data)
    
    var requestHead = HTTPRequestHead(version: httpVersion, method: .PUT, uri: "/fake/path")
    requestHead.headers.add(name: "content-length", value: String(data.count))

    try serverChannel.writeInbound(HTTPServerRequestPart.head(requestHead))
    try serverChannel.writeInbound(HTTPServerRequestPart.body(buffer))
    try serverChannel.writeInbound(HTTPServerRequestPart.end(nil))
    
    outboundTestHandler.assertPartReceived(
      HTTPServerResponsePart.head(HTTPResponseHead(version: httpVersion, status: .ok))
    )
    outboundTestHandler.assertPartReceived(HTTPServerResponsePart.end(nil))
    outboundTestHandler.assertNoParts()
  }

  func testPutAndGetFile() throws {
    try setupServerChannel()

    var requestHead = HTTPRequestHead(version: httpVersion, method: .GET, uri: "/fake/path")

    try serverChannel.writeInbound(HTTPServerRequestPart.head(requestHead))
    try serverChannel.writeInbound(HTTPServerRequestPart.end(nil))

    outboundTestHandler.assertPartReceived(
      HTTPServerResponsePart.head(HTTPResponseHead(version: httpVersion, status: .notFound))
    )
    outboundTestHandler.assertPartReceived(HTTPServerResponsePart.end(nil))
    outboundTestHandler.assertNoParts()

    let data = "my contents".data(using: .utf8)!
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.write(bytes: data)

    requestHead = HTTPRequestHead(version: httpVersion, method: .PUT, uri: "/fake/path")
    requestHead.headers.add(name: "content-length", value: String(data.count))

    try serverChannel.writeInbound(HTTPServerRequestPart.head(requestHead))
    try serverChannel.writeInbound(HTTPServerRequestPart.body(buffer))
    try serverChannel.writeInbound(HTTPServerRequestPart.end(nil))

    outboundTestHandler.assertPartReceived(
      HTTPServerResponsePart.head(HTTPResponseHead(version: httpVersion, status: .ok))
    )
    outboundTestHandler.assertPartReceived(HTTPServerResponsePart.end(nil))
    outboundTestHandler.assertNoParts()

    requestHead = HTTPRequestHead(version: httpVersion, method: .GET, uri: "/fake/path")

    try serverChannel.writeInbound(HTTPServerRequestPart.head(requestHead))
    try serverChannel.writeInbound(HTTPServerRequestPart.end(nil))

    var responseHead = HTTPResponseHead(version: httpVersion, status: .ok)
    responseHead.headers.add(name: "content-length", value: String(data.count))
    responseHead.headers.add(name: "content-type", value: "application/octet-stream")

    outboundTestHandler.assertPartReceived(HTTPServerResponsePart.head(responseHead))
    outboundTestHandler.assertPartReceived(HTTPServerResponsePart.body(.byteBuffer(buffer)))
    outboundTestHandler.assertPartReceived(HTTPServerResponsePart.end(nil))
    outboundTestHandler.assertNoParts()
  }
}
