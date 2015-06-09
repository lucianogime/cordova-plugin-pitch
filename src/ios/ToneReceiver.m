//
//  ToneReceiver.m
//  Frequency
//
//  Created by Quentin on 23/09/2014.
//  Copyright (c) 2015 BandPad. All rights reserved.
//

#import "ToneReceiver.h"
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>

@interface ToneReceiver() <AVCaptureAudioDataOutputSampleBufferDelegate>

@property (strong, nonatomic) AVCaptureSession *captureSession;
@property (strong, nonatomic) AVCaptureConnection *audioConnection;
@property (strong, nonatomic) dispatch_queue_t captureQueue;

@property (nonatomic) UInt32 spectrumResolution;
@property (nonatomic) long nOver2;
@property (nonatomic) UInt32 log2FFTLength;
@property (nonatomic) FFTSetup fftsetup;
@property (nonatomic) Float32 *window;
@property (nonatomic) DSPSplitComplex complexBuffer;

@property (nonatomic) UInt32 accumulatorFillIndex;
@property (nonatomic) NSMutableData *dataAccumulator;

@end

@implementation ToneReceiver

- (ToneReceiver*)initWithSpectrumResolution:(UInt32)spectrumResolution
{
    self = [super init];

    if (self)
    {
        _spectrumResolution = spectrumResolution;

        [self initSignalProcessingData];

        [self initAudio];

        [self totalHackToGetAroundAppleNotSettingIOBufferDuration];
    }

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionRouteChangeNotification object:nil];

    vDSP_destroy_fftsetup(_fftsetup);
    [self destroyAccumulator];
}


#pragma -mark signal processing data initialization

- (void)initSignalProcessingData
{
    // For an FFT, numSamples must be a power of 2, i.e. is always even
    _nOver2 = _spectrumResolution / 2;

    // Setup the radix (exponent)
    _log2FFTLength = log2f(_spectrumResolution);

    // Calculate the weights array. This is a one-off operation.
    _fftsetup = vDSP_create_fftsetup(self.log2FFTLength, FFT_RADIX2); // this only needs to be created once

    // Creates a single-precision Hamming or Blackman window
    _window = malloc( sizeof(Float32) * _spectrumResolution );
    vDSP_hamm_window( _window, _spectrumResolution, 0 );

    // Define complex buffer
    _complexBuffer.realp = malloc( sizeof(Float32) * _nOver2 );
    _complexBuffer.imagp = malloc( sizeof(Float32) * _nOver2 );

    [self initializeAccumulator];
}


#pragma -mark audio capture initialization

- (void)initAudio
{
    // create an AV Capture session
    self.captureSession = [[AVCaptureSession alloc] init];

    // continue recording when an external media is played
    // UInt32 audioRouteOverride = kAudioSessionCategory_AmbientSound;
    // AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(audioRouteOverride), &audioRouteOverride);
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];

    NSNotificationCenter* listener = [NSNotificationCenter defaultCenter];
    [listener addObserver:self selector:@selector(audioSessionRouteChange:) name:AVAudioSessionRouteChangeNotification object:nil];

    // setup the audio input
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    if(audioDevice) {
        NSError *error;
        AVCaptureDeviceInput *audioIn = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
        if ( !error ) {
            if ([self.captureSession canAddInput:audioIn]){
                [self.captureSession addInput:audioIn];
            } else {
                NSLog(@"Couldn't add audio input");
            }
        } else {
            NSLog(@"Couldn't create audio input");
        }
    } else {
        NSLog(@"Couldn't create audio capture device");
    }

    // setup the audio output
    AVCaptureAudioDataOutput* audioOut = [[AVCaptureAudioDataOutput alloc] init];
    if ([self.captureSession canAddOutput:audioOut]) {
        [self.captureSession addOutput:audioOut];
        self.audioConnection = [audioOut connectionWithMediaType:AVMediaTypeAudio];
    } else {
        NSLog(@"Couldn't add audio output");
    }
    _captureQueue = dispatch_queue_create("buffer queue", DISPATCH_QUEUE_SERIAL);
    [audioOut setSampleBufferDelegate:self queue:_captureQueue];
}

-(void)audioSessionRouteChange:(NSNotification*)notification
{
    // restores the AudioSession's category if it changed by an other session
    NSDictionary *interuptionDict = notification.userInfo;
    NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    if (routeChangeReason == AVAudioSessionRouteChangeReasonCategoryChange) {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        if ([session category] != AVAudioSessionCategoryAmbient) {
            [session setCategory:AVAudioSessionCategoryAmbient withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
        }
    }
}

- (void)start
{
    [self.captureSession startRunning];
}

- (void)stop
{
    [self.captureSession stopRunning];
}


- (void)totalHackToGetAroundAppleNotSettingIOBufferDuration
{
    self.captureSession = [[AVCaptureSession alloc] init];
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:NULL];

    [self.captureSession addInput:input];

    AVCaptureAudioDataOutput *output = [[AVCaptureAudioDataOutput alloc] init];
    [output setSampleBufferDelegate:self queue:_captureQueue];
    [self.captureSession addOutput:output];

    [self.captureSession startRunning];
    [self.captureSession stopRunning];
}


