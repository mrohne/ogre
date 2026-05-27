/*
-----------------------------------------------------------------------------
This source file is part of OGRE
(Object-oriented Graphics Rendering Engine)
For the latest info, see http://www.ogre3d.org

Copyright (c) 2000-2014 Torus Knot Software Ltd

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
-----------------------------------------------------------------------------
*/

#import "OgreOSXEGLSupport.h"
#import "OgreOSXEGLWindow.h"
#import "OgreRoot.h"
#import "OgreLogManager.h"
#import "OgreStringConverter.h"

#import "OgreGLRenderSystemCommon.h"
#import "OgreGLNativeSupport.h"
#import <GL/gl.h>
#import <GL/glext.h>
#import <EGL/egl.h>
#import <EGL/eglext.h>
#import <AppKit/AppKit.h>
#import <AppKit/NSScreen.h>
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <QuartzCore/CVDisplayLink.h>
#import <iomanip>

@implementation OgreGLWindow

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

@end

namespace Ogre {
    
  OSXEGLWindow::OSXEGLWindow(OSXEGLSupport* support) : EGLWindow(support), mWindow(nil), mView(nil), mWindowOriginPt(NSZeroPoint),
    mHasResized(false), mWindowTitle(""),
    mUseOgreGLView(true), mContentScalingFactor(1.0), mStyleMask(NSResizableWindowMask|NSTitledWindowMask)
    {
      // Set vsync by default to save battery and reduce tearing
    }

  OSXEGLWindow::~OSXEGLWindow()
    {
      // defer to parent dtor
    }
	
