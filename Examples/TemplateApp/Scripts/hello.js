// First-run demo: runs anywhere without depending on specific UI.
auto.toast("AutoSDK ready");

// Device information
const info = device.getDeviceInfo();
console.log("model:", info.model, "| iOS:", info.systemVersion);
console.log("battery:", device.getBattery(), "| charging:", device.isCharging());

// Sandbox file round trip
file.mkdirs("demo");
file.writeText("demo/hello.txt", "Hello from AutoSDK!");
console.log("sandbox read:", file.readText("demo/hello.txt"));
file.deleteAllFile("demo/hello.txt");

// Named storage
const helloStore = storages.create("demo");
helloStore.put("firstRun", Date.now());
console.log("storage:", helloStore.get("firstRun"));

// Cooperative timer
let fired = false;
setTimeout(function () { fired = true; }, 10);
auto.sleep(30);
console.log("timer fired:", fired);

// System control
console.log("brightness:", device.getBrightness());
device.setClipboard("AutoSDK demo");
console.log("clipboard:", device.getClipboard());

auto.toast("hello.js finished");
"done";
