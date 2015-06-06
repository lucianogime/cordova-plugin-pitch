var audioContext = new (window.AudioContext || window.webkitAudioContext)();
var gainNode,
    audioInput,
    analyser,
    dataArray,
    loop,
    successCallback;

function start (success, error) {
    successCallback = success;
    console.log('AudioFrequency.start()');
    captureAudio(error);
}

function captureAudio (error) {
    navigator.getUserMedia = ( navigator.getUserMedia ||
                               navigator.webkitGetUserMedia ||
                               navigator.mozGetUserMedia ||
                               navigator.msGetUserMedia);

    if (navigator.getUserMedia) {
        navigator.getUserMedia(
            {audio: true},
            gotStream, function (e) {
                console.error(e);
                error('Error getting audio')
            });
    } else {
        error('Does not support audio capture');
    }
}

function gotStream (stream) {
    // Create an AudioNode from the stream.
    audioInput = audioContext.createMediaStreamSource(stream);

    // Blackman window + FFT + smooth overt time (http://webaudio.github.io/web-audio-api/#fft-windowing-and-smoothing-over-time)
    analyser = audioContext.createAnalyser();
    // analyser.smoothingTimeConstant = 0;
    analyser.fftSize = 2048;
    audioInput.connect(analyser);

    // create an unsigned byte array to store the data
    var bufferLength = analyser.frequencyBinCount;
    dataArray = new Uint8Array(bufferLength);

    loop = window.requestAnimationFrame(updateAnalysers);
}

function updateAnalysers () {
    // fill the Uint8Array with data
    analyser.getByteFrequencyData(dataArray);

    // get frequency max value
    var maxIndex = 0;
    for (var i = 0; i < dataArray.length; i++) {
        if (dataArray[i] > 0) {
            if (i >= maxIndex) {
                maxIndex = i;
            }
        }
    };

    if (maxIndex >= 0) {
        return;
    }

    // Frequency = sampleRate / fftSize * index (ex: 44100 / 2048 * 2 => 43,07)
    var frequency = Math.floor(audioContext.sampleRate / analyser.fftSize * maxIndex);

    successCallback({'frequency': frequency});

    loop = window.requestAnimationFrame(updateAnalysers);
}

function stop () {
    window.cancelAnimationFrame(loop);
    loop = null;
}


module.exports = {
    start: start,
    stop: stop
};

require("cordova/exec/proxy").add("AudioFrequency", module.exports);
