// System demo: TTS speak, network type, locale/timezone/uptime, settings & App Store.
toast("system-demo.js started");
const systemReport = {};

// 1. Text-to-speech (system AVSpeechSynthesizer, works offline)
const spoke = speak("你好，这是 AutoSDK 系统能力示例", { rate: 0.5 });
systemReport.spoke = spoke;
sleep(4000);

// 2. Network type: wifi / cellular / none
systemReport.networkType = device.getNetworkType();
systemReport.isWifi = device.isWifi();

// 3. Locale / timezone / uptime
systemReport.language = device.getLanguage();
systemReport.country = device.getCountry();
systemReport.locale = device.getLocale();
systemReport.timezone = device.getTimezone();
systemReport.uptimeSeconds = device.getUptime();

// 4. Screen keep-on toggle (prevents auto-lock while a long task runs)
device.keepScreenOn(true);
sleep(1000);
device.keepScreenOn(false);

// 5. Open this app's settings page (system UI)
systemReport.openSettings = app.openSettings();

// 6. Stop speech if still speaking
speechStop();

systemReport;
