package com.bandpad.cordova.audiofrequency;

import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CallbackContext;
import org.apache.cordova.PluginResult;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.lang.ref.WeakReference;

import android.os.Handler;
import android.os.Message;
import android.util.Log;

public class AudioFrequency extends CordovaPlugin
{
    private static final String LOG_TAG = "AudioFrequency";

    private CallbackContext callbackContext = null;

    private ToneReceiver receiver;

    private final FrequencyHandler handler = new FrequencyHandler(this);

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        if (action.equals("start")) {
            if (this.callbackContext != null) {
                callbackContext.error( "AudioFrequency listener already running.");
                return true;
            }
            this.callbackContext = callbackContext;

            try {
                receiver = new ToneReceiver(16384);
                receiver.setHandler(handler);
                receiver.start();
            } catch (Exception e) {
                e.printStackTrace();
                receiver.interrupt();
            }

            // Don't return any result now, since status results will be sent when events come in from broadcast receiver
            PluginResult pluginResult = new PluginResult(PluginResult.Status.NO_RESULT);
            pluginResult.setKeepCallback(true);
            callbackContext.sendPluginResult(pluginResult);
            return true;
        }

        else if (action.equals("stop")) {
            receiver.interrupt();
            this.sendUpdate(new JSONObject(), false); // release status callback in JS side
            this.callbackContext = null;
            callbackContext.success();
            return true;
        }

        return false;
    }

    public void onDestroy() {
        if (!receiver.isInterrupted()) {
            receiver.interrupt();
        }
    }

    public void onReset() {
        if (!receiver.isInterrupted()) {
            receiver.interrupt();
        }
    }

    /**
     * Create a new plugin result and send it back to JavaScript
     */
    private void sendUpdate(JSONObject info, boolean keepCallback) {
        if (this.callbackContext != null) {
            PluginResult result = new PluginResult(PluginResult.Status.OK, info);
            result.setKeepCallback(keepCallback);
            this.callbackContext.sendPluginResult(result);
        }
    }

    private static class FrequencyHandler extends Handler {
        private final WeakReference<AudioFrequency> mActivity;

        public FrequencyHandler(AudioFrequency activity) {
            mActivity = new WeakReference<AudioFrequency>(activity);
        }

        @Override
        public void handleMessage(Message msg) {
            AudioFrequency activity = mActivity.get();
            if (activity != null) {
                // Log.d(LOG_TAG, msg.getData().toString());

                JSONObject info = new JSONObject();
                try {
                    info.put("frequency", msg.getData().getLong("frequency"));
                } catch (JSONException e) {
                    Log.e(LOG_TAG, e.getMessage(), e);
                }

                activity.sendUpdate(info, true);
            }
        }
    }
}
