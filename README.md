# Remote Cache Server

This is an HTTP server optimized for Bazel
[Remote Caching](https://docs.bazel.build/versions/master/remote-caching.html).

## Usage note

In order to run, clone this repository and execute it with:
```
swift run RemoteCacheServer
```

### Available options:
* `--host HOST`: Defaults to `127.0.0.1`. Bazel does not support IPV6.
* `--port PORT`: Defaults to `9000`.
* `--storage_path`: Defaults to empty. If not specified, an in-memory cache will be used,
  meaning that the cache will be lost when the server is killed. If this option is specified,
  a file system cache will be used, which is persisted across server restarts.

## Changelog

* **0.1.0 (2019.01.05):** Initial release.
