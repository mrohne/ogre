#import <EGL/egl.h>
#import <EGL/eglext.h>
#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

#include "OgreException.h"
#include "OgreLogManager.h"
#include "OgreRoot.h"

#include "OgreEGLWindow.h"
#include "OgreGLUtil.h"
#include "OgreOSXEGLSupport.h"
#include "OgreOSXEGLWindow.h"

#include <stdlib.h>
#include <vector>

#ifdef __APPLE__
extern "C" {
    void glFlushRenderAPPLE() 
    {
        // Intentionally left blank.
        // Mesa's EGL context uses standard glFlush() or eglSwapBuffers() pipelines,
        // so this hardware-specific Apple driver command is a no-op here.
    }
}
#endif

namespace Ogre {
  static auto eglQueryDevicesEXT = (PFNEGLQUERYDEVICESEXTPROC) eglGetProcAddress("eglQueryDevicesEXT");
  static auto eglQueryDeviceStringEXT = (PFNEGLQUERYDEVICESTRINGEXTPROC) eglGetProcAddress("eglQueryDeviceStringEXT");
  void ProbeEGLPlatform() {
    @autoreleasepool {
      NSLog(@"==================================================");
      NSLog(@"       MESA EGL PLATFORM PROBE (PROTOTYPES)       ");
      NSLog(@"==================================================");
      // 1. Fetch Core Client Extensions (No active display connection needed)
      const char *clientExts = eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
      if (!clientExts) {
        NSLog(@"[ERROR] Could not query EGL Client Extensions.");
        return;
      }
      // 2. List extensions
      EGLint foundCount = 0;
      NSString *extsString = [NSString stringWithUTF8String:clientExts];
      NSArray<NSString *> *extensionsList = [extsString componentsSeparatedByString:@" "];
      NSLog(@"\n--- Global EGL Client Extensions ---");
      for (NSString *extName in extensionsList) {
        NSString *trimmedExt = [extName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        BOOL platform = trimmedExt.length > 0 && [trimmedExt localizedCaseInsensitiveContainsString:@"platform"];
        NSLog(@"  %@ %@", platform ? @"*" : @" ", trimmedExt);
        if (platform) foundCount++;
      }
      if (foundCount == 0) {
        NSLog(@"  (No explicit 'platform' extensions identified)");
      } else {
        NSLog(@"\n--- Found %d  'platform' extensions", foundCount);
      }
      NSLog(@"==================================================");
    }
  }
  void ProbeEGLDevice() {
    @autoreleasepool {
      NSLog(@"==================================================");
      NSLog(@"       MESA EGL DEVICE PROBE (PROTOTYPES)         ");
      NSLog(@"==================================================");
      // 3. Query Low-Level Devices Directly (No eglGetProcAddress needed!)
      EGLint maxDevices = 16;
      std::vector<EGLDeviceEXT> devices(maxDevices);
      EGLint numDevices = 0;
      EGLBoolean success = eglQueryDevicesEXT(maxDevices, devices.data(), &numDevices);
      if (!success || numDevices == 0) {
        NSLog(@"[ERROR] No isolated physical device tracking loops reported.");
        return;
      }
      NSLog(@"\n--- Enumerating Independent GPU/Software Devices (%d found) ---", numDevices);
      for (EGLint i = 0; i < numDevices; ++i) {
        NSLog(@"  Device Index [%d]:", i);
        const char *deviceExtensions = eglQueryDeviceStringEXT(devices[i], EGL_EXTENSIONS);
        if (deviceExtensions) {
          NSString *devExtStr = [NSString stringWithUTF8String:deviceExtensions];
          NSArray<NSString *> *devExtList = [devExtStr componentsSeparatedByString:@" "];
          BOOL isSoftware = [devExtStr containsString:@"EGL_MESA_device_software"];
          NSLog(@"    - Compute Engine Profile: %@", isSoftware ? @"CPU Software (llvmpipe)" : @"Hardware Accelerated (GPU)");
          NSLog(@"    - Device Extensions Supported:");
          for (NSString *dExt in devExtList) {
            if ([dExt length] > 0) {
              NSLog(@"        + %@", dExt);
            }
          }
        }
      }
      NSLog(@"==================================================");
    }
  }  

  GLNativeSupport* getGLSupport(int profile)
  {
    LogManager::getSingleton().stream() << "Ogre::getGLSupport(" << profile << ")";
    return new OSXEGLSupport(profile);
  }

  OSXEGLSupport::OSXEGLSupport(int profile) : EGLSupport(profile)
    {
      // Defer to parent class EGLSupport
      ProbeEGLPlatform();
      mNativeDisplay = EGL_DEFAULT_DISPLAY;
      mGLDisplay = getGLDisplay();
      ProbeEGLDevice();
      // Populate a fallback video mode configuration. 
      // Since Qt6 controls window dimensions, this serves as an Ogre initialization sanity check.
      mCurrentMode.width = 1024;
      mCurrentMode.height = 768;
      mCurrentMode.refreshRate = 60;
      mVideoModes.push_back(mCurrentMode);
      mOriginalMode = mCurrentMode;
      // Query capabilities from the Mesa EGL config space
      EGLConfig *glConfigs;
      int config, nConfigs = 0;
      glConfigs = chooseGLConfig(NULL, &nConfigs);

      for (config = 0; config < nConfigs; config++)
        {
          int caveat, samples;
          getGLConfigAttrib(glConfigs[config], EGL_CONFIG_CAVEAT, &caveat);
          if (caveat != EGL_SLOW_CONFIG)
            {
              getGLConfigAttrib(glConfigs[config], EGL_SAMPLES, &samples);
              mFSAALevels.push_back(samples);
            }
        }

      if (glConfigs) {
        free(glConfigs);
      }
      initialiseExtensions();
    }

  OSXEGLSupport::~OSXEGLSupport()
    {
      if (mGLDisplay)
        {
          eglTerminate(mGLDisplay);
        }
    }

  RenderWindow* OSXEGLSupport::newWindow(const String &name, 
                                         unsigned int width, 
                                         unsigned int height, 
                                         bool fullScreen, 
                                         const NameValuePairList *miscParams)
  {
    // Instantiating a plain vanilla EGLWindow completely bypasses platform-specific UI bindings
    // (like Cocoa NSWindows, X11 windows, or Wayland surfaces).
    OSXEGLWindow* window = new OSXEGLWindow(this);
    window->create(name, width, height, fullScreen, miscParams);
        
    return window;
  }
  void OSXEGLSupport::start()
  {
    LogManager::getSingleton().logMessage("OSX EGL/mesa starting");
  }

  void OSXEGLSupport::stop()
  {
    LogManager::getSingleton().logMessage("OSX EGL/mesa stopping");
  }    
  CFComparisonResult OSXEGLSupport::_compareModes (const void *val1, const void *val2, void *context)
  {
    // These are the values we will be interested in...
    /*
      CGDisplayModeGetWidth
      CGDisplayModeGetHeight
      CGDisplayModeGetRefreshRate
      _getDictionaryLong((mode), kCGDisplayBitsPerPixel)
      CGDisplayModeGetIOFlags((mode), kDisplayModeStretchedFlag)
      CGDisplayModeGetIOFlags((mode), kDisplayModeSafetyFlags)
    */
	
    // CFArray comparison callback for sorting display modes.
#pragma unused(context)
    CGDisplayModeRef thisMode = (CGDisplayModeRef)val1;
    CGDisplayModeRef otherMode = (CGDisplayModeRef)val2;
	
    size_t width = CGDisplayModeGetWidth(thisMode);
    size_t otherWidth = CGDisplayModeGetWidth(otherMode);
	
    size_t height = CGDisplayModeGetHeight(thisMode);
    size_t otherHeight = CGDisplayModeGetHeight(otherMode);

    // Sort modes in screen size order
    if (width * height < otherWidth * otherHeight)
      {
        return kCFCompareLessThan;
      }
    else if (width * height > otherWidth * otherHeight)
      {
        return kCFCompareGreaterThan;
      }

    // Sort modes by refresh rate.
    double refreshRate = CGDisplayModeGetRefreshRate(thisMode);
    double otherRefreshRate = CGDisplayModeGetRefreshRate(otherMode);

    if (refreshRate < otherRefreshRate)
      {
        return kCFCompareLessThan;
      }
    else if (refreshRate > otherRefreshRate)
      {
        return kCFCompareGreaterThan;
      }

    return kCFCompareEqualTo;
  }

  Boolean OSXEGLSupport::_getDictionaryBoolean(CFDictionaryRef dict, const void* key)
  {
    Boolean value = false;
    CFBooleanRef boolRef;
    boolRef = (CFBooleanRef)CFDictionaryGetValue(dict, key);
	
    if (boolRef != NULL)
      value = CFBooleanGetValue(boolRef); 	
		
    return value;
  }

  long OSXEGLSupport::_getDictionaryLong(CFDictionaryRef dict, const void* key)
  {
    long value = 0;
    CFNumberRef numRef;
    numRef = (CFNumberRef)CFDictionaryGetValue(dict, key);
	
    if (numRef != NULL)
      CFNumberGetValue(numRef, kCFNumberLongType, &value);	
		
    return value;
  }
}

// Local Variables:
// mode: objc
// tab-width: 2
// End:
