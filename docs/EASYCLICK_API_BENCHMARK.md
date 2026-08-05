# EasyClick iOS USB API benchmark

Audit date: 2026-08-05

Source: <https://ieasyclick.com/iosdocs/zh-cn/funcs> (EasyClick iOS USB 官方文档).
This table compares the EasyClick iOS USB function surface with AutoSDK. Rows
marked ✅ are covered, 🟡 are covered with a different signature/alias, and ❌
are not implemented.

## 全局/快捷（global-shortcut）

| EasyClick | AutoSDK | 说明 |
| --- | --- | --- |
| clickPoint / doubleClickPoint | ✅ `clickPoint` / `doubleClickPoint` | 坐标点击/双击 |
| clickPointPressure / swipeToPointPressure | ❌ | 压力触摸，需私有触摸注入 |
| longClickPoint | 🟡 `longClick(selector)` | 长按点坐标变体未做 |
| swipeToPoint | ✅ `swipeToPoint` / `swipe` | 坐标滑动（秒） |
| drag | ✅ `drag(x1,y1,x2,y2,durationMs)` | 长按拖拽 |
| multiTouch | ✅ `gesture` / `multiGesture` / `pinch` | W3C 触摸动作 |
| inputText / typingText | ✅ `input(selector,text)` / `setText` | 输入文字 |
| openUrl | ✅ `openURL` | 打开链接 |
| home / homeScreen / lockScreen / unlockScreen / isLocked | ✅ `app.homeScreen` / `app.lock` / `app.unlock` / `device.isScreenOn` | WDA 系统操作 |
| getOrientation / adjustScreenOrientation / setOrientation | 🟡 `device.getOrientation` | 旋转控制未做 |
| appLaunch / appLaunchEx | ✅ `launchApp` / `app.launch` | 启动应用 |
| appLaunchByPrefix | ✅ `launchAppByPrefix(prefix)` / `app.launchByPrefix` | 按前缀启动 |
| appKillByBundleId(Ex) | ✅ `terminateApp` / `app.terminate` | 结束应用 |
| installApp / erasePhone / reboot / reconnectUsb / resetUsbConn | ❌ | 需系统级权限/设备管理 |
| press / ioHIDEvent / setAssistiveTouch | 🟡 `device.volumeUp/volumeDown` | 硬件键有限支持 |
| uploadInsertImage / uploadInsertVideo | 🟡 `media.saveImage` / `saveVideo` | 相册写入 |
| readAllUIConfig(2) / setAgentSetting / setAgentTimeout / fsyncFilePushPull | ❌ | 中控/代理侧功能 |
| getCliArgs / version / ipaVersion | ❌ | 中控运行参数 |

## 节点（node-api）

| EasyClick | AutoSDK | 说明 |
| --- | --- | --- |
| lockNode / releaseNode / lockNodeFromXml / setFetchNodeParam | ❌ | 节点锁定/抓取参数（iOS 限制） |
| label / id / type / name / xpath / bounds / depth / visible / enable / selected / value / index / accessible | ✅ WDA 选择器 + `getAttribute` | 属性过滤 |
| getOneNodeInfo / getNodeInfo | 🟡 `findElement` / `getAttribute` | 完整节点字典变体 |
| child / childcount / parent / siblings / nextSiblings / previousSiblings / allChildren | ✅ `getChild` / `childCount` / `getParent` / `getSiblings` / `getPreviousSiblings` / `getNextSiblings` / `getChildren` | 层级遍历 |
| clickCenter / clickRandom | ✅ `clickCenter` / `clickRandom` | 中心/随机点击 |
| timeout | ✅ `waitFor(selector, timeoutMs)` | 等待节点 |

## 设备（device-api）

| EasyClick | AutoSDK | 说明 |
| --- | --- | --- |
| getDeviceInfo / getDeviceMsg | ✅ `device.getDeviceInfo()` / `device.info()` | 设备信息 |
| getScreenWidth / getScreenHeight / getScale / getScreenWidthHeightText | ✅ 全部 | 屏幕尺寸 |
| getModel / getOSVersion / getDeviceName / getBattery / isCharging / getOrientation | ✅ 全部 | 设备属性 |
| applist | ✅ `app.appList()` / `app.installedApps()` | 已安装应用 |
| getDeviceId / getDeviceAlias / getSerialNo | ❌ | 序列号等 iOS 不可公开获取 |

## 文件（file-api）

| EasyClick | AutoSDK | 说明 |
| --- | --- | --- |
| getSandBoxDir / getSandBoxFilePath | ✅ `file.getSandBoxDir` / `file.getSandBoxFilePath` | 沙盒路径 |
| readFile / writeFile / create / exists / appendLine / readLine / readAllLines / deleteLine / deleteAllFile / mkdirs / listDir / copy / move | ✅ 全部 | 文件 CRUD |
| readExcelRow / readExcelAllRow | ❌ | Excel 解析 |

## 网络（http-api）

| EasyClick | AutoSDK | 说明 |
| --- | --- | --- |
| request / requestEx / postJSON | ✅ `http.request` / `http.postJSON` / `http.post` | 请求 |
| downloadFile / downloadFileDefault | ✅ `http.downloadFile` | 下载 |
| agentForwardRequest / agentHttpGetString / agentHttpPostJson | ❌ | 代理转发（中控） |

## 图色（image-api）

| EasyClick | AutoSDK | 说明 |
| --- | --- | --- |
| captureFullScreen / captureScreenStream | 🟡 `screenshot()` / `screenshotRegion(x,y,w,h)` | 截屏/区域截屏 |
| findColor / findMultiColor / cmpColor / cmpMultiColor | ✅ `findColor` / `findMultiColor` / `cmpColor` | 找色 |
| findColorEx | ✅ `findColorEx(colors, threshold, x, y, ex, ey, limit, direction)` | 区域多点找色，返回坐标数组 |
| findImage / findImage2 / matchTemplate | 🟡 `findImage`（CoreGraphics 相似度匹配） | 非 OpenCV |
| findNotColor | ✅ `findNotColor(colors, threshold, x, y, ex, ey, limit, direction)` | 找非色（变化检测） |
| pixel / getPixelBitmap | ✅ `getPixelColor` | 取色 |
| clip / scaleBitmap / rotateImage / gray / binaryzation | ✅ `image.clip/scale/gray/binaryzation/rotate`（路径式） | 图像处理管线 |
| recycle | ❌ | 对象内存管理，路径式 API 无需 |
| getWidth / getHeight | ✅ `file.imageSize(path)` / `image.getSize(path)` | 图像尺寸查询 |
| saveBitmap / saveTo | 🟡 `media.saveImage` | 保存 |

## OCR（ocr-api）

| EasyClick | AutoSDK | 说明 |
| --- | --- | --- |
| ocr.initOcr / ocrInstance.ocrImage / ocrBitmap | ✅ `ocr(options)`（Apple Vision） | 设备端 OCR |
| ocrInstance.releaseAll | ✅ 自动释放 | — |

## 存储（storage-api）

| EasyClick | AutoSDK | 说明 |
| --- | --- | --- |
| storages.create / putString / putInt / putFloat / putBoolean / get* / remove / clear / keys / all / contains | ✅ 全部 | 命名存储 |

## 线程（thread-api）

| EasyClick | AutoSDK | 说明 |
| --- | --- | --- |
| execAsync / execSync / cancelThread / isCancelled / stopAll | ❌ | 真实并行线程；AutoSDK 为协作式定时器 |

## 工具（utils-api）

| EasyClick | AutoSDK | 说明 |
| --- | --- | --- |
| randomInt / getRangeInt | ✅ `randomInt(min,max)` | 随机数 |
| randomCharNumber | ✅ `randomString(n)` / `randomCharNumber(n)` | 随机字符串 |
| zip / unzip / unzipWithEncode / readFileInZip | ❌ | 压缩 |
| dataMd5 / fileMd5 | ✅ `md5(text)` / `sha1(text)` / `file.md5(path)` / `file.md5File(path)` | 字符串与文件哈希 |
| playMp3 / stopMp3 | ✅ `playMp3(path, volume, queue, stopWhenScriptEnd)` / `stopMp3()` | 系统音频播放 |
| deleteAllPhotos / deleteAllVideos | ❌ | 破坏性清空相册，未实现 |
| requestPhotoAuthorization | ✅ `media.requestPhotoAuthorization()` / `media.getPhotoAuthorizationStatus()` | 相册权限 |
| getPCIps / getRatio | ❌ | 中控网络工具 |

## 结论

- AutoSDK 已覆盖 EasyClick iOS USB 约 70% 的常用可移植函数（触摸/节点/文件/存储/HTTP/OCR/设备信息）。
- 剩余缺口集中在：真实并行线程、图像对象管线（裁剪/缩放/灰度）、Excel/zip、序列号等系统级能力、以及中控专属功能。
- 图像对象管线（image.clip/scale/gray）是下一个最有价值的方向。