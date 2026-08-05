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

report;
