//
//  main.m
//  wiiu-gcc-adapter
//
//  Created by Mitch Dzugan on 1/29/15.
//  Copyright (c) 2015 Mitch Dzugan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "libusb.h"
#import <WirtualJoy/WJoyDevice.h>
#import <VHID/VHIDDevice.h>

@interface Gcc : NSObject <VHIDDeviceDelegate>
@property (strong, nonatomic) VHIDDevice *VHID;
@property (strong, nonatomic) WJoyDevice *virtualDevice;
@end


@implementation Gcc

@synthesize VHID;
@synthesize virtualDevice;

- (Gcc *)setup:(int)ind {
    [WJoyDevice prepare];
    VHID = [[VHIDDevice alloc] initWithType:VHIDDeviceTypeJoystick pointerCount:3 buttonCount:12 isRelative:NO];
    
    NSDictionary *properties = @{
            WJoyDeviceProductStringKey : (
                [NSString stringWithFormat:@"WiiU GCC Port %@", @[@"1", @"2", @"3", @"4"][ind]]
            )
        };
    virtualDevice = [[WJoyDevice alloc] initWithHIDDescriptor:[VHID descriptor] properties:properties];
    [VHID setDelegate:self];
    return self;
}

- (void) remove {
    VHID = nil;
    virtualDevice = nil;
}

- (void)VHIDDevice:(VHIDDevice *)device stateChanged:(NSData *)state {
    [virtualDevice updateHIDState:state];
}

@end

@interface GccManager :NSObject
@property (nonatomic) libusb_device_handle *dev_handle;
@property (nonatomic) NSArray *controllers;
@end

@implementation GccManager

@synthesize dev_handle;
@synthesize controllers;

- (void) setup {
    SInt32 idVendor = 0x057e;
    SInt32 idProduct = 0x0337;
    
    libusb_context *ctx;
    libusb_device **devs;
    int r;
    ssize_t cnt;
    r = libusb_init(&ctx);
    libusb_set_debug(ctx, 3);
    cnt = libusb_get_device_list(ctx, &devs);
    dev_handle = libusb_open_device_with_vid_pid(ctx, idVendor, idProduct);
    libusb_free_device_list(devs, 1);
    
    if (dev_handle == NULL) {
        return;
    }
    
    if(libusb_kernel_driver_active(dev_handle, 0) == 1) {
        libusb_detach_kernel_driver(dev_handle, 0);
    }
    
    r = libusb_claim_interface(dev_handle, 0);
    
    int actual;
    unsigned char data[40];
    data[0] = 0x13;
    libusb_bulk_transfer(dev_handle, (2 | LIBUSB_ENDPOINT_OUT), data, 1, &actual, 0);
    
    controllers = @[[[[Gcc alloc] init] setup:0],
                    [[[Gcc alloc] init] setup:1],
                    [[[Gcc alloc] init] setup:2],
                    [[[Gcc alloc] init] setup:3]];
    
    [self poll];
}

- (void)poll {
    int actual;
    unsigned char data[40];
    unsigned char stickXRaw, stickYRaw;
    float stickX, stickY;
    NSPoint point = NSZeroPoint;
    while(true)
    {
        data[38] = 0;
        unsigned char * p = data + 1;
        if (0 != libusb_bulk_transfer(dev_handle, (129 | LIBUSB_ENDPOINT_IN), data, 37, &actual, 0)) {
            return;
        }
        
        if (actual == 37 && data[0] == 33) {
            for (int i=0; i<4; i++) {
                if (p[0] > 0) {
                    VHIDDevice *VHID = [controllers[i] VHID];
                    [VHID setButton:0  pressed:(p[1] & (1 << 0)) != 0];
                    [VHID setButton:1  pressed:(p[1] & (1 << 1)) != 0];
                    [VHID setButton:2  pressed:(p[1] & (1 << 2)) != 0];
                    [VHID setButton:3  pressed:(p[1] & (1 << 3)) != 0];
                    [VHID setButton:4  pressed:(p[1] & (1 << 4)) != 0];
                    [VHID setButton:5  pressed:(p[1] & (1 << 5)) != 0];
                    [VHID setButton:6  pressed:(p[1] & (1 << 6)) != 0];
                    [VHID setButton:7  pressed:(p[1] & (1 << 7)) != 0];
                    [VHID setButton:8  pressed:(p[2] & (1 << 0)) != 0];
                    [VHID setButton:9  pressed:(p[2] & (1 << 1)) != 0];
                    [VHID setButton:10 pressed:(p[2] & (1 << 2)) != 0];
                    [VHID setButton:11 pressed:(p[2] & (1 << 3)) != 0];
                    
                    stickXRaw = p[3];
                    stickYRaw = p[4];
                    stickX = (float)stickXRaw / (128.0) - 1.0;
                    stickY = (float)stickYRaw / (128.0) - 1.0;
                    point.x = stickX;
                    point.y = stickY;
                    [VHID setPointer:0 position:point];
                    
                    stickXRaw = p[5];
                    stickYRaw = p[6];
                    stickX = (float)stickXRaw / (128.0) - 1.0;
                    stickY = (float)stickYRaw / (128.0) - 1.0;
                    point.x = stickX;
                    point.y = stickY;
                    [VHID setPointer:1 position:point];
                
                    stickXRaw = p[7];
                    stickYRaw = p[8];
                    stickX = (float)stickXRaw / (255.0);
                    stickY = (float)stickYRaw / (255.0);
                    point.x = stickX;
                    point.y = stickY;
                    [VHID setPointer:2 position:point];
                }
                else {
                    VHIDDevice *VHID = [controllers[i] VHID];
                    point.x = 0;
                    point.y = 0;
                    [VHID setPointer:0 position:point];
                    [VHID setPointer:1 position:point];
                    [VHID setPointer:2 position:point];
                }
            
                p += 9;
            }
        }
        
        [NSThread sleepForTimeInterval:0.005f];
    }
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        [[[GccManager alloc] init] setup];    }
    return 0;
}
