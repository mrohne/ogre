#ifndef __OgreOSXEGLSupport_H__
#define __OgreOSXEGLSupport_H__

#include "OgreEGLSupport.h"
#include <CoreFoundation/CoreFoundation.h>

namespace Ogre {

  class _OgreGLExport OSXEGLSupport : public EGLSupport
  {
  public:
    OSXEGLSupport(int profile);
    ~OSXEGLSupport();

    RenderWindow* newWindow(const String &name, unsigned int width, unsigned int height,
                            bool fullScreen, const NameValuePairList *miscParams) override;

    void start() override;
    void stop() override;
    
    static CFComparisonResult _compareModes (const void *val1, const void *val2, void *context);
    static Boolean _getDictionaryBoolean(CFDictionaryRef dict, const void* key);
    static long _getDictionaryLong(CFDictionaryRef dict, const void* key);

  };

} // namespace Ogre

#endif // __OgreOSXEGLSupport_H__
