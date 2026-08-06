// Gesture demo: swipe, explicit gesture tracks, and multi-touch pinch.
// Multi-touch APIs are guarded by the automation capability reported by the adapter.
toast("gesture-demo.js started");
const gestureReport = {};
const gestureAutomation = /** @type {Record<string, unknown> | undefined} */ (auto.capabilities().automation);
const gestureMultiTouch = gestureAutomation != null && gestureAutomation.multiTouch === true;

// 1. Simple swipe (single finger)
gestureReport.swipe = auto.swipe(120, 320, 120, 180, 250);

// 2. Explicit single-finger gesture track
gestureReport.gesture = auto.gesture([
  { type: "down", x: 100, y: 260 },
  { type: "move", x: 160, y: 260, duration: 150 },
  { type: "move", x: 160, y: 320, duration: 150 },
  { type: "up" }
]);

// 3. Multi-touch pinch and custom multi-finger tracks (built-in no-WDA adapter multiTouch)
if (gestureMultiTouch) {
  gestureReport.pinch = auto.pinch(160, 300, 2.0, 300);
  gestureReport.multiGesture = auto.multiGesture([
    [
      { type: "down", x: 100, y: 300 },
      { type: "move", x: 100, y: 220, duration: 200 },
      { type: "up" }
    ],
    [
      { type: "down", x: 220, y: 300 },
      { type: "move", x: 220, y: 220, duration: 200 },
      { type: "up" }
    ]
  ]);
} else {
  gestureReport.pinch = "disabled (adapter has no multiTouch)";
  gestureReport.multiGesture = "disabled (adapter has no multiTouch)";
}

gestureReport;