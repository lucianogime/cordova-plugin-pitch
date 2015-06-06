# com.bandpad.cordova.audiofrequency

This plugin captures the device's audio input stream and analyses it to return the maximum frequency.

It adds the following `window` event:

* audiofrequency

## Installation

```
cordova plugin add com.bandoad.cordova.audiofrequency
```

## Supported Platforms

* iOS
* Android

## Example

```javascript
window.addEventListener("audiofrequency", onAudiofrequency, false);

function onAudiofrequency(e) {
    console.log("Frequency: " + e.frequency + " Hz");
}
```
