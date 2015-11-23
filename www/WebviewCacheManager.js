
function WebviewCacheManager() {}

WebviewCacheManager.prototype.clearBrowserCache = function (doneCb, errorCb) {
    cordova.exec(doneCb, errorCb, "WebviewCacheManager", "clearBrowserCache", []);
};

WebviewCacheManager.prototype.clearAppCacheByUrl = function (config, doneCb, errorCb) {
    cordova.exec(doneCb, errorCb, "WebviewCacheManager", "clearAppCacheByUrl", [config.urls, config.exceptGivenUrls, config.likeFormat]);
};

WebviewCacheManager.prototype.clearAllAppCache = function (doneCb, errorCb) {
    cordova.exec(doneCb, errorCb, "WebviewCacheManager", "clearAllAppCache", []);
};

WebviewCacheManager.prototype.clearCookies = function (doneCb, errorCb) {
    cordova.exec(doneCb, errorCb, "WebviewCacheManager", "clearCookies", []);
};

if (typeof module != 'undefined' && module.exports) {
    module.exports = new WebviewCacheManager();
}
