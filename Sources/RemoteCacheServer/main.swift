import Commander
import Foundation

let hostOption = Option("host", default: "127.0.0.1", description: "host for the server")
let portOption = Option("port", default: 9000, description: "port for the server")
let storagePathOption = Option("storage_path", default: "", description: "storage path. If nil, in memory storage")
let verboseFlag = Flag("verbose", default: false, description: "whether to show logs")

command(hostOption, portOption, storagePathOption, verboseFlag) { host, port, storagePath, verbose in
  let storageType: StorageType
  if storagePath.utf8.count > 0 {
    storageType = .filesystem(storagePath)
    print("Using local storage in '\(storagePath)'")
  } else {
    storageType = .inMemory
    print("Using in-memory storage")
  }

  let server = RemoteCacheServer(host: host,
                                 port: port,
                                 storageType: storageType,
                                 verbose: verbose)

  do {
    // server.start() will block the thread while the server is running.
    try server.start()
  } catch let error {
    print("Error: \(error.localizedDescription)")
    server.stop()
  }
}.run()
