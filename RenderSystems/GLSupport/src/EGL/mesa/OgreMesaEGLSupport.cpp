/*
-----------------------------------------------------------------------------
This source file is part of OGRE
    (Object-oriented Graphics Rendering Engine)
For the latest info, see http://www.ogre3d.org/

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

#include "OgreException.h"
#include "OgreLogManager.h"
#include "OgreRoot.h"

#include "OgreEGLWindow.h"
#include "OgreGLUtil.h"
#include "OgreMesaEGLSupport.h"

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

    GLNativeSupport* getGLSupport(int profile)
    {
        return new MesaEGLSupport(profile);
    }

    MesaEGLSupport::MesaEGLSupport(int profile) : EGLSupport(profile)
    {        
        // Qt6 and Homebrew Mesa establish the environment context.
        // We link directly to the default EGL display token.
        mNativeDisplay = EGL_DEFAULT_DISPLAY;
        mGLDisplay = getGLDisplay();

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

    MesaEGLSupport::~MesaEGLSupport()
    {
        if (mGLDisplay)
        {
            eglTerminate(mGLDisplay);
        }
    }

    RenderWindow* MesaEGLSupport::newWindow(const String &name, 
                                           unsigned int width, 
                                           unsigned int height, 
                                           bool fullScreen, 
                                           const NameValuePairList *miscParams)
    {
        // Instantiating a plain vanilla EGLWindow completely bypasses platform-specific UI bindings
        // (like Cocoa NSWindows, X11 windows, or Wayland surfaces).
        EGLWindow* window = new EGLWindow(this);
        window->create(name, width, height, fullScreen, miscParams);
        
        return window;
    }
}
