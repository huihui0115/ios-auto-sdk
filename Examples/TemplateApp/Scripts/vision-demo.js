// Vision demo: screenshot, pixel color, color search, multi-color compare,
// template image matching and OCR. OCR/image matching are capability-guarded.
toast("vision-demo.js started");
const visionReport = {};
const visionAutomation = /** @type {Record<string, unknown> | undefined} */ (auto.capabilities().automation);
const visionOcr = visionAutomation != null && visionAutomation.ocr === true;
const visionFindImage = visionAutomation != null && visionAutomation.findImage === true;

file.mkdirs("demo");

// 1. Screenshot into the sandbox (base64 PNG)
const visionScreenshot = auto.screenshot();
if (visionScreenshot) {
  file.writeBase64("demo/screen.png", visionScreenshot);
  visionReport.screenshotBytes = file.readBase64("demo/screen.png").length;
} else {
  visionReport.screenshotBytes = 0;
}

// 2. Pixel color at the screen center
const visionMetrics = metrics.get();
const visionCenter = auto.getPixelColor(Math.round(visionMetrics.width / 2), Math.round(visionMetrics.height / 2));
visionReport.centerColor = visionCenter ? visionCenter.hex : null;

// 3. Search a red-ish pixel on screen
const visionColorMatch = auto.findColor("#ff0000",
  { x: 0, y: 0, width: visionMetrics.width, height: visionMetrics.height },
  { tolerance: 40, maxCandidates: 200000 });
visionReport.findColor = visionColorMatch.found;

// 4. Multi-color point comparison at the center
visionReport.cmpColor = auto.cmpColor([
  { x: visionCenter.x, y: visionCenter.y, color: visionCenter.hex, tolerance: 60 }
], { tolerance: 60 });

// 5. OCR (guarded by adapter capability)
if (visionOcr) {
  const visionItems = auto.ocr({ mode: "fast" });
  visionReport.ocrCount = visionItems.length;
  visionReport.ocrSample = visionItems.length ? visionItems[0].text : "";
} else {
  visionReport.ocrCount = "disabled (adapter has no ocr)";
}

// 6. Template image matching: locate the screenshot inside itself
if (visionFindImage && visionScreenshot) {
  file.writeBase64("demo/template.png", visionScreenshot);
  const visionMatch = auto.findImage("demo/template.png",
    { maxCandidates: 200000, maxComparedPixels: 5000000 });
  visionReport.findImage = visionMatch.found;
} else {
  visionReport.findImage = "disabled (adapter has no findImage)";
}

visionReport;