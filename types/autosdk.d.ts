type AutoColor = string | [number, number, number] | { r: number; g: number; b: number };
type AutoPoint = { x: number; y: number };
type AutoColorExInput = string | Array<string | AutoColor | [number, number, number, number]>;

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
  lineCount(path: string): number;
  getLineCount(path: string): number;
  getLineText(path: string, index: number): string | null;
  insertLineText(path: string, index: number, text: string): boolean;
  resetLineText(path: string, index: number, text: string): boolean;
  readPlist(path: string): unknown;
  writePlist(path: string, value: unknown): boolean;
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
  stat(path: string): AutoFileStat | null;
  getSize(path: string): number | null;
  getModifiedTime(path: string): number | null;
  isDir(path: string): boolean;
  isFile(path: string): boolean;
  imageSize(path: string): { width: number; height: number; pixelWidth: number; pixelHeight: number; scale: number } | null;
  md5(path: string): string;
  md5File(path: string): string;
  sha1(path: string): string;
  sha1File(path: string): string;
  zip(destination: string, sources: string[], passwd?: string): string | null;
  unzip(zipPath: string, destination: string, passwd?: string): boolean;
  readFileInZip(zipPath: string, entry: string, passwd?: string): string | null;
  readExcelAllRow(path: string, sheetIndex?: number): Array<Record<string, string | number>>;
  readExcelRow(path: string, sheetIndex?: number, row?: number): Array<string | number> | null;
}

interface AutoFileStat {
  name: string;
  path: string;
  isDirectory: boolean;
  isFile: boolean;
  size: number;
  modifiedAtMs: number | null;
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
  getScreenWidthHeightText(): string;
  getScale(): number;
  getModel(): string;
  getOSVersion(): string;
  getDeviceName(): string;
  getBattery(): number | null;
  isCharging(): boolean;
  getOrientation(): string;
  getDeviceId(): string;
  getDeviceAlias(): string;
  getSerialNo(): string | null;
  getAppVersion(): string;
  getPackageName(): string;
  getMemoryInfo(): { totalBytes: number; freeBytes: number; appUsedBytes: number };
  getTotalMemory(): number | null;
  getAvailableMemory(): number | null;
  getUsedMemory(): number | null;
  getClipboard(): string | null;
  setClipboard(text: string): boolean;
  getBrightness(): number;
  setBrightness(value: number): boolean;
  getVolume(): number;
  vibrate(durationMs?: number): boolean;
  volumeUp(): boolean;
  volumeDown(): boolean;
  isScreenOn(): boolean;
}

interface AutoMediaAPI {
  saveImage(path: string): boolean;
  saveImageBase64(base64: string): boolean;
  saveVideo(path: string): boolean;
  saveScreenshot(): boolean;
  deleteAllPhotos(): number;
  deleteAllVideos(): number;
  deleteAllMedia(): number;
  requestPhotoAuthorization(): AutoPhotoAuthorizationStatus;
  getPhotoAuthorizationStatus(): AutoPhotoAuthorizationStatus;
}

type AutoPhotoAuthorizationStatus = "notDetermined" | "restricted" | "denied" | "authorized" | "limited" | "unknown";

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
  current(): string | null;
  currentApp(): string | null;
  appList(): Array<{ bundleId: string; name: string }>;
  isInstalled(bundleId: string): boolean;
  getAppName(bundleId: string): string | null;
  isRunning(bundleId: string): boolean;
  installedApps(): Array<{ bundleId: string; name: string }>;
  launchByPrefix(bundleIdPrefix: string): boolean;
  getAppVersion(): string;
  getPackageName(): string;
}


interface AutoScreenAPI {
  getColor(x: number, y: number): AutoPixelColor;
  getColorRGB(x: number, y: number): { r: number; g: number; b: number } | null;
  getColorHex(x: number, y: number): string | null;
  findImage(path: string, options?: AutoImageOptions): AutoMatch;
  findColor(color: AutoColor, region?: AutoRect, options?: AutoColorSearchOptions): AutoMatch;
  findColorEx(colors: AutoColorExInput, threshold?: number, x?: number, y?: number, ex?: number, ey?: number, limit?: number, direction?: number): AutoPoint[] | null;
  findNotColor(colors: AutoColorExInput, threshold?: number, x?: number, y?: number, ex?: number, ey?: number, limit?: number, direction?: number): AutoPoint[] | null;
  findMultiColor(color: AutoColor, offsets: AutoColorOffsetLike[], region?: AutoRect, options?: AutoColorSearchOptions): AutoMatch;
  findColors(points: AutoColorPoint[], options?: { tolerance?: number }): boolean;
  isColors(points: AutoColorPoint[], options?: { tolerance?: number }): boolean;
  cmpColor(points: AutoColorPoint[], options?: { tolerance?: number }): boolean;
  ocr(options?: AutoOCROptions): AutoOCRItem[];
  screenshot(): string;
}

interface AutoAPI {
  click(selector: AutoSelectorLike): boolean;
  clickPoint(x: number, y: number): boolean;
  doubleClickPoint(x: number, y: number, intervalSeconds?: number): boolean;
  longClick(selector: AutoSelectorLike, durationSeconds?: number): boolean;
  swipe(x1: number, y1: number, x2: number, y2: number, durationSeconds?: number): boolean;
  swipeUp(percent?: number, durationMs?: number): boolean;
  swipeDown(percent?: number, durationMs?: number): boolean;
  swipeLeft(percent?: number, durationMs?: number): boolean;
  swipeRight(percent?: number, durationMs?: number): boolean;
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
  screenshotRegion(x: number, y: number, width: number, height: number): string | null;
  childCount(selector: AutoSelectorLike): number;
  randomString(length?: number, chars?: string): string;
  md5(text: string): string;
  sha1(text: string): string;
  sha256(text: string): string;
  sha512(text: string): string;
  alert(message: string, title?: string): boolean;
  exit(): boolean;
  restartScript(): boolean;
  aes128Encrypt(text: string, key: string): string;
  aes128Decrypt(base64: string, key: string): string;
  toPinYin(text: string): string;
  stripUtf8Bom(text: string): string;
  fromUnicode(text: string): string;
  startWith(text: string, prefix: string): boolean;
  endWith(text: string, suffix: string): boolean;
  contains(text: string, sub: string): boolean;
  indexOf(text: string, sub: string, from?: number): number;
  lastIndexOf(text: string, sub: string): number;
  substring(text: string, start: number, end?: number): string;
  replaceAll(text: string, search: string, replacement: string): string;
  toUpperCase(text: string): string;
  toLowerCase(text: string): string;
  join(array: unknown[], separator?: string): string;
  repeat(text: string, count: number): string;
  length(text: string): number;
  padZero(text: string | number, length: number): string;
  padStart(text: string | number, length: number, pad?: string): string;
  padEnd(text: string | number, length: number, pad?: string): string;
  format(pattern: string, ...args: unknown[]): string;
  formatDate(timestamp?: number, pattern?: string): string;
  readPlist(path: string): unknown;
  writePlist(path: string, value: unknown): boolean;
  playMp3(path: string, volume?: number, queue?: boolean, stopWhenScriptEnd?: boolean): boolean;
  stopMp3(): boolean;
  randomCharNumber(length?: number): string;
  drag(x1: number, y1: number, x2: number, y2: number, durationMs?: number): boolean;
  launchAppByPrefix(bundleIdPrefix: string): boolean;
  saveImageToAlbum(path: string): boolean;
  saveImageBase64ToAlbum(base64: string): boolean;
  saveVideoToAlbum(path: string): boolean;
  saveScreenshotToAlbum(): boolean;
  deleteAllPhotos(): number;
  deleteAllVideos(): number;
  deleteAllMedia(): number;
  findImage(path: string, options?: AutoImageOptions): AutoMatch;
  findColor(color: AutoColor, region?: AutoRect, options?: AutoColorSearchOptions): AutoMatch;
  getPixelColor(x: number, y: number): AutoPixelColor;
  compareColors(points: AutoColorPoint[], options?: { tolerance?: number }): boolean;
  cmpColor(points: AutoColorPoint[], options?: { tolerance?: number }): boolean;
  findMultiColor(color: AutoColor, offsets: AutoColorOffsetLike[], region?: AutoRect, options?: AutoColorSearchOptions): AutoMatch;
  findColorEx(colors: AutoColorExInput, threshold?: number, x?: number, y?: number, ex?: number, ey?: number, limit?: number, direction?: number): AutoPoint[] | null;
  findNotColor(colors: AutoColorExInput, threshold?: number, x?: number, y?: number, ex?: number, ey?: number, limit?: number, direction?: number): AutoPoint[] | null;
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
  getRangeInt(min: number, max: number): number;
  getRatio(ratio: number): boolean;
  execAsync(fn: Function, ...args: unknown[]): AutoThread | null;
  execSync<T = unknown>(fn: Function, ...args: unknown[]): T | null;
  cancelThread(thread: AutoThread | null): boolean;
  stopAllThreads(): boolean;
  isCancelled(): boolean;
  longClickPoint(x: number, y: number, durationMs?: number): boolean;
  getOneNodeInfo(selector: AutoSelectorLike): unknown;
  getNodeInfo(selector: AutoSelectorLike): unknown;
  [nativeMethod: string]: any;
}

interface AutoStringsAPI {
  trim(text: string): string;
  ltrim(text: string): string;
  rtrim(text: string): string;
  split(text: string, separator?: string): string[];
  chars(text: string): string[];
  toHex(text: string): string;
  fromHex(hex: string): string;
  isUpper(text: string): boolean;
  isLower(text: string): boolean;
  isNumber(text: string): boolean;
  isIntrger(text: string): boolean;
  isLetter(text: string): boolean;
  isChinese(text: string): boolean;
  isEmail(text: string): boolean;
  isLink(text: string): boolean;
  md5(text: string): string;
  sha1(text: string): string;
  sha256(text: string): string;
  sha512(text: string): string;
  base64Encode(text: string): string;
  base64Decode(base64: string): string;
  aes128Encrypt(text: string, key: string): string;
  aes128Decrypt(base64: string, key: string): string;
  toPinYin(text: string): string;
  stripUtf8Bom(text: string): string;
  fromUnicode(text: string): string;
  startWith(text: string, prefix: string): boolean;
  endWith(text: string, suffix: string): boolean;
  contains(text: string, sub: string): boolean;
  indexOf(text: string, sub: string, from?: number): number;
  lastIndexOf(text: string, sub: string): number;
  substring(text: string, start: number, end?: number): string;
  replaceAll(text: string, search: string, replacement: string): string;
  toUpperCase(text: string): string;
  toLowerCase(text: string): string;
  join(array: string[], separator?: string): string;
  repeat(text: string, count: number): string;
  length(text: string): number;
  padZero(text: string | number, length: number): string;
  padStart(text: string, length: number, pad?: string): string;
  padEnd(text: string, length: number, pad?: string): string;
  format(pattern: string, ...args: unknown[]): string;
  formatDate(timestamp?: number, pattern?: string): string;
}

interface AutoPlistAPI {
  read(path: string): unknown;
  write(path: string, value: unknown): boolean;
}

interface AutoWebViewAPI {
  init(url?: string): string;
  show(token: string, x?: number, y?: number, width?: number, height?: number): boolean;
  hidden(token: string): boolean;
  eval(token: string, js: string): unknown;
  release(token: string): boolean;
}

interface AutoScreenDrawAPI {
  init(): string;
  setBorderWidth(token: string, width: number): boolean;
  setBorderColor(token: string, color: string): boolean;
  setTitle(token: string, title: string): boolean;
  show(token: string, x: number, y: number, width: number, height: number): boolean;
  move(token: string, x: number, y: number): boolean;
  hide(token: string): boolean;
  release(token: string): boolean;
  clearAll(): boolean;
}

interface AutoFloatBallAPI {
  show(title?: string, x?: number, y?: number): boolean;
  move(x: number, y: number): boolean;
  hide(): boolean;
  isShow(): boolean;
}

interface AutoNodeAPI {
  keep(node: unknown): unknown;
  unkeep(node: unknown): unknown;
  keptCount(): number;
}

interface AutoThread {
  join(): unknown;
  isFinished(): boolean;
  getResult(): unknown;
  cancel(): boolean;
}

declare const auto: AutoAPI;
declare function toast(message: string): boolean;
declare function toastLog(message: string): void;
declare const file: AutoFileAPI;
declare const zip: AutoFileAPI["zip"];
declare const unzip: AutoFileAPI["unzip"];
declare const readFileInZip: AutoFileAPI["readFileInZip"];
declare const storages: { create(name: string): AutoStorage };
declare const device: AutoDeviceAPI;
declare const media: AutoMediaAPI;
declare const app: AutoAppAPI;
declare const http: AutoHTTP;
declare const image: {
  findImage: AutoAPI["findImage"];
  findColor: AutoAPI["findColor"];
  findColorEx: AutoAPI["findColorEx"];
  findNotColor: AutoAPI["findNotColor"];
  findMultiColor: AutoAPI["findMultiColor"];
  cmpColor: AutoAPI["compareColors"];
  pixel: AutoAPI["getPixelColor"];
  screenshot: AutoAPI["screenshot"];
  clipRegion: AutoAPI["screenshotRegion"];
  getSize(path: string): ReturnType<AutoFileAPI["imageSize"]>;
  getWidth(path: string): number | null;
  getHeight(path: string): number | null;
  clip(src: string, x: number, y: number, ex: number, ey: number, dest: string): string | null;
  scale(src: string, width: number, height: number, dest: string): string | null;
  gray(src: string, dest: string): string | null;
  binaryzation(src: string, dest: string, threshold?: number): string | null;
  rotate(src: string, degrees: number, dest: string): string | null;
  pixelAt(src: string, x: number, y: number): AutoPixelColor | null;
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
declare function swipeUp(percent?: number, durationMs?: number): boolean;
declare function swipeDown(percent?: number, durationMs?: number): boolean;
declare function swipeLeft(percent?: number, durationMs?: number): boolean;
declare function swipeRight(percent?: number, durationMs?: number): boolean;
declare function sleep(milliseconds: number): boolean;
declare function saveImageToAlbum(path: string): boolean;
declare function saveImageBase64ToAlbum(base64: string): boolean;
declare function saveVideoToAlbum(path: string): boolean;
declare function deleteAllPhotos(): number;
declare function deleteAllVideos(): number;
declare function deleteAllMedia(): number;
declare function sha256(text: string): string;
declare function sha512(text: string): string;
declare function alert(message: string, title?: string): boolean;
declare function exit(): boolean;
declare function restartScript(): boolean;
declare function trim(text: string): string;
declare function ltrim(text: string): string;
declare function rtrim(text: string): string;
declare function split(text: string, separator?: string): string[];
declare function chars(text: string): string[];
declare function toHex(text: string): string;
declare function fromHex(hex: string): string;
declare function isUpper(text: string): boolean;
declare function isLower(text: string): boolean;
declare function isNumber(text: string): boolean;
declare function isIntrger(text: string): boolean;
declare function isLetter(text: string): boolean;
declare function isChinese(text: string): boolean;
declare function isEmail(text: string): boolean;
declare function isLink(text: string): boolean;
declare function lineCount(path: string): number;
declare function getLineText(path: string, index: number): string | null;
declare function insertLineText(path: string, index: number, text: string): boolean;
declare function resetLineText(path: string, index: number, text: string): boolean;
declare function readPlist(path: string): unknown;
declare function writePlist(path: string, value: unknown): boolean;
declare function aes128Encrypt(text: string, key: string): string;
declare function aes128Decrypt(base64: string, key: string): string;
declare const plist: AutoPlistAPI;
declare const webView: AutoWebViewAPI;
declare const strings: AutoStringsAPI;
declare function saveScreenshotToAlbum(): boolean;
declare function time(): number;
declare function random(min: number, max?: number): number;
declare function randomInt(min: number, max?: number): number;
declare function randomString(length?: number, chars?: string): string;
declare function md5(text: string): string;
declare function sha1(text: string): string;
declare function playMp3(path: string, volume?: number, queue?: boolean, stopWhenScriptEnd?: boolean): boolean;
declare function stopMp3(): boolean;
declare function findColorEx(colors: AutoColorExInput, threshold?: number, x?: number, y?: number, ex?: number, ey?: number, limit?: number, direction?: number): AutoPoint[] | null;
declare function findNotColor(colors: AutoColorExInput, threshold?: number, x?: number, y?: number, ex?: number, ey?: number, limit?: number, direction?: number): AutoPoint[] | null;
declare function requestPhotoAuthorization(): AutoPhotoAuthorizationStatus;
declare function getPhotoAuthorizationStatus(): AutoPhotoAuthorizationStatus;
declare function randomCharNumber(length?: number): string;
declare function screenshotRegion(x: number, y: number, width: number, height: number): string | null;
declare function childCount(selector: AutoSelectorLike): number;
declare function drag(x1: number, y1: number, x2: number, y2: number, durationMs?: number): boolean;
declare function execAsync(fn: Function, ...args: unknown[]): AutoThread | null;
declare function execSync<T = unknown>(fn: Function, ...args: unknown[]): T | null;
declare function cancelThread(thread: AutoThread | null): boolean;
declare function stopAllThreads(): boolean;
declare function isCancelled(): boolean;
declare function longClickPoint(x: number, y: number, durationMs?: number): boolean;
declare function getRangeInt(min: number, max: number): number;
declare function getRatio(ratio: number): boolean;
declare function getOneNodeInfo(selector: AutoSelectorLike): unknown;
declare function getNodeInfo(selector: AutoSelectorLike): unknown;
declare function getAppVersion(): string;
declare function getPackageName(): string;
declare function launchAppByPrefix(bundleIdPrefix: string): boolean;
declare function getScreenWidthHeightText(): string;
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
declare const screenDraw: AutoScreenDrawAPI;
declare const floatBall: AutoFloatBallAPI;
declare function setFloatBallPoint(x: number, y: number): boolean;
declare const node: AutoNodeAPI;
declare function keepNode(node: unknown): unknown;
declare function unkeepNode(node: unknown): unknown;
declare function toPinYin(text: string): string;
declare function stripUtf8Bom(text: string): string;
declare function fromUnicode(text: string): string;
declare function formatDate(timestamp?: number, pattern?: string): string;
declare const dateFormat: typeof formatDate;
declare function sleepRandom(min: number, max?: number): boolean;
declare function startWith(text: string, prefix: string): boolean;
declare function endWith(text: string, suffix: string): boolean;
declare function contains(text: string, sub: string): boolean;
declare function padZero(text: string | number, length: number): string;
declare function isInstalled(bundleId: string): boolean;
declare const screen: AutoScreenAPI;
declare const string: AutoStringsAPI;
