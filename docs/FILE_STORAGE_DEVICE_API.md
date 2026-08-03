# File, storage and device APIs

## File sandbox

Script file paths are confined to `Documents/AutoSDK` by default. Configure a
different directory inside the app sandbox with `fileRoot`. Reads and writes
can be disabled independently:

```objc
[engine configureWithConfig:@{
    @"allowFileAccess": @YES,
    @"allowFileWrite": @YES,
    @"fileRoot": @"AutomationData",
    @"maxFileReadBytes": @(10 * 1024 * 1024),
    @"maxFileWriteBytes": @(10 * 1024 * 1024),
    @"maxFileCopyBytes": @(10 * 1024 * 1024),
    @"maxFileListItems": @2000,
    @"maxFileOperationItems": @4096,
    @"maxFileLineCount": @100000
}];
```

Read and write limits default to 10 MiB and have 64 MiB hard maximums. File
metadata and base64 encoded length are checked before allocating or decoding;
the decoded size is checked again before the operation completes. The write
limit applies to the resulting size of an appended file. Copies default to
the write-byte limit and have the same 64 MiB hard maximum. Directory lists
default to 2,000 entries (10,000 hard maximum); recursive copy/remove work
defaults to 4,096 items (100,000 hard maximum). Exceeding a limit returns an
error instead of silently truncating work. Failed staged copies/downloads are
removed before returning. `readLines` counts newline bytes before creating
line strings and defaults to at most 100,000 lines (1,000,000 hard maximum).

```javascript
file.mkdirs("reports");
file.writeFile("reports/latest.txt", "started");
file.appendLine("reports/latest.txt", "finished");
const text = file.readFile("reports/latest.txt");
const entries = file.listDir("reports");
file.copy("reports/latest.txt", "reports/copy.txt", true);
file.deleteAllFile("reports/copy.txt");
```

Also available: `sandboxDir`, `getSandBoxDir`, `resolvePath`,
`getSandBoxFilePath`, `exists`, `readText`, `readBase64`, `readLines`,
`readAllLines`, `writeText`, `writeBase64`, `appendText`, `mkdir`, `remove`,
`list`, and `copy`.

## Named storage

```javascript
const settings = storages.create("settings");
settings.putString("endpoint", "https://example.com");
settings.putBoolean("enabled", true);
const endpoint = settings.getString("endpoint", "");
const enabled = settings.getBoolean("enabled", false);
```

Stores accept JSON-safe values. Methods are `keys`, `all`, `put`, `get`,
typed `put*`/`get*` wrappers, `contains`, `remove`, and `clear`. Set
`allowStorage` to `NO` to disable the module, `maxStorageBytes` to change the
default 1 MiB per-store limit (hard maximum 16 MiB), or `maxStorageEntries` to
change the default 4,096-key limit (hard maximum 100,000). Stored bytes and
entry counts are checked before use. `clear` remains available to recover a
store whose persisted data is corrupt or exceeds a newly lowered limit.

## Device information

```javascript
const info = device.getDeviceInfo();
console.log(info.systemVersion, info.screenWidth, info.batteryLevel);
console.log(auto.capabilities());
```

The device module exposes public iOS information only. It cannot return a
hardware serial number or control other apps through `AutoUIKitAdapter`.
