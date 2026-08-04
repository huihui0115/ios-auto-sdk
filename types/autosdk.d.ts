type AutoColor = string | [number, number, number] | { r: number; g: number; b: number };

interface AutoRect {
  x: number;
  y: number;
  width: number;
  height: number;
  centerX?: number;
  centerY?: number;
  mode?: "intersects" | "contains" | "inside";
}

interface AutoSelector {
  handle?: string;
  uid?: string;
  id?: string;
  idMatch?: string;
  idRegex?: string;
  label?: string;
  labelMatch?: string;
  labelRegex?: string;
  name?: string;
  nameMatch?: string;
  nameRegex?: string;
  text?: string;
  textMatch?: string;
  textRegex?: string;
  value?: string;
  valueMatch?: string;
  valueRegex?: string;
  type?: string;
  typeMatch?: string;
  typeRegex?: string;
  enabled?: boolean;
  enable?: boolean;
  visible?: boolean;
  selected?: boolean;
  accessible?: boolean;
  index?: number;
  depth?: number;
  childCount?: number;
  childcount?: number;
  bounds?: AutoRect;
  maxResults?: number;
  includeInvisible?: boolean;
  xpath?: string;
  predicate?: string;
  classChain?: string;
}

type AutoSelectorLike = string | AutoSelector | AutoNode;

interface AutoNode {
  selector: AutoSelectorLike | { handle: string };
  handle: string;
  elementId?: string;
  wdElementId?: string;
  sessionId?: string;
  sourceDerived?: boolean;
  uid?: string;
  nodeId?: string;
  parentId?: string | null;
  id?: string | null;
  label?: string | null;
  name?: string | null;
  value?: string | null;
  text?: string | null;
  type?: string;
  className?: string;
  enabled?: boolean;
  selected?: boolean;
  accessible?: boolean;
  visible?: boolean;
  index?: number;
  order?: number;
  depth?: number;
  childCount?: number;
  bounds?: AutoRect;
}

interface AutoMatch {
  found: boolean;
  truncated?: boolean;
  coarseCandidates?: number;
  verifiedCandidates?: number;
  comparedPixelBudget?: number;
  scannedCandidates?: number;
  comparedPixels?: number;
  effectiveStep?: number;
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  centerX?: number;
  centerY?: number;
  similarity?: number;
}

interface AutoImageOptions {
  region?: AutoRect;
  threshold?: number;
  /** Coarse origin step. Defaults to 1 and may grow to satisfy maxCandidates. */
  step?: number;
  verifyStep?: number;
  /** Shared coarse + verification budget. Defaults to 200,000; maximum 5,000,000. */
  maxCandidates?: number;
  /** Worst-case sampled-pixel budget. Defaults to 50,000,000; maximum 500,000,000. */
  maxComparedPixels?: number;
}

interface AutoOCROptions {
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  mode?: "fast" | "accurate";
  accurate?: boolean;
  languageCorrection?: boolean;
  languages?: string[];
  customWords?: string[];
  minimumTextHeight?: number;
  maxResults?: number;
}

interface AutoColorPoint {
  x: number;
  y: number;
  color: AutoColor;
  tolerance?: number;
}

interface AutoColorSearchOptions {
  tolerance?: number;
  /** Origin step. Defaults to 1 and may grow to satisfy maxCandidates. */
  step?: number;
  /** Origin scan budget. Defaults to 200,000; values are clamped to 1,000-5,000,000. */
  maxCandidates?: number;
  /** Actual base/offset comparison budget. Defaults to 50,000,000; maximum 500,000,000. */
  maxComparedPixels?: number;
}

interface AutoPixelColor {
  x: number;
  y: number;
  r: number;
  g: number;
  b: number;
  a: number;
  hex: string;
}

interface AutoColorOffset {
  dx: number;
  dy: number;
  color: AutoColor;
  tolerance?: number;
}

type AutoColorOffsetLike = AutoColorOffset | [number, number, AutoColor];

interface AutoOCRItem {
  text: string;
  confidence: number;
  bounds: AutoRect;
  normalizedBounds: AutoRect;
}

