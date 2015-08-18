//
//  ToneReceiver.m
//  Frequency
//
//  Created by Quentin on 23/09/2014.
//  Copyright (c) 2014 Cellules. All rights reserved.
//

#import "ToneReceiver.h"

#import "mo_audio.h" //stuff that helps set up low-level audio
#import "FFTHelper.h"

#define SAMPLE_RATE 44100  //22050 //44100
#define FRAMESIZE  4096
#define NUMCHANNELS 2

@implementation ToneReceiver

// C "trampoline" function to invoke Objective-C method
int MyObjectDoSomethingWith (void *self,  Float32 aParameter)
{
  // Call the Objective-C method using Objective-C syntax
  return [(id) self doSomethingWith:aParameter];
}

- (int) doSomethingWith:(float) aParameter
{
  // The Objective-C function you wanted to call from C++.
  // do work here..
  [self.delegate didReceiveFrequency:aParameter];
  return 21 ; // half of 42
}

- (ToneReceiver*)initWithSpectrumResolution:(UInt32)spectrumResolution {
  self = [super init];
  mySelf = self;

  return self;
}

#pragma -mark signal processing data initialization

- (void)dealloc
{
  NSLog(@"Dealloc");
}

void *mySelf = NULL;

- (void)start
{
  NSLog(@"Start");
  [self initMomuAudio];
}

// init momu library
-(void) initMomuAudio {
  
  bool result = false;
  
  result = MoAudio::init( SAMPLE_RATE, FRAMESIZE, NUMCHANNELS, false);
  if (!result) { NSLog(@" MoAudio init ERROR"); }
  
  result = MoAudio::start( AudioCallback, NULL );
  if (!result) { NSLog(@" MoAudio start ERROR"); }
}


- (void)stop
{
  NSLog(@"Stop");
  MoAudio::stop();
}

void AudioCallback( Float32 * buffer, UInt32 frameSize, void * userData )
{
  Float32 x = objcYIN(frameSize, SAMPLE_RATE, buffer);
  MyObjectDoSomethingWith(mySelf, x);
  
}



// YIN ALGORITHM from https://github.com/CRoig/objectiveCYIN
//-------------------
//
//  objCYIN.m
//  objectiveCYIN
//
//  Created by Carles Roig (ATIC) on 02/07/13.
//  Copyright (c) 2013 Carles Roig (ATIC). All rights reserved.
//

//  [1] De Cheveigné, Alain, and Hideki Kawahara. "YIN, a fundamental
//      frequency estimator for speech and music." The Journal of the
//      Acoustical Society of America 111.4 (2002): 1917-1930.

void difference (float *inputBuffer, float *yinBuffer, int bufferSize){
  int bufferSize2 = (int) bufferSize/2;
  int j, tau;
  float delta;
  
  for (tau = 0; tau < bufferSize2; tau++) {
    yinBuffer[tau] = 0;
  }
  for (tau = 1; tau < bufferSize2; tau++) {
    for (j = 0; j < bufferSize2; j++) {
      delta = inputBuffer[j] - inputBuffer[j+tau];
      yinBuffer[tau] += delta * delta;
    }
  }
}

void cummulativeMeanNormalizedDifference(float *yinBuffer, int bufferSize){
  int bufferSize2 = (int) bufferSize/2;
  int tau;
  
  yinBuffer[0] = 1;
  //Very small optimization in comparison with AUBIO
  //start the running sum with the correct value:
  //the first value of the yinBuffer
  
  float runningSum = yinBuffer[1];
  
  //yinBuffer[1] is always 1
  yinBuffer[1] = 1;
  
  //now start at tau = 2
  for (tau = 2; tau < bufferSize2; tau++) {
    runningSum += yinBuffer[tau];
    yinBuffer[tau] *= tau / runningSum;
  }
}

int absoluteThreshold(float *yinBuffer, int bufferSize){
  int bufferSize2 = (int) bufferSize/2;
  double threshold = 0.15;
  int tau;
  
  for (tau = 1; tau < bufferSize2; tau++){
    if  (yinBuffer[tau] < threshold) {
      while (tau+1 < bufferSize2 && yinBuffer[tau+1] < yinBuffer[tau]) tau++;
      return tau;
    }
  }
  return -1;
}

float parabolicInterpolation(int tauEstimate, float *yinBuffer, int bufferSize){
  int bufferSize2 = (int) bufferSize/2;
  float s0, s1, s2;
  int x0 = (tauEstimate < 1) ? tauEstimate : tauEstimate -1;
  int x2 = (tauEstimate + 1 < bufferSize2) ? tauEstimate + 1 : tauEstimate;
  if (x0 == tauEstimate)
    return (yinBuffer[tauEstimate] <= yinBuffer[x2]) ? tauEstimate : x2;
  if (x2 == tauEstimate)
    return (yinBuffer[tauEstimate] <= yinBuffer[x0]) ? tauEstimate : x0;
  s0 = yinBuffer[x0];
  s1 = yinBuffer[tauEstimate];
  s2 = yinBuffer[x2];
  return tauEstimate + 0.5f * (s2 - s0) / (2.0f * s1 - s2 - s0);
}

Float32 *inputBuffer= NULL;
Float32 *yinBuffer= NULL;

float objcYIN(UInt32 inNumberFrames, float sampleRate, float *inData){
  int bufferSize = inNumberFrames;
  
  inputBuffer = (Float32*)malloc(bufferSize * sizeof(Float32));
  yinBuffer = (Float32*)malloc((bufferSize/2) * sizeof(Float32));
  
  int tauEstimate = -1;
  float pitchInHertz = 0;
  
  // Setp 0: Get the data
  for (int i = 0; i < bufferSize; i++) {
    inputBuffer[i] = inData[i]/(32768); // 2^15 = 32768
  }
  
  // Step 2: Difference
  difference(inputBuffer, yinBuffer, bufferSize);
  
  // Step 3: cumulativeMeanNormalizedDifference
  cummulativeMeanNormalizedDifference(yinBuffer, bufferSize);
  // The cumulative mean normalized difference function
  // as described in step 3 of the YIN paper [1]
  
  // Step 4: absoluteThreshold
  tauEstimate = absoluteThreshold(yinBuffer, bufferSize);
  
  // Step 5: parabolicInterpolation
  if (tauEstimate !=-1) {
    float betterTau = parabolicInterpolation(tauEstimate, yinBuffer, bufferSize);
    pitchInHertz = sampleRate/betterTau;
  }
  
  return pitchInHertz;
}

@end
