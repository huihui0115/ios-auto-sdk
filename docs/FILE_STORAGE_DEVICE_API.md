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
file.writeLines("reports/points.txt", ["1,2", "3,4"]);
file.copy("reports/latest.txt", "reports/copy.txt", true);
file.move("reports/copy.txt", "reports/moved.txt", true);
file.rename("reports/moved.txt", "final.txt");
file.deleteAllFile("reports/final.txt");
```

Also available: `sandboxDir`, `getSandBoxDir`, `resolvePath`,
`getSandBoxFilePath`, `exists`, `readText`, `readBase64`, `readLines`,
`readAllLines`, `readLine` (by index), `writeText`, `writeBase64`, `writeLines`,
`appendText`, `appendLine`, `create`, `deleteLine` (by index), `mkdir`, `remove`,
`list`, `copy`, `move`, and `rename`. `move` /
`rename` respect the same byte/item budgets as `copy` and refuse to move a
path into itself or one of its children.

## Named storage

```javascript
const settings = storages.create("settings");
settings.putString("endpoint", "https://example.com");
settings.putBoolean("enabled", true);
const endpoint = settings.getString("endpoint", "");
const enabled = settings.getBoolean("enabled", false);
```

Stores accept JSON-safe values. Methods are `keys`, `all`, `put`, `get`,
typed wrappers `putString`, `putInt`, `putFloat`, `putBoolean`,
`getString`, `getInt`, `getFloat`, `getBoolean`, plus `contains`, `remove`, and `clear`. Set
`allowStorage` to `NO` to disable the module, `maxStorageBytes` to change the
default 1 MiB per-store limit (hard maximum 16 MiB), or `maxStorageEntries` to
change the default 4,096-key limit (hard maximum 100,000). Stored bytes and
entry counts are checked before use. `clear` remains available to recover a
store whose persisted data is corrupt or exceeds a newly lowered limit.

## Device information

```javascript
const info = device.getDeviceInfo();
console.log(info.systemVersion, info.screenWidth, info.batteryLevel);
const memory = device.getMemoryInfo(); // { totalBytes, freeBytes, appUsedBytes }
console.log(auto.capabilities());
```

Standalone getters are also available: `getScreenWidth`, `getScreenHeight`,
`getScale`, `getModel`, `getOSVersion`, `getDeviceName`, `getBattery`,
`isCharging` and `getOrientation`.

The device module exposes public iOS information only. Memory figures come
from Mach APIs (`host_statistics64` / `task_info`) and are advisory: they
describe the current process view, not a fixed device quota. It cannot return a
hardware serial number or control other apps through `AutoUIKitAdapter`.

## System control

The engine can also read and write device-global system state from the
process it runs in (the host app in embedded mode, or the automation app in
WDA mode):

```javascript
const clip = device.getClipboard();        // string | null
device.setClipboard("copied text");         // true
const brightness = device.getBrightness(); // 0...1
device.setBrightness(0.5);                  // true (validated to 0...1)
const volume = device.getVolume();         // 0...1 (read-only)
device.vibrate(300);                        // true (advisory duration, capped)
auto.openURL("myapp://open?id=42");        // true when the system opened it
auto.openURL("https://example.com");
app.homeScreen();  // WDA runners: go to the home screen
app.lock();        // WDA runners: lock the device
app.unlock();      // WDA runners: unlock the device
```

Top-level aliases `auto.getClipboard`, `auto.setClipboard`,
`auto.getBrightness`, `auto.setBrightness`, `auto.getVolume`,
`auto.vibrate`, `auto.toast` and `auto.toastLog` are also available.
Clipboard text is capped at 1 MiB; brightness must be in 0...1; `openURL`
accepts `http(s)` URLs and safe custom schemes (file, data, javascript, ftp
and websocket targets are rejected); `homeScreen`/`lock`/`unlock` require
an adapter that implements them (the WDA adapter does; embedded adapters
usually return an unavailable error).

`toast(message)` is built into the engine and shows a short overlay in the
host app's key window; hosts may still override it by registering a native
`toast` method. `toastLog(message)` additionally writes to the script log.

Set `allowSystemControl: @NO` in the configuration to disable clipboard,
brightness, volume, vibration and URL opening (read-only device information
such as `device.getModel()` and `device.getMemoryInfo()` stays available).
The capability is reported as `systemControl` by `auto.capabilities()`.

## Photo library media

The template can add images, videos, and screenshots to the iOS Photos
library (the normal Recents/camera-roll destination). The first write asks for
the iOS add-only Photos permission. The template declares
`NSPhotoLibraryAddUsageDescription`; host applications embedding AutoSDK must
declare the same key in their own `Info.plist`.

```objc
[engine configureWithConfig:@{
    @"allowMediaLibrary": @YES,
    @"maxMediaBytes": @(512 * 1024 * 1024),
    @"maxMediaImageBytes": @(64 * 1024 * 1024)
}];
```

```javascript
media.saveImage("images/result.png");
media.saveImageBase64(auto.screenshot());
media.saveScreenshot();
media.saveVideo("videos/result.mp4");
```

`media.saveImage` and `media.saveVideo` accept files below the AutoSDK file
sandbox. `media.saveImageBase64` accepts strict base64 image data, which makes
it convenient to persist the result of `auto.screenshot()`. All methods return
`true` after Photos confirms the change. Aliases are available as
`auto.saveImageToAlbum`, `auto.saveImageBase64ToAlbum`,
`auto.saveVideoToAlbum`, `auto.saveScreenshotToAlbum`, and the corresponding
global functions. `image.saveToAlbum` and `image.saveScreenshotToAlbum` are
also available for image-oriented scripts.

Set `allowMediaLibrary: @NO` to disable all four operations. `maxMediaBytes`
defaults to 512 MiB (2 GiB hard maximum); `maxMediaImageBytes` defaults to
64 MiB (256 MiB hard maximum). The capability is reported as
`mediaLibraryWrite` by `auto.capabilities()`. A denied Photos permission is
returned as a script error and never silently treated as success.

## Convenience aliases

The bootstrap layer keeps the AutoScript-style names as aliases so scripts
written for AutoScript/Auto.js port over with minimal changes:

- Logs: `logd` / `logi` / `logw` / `loge` alias `console.debug` /
  `console.info` / `console.warn` / `console.error`.
- Timing: `setTimeout` / `setInterval` / `clearTimeout` /
  `clearInterval` (aliases `cancelTimeout` / `cancelInterval`), plus
  `time` / `timeEnd` (console-style timing: `time(label)` starts a timer,
  `timeEnd(label)` prints and returns elapsed ms), and `random` /
  `randomInt` (inclusive range).
- Touch: `clickPoint`, `doubleClickPoint`, `swipeToPoint` (alias of
  `swipe`), `input` / `setText` (aliases: selector + text), `sleep`.
- Image: `image.findImage`, `image.findColor`, `image.findMultiColor`,
  `image.cmpColor`, `image.pixel` (alias of `getPixelColor`),
  `image.screenshot`.
- Top-level globals: `auto`, `file`, `storages` (via `storages.create`),
  `device`, `http` (also `httpGet` / `httpPost`), `app`, `image`,
  `toast`, `toastLog`, `openURL`, `getClipboard`, `setClipboard`,
  `getBrightness`, `setBrightness`, `getVolume`, and `vibrate`.
