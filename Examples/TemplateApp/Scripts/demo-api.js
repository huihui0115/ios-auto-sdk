// AutoSDK API showcase: device, files, storage, timers and system control.
// Self-contained: it does not depend on specific UI in the host app.
const report = {};

// 1. Device information
report.device = {
  model: device.getModel(),
  os: device.getOSVersion(),
  battery: device.getBattery(),
  charging: device.isCharging(),
  orientation: device.getOrientation(),
  scale: device.getScale(),
};

// 2. Sandbox files
file.mkdirs("demo");
file.writeText("demo/report.txt", JSON.stringify(report.device));
report.fileRoundTrip = file.readText("demo/report.txt").length > 0;
report.fileList = file.listDir("demo");
file.deleteAllFile("demo/report.txt");

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

report;
