//
//  ToneReceiver.h
//  Frequency
//
//  Created by Quentin on 23/09/2014.
//  Copyright (c) 2014 Cellules. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MyObject-C-Interface.h"

@interface ToneReceiver : NSObject

- (ToneReceiver*)initWithSpectrumResolution:(UInt32)spectrumResolution;
- (void)start;
- (void)stop;
- (int) doSomethingWith:(float) aParameter;


@property (nonatomic, assign) id delegate;

@end

@protocol ToneReceiverProtocol

- (void)didReceiveFrequency:(Float32)frequency;

@end
