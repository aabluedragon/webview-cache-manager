package org.alonamir.cache;

import java.io.File;
import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.Map;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaActivity;
import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaWebView;
import org.json.JSONArray;
import org.json.JSONException;
import android.annotation.SuppressLint;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.webkit.CookieManager;
import android.webkit.ValueCallback;

public class WebviewCacheManager extends CordovaPlugin {

    private static Field appViewField;
    private static WebViewKind webViewKind;

    private interface CordovaCall {
        void execute(JSONArray data, CallbackContext callbackContext, CordovaInterface cordova);
    }

    enum WebViewKind {
        BuiltIn,
        Crosswalk
    }

    static boolean deleteRecursive(File fileOrDirectory) {
        if (fileOrDirectory.isDirectory())
            for (File child : fileOrDirectory.listFiles())
                deleteRecursive(child);

        return fileOrDirectory.delete();
    }

    static String getWebViewPath(CordovaInterface cordova) {
        if(webViewKind == WebViewKind.Crosswalk) {
            return cordova.getActivity().getApplicationContext().getDir("xwalkcore", 0).getPath() + "/Default/Application Cache";
        } else {
            return cordova.getActivity().getApplicationContext().getDir("webview", 0).getPath() + "/Application Cache";
        }
    }

    @Override
    public void initialize(CordovaInterface cordova, CordovaWebView webView) {
        File xwalkDir = cordova.getActivity().getApplicationContext().getDir("xwalkcore", 0);
        webViewKind = xwalkDir.exists()? WebViewKind.Crosswalk:WebViewKind.BuiltIn;

        super.initialize(cordova, webView);
    }

    static Map<String, CordovaCall> cordovaMethods = new HashMap<String, CordovaCall>();
    static {

        try {
            Class<?> cdvActivityClass = CordovaActivity.class;
            Field wvField = cdvActivityClass.getDeclaredField("appView");
            wvField.setAccessible(true);
            appViewField = wvField;
        } catch (NoSuchFieldException e) {
            e.printStackTrace();
        }

        cordovaMethods.put("clearCookies", new CordovaCall() {
            @SuppressLint("NewApi")
            @SuppressWarnings("deprecation")
            @Override public void execute(JSONArray data, final CallbackContext callbackContext, CordovaInterface cordova) {
                try {
                    int apiLevel = Build.VERSION.SDK_INT;
                    if(apiLevel >= 21){
                        CookieManager.getInstance().removeAllCookies(new ValueCallback<Boolean>() {
                            @Override
                            public void onReceiveValue(Boolean value) {
                                callbackContext.success();
                            }
                        });
                    } else {
                        CookieManager.getInstance().removeAllCookie();
                        callbackContext.success();
                    }
                } catch(Exception e) {
                    callbackContext.error(e.getMessage());
                }
            }
        });

        cordovaMethods.put("clearBrowserCache", new CordovaCall() {
            @Override public void execute(JSONArray data, final CallbackContext callbackContext, CordovaInterface cordova) {
                try {
                    final CordovaWebView webView = (CordovaWebView) appViewField.get(cordova.getActivity());
                    Handler mainHandler = new Handler(cordova.getActivity().getMainLooper());
                    final Looper myLooper = Looper.myLooper();
                    mainHandler.post(new Runnable() {
                        @Override
                        public void run() {
                            webView.clearCache();
                            new Handler(myLooper).post(new Runnable() {
                                @Override
                                public void run() {
                                    callbackContext.success();
                                }
                            });
                        }
                    });

                } catch (Throwable e) {
                    callbackContext.error(e.getMessage());
                }

            }
        });

        cordovaMethods.put("clearAppCacheByUrl", new CordovaCall() {
            @Override public void execute(JSONArray data, final CallbackContext callbackContext, CordovaInterface cordova) {
                callbackContext.error("Not implemented for android. See: http://stackoverflow.com/q/33746621/230637");
            }
        });



        cordovaMethods.put("clearAllAppCache", new CordovaCall() {
            @Override
            public void execute(JSONArray data, final CallbackContext callbackContext, CordovaInterface cordova) {
                try {
                    String path = getWebViewPath(cordova);
                    File c = new File(path);
                    deleteRecursive(c);
                    callbackContext.success();
                } catch (Exception e) {
                    callbackContext.error(e.getMessage());
                }

            }
        });

    }

    @Override
    public boolean execute(String action, JSONArray data, CallbackContext callbackContext) throws JSONException {
        CordovaCall cordovaCall = cordovaMethods.get(action);
        if(cordovaCall != null) {
            cordovaCall.execute(data, callbackContext, cordova);
            return true;
        }

        return false;
    }

}
