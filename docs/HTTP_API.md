# HTTP API

Network access is disabled by default. Enable it only for a trusted script
source:

```objc
[[AutoEngine sharedEngine] configureWithConfig:@{
    @"allowNetwork": @YES
}];
```

Requests are synchronous from the script's point of view while the engine
continues pumping the main run loop. URLs must use `http` or `https`.

```javascript
const response = auto.http("https://example.com/api", {
  method: "POST",
  headers: {"Authorization": "Bearer token"},
  body: {"enabled": true},
  timeout: 10000
});

if (response.status === 200) {
  console.log(response.json || response.body);
}
```

The response contains `status`, `headers`, and a UTF-8 `body`. JSON bodies
also receive a parsed `json` field. `bodyBase64` is present for binary-safe
handling. Responses also include `statusCode`, `ok`, and the final `url`.
For a lower peak memory footprint, set `includeBody`, `includeBase64`, or
`parseJson` to `false` when that representation is not needed. The skipped
string field remains present as an empty string for compatibility.

Convenience methods include `auto.httpGet`, `auto.httpPost`,
`http.request`, `http.get`, `http.post`, `http.postJSON`, and
`http.downloadFile`. Downloads use `NSURLSessionDownloadTask`, stay in a
temporary file instead of crossing the JavaScript bridge as base64, and are
atomically installed below the configured AutoSDK file root. The destination
and write policy are validated before the request starts. Empty files are
supported. Set `requireSuccess: true` to reject non-2xx responses; the default
remains `false` for compatibility with earlier releases.

The URLSession completion callback only moves a completed download into an SDK
temporary staging file. The script thread installs that file after confirming
the request completed and the script was not cancelled. Timeout, cancellation,
HTTP failure, and install failure paths remove the staging file, so a late
completion callback cannot modify the requested destination.

Use `allowedNetworkHosts` for an exact host allowlist, `maxHTTPRequestBytes`
for a request-body limit, and `maxHTTPResponseBytes` for a response limit.
Host lists accept at most 256 non-empty host strings; invalid list types or
entries fail closed before a request starts, and the same immutable list is
used for redirects. Both byte limits default to 10 MiB and have a 64 MiB hard
maximum:

```objc
[engine configureWithConfig:@{
    @"allowNetwork": @YES,
    @"allowedNetworkHosts": @[@"api.example.com"],
    @"maxHTTPRequestBytes": @(1 * 1024 * 1024),
    @"maxHTTPResponseBytes": @(2 * 1024 * 1024)
}];
```

Requests accept at most 128 headers. Header names are limited to 256
characters and values to 8,192 characters; control characters are rejected.
Responses accept at most 256 fields, 128 KiB of copied header text, 1,024
characters per name, and 16,384 characters per value.

Normal responses are received incrementally and each chunk is checked before
it is appended to the SDK response buffer. Downloads are written to a
temporary file. In both modes URLSession's expected/received byte counts and
the completed length are checked as additional defenses for compressed and
chunked responses.

The host remains responsible for TLS pinning and authentication. The current
JavaScript facade is synchronous and pumps the main run loop while URLSession
performs network I/O.

Remote JavaScript loading is a separate capability. Enable
`allowRemoteScripts`, optionally restrict `allowedRemoteScriptHosts`, and set
`remoteScriptTimeout` in seconds. Remote script redirects are restricted to
the configured host list, or to the original host when no list is provided.
