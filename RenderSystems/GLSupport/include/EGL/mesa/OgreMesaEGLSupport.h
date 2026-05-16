#ifndef __OgreMesaEGLSupport_H__
#define __OgreMesaEGLSupport_H__

#include "OgreEGLSupport.h"

namespace Ogre {

    class _OgreGLExport MesaEGLSupport : public EGLSupport
    {
    public:
        MesaEGLSupport(int profile);
        ~MesaEGLSupport();

        RenderWindow* newWindow(const String &name, unsigned int width, unsigned int height,
                                bool fullScreen, const NameValuePairList *miscParams) override;
    };

} // namespace Ogre

#endif // __OgreMesaEGLSupport_H__