  void OSXEGLWindow::create(const String& name, unsigned int widthPt, unsigned int heightPt,
                            bool fullScreen, const NameValuePairList *miscParams)
  {
    LogManager::getSingleton().stream() << "OSXEGLWindow::create " << name << " " << widthPt << "x" << heightPt << ".";

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSApplicationLoad();

    /*
   ***Key: "title" Description: The title of the window that will appear in the title bar
   Values: string Default: RenderTarget name

   ***Key: "colourDepth" Description: Colour depth of the resulting rendering window;
   only applies if fullScreen is set. Values: 16 or 32 Default: desktop depth Notes: [W32 specific]

   ***Key: "left" Description: screen x coordinate from left Values: positive integers
   Default: 'center window on screen' Notes: Ignored in case of full screen

   ***Key: "top" Description: screen y coordinate from top Values: positive integers
   Default: 'center window on screen' Notes: Ignored in case of full screen

   ***Key: "depthBuffer" [DX9 specific] Description: Use depth buffer Values: false or true Default: true

   ***Key: "externalWindowHandle" [API specific] Description: External window handle, for embedding the
   OGRE context Values: positive integer for W32 (HWND handle) poslong:posint:poslong (display*:screen:windowHandle)
   or poslong:posint:poslong:poslong (display*:screen:windowHandle:XVisualInfo*) for GLX Default: 0 (None)

   ***Key: "FSAA" Description: Full screen antialiasing factor Values: 0,2,4,6,... Default: 0

   ***Key: "displayFrequency" Description: Display frequency rate, for fullscreen mode Values: 60...?
   Default: Desktop vsync rate

   ***Key: "vsync" Description: Synchronize buffer swaps to vsync Values: true, false Default: 0

   ***Key: "currentGLContext" Description: use an externally created OpenGL context (must be current)
   Values: true, false Default: false
    */

    mName = name;
    mIsFullScreen = fullScreen;
    BOOL hasDepthBuffer = YES;
    int fsaa_samples = 0;
    bool hidden = false;
    NSString *windowTitle = [NSString stringWithCString:name.c_str() encoding:NSUTF8StringEncoding];
    int winxPt = 0, winyPt = 0;
    int colourDepth = 32;
    int surfaceOrder = 1;
    int contextProfile = GLNativeSupport::CONTEXT_CORE;
    bool currentGLContext = false;
    NSObject *externalGLContext = nil;
    NSObject* externalWindowHandle = nil; // NSOpenGLView, NSView or NSWindow
    NameValuePairList::const_iterator opt;
    if(miscParams) {
        opt = miscParams->find("title");
        if(opt != miscParams->end())
          windowTitle = [NSString stringWithCString:opt->second.c_str() encoding:NSUTF8StringEncoding];
				
        opt = miscParams->find("left");
        if(opt != miscParams->end())
          winxPt = StringConverter::parseUnsignedInt(opt->second);
				
        opt = miscParams->find("top");
        if(opt != miscParams->end())
          winyPt = (int)NSHeight([[NSScreen mainScreen] frame]) - StringConverter::parseUnsignedInt(opt->second) - heightPt;

        opt = miscParams->find("hidden");
        if (opt != miscParams->end())
          hidden = StringConverter::parseBool(opt->second);

        opt = miscParams->find("depthBuffer");
        if(opt != miscParams->end())
          hasDepthBuffer = StringConverter::parseBool(opt->second);
				
        opt = miscParams->find("FSAA");
        if(opt != miscParams->end())
          fsaa_samples = StringConverter::parseUnsignedInt(opt->second);
			
        opt = miscParams->find("gamma");
        if(opt != miscParams->end())
          mHwGamma = StringConverter::parseBool(opt->second);

        opt = miscParams->find("vsync");
        if(opt != miscParams->end())
          mVSync = StringConverter::parseBool(opt->second);

        opt = miscParams->find("colourDepth");
        if(opt != miscParams->end())
          colourDepth = StringConverter::parseUnsignedInt(opt->second);

        opt = miscParams->find("Full Screen");
        if(opt != miscParams->end())
          fullScreen = StringConverter::parseBool(opt->second);

        opt = miscParams->find("contentScalingFactor");
        if(opt != miscParams->end())
          mContentScalingFactor = StringConverter::parseReal(opt->second);
            
        opt = miscParams->find("contextProfile");
        if(opt != miscParams->end())
          contextProfile = StringConverter::parseInt(opt->second);

        opt = miscParams->find("currentGLContext");
        if (opt != miscParams->end())
          currentGLContext = StringConverter::parseBool(opt->second);

        opt = miscParams->find("externalGLControl");
        if (opt != miscParams->end())
          mIsExternalGLControl = StringConverter::parseBool(opt->second);
            
        opt = miscParams->find("externalGLContext");
        if(opt != miscParams->end())
          externalGLContext = (NSObject*)StringConverter::parseSizeT(opt->second);
            
        opt = miscParams->find("externalWindowHandle");
        if(opt != miscParams->end())
          externalWindowHandle = (NSObject*)StringConverter::parseSizeT(opt->second);
            
        opt = miscParams->find("border");
        if(opt != miscParams->end())
          {
            String border = opt->second;
            if (border == "none")
              {
                mStyleMask = NSBorderlessWindowMask;
              }
            else if (border == "fixed")
              {
                mStyleMask = NSTitledWindowMask;
              }
            // Default case set in initializer.
          }

        opt = miscParams->find("NSOpenGLCPSurfaceOrder");
        if(opt != miscParams->end())
          surfaceOrder = StringConverter::parseInt(opt->second);

        opt = miscParams->find("stereoMode");
        if (opt != miscParams->end())
          {
            mStereoEnabled = StringConverter::parseBool(opt->second);
          }
        
        opt = miscParams->find("FSAA");
        if (opt != miscParams->end())
          {
            int mSamples = StringConverter::parseUnsignedInt(opt->second);
          }
      }

    // EGL display
    mEglDisplay = mGLSupport->getGLDisplay();

    // ::EGLConfig
    int minAttribs[] = {
      EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
      EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
      EGL_BLUE_SIZE,    8,
      EGL_GREEN_SIZE,   8,
      EGL_RED_SIZE,     8,
      EGL_DEPTH_SIZE,   24,
      EGL_NONE
    };
    int maxAttribs[] = {
      EGL_RED_SIZE,        16,
      EGL_GREEN_SIZE,      16,
      EGL_BLUE_SIZE,       16,
      EGL_ALPHA_SIZE,      8,
      EGL_DEPTH_SIZE,      32,
      EGL_STENCIL_SIZE,    8,
      EGL_SAMPLE_BUFFERS,  1,
      EGL_SAMPLES,         4,
      EGL_NONE
    };
    mEglConfig = mGLSupport->selectGLConfig(minAttribs, maxAttribs);

    // ::EGLContext
    if (!eglBindAPI(EGL_OPENGL_API)) {
        OGRE_EXCEPT(Exception::ERR_RENDERINGAPI_ERROR, "eglBindAPI failed");
      }
    EGL_CHECK_ERROR
    EGLint contextAttribs[] = {
      EGL_CONTEXT_MAJOR_VERSION, 4,
      EGL_CONTEXT_MINOR_VERSION, 5,
      EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR,
      EGL_NONE
    };
    mEglContext = eglCreateContext(mEglDisplay, mEglConfig, nullptr, contextAttribs);

    // ::EGLSurface
    if(externalWindowHandle) {
        mView =
          [externalWindowHandle isKindOfClass:[NSWindow class]] ? 
          [(NSWindow*)externalWindowHandle contentView] : (NSView*)externalWindowHandle;
        if (![mView wantsLayer]) {
          [mView setWantsLayer:YES];
          [mView setLayerContentsRedrawPolicy:NSViewLayerContentsRedrawDuringViewResize];
        }
      }
    unsigned widthPx = _getPixelFromPoint(widthPt);
    unsigned heightPx = _getPixelFromPoint(heightPt);
    mWidth =  widthPx;
    mHeight = heightPx;

    // Keep our size up to date
    LogManager::getSingleton().stream() << "Create surface " << mWidth << "x" << mHeight << ".";
    int attribs[] = {
      EGL_WIDTH, int(mWidth),
      EGL_HEIGHT, int(mHeight),
      EGL_NONE,
    };
    mEglSurface = eglCreatePbufferSurface(mEglDisplay, mEglConfig, attribs);
    
    mContext = new EGLContext(mEglDisplay, mGLSupport, mEglConfig, mEglSurface, mEglContext);
    mContext->setCurrent();
    glEnable(GL_DEBUG_OUTPUT);
    glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS); 

