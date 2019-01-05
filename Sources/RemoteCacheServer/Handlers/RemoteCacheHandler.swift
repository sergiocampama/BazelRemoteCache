import Foundation
import NIO
import NIOHTTP1

/// State machine that processes incoming events from the handler.
struct RemoteCacheStateMachine {
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

  init(storage: CacheStorage) {
    self.state = .expectingHead
    self.storage = storage
  }

  mutating func headReceived(_ head: HTTPRequestHead) -> [HTTPServerResponsePart]  {
    precondition(state == .expectingHead, "expected head, was \(state)")
    var responseParts = [HTTPServerResponsePart]()
    resourceURI = head.uri
    switch head.method {
    case .GET:
      if storage.contains(resourceURI), let cachedData = storage.read(resourceURI) {
        var headers = HTTPHeaders()
        headers.add(name: "content-length", value: "\(cachedData.readableBytes)")
        headers.add(name: "content-type", value: "application/octet-stream")
        responseParts.append(.head(HTTPResponseHead(version: httpVersion, status: .ok, headers: headers)))
        responseParts.append(.body(cachedData))
      } else {
        responseParts.append(.head(HTTPResponseHead(version: httpVersion, status: .notFound)))
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
      responseParts.append(.head(HTTPResponseHead(version: httpVersion, status: .methodNotAllowed)))
      state = .expectingEnd
    }
    return responseParts
  }

  mutating func bodyReceived(_ body: inout ByteBuffer) {
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

  mutating func endReceived() -> [HTTPServerResponsePart] {
    precondition(state == .expectingEnd, "expected end, was \(state)")
    guard let resourceURI = resourceURI else {
      fatalError("resourceURI should be set by now")
    }

    var responseParts = [HTTPServerResponsePart]()
    if shouldStoreData {
      responseParts.append(.head(HTTPResponseHead(version: httpVersion, status: .ok)))
      storage.write(resourceURI, data: storedData)
    }
    reset()
    return responseParts
  }

  private mutating func reset() {
    state = .expectingHead
    resourceURI = nil
    expectedLength = 0
    storedLength = 0
    storedData = Data()
    shouldStoreData = false
  }
}

/// Handler that manages remote cache events. It only supports PUT and GET requests.
class RemoteCacheHandler {
  private var stateMachine: RemoteCacheStateMachine
  private var filesToClose = [FileRegion]()

  init(storage: CacheStorage) {
    stateMachine = RemoteCacheStateMachine(storage: storage)
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
      for part in stateMachine.headReceived(requestHead) {
        // In case there were FileRegion objects being returned, capture them to be closed
        // when the handler is being removed.
        if case .body(let body) = part, case .fileRegion(let fileRegion) = body {
          filesToClose.append(fileRegion)
        }
        ctx.write(wrapOutboundOut(part), promise: nil)
      }
    case .body(var body):
      stateMachine.bodyReceived(&body)
    case .end(_):
      for part in stateMachine.endReceived() {
        ctx.write(wrapOutboundOut(part), promise: nil)
      }
      ctx.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
  }
}
