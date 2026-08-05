// AutoSDK API showcase: device, files, storage, timers and system control.
// Self-contained: it does not depend on specific UI in the host app.
toast("demo-api.js started");
toastLog("toast + log helper works");
const report = {};

// 1. Device information
report.device = {
  model: device.getModel(),
  os: device.getOSVersion(),
  battery: device.getBattery(),
  charging: device.isCharging(),
  orientation: device.getOrientation(),
  scale: device.getScale(),
  memoryMB: Math.round(device.getMemoryInfo().totalBytes / (1024 * 1024)),
};

// 2. Sandbox files
file.mkdirs("demo");
file.writeLines("demo/report.txt", [JSON.stringify(report.device), "second line"]);
report.fileRoundTrip = file.readText("demo/report.txt").includes("second line");
file.move("demo/report.txt", "demo/report-moved.txt");
report.fileMoved = file.exists("demo/report-moved.txt") && !file.exists("demo/report.txt");
file.rename("demo/report-moved.txt", "report-final.txt");
report.fileRenamed = file.exists("demo/report-final.txt");
report.fileList = file.listDir("demo");
file.deleteAllFile("demo/report.txt");
file.deleteAllFile("demo/report-moved.txt");
file.deleteAllFile("demo/report-final.txt");

// 3. Named storage
const demoStore = storages.create("demo");
demoStore.put("ranAt", Date.now());
report.storageRoundTrip = demoStore.get("ranAt") != null;
demoStore.clear();

// 4. Cooperative timer
let timerFired = false;
setTimeout(function () { timerFired = true; }, 10);
auto.sleep(30);
report.timerFired = timerFired;

// 5. System control (clipboard, brightness, volume, vibration)
report.brightness = device.getBrightness();
device.setClipboard("AutoSDK demo " + Date.now());
report.clipboard = device.getClipboard();
report.volume = device.getVolume();
device.vibrate(80);

// 6. HTTP is guarded by the capability reported by the host configuration
if (auto.capabilities().http === true) {
  try {
    const response = http.get("https://example.com", { timeout: 5000, includeBody: true, requireSuccess: false });
    report.httpStatus = response && response.status;
  } catch (e) {
    report.httpError = String(e);
  }
} else {
  report.http = "disabled";
}

// 7. Direction swipes and installed-app list (guarded by capabilities)
const caps = auto.capabilities();
if (caps.swipe === true) {
  try {
    report.swipeUp = swipeUp(0.4, 250);
    auto.sleep(300);
    report.swipeDown = swipeDown(0.4, 250);
  } catch (e) {
    report.swipeError = String(e);
  }
} else {
  report.swipe = "disabled";
}
if (caps.appList === true) {
  try {
    const apps = app.appList();
    report.appCount = apps.length;
    report.firstApp = apps.length > 0 ? apps[0].bundleId : null;
  } catch (e) {
    report.appListError = String(e);
  }
} else {
  report.appList = "disabled";
}

// 8. Region color search, audio and photo authorization (guarded by capabilities)
if (caps.findColorEx === true) {
  try {
    const points = findColorEx("0xCDD7E9-0x101010", 0.9, 0, 0, 0, 0, 10, 1);
    report.colorExPoints = points ? points.length : 0;
  } catch (e) {
    report.colorExError = String(e);
  }
} else {
  report.findColorEx = "disabled";
}
if (caps.audioPlayback === true) {
  try {
    report.playMp3 = playMp3("sounds/alert.mp3", 80, false, true);
    auto.sleep(300);
    report.stopMp3 = stopMp3();
  } catch (e) {
    report.audioError = String(e);
  }
} else {
  report.audio = "disabled";
}
report.photoStatus = getPhotoAuthorizationStatus();
const photoStatus = media.requestPhotoAuthorization();
report.photoRequested = photoStatus;