    RenderWindow::resize(mWidth, mHeight);

    finaliseWindow();

    LogManager::getSingleton().stream()
      << "Pbuffer created " << widthPt << "x" << heightPt
      << " with backing store size " << mWidth << "x" << mHeight
      << " using content scaling factor " << std::fixed << std::setprecision(1) << getViewPointToPixelScale();
  }

  void OSXEGLWindow::destroy(void)
  {
    eglMakeCurrent(mEglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, nullptr);
    if(!mIsFullScreen) {
        // Unregister and destroy OGRE GLContext
        OGRE_DELETE mContext;

        if(mWindow) {
          [mWindow performClose:nil];
        }
    }
        
    mActive = false;
    mClosed = true;
  }

  void OSXEGLWindow::setHidden(bool hidden)
  {
    mHidden = hidden;
    if (hidden)
      [mWindow orderOut:nil];
    else
      [mWindow makeKeyAndOrderFront:nil];
  }

  void OSXEGLWindow::setVSyncEnabled(bool vsync)
  {
    mVSync = vsync;
  }

  float OSXEGLWindow::getViewPointToPixelScale()
  {
    return mContentScalingFactor > 1.0f ? mContentScalingFactor : 1.0f;
  }
    
  int OSXEGLWindow::_getPixelFromPoint(int viewPt) const
  {
    return mContentScalingFactor > 1.0 ? viewPt * mContentScalingFactor : viewPt;
  }
    
  void OSXEGLWindow::reposition(int leftPt, int topPt)
  {
    if(!mWindow)
      return;

    if(mIsFullScreen)
      return;

    NSRect frame = [mWindow frame];
    NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
    frame.origin.x = leftPt;
    frame.origin.y = screenFrame.size.height - frame.size.height - topPt;
    mWindowOriginPt = frame.origin;

    [mWindow setFrame:frame display:YES];
  }

  void OSXEGLWindow::resize(unsigned int widthPt, unsigned int heightPt)
  {
    // Check if the window size really changed
    unsigned widthPx = _getPixelFromPoint(widthPt);
    unsigned heightPx = _getPixelFromPoint(heightPt);
    if(mWidth == widthPx && mHeight == heightPx) return;
    mWidth =  widthPx;
    mHeight = heightPx;    
    mContext->endCurrent();
    static_cast<EGLContext*>(mContext)->_updateInternalResources(mEglDisplay, mEglConfig, EGL_NO_SURFACE);
    if (mEglSurface != EGL_NO_SURFACE) {
      int attribs[] = {
        EGL_WIDTH, int(mWidth),
        EGL_HEIGHT, int(mHeight),
        EGL_NONE,
      };
      eglDestroySurface(mEglDisplay, mEglSurface);
      mEglSurface = eglCreatePbufferSurface(mEglDisplay, mEglConfig, attribs);
    }
    static_cast<EGLContext*>(mContext)->_updateInternalResources(mEglDisplay, mEglConfig, mEglSurface);
    mContext->setCurrent();
    RenderWindow::resize(mWidth, mHeight); 
  }

  void OSXEGLWindow::windowMovedOrResized()
  {
    NSRect b = [mView bounds];
    unsigned widthPt = (unsigned)b.size.width;
    unsigned heightPt =(unsigned)b.size.height;
    unsigned widthPx = _getPixelFromPoint(widthPt);
    unsigned heightPx = _getPixelFromPoint(heightPt);
    if(mWidth == widthPx && mHeight == heightPx) return;
    mWidth =  widthPx;
    mHeight = heightPx;
    mContext->setCurrent();
    RenderWindow::resize(mWidth, mHeight); 
  }

  void OSXEGLWindow::swapBuffers()
  {
    if (mClosed) return;
    // Adopt to current view
    NSView* targetView = mView;
    if (!targetView) return;    
    // size and scale
    double scaleFactor = getViewPointToPixelScale();
    size_t physicalWidth  = static_cast<size_t>(mWidth);
    size_t physicalHeight = static_cast<size_t>(mHeight);
    size_t bytesPerRow    = physicalWidth * 4; 
    size_t dataLength     = bytesPerRow * physicalHeight;    
    mPixelBuffer.resize(dataLength);
    // read pixels
    mContext->setCurrent();
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, mWidth, mHeight, GL_RGBA, GL_UNSIGNED_BYTE, mPixelBuffer.data());
    // image backing
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, mPixelBuffer.data(), dataLength, NULL);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef imageRef = 
      CGImageCreate(
                    physicalWidth,
                    mHeight,
                    8,                                             // Bits per component
                    32,                                            // Bits per pixel
                    bytesPerRow,                                   // Bytes per row
                    colorSpace,
                    kCGImageAlphaLast | kCGBitmapByteOrderDefault, // Standard RGBA layout
                    provider,
                    NULL,
                    false,
                    kCGRenderingIntentDefault
                    );
    // Lambda encapsulating the raw CALayer blit operation
    auto blitToLayer = ^{
      if ([targetView layer] == nil) {
        [targetView setWantsLayer:YES];
        [targetView setLayerContentsRedrawPolicy:NSViewLayerContentsRedrawDuringViewResize];
      }
      CALayer *layer = [targetView layer];
      if (layer) {
        // 1. Tell Core Animation that the image matches your Retina scale factor.
        // This handles the (1 / scaleFactor) sizing reduction automatically on the GPU!
        [layer setContentsScale:scaleFactor];
        // 2. Lock gravity to the bottom-left corner
        [layer setContentsGravity:kCAGravityBottomLeft];
        // 3. Flip and shift using logical view dimensions (points) instead of raw pixels.
        double hh = mHeight / scaleFactor; 
        [layer setTransform:CATransform3DTranslate(CATransform3DMakeScale(1.0, -1.0, 1.0), 0.0, -hh, 0.0)];
        [layer setContents:(__bridge id)imageRef];
      }
    };    
    // Protect against libdispatch queue ownership assertions
    if ([NSThread isMainThread]) {
      // We are already on the main thread (driven by Qt repaint events) -> execute immediately
      blitToLayer();
    } else {
      // We are on a background rendering thread -> dispatch synchronously
      dispatch_sync(dispatch_get_main_queue(), blitToLayer);
    }
    // Safely free the transient structural definitions
    CGImageRelease(imageRef);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
  }
 
  //-------------------------------------------------------------------------------------------------//
  void OSXEGLWindow::getCustomAttribute( const String& name, void* pData )
  {
    if( name == "GLCONTEXT" ) 
      {
        *static_cast<GLContext**>(pData) = mContext;
        return;
      } 
    else if( name == "WINDOW" ) 
      {
        *(void**)(pData) = mWindow;
        return;
      } 
    else if( name == "VIEW" ) 
      {
        *(void**)(pData) = mView;
        return;
      }		
  }

  void OSXEGLWindow::createNewWindow(unsigned int width, unsigned int height, String title)
  {
    OGRE_EXCEPT(Exception::ERR_NOT_IMPLEMENTED, "Builtin Window creation broken. Use an external Window (e.g SDL2) or fix this");
  }

  void OSXEGLWindow::createWindowFromExternal(NSView *viewRef)
  {
    LogManager::getSingleton().logMessage("Creating external window");
    OGRE_EXCEPT(Exception::ERR_NOT_IMPLEMENTED, "External Window creation broken. Use an external Window (e.g SDL2) or fix this");
  }

  void OSXEGLWindow::_setWindowParameters(unsigned int width, unsigned int height)
  {
    if(mWindow)
      {
        if(mIsFullScreen)
          {
            // Set the backing store size to the viewport dimensions
            // This ensures that it will scale to the full screen size
            NSRect mainDisplayRect = [[NSScreen mainScreen] frame];
            NSRect backingRect = NSZeroRect;
            if(mContentScalingFactor > 1.0)
              backingRect = [[NSScreen mainScreen] convertRectToBacking:mainDisplayRect];
            else
              backingRect = mainDisplayRect;

            GLint backingStoreDimensions[2] = { static_cast<GLint>(backingRect.size.width), static_cast<GLint>(backingRect.size.height) };

            NSRect windowRect = NSMakeRect(0.0, 0.0, mainDisplayRect.size.width, mainDisplayRect.size.height);
            [mWindow setFrame:windowRect display:YES];
            [mView setFrame:windowRect];

            // Set window properties for full screen and save the origin in case the window has been moved
            [mWindow setStyleMask:NSBorderlessWindowMask];
            [mWindow setOpaque:YES];
            [mWindow setHidesOnDeactivate:YES];
            [mWindow setContentView:mView];
            [mWindow setFrameOrigin:NSZeroPoint];
            [mWindow setLevel:NSMainMenuWindowLevel+1];
                
            mWindowOriginPt = mWindow.frame.origin;
            mLeft = mTop = 0;
          }
        else
          {
            // Reset and disable the backing store in windowed mode
            GLint backingStoreDimensions[2] = { 0, 0 };

            NSRect viewRect = NSMakeRect(mWindowOriginPt.x, mWindowOriginPt.y, width, height);
            [mWindow setFrame:viewRect display:YES];
            [mView setFrame:viewRect];
            [mWindow setStyleMask:mStyleMask];
            [mWindow setOpaque:YES];
            [mWindow setHidesOnDeactivate:NO];
            [mWindow setContentView:mView];
            [mWindow setLevel:NSNormalWindowLevel];
            [mWindow center];

          }
            
        // Even though OgreCocoaView doesn't accept first responder, it will get passed onto the next in the chain
        [mWindow makeFirstResponder:mView];
        [NSApp activateIgnoringOtherApps:YES];
      }
  }

  void OSXEGLWindow::setFullscreen(bool fullScreen, unsigned int width, unsigned int height)
  {
    unsigned widthPx = _getPixelFromPoint(width);
    unsigned heightPx = _getPixelFromPoint(height);
    if (mIsFullScreen != fullScreen || widthPx != mWidth || heightPx != mHeight)
      {
        // Set the full screen flag
        mIsFullScreen = fullScreen;

        // Create a window if we haven't already, existence check is done within the functions
        if(!mWindow)
          {
            if(mIsExternal)
              createWindowFromExternal(mView);
            else
              createNewWindow(width, height, mWindowTitle);
          }

        _setWindowParameters(width, height);

        mWidth = widthPx;
        mHeight = heightPx;
      }
  }
}

// Local Variables:
// mode: objc
// tab-width: 4
// End:
