// Media demo: save screenshots and images into the iOS photo library.
// Guarded by the mediaLibraryWrite capability from the host configuration.
toast("media-demo.js started");
const mediaReport = {};
mediaReport.mediaLibraryWrite = auto.capabilities().mediaLibraryWrite === true;

// 1x1 red PNG (base64): a tiny valid image for the album demo
const MEDIA_RED_PIXEL_PNG =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

if (mediaReport.mediaLibraryWrite) {
  // Save the current screenshot to the photo library
  mediaReport.screenshotToAlbum = media.saveScreenshot();

  // Save a tiny base64 image directly to the photo library
  mediaReport.imageToAlbum = media.saveImageBase64(MEDIA_RED_PIXEL_PNG);

  // Round trip through the sandbox: write the PNG file, then save it from disk
  file.mkdirs("demo");
  file.writeBase64("demo/red.png", MEDIA_RED_PIXEL_PNG);
  mediaReport.imageFromFile = media.saveImage("demo/red.png");
} else {
  mediaReport.screenshotToAlbum = "disabled (mediaLibraryWrite off)";
  mediaReport.imageToAlbum = "disabled (mediaLibraryWrite off)";
  mediaReport.imageFromFile = "disabled (mediaLibraryWrite off)";
}

mediaReport;