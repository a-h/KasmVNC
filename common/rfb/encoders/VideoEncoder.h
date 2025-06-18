#pragma once

namespace rfb {
    class VideoEncoder {
    public:
        virtual void writeSkipRect() = 0;
        virtual ~VideoEncoder() = default;
    };
} // namespace rfb
