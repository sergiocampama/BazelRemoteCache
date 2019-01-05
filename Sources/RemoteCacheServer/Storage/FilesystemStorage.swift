import Dispatch
import Foundation
import NIO

class FilesystemStorage: CacheStorage {
  private let localPath: String
  private let concurrentFileQueue = DispatchQueue(label: "com.google.remote_cache.file", attributes: .concurrent)

  init(localPath: String) {
    self.localPath = localPath
    if !FileManager.default.fileExists(atPath: localPath + "/ac") {
      do {
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: localPath + "/ac"),
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: localPath + "/cas"),
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
      } catch let error {
        fatalError("Could not initialize FilesystemStorage: \(error)")
      }
    }
  }

  func contains(_ resourceURI: String) -> Bool {
    let url = URL(fileURLWithPath: localPath).appendingPathComponent(resourceURI).path
    return FileManager.default.fileExists(atPath: url)
  }

  func read(_ resourceURI: String) -> IOData? {
    let url = URL(fileURLWithPath: localPath).appendingPathComponent(resourceURI).path

    if let fileHandle = try? FileHandle(path: url),
      let fileRegion = try? FileRegion(fileHandle: fileHandle) {
      return .fileRegion(fileRegion)
    }
    fatalError("Could not read file \(resourceURI)")
    return nil
  }

  func write(_ resourceURI: String, data: Data) {
    let url = URL(fileURLWithPath: localPath).appendingPathComponent(resourceURI)
    concurrentFileQueue.async {
      do {
        try data.write(to: url, options: [.atomic])
      } catch let error {
        fatalError("Could not write file: \(error)")
      }
    }
  }
}
