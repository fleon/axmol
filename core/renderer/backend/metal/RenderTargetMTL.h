#pragma once
#include "../RenderTarget.h"
#include "CommandBufferMTL.h"

NS_AX_BACKEND_BEGIN

class RenderTargetMTL : public RenderTarget
{
public:
    struct Attachment
    {
        id<MTLTexture> texture = nil;
        int level              = 0;
        explicit operator bool() const { return texture != nullptr; }
    };

    /*
     * generateFBO, false, use for screen framebuffer
     */
    RenderTargetMTL(bool defaultRenderTarget);
    ~RenderTargetMTL();

    void applyRenderPassAttachments(const RenderPassDescriptor&, MTLRenderPassDescriptor*) const;

    Attachment getColorAttachment(int index) const;
    Attachment getDepthAttachment() const;
    Attachment getStencilAttachment() const;

    PixelFormat getColorAttachmentPixelFormat(int index) const;
    PixelFormat getDepthAttachmentPixelFormat() const;
    PixelFormat getStencilAttachmentPixelFormat() const;
    NSUInteger getSampleCount() const;
};

NS_AX_BACKEND_END