interface AutoHTTPOptions {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE" | "HEAD" | "OPTIONS";
  headers?: Record<string, string>;
  body?: string | Record<string, unknown> | unknown[];
  bodyBase64?: string;
  followRedirects?: boolean;
  timeout?: number;
  /** Set false to skip constructing the UTF-8 response copy. */
  includeBody?: boolean;
  /** Set false to skip constructing the base64 response copy. */
  includeBase64?: boolean;
  /** Set false to skip JSON parsing. */
  parseJson?: boolean;
  /** For downloadFile only, reject non-2xx responses before installing the file. */
  requireSuccess?: boolean;
}

interface AutoHTTPResponse {
  status: number;
  statusCode: number;
  ok: boolean;
  url: string;
  headers: Record<string, string>;
  body: string;
  bodyBase64: string;
  json?: unknown;
}

interface AutoHTTP {
  (url: string, options?: AutoHTTPOptions): AutoHTTPResponse;
  request(url: string, options?: AutoHTTPOptions): AutoHTTPResponse;
  get(url: string, options?: AutoHTTPOptions): AutoHTTPResponse;
  httpGet(url: string, options?: AutoHTTPOptions): AutoHTTPResponse;
  getJSON(url: string, options?: AutoHTTPOptions): AutoHTTPResponse;
  post(url: string, body?: unknown, options?: AutoHTTPOptions): AutoHTTPResponse;
  httpPost(url: string, body?: unknown, options?: AutoHTTPOptions): AutoHTTPResponse;
  postJSON(url: string, body?: unknown, options?: AutoHTTPOptions): AutoHTTPResponse;
  downloadFile(url: string, path: string, options?: AutoHTTPOptions): boolean;
  httpGetDefault(url: string, options?: AutoHTTPOptions): AutoHTTPResponse;
  downloadFileDefault(url: string, path: string, options?: AutoHTTPOptions): boolean;
}

interface AutoFileEntry {
  name: string;
  path: string;
  isDirectory: boolean;
  size: number;
  modifiedAtMs: number | null;
}

interface AutoFileAPI {
  sandboxDir(): string;
  getSandBoxDir(): string;
  resolvePath(path: string): string;
  getSandBoxFilePath(path: string): string;
  exists(path: string): boolean;
  readText(path: string): string;
  readFile(path: string): string;
  readBase64(path: string): string;
  readLines(path: string): string[];
  readAllLines(path: string): string[];
  readLine(path: string, index: number): string | null;
  writeText(path: string, text: string): boolean;
  writeFile(path: string, text: string): boolean;
  writeBase64(path: string, base64: string): boolean;
  create(path: string): boolean;
  appendText(path: string, text: string): boolean;
  appendLine(path: string, text: string): boolean;
  deleteLine(path: string, index: number): boolean;
  list(path?: string): AutoFileEntry[];
  listDir(path?: string): string[];
  mkdir(path: string): boolean;
  mkdirs(path: string): boolean;
  remove(path: string): boolean;
  deleteAllFile(path: string): boolean;
  copy(source: string, destination: string, overwrite?: boolean): boolean;
  writeLines(path: string, lines: string[]): boolean;
  move(source: string, destination: string, overwrite?: boolean): boolean;
  rename(path: string, newName: string): boolean;
}

interface AutoStorage {
  keys(): string[];
  all(): Record<string, unknown>;
  put(key: string, value: unknown): boolean;
  putString(key: string, value: string): boolean;
  putInt(key: string, value: number): boolean;
  putBoolean(key: string, value: boolean): boolean;
  putFloat(key: string, value: number): boolean;
  get<T>(key: string, defaultValue?: T): T;
  getString(key: string, defaultValue?: string): string | null;
  getInt(key: string, defaultValue?: number): number;
  getBoolean(key: string, defaultValue?: boolean): boolean;
  getFloat(key: string, defaultValue?: number): number;
  remove(key: string): boolean;
  contains(key: string): boolean;
  clear(): boolean;
}

interface AutoDeviceAPI {
  info(): Record<string, unknown>;
  getDeviceInfo(): Record<string, unknown>;
  width(): number;
  height(): number;
  scale(): number;
  getScreenWidth(): number;
  getScreenHeight(): number;
  getScale(): number;
  getModel(): string;
  getOSVersion(): string;
  getDeviceName(): string;
  getBattery(): number | null;
  isCharging(): boolean;
  getOrientation(): string;
  getMemoryInfo(): { totalBytes: number; freeBytes: number; appUsedBytes: number };
  getClipboard(): string | null;
  setClipboard(text: string): boolean;
  getBrightness(): number;
  setBrightness(value: number): boolean;
  getVolume(): number;
  vibrate(durationMs?: number): boolean;
}

interface AutoMediaAPI {
  saveImage(path: string): boolean;
  saveImageBase64(base64: string): boolean;
  saveVideo(path: string): boolean;
  saveScreenshot(): boolean;
}

type AutoGestureAction =
  | { type: "down"; x: number; y: number }
  | { type: "move"; x: number; y: number; duration?: number }
  | { type: "up" }
  | { type: "wait"; duration: number }
  | { type: string; [key: string]: unknown };

interface AutoGestureAPI {
  gesture(actions: AutoGestureAction[]): boolean;
  multiGesture(fingers: AutoGestureAction[][]): boolean;
  pinch(x: number, y: number, scale: number, durationMs?: number): boolean;
}

interface AutoAppAPI {
  launch(bundleId: string): boolean;
  activate(bundleId: string): boolean;
  terminate(bundleId: string): boolean;
  state(bundleId: string): number;
  openURL(url: string): boolean;
  homeScreen(): boolean;
  lock(): boolean;
  unlock(): boolean;
}

interface AutoAPI {
  click(selector: AutoSelectorLike): boolean;
  clickPoint(x: number, y: number): boolean;
  doubleClickPoint(x: number, y: number, intervalSeconds?: number): boolean;
  longClick(selector: AutoSelectorLike, durationSeconds?: number): boolean;
  swipe(x1: number, y1: number, x2: number, y2: number, durationSeconds?: number): boolean;
  input(selector: AutoSelectorLike, text: string): boolean;
  setText(selector: AutoSelectorLike, text: string): boolean;
  sleep(milliseconds: number): boolean;
  getClipboard(): string | null;
  setClipboard(text: string): boolean;
  getBrightness(): number;
  setBrightness(value: number): boolean;
  getVolume(): number;
  vibrate(durationMs?: number): boolean;
  toast(message: string): boolean;
  toastLog(message: string): void;
  openURL(url: string): boolean;
  getText(selector: AutoSelectorLike): string | null;
  findElement(selector: AutoSelectorLike): AutoNode | null;
  findElements(selector: AutoSelectorLike): AutoNode[];
  exists(selector: AutoSelectorLike): boolean;
  waitFor(selector: AutoSelectorLike, timeoutMs?: number): boolean;
  getAttribute(selector: AutoSelectorLike, name: string): unknown;
  getBounds(selector: AutoSelectorLike): AutoRect | null;
  getChildren(selector: AutoSelectorLike): AutoNode[];
  getParent(selector: AutoSelectorLike): AutoNode | null;
  getChild(selector: AutoSelectorLike, index: number): AutoNode | null;
  getSiblings(node: AutoNode): AutoNode[];
  getPreviousSiblings(node: AutoNode): AutoNode[];
  getNextSiblings(node: AutoNode): AutoNode[];
  scrollIntoView(selector: AutoSelectorLike): boolean;
  launchApp(bundleId: string): boolean;
  activateApp(bundleId: string): boolean;
  terminateApp(bundleId: string): boolean;
  appState(bundleId: string): number;
  gesture(actions: AutoGestureAction[]): boolean;
  multiGesture(fingers: AutoGestureAction[][]): boolean;
  pinch(x: number, y: number, scale: number, durationMs?: number): boolean;
  clickCenter(selector: AutoSelectorLike): boolean;
  clickRandom(selector: AutoSelectorLike): boolean;
  screenshot(): string;
  saveImageToAlbum(path: string): boolean;
  saveImageBase64ToAlbum(base64: string): boolean;
  saveVideoToAlbum(path: string): boolean;
  saveScreenshotToAlbum(): boolean;
  findImage(path: string, options?: AutoImageOptions): AutoMatch;
  findColor(color: AutoColor, region?: AutoRect, options?: AutoColorSearchOptions): AutoMatch;
  getPixelColor(x: number, y: number): AutoPixelColor;
  compareColors(points: AutoColorPoint[], options?: { tolerance?: number }): boolean;
  cmpColor(points: AutoColorPoint[], options?: { tolerance?: number }): boolean;
  findMultiColor(color: AutoColor, offsets: AutoColorOffsetLike[], region?: AutoRect, options?: AutoColorSearchOptions): AutoMatch;
  ocr(options?: AutoOCROptions): AutoOCRItem[];
  http: AutoHTTP;
  httpGet(url: string, options?: AutoHTTPOptions): AutoHTTPResponse;
  httpPost(url: string, body?: unknown, options?: AutoHTTPOptions): AutoHTTPResponse;
  file: AutoFileAPI;
  storage(name: string): AutoStorage;
  device: AutoDeviceAPI;
  media: AutoMediaAPI;
  app: AutoAppAPI;
  capabilities(): Record<string, unknown>;
  time(): number;
  randomInt(min: number, max?: number): number;
  [nativeMethod: string]: any;
}

declare const auto: AutoAPI;
declare function toast(message: string): boolean;
declare function toastLog(message: string): void;
declare const file: AutoFileAPI;
declare const storages: { create(name: string): AutoStorage };
declare const device: AutoDeviceAPI;
declare const media: AutoMediaAPI;
declare const app: AutoAppAPI;
declare const http: AutoHTTP;
declare const image: {
  findImage: AutoAPI["findImage"];
  findColor: AutoAPI["findColor"];
  findMultiColor: AutoAPI["findMultiColor"];
  cmpColor: AutoAPI["compareColors"];
  pixel: AutoAPI["getPixelColor"];
  screenshot: AutoAPI["screenshot"];
  saveToAlbum: AutoAPI["saveImageToAlbum"];
  saveBase64ToAlbum: AutoAPI["saveImageBase64ToAlbum"];
  saveScreenshotToAlbum: AutoAPI["saveScreenshotToAlbum"];
};

interface AutoMetrics {
  width: number;
  height: number;
  screenWidth: number;
  screenHeight: number;
  scaleX: number;
  scaleY: number;
}

interface AutoMetricsAPI {
  set(width: number, height: number): boolean;
  get(): AutoMetrics;
  x(value: number): number;
  y(value: number): number;
  point(x: number, y: number): { x: number; y: number };
}

interface AutoBase64 {
  encode(text: string): string;
  decode(base64: string): string;
}

interface AutoConsole {
  log(...values: unknown[]): void;
  debug(...values: unknown[]): void;
  info(...values: unknown[]): void;
  warn(...values: unknown[]): void;
  error(...values: unknown[]): void;
  time(label?: string): void;
  timeEnd(label?: string): number | null;
}

declare const console: AutoConsole;
declare function setTimeout(callback: (...args: any[]) => void, milliseconds?: number, ...args: any[]): number;
declare function clearTimeout(timerId: number): void;
declare function cancelTimeout(timerId: number): void;
declare function setInterval(callback: (...args: any[]) => void, milliseconds?: number, ...args: any[]): number;
declare function clearInterval(timerId: number): void;
declare function cancelInterval(timerId: number): void;

declare function clickPoint(x: number, y: number): boolean;
declare function doubleClickPoint(x: number, y: number, intervalSeconds?: number): boolean;
declare function swipeToPoint(x1: number, y1: number, x2: number, y2: number, durationSeconds?: number): boolean;
declare function sleep(milliseconds: number): boolean;
declare function saveImageToAlbum(path: string): boolean;
declare function saveImageBase64ToAlbum(base64: string): boolean;
declare function saveVideoToAlbum(path: string): boolean;
declare function saveScreenshotToAlbum(): boolean;
declare function time(): number;
declare function random(min: number, max?: number): number;
declare function randomInt(min: number, max?: number): number;
declare function setScreenMetrics(width: number, height: number): boolean;
declare function getScreenMetrics(): AutoMetrics;
declare const metrics: AutoMetricsAPI;
declare function uuid(): string;
declare function uniqueId(): string;
declare const base64: AutoBase64;
declare function clickCenter(selector: AutoSelectorLike): boolean;
declare function gesture(actions: AutoGestureAction[]): boolean;
declare function multiGesture(fingers: AutoGestureAction[][]): boolean;
declare function pinch(x: number, y: number, scale: number, durationMs?: number): boolean;
declare function clickRandom(selector: AutoSelectorLike): boolean;
declare function openURL(url: string): boolean;
declare function getClipboard(): string | null;
declare function setClipboard(text: string): boolean;
declare function getBrightness(): number;
declare function setBrightness(value: number): boolean;
declare function getVolume(): number;
declare function vibrate(durationMs?: number): boolean;
declare function logd(...values: unknown[]): void;
declare function logi(...values: unknown[]): void;
declare function logw(...values: unknown[]): void;
declare function loge(...values: unknown[]): void;
