#include "RenderTargetMTL.h"
#include "UtilsMTL.h"

NS_AX_BACKEND_BEGIN

static MTLLoadAction getLoadAction(const RenderPassDescriptor& params, TargetBufferFlags buffer)
{
    const auto clearFlags        = (TargetBufferFlags)params.flags.clear;
    const auto discardStartFlags = params.flags.discardStart;
    if (bitmask::any(clearFlags, buffer))
    {
        return MTLLoadActionClear;
    }
    else if (bitmask::any(discardStartFlags, buffer))
    {
        return MTLLoadActionDontCare;
    }
    return MTLLoadActionLoad;
}

static MTLStoreAction getStoreAction(const RenderPassDescriptor& params, TargetBufferFlags buffer)
{
    const auto discardEndFlags = params.flags.discardEnd;
    if (bitmask::any(discardEndFlags, buffer))
    {
        return MTLStoreActionDontCare;
    }
    return MTLStoreActionStore;
}

static MTLStoreAction getMSAAStoreAction(const RenderPassDescriptor& params, TargetBufferFlags buffer)
{
    const auto baseStoreAction = getStoreAction(params, buffer);
    if (baseStoreAction == MTLStoreActionDontCare)
        return MTLStoreActionDontCare;

#if defined(__IPHONE_10_0) || defined(__MAC_10_12)
    if (@available(iOS 10.0, macOS 10.12, *))
        return MTLStoreActionStoreAndMultisampleResolve;
#endif
    return MTLStoreActionMultisampleResolve;
}

RenderTargetMTL::RenderTargetMTL(bool defaultRenderTarget) : RenderTarget(defaultRenderTarget) {}
RenderTargetMTL::~RenderTargetMTL() {}

void RenderTargetMTL::applyRenderPassAttachments(const RenderPassDescriptor& params,
                                                 MTLRenderPassDescriptor* descriptor) const
{
    // const auto discardFlags = params.flags.discardEnd;
    auto clearFlags = params.flags.clear;

    for (size_t i = 0; i < MAX_COLOR_ATTCHMENT; i++)
    {
        auto attachment = getColorAttachment(static_cast<int>(i));
        if (!attachment)
        {
            continue;
        }

        const auto MRTColorFlag = getMRTColorFlag(i);

        descriptor.colorAttachments[i].texture = attachment.texture;
        descriptor.colorAttachments[i].level   = attachment.level;
        // descriptor.colorAttachments[i].slice = attachment.layer;
        descriptor.colorAttachments[i].loadAction  = getLoadAction(params, MRTColorFlag);
        descriptor.colorAttachments[i].storeAction = getStoreAction(params, MRTColorFlag);
        if (bitmask::any(clearFlags, MRTColorFlag))
            descriptor.colorAttachments[i].clearColor =
                MTLClearColorMake(params.clearColorValue[0], params.clearColorValue[1], params.clearColorValue[2],
                                params.clearColorValue[3]);

        if (isDefaultRenderTarget() && i == 0)
        {
            auto msaaColorAttachment = UtilsMTL::getDefaultColorAttachmentTexture();
            if (msaaColorAttachment != nil)
            {
                descriptor.colorAttachments[i].texture     = msaaColorAttachment;
                descriptor.colorAttachments[i].level       = 0;
                descriptor.colorAttachments[i].storeAction = getMSAAStoreAction(params, MRTColorFlag);
                if (descriptor.colorAttachments[i].storeAction != MTLStoreActionDontCare)
                {
                    descriptor.colorAttachments[i].resolveTexture = attachment.texture;
                    descriptor.colorAttachments[i].resolveLevel   = attachment.level;
                }
            }
        }
    }

    // Sets descriptor depth and stencil params, should match RenderTargetMTL::chooseAttachmentFormat
    {
        auto depthAttachment = getDepthAttachment();
        if (depthAttachment)
        {
            descriptor.depthAttachment.texture = depthAttachment.texture;
            descriptor.depthAttachment.level   = depthAttachment.level;
            // descriptor.depthAttachment.slice = depthAttachment.layer;
            descriptor.depthAttachment.loadAction  = getLoadAction(params, TargetBufferFlags::DEPTH);
            descriptor.depthAttachment.storeAction = getStoreAction(params, TargetBufferFlags::DEPTH);
            if (bitmask::any(clearFlags, TargetBufferFlags::DEPTH))
                descriptor.depthAttachment.clearDepth = params.clearDepthValue;
        }

        auto stencilAttachment = getStencilAttachment();
        if (stencilAttachment)
        {
            descriptor.stencilAttachment.texture = stencilAttachment.texture;
            descriptor.stencilAttachment.level   = stencilAttachment.level;
            // descriptor.stencilAttachment.slice = depthAttachment.layer;
            descriptor.stencilAttachment.loadAction  = getLoadAction(params, TargetBufferFlags::STENCIL);
            descriptor.stencilAttachment.storeAction = getStoreAction(params, TargetBufferFlags::STENCIL);
            if (bitmask::any(clearFlags, TargetBufferFlags::STENCIL))
                descriptor.stencilAttachment.clearStencil = params.clearStencilValue;
        }
    }

    _dirtyFlags = TargetBufferFlags::NONE;
}