#pragma -mark capture audio output

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    //Identifying a Tone: http://mattmercieca.com/identifying-a-tone-sine-wave-in-ios-with-the-accelerate-framework/
    //StackOverflow: http://stackoverflow.com/questions/14088290/passing-avcaptureaudiodataoutput-data-into-vdsp-accelerate-framework
    // trying http://batmobile.blogs.ilrt.org/fourier-transforms-on-an-iphone/

    // check format of audio
    CMAudioFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    const AudioStreamBasicDescription *streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);

    // get samples
    CMItemCount numSamples = CMSampleBufferGetNumSamples(sampleBuffer);
    NSUInteger channelIndex = 0;

    CMBlockBufferRef audioBlockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t audioBlockBufferOffset = (channelIndex * numSamples * sizeof(SInt16));
    size_t lengthAtOffset = 0;
    size_t totalLength = 0; // I think this is the same as $numSamples above, since it's mono
    char *dataPointer = NULL;
    CMBlockBufferGetDataPointer(audioBlockBuffer, audioBlockBufferOffset, &lengthAtOffset, &totalLength, &dataPointer);

    // check what sample format we have, this should always be linear PCM but may have 1 or 2 channels
    assert(streamDescription->mFormatID == kAudioFormatLinearPCM);
    if (streamDescription->mChannelsPerFrame == 1 && streamDescription->mBitsPerChannel == 16)
    {
        if (*dataPointer == '\0')
        {
            return;
        }

        // Convert samples to floats
        Float32 *samples = malloc(numSamples * sizeof(float));
        vDSP_vflt16((short *)dataPointer, 1, samples, 1, numSamples);

        if ([self accumulateFrames:samples withNumSamples:numSamples])
        {
            [self processSample:_dataAccumulator rate:streamDescription->mSampleRate];

            [self emptyAccumulator];
        }

        free(samples);
    }
}


#pragma -mark signal processing data
// amit - this is the main process function
- (void)processSample:(NSMutableData *)data rate:(int)sampleRate
{
    Float32 *samples = [data mutableBytes];

    // Window the samples (Multiplies vector A by vector B and leaves the result in vector C)
    vDSP_vmul(samples, 1, _window, 1, samples, 1, _spectrumResolution);

    // Pack samples (Copies the contents of an interleaved complex vector to a split complex vector)
    vDSP_ctoz((COMPLEX*)samples, 2, &_complexBuffer, 1, _nOver2);

    // Transform Time-Domain Data into Frequency Domain (forward FFT). Results are returned in A.
    vDSP_fft_zrip(_fftsetup, &_complexBuffer, 1, _log2FFTLength, FFT_FORWARD);

    // scale FFT (Multiplies vector by scalar and leaves the result in vector)
    Float32 scale = 1.0 / (2 * _spectrumResolution);
    vDSP_vsmul(_complexBuffer.realp, 1, &scale, _complexBuffer.realp, 1, _nOver2);
    vDSP_vsmul(_complexBuffer.imagp, 1, &scale, _complexBuffer.imagp, 1, _nOver2);

    Float32 *outFFTData = (Float32 *) malloc(sizeof(Float32) * _nOver2);
    memset(outFFTData, 0, sizeof(Float32) * _nOver2 );

    // Complex vector magnitudes squared
    vDSP_zvmags(&_complexBuffer, 1, outFFTData, 1, _nOver2);

    // zero fill
    float zero = 0.0f;
    vDSP_vfill(&zero, outFFTData, 1, 1000);

    // max value from vector with value index
    Float32 maxVal;
    vDSP_Length maxIndex = 0;
    vDSP_maxvi(outFFTData, 1, &maxVal, &maxIndex, _nOver2);

    Float32 frequencyHZ = maxIndex * sampleRate / _spectrumResolution;

    [self.delegate didReceiveFrequency:frequencyHZ];

    free(outFFTData);
}


#pragma -mark buffer accumulator

- (void)initializeAccumulator
{
    _dataAccumulator = [[NSMutableData alloc] initWithLength:_spectrumResolution * sizeof(Float32)];
    _accumulatorFillIndex = 0;
}

- (void)destroyAccumulator
{
    if (_dataAccumulator) {
        _dataAccumulator = nil;
    }
    _accumulatorFillIndex = 0;
}

- (BOOL)accumulateFrames:(Float32 *)frames withNumSamples:(CMItemCount)numSamples
{
    if (self.accumulatorFillIndex >= _spectrumResolution) {
        return YES;
    } else {
        [_dataAccumulator appendBytes:frames length:numSamples * sizeof(Float32)];
        _accumulatorFillIndex = _accumulatorFillIndex + (UInt32)numSamples;
        if (_accumulatorFillIndex >= _spectrumResolution) {
            return YES;
        }
    }
    return NO;
}

- (void)emptyAccumulator
{
    _accumulatorFillIndex = 0;
    [_dataAccumulator setLength:0];
}

@end