// 9. Image processing pipeline (path-based, file gates apply)
if (file.exists("shots/sample.png")) {
  try {
    const info = image.getSize("shots/sample.png");
    report.imageSize = info ? info.width + "x" + info.height : null;
    report.imageClipped = image.clip("shots/sample.png", 0, 0, info ? info.width : 100, 60, "shots/head.png") != null;
    report.imageScaled = image.scale("shots/sample.png", 100, 200, "shots/small.png") != null;
    report.imageGray = image.gray("shots/sample.png", "shots/gray.png") != null;
    report.imageBinarized = image.binaryzation("shots/sample.png", "shots/bw.png", 128) != null;
    const pixel = image.pixelAt("shots/sample.png", 10, 10);
    report.pixel = pixel ? pixel.hex : null;
  } catch (e) {
    report.imageError = String(e);
  }
} else {
  report.image = "no sample";
}
// 10. ZIP archive (path-based, file gates apply)
try {
  file.writeText("demo/zip-note.txt", "zipped content " + Date.now());
  const zipPath = file.zip("demo/backup.zip", ["demo/zip-note.txt"]);
  report.zipCreated = zipPath != null;
  report.zipUnzipped = file.unzip("demo/backup.zip", "demo/zip-out");
  report.zipEntry = file.readFileInZip("demo/backup.zip", "demo/zip-note.txt");
  file.deleteAllFile("demo/zip-note.txt");
  file.deleteAllFile("demo/backup.zip");
  file.deleteAllFile("demo/zip-out");
} catch (e) {
  report.zipError = String(e);
}
// 11. Excel reading (xlsx/csv) and app identity
try {
  file.writeText("demo/data.csv", "name,age\nAlice,30\nBob,25\n");
  const excelRows = file.readExcelAllRow("demo/data.csv");
  report.excelRows = excelRows.length;
  report.excelFirst = excelRows[0] ? excelRows[0].name : null;
  report.deviceId = device.getDeviceId();
  report.appVersion = getAppVersion();
  report.packageName = getPackageName();
  file.deleteAllFile("demo/data.csv");
} catch (e) {
  report.excelError = String(e);
}
// 12. Real parallel threads (independent JSContext per thread)
try {
  const thread = execAsync(function () {
    const sum = 0;
    return 6 * 7;
  });
  const threadValue = thread.join();
  report.threadResult = threadValue;
  report.threadFinished = thread.isFinished();
  report.threadCancelled = thread.cancel();
  report.execSyncResult = execSync(function () { return 1 + 1; });
} catch (e) {
  report.threadError = String(e);
}
report.findNotColorSupported = typeof findNotColor === "function";

// 13. String toolkit: pinyin, BOM, Unicode, hashes and AES (round 8-11)
try {
  report.strings = {
    trim: strings.trim("  hi  "),
    toPinYin: toPinYin("你好世界"),
    sha256: sha256("hello"),
    isEmail: isEmail("a@b.com"),
    fromUnicode: fromUnicode("\\u4f60\\u597d"),
    stripBom: stripUtf8Bom("\uFEFFabc"),
    aesRoundTrip: strings.aes128Decrypt(strings.aes128Encrypt("secret", "k"), "k") === "secret",
  };
} catch (e) {
  report.stringsError = String(e);
}

// 14. Plist round trip
try {
  file.writePlist("demo/config.plist", { count: 3, enabled: true, name: "AutoSDK" });
  const cfg = file.readPlist("demo/config.plist");
  report.plist = cfg != null && typeof cfg === "object" && "count" in cfg && "name" in cfg && cfg.count === 3 && cfg.name === "AutoSDK";
  file.deleteAllFile("demo/config.plist");
} catch (e) {
  report.plistError = String(e);
}

// 15. Floating overlay: screenDraw rectangle + floatBall (round 11)
try {
  const draw = screenDraw.init();
  screenDraw.setBorderColor(draw, "#00FF00");
  screenDraw.setTitle(draw, "AutoSDK");
  screenDraw.show(draw, 20, 100, 200, 120);
  floatBall.show("运行中", 20, 240);
  report.overlay = draw != null && floatBall.isShow();
  sleep(1200);
  screenDraw.hide(draw);
  floatBall.hide();
} catch (e) {
  report.overlayError = String(e);
}

// 16. Node keep/unkeep registry
try {
  const kept = keepNode({ id: "demo-node" });
  report.nodeKeep = node.keptCount() >= 1;
  unkeepNode(kept);
  report.nodeRelease = node.keptCount() === 0;
} catch (e) {
  report.nodeError = String(e);
}

report;

// 17. Date formatting, random sleep and string toolkit (round 12)
try {
  report.dateFormat = formatDate(time(), "yyyy-MM-dd HH:mm:ss");
  report.dateCustom = dateFormat(time(), "MM-dd E");
  const sleepBefore = Date.now();
  sleepRandom(20, 40);
  report.randomSleepMs = Date.now() - sleepBefore;
  report.strings = {
    startWith: startWith("hello world", "hello"),
    contains: contains("hello", "ell"),
    indexOf: strings.indexOf("abab", "b"),
    replaceAll: strings.replaceAll("a-b-c", "-", "+"),
    padZero: padZero(7, 3),
    format: strings.format("id=%d name=%s", 1, "tom"),
  };
  report.appInstalled = app.isInstalled(getPackageName());
  report.totalMemory = device.getTotalMemory();
  report.lineCount = file.getLineCount !== undefined;
} catch (e) {
  report.round12Error = String(e);
}

// 18. EasyClick-compatible screen module + app name/run state (round 14)
try {
  report.screen = {
    rgb: screen.getColorRGB(10, 10),
    hex: screen.getColorHex(10, 10),
    hasFindImage: typeof screen.findImage === "function",
    hasOcr: typeof screen.ocr === "function",
    compare: screen.isColors([{ x: 10, y: 10, color: screen.getColorHex(10, 10) }]),
  };
  report.stringAlias = string.trim("  alias  ") === "alias";
} catch (e) {
  report.screenError = String(e);
}
if (caps.appList === true) {
  try {
    const firstBundleId = app.appList()[0] && app.appList()[0].bundleId;
    report.appName = app.getAppName(firstBundleId);
    report.appRunning = app.isRunning(firstBundleId);
  } catch (e) {
    report.appInfoError = String(e);
  }
}

report;