RenderTargetMTL::Attachment RenderTargetMTL::getColorAttachment(int index) const
{
    if (isDefaultRenderTarget() && index == 0)
        return {DriverMTL::getCurrentDrawable().texture, 0};
    auto& rb = this->_color[index];
    return RenderTargetMTL::Attachment{static_cast<bool>(rb) ? (id<MTLTexture>)(rb.texture->getHandler()) : nil,
                                       rb.level};
}

RenderTargetMTL::Attachment RenderTargetMTL::getDepthAttachment() const
{
    if (isDefaultRenderTarget())
        return {UtilsMTL::getDefaultDepthStencilTexture(), 0};
    auto& rb = this->_depth;
    return RenderTargetMTL::Attachment{!!rb ? (id<MTLTexture>)(rb.texture->getHandler()) : nil, rb.level};
}

RenderTargetMTL::Attachment RenderTargetMTL::getStencilAttachment() const
{
    if (isDefaultRenderTarget())
        return RenderTargetMTL::Attachment{UtilsMTL::getDefaultDepthStencilTexture(), 0};
    auto& rb = this->_stencil;
    return RenderTargetMTL::Attachment{!!rb ? (id<MTLTexture>)(rb.texture->getHandler()) : nil, rb.level};
}

PixelFormat RenderTargetMTL::getColorAttachmentPixelFormat(int index) const
{
    // !!!important
    // the default framebuffer pixel format is: MTLPixelFormatBGRA8Unorm
    if (isDefaultRenderTarget() && index == 0)
        return PixelFormat::BGRA8;
    auto& rb = this->_color[index];
    return rb ? rb.texture->getTextureFormat() : PixelFormat::NONE;
}

PixelFormat RenderTargetMTL::getDepthAttachmentPixelFormat() const
{  // FIXME: axmol only support D24S8
    if (isDefaultRenderTarget())
        return PixelFormat::D24S8;
    if (_depth)
        return _depth.texture->getTextureFormat();
    return PixelFormat::NONE;
}

PixelFormat RenderTargetMTL::getStencilAttachmentPixelFormat() const
{  // FIXME: axmol only support D24S8
    if (isDefaultRenderTarget())
        return PixelFormat::D24S8;
    if (_stencil)
        return _stencil.texture->getTextureFormat();
    return PixelFormat::NONE;
}

NSUInteger RenderTargetMTL::getSampleCount() const
{
    if (isDefaultRenderTarget())
        return UtilsMTL::getDefaultRenderTargetSampleCount();

    auto attachment = getColorAttachment(0);
    if (attachment.texture != nil)
        return attachment.texture.sampleCount;

    auto depthAttachment = getDepthAttachment();
    if (depthAttachment.texture != nil)
        return depthAttachment.texture.sampleCount;

    return 1;
}

NS_AX_BACKEND_END
