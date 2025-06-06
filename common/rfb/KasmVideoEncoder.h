/* Copyright (C) 2024 Kasm.  All Rights Reserved.
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this software; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307,
 * USA.
 */
#ifndef __RFB_KASMVIDEOENCODER_H__
#define __RFB_KASMVIDEOENCODER_H__

#include <rfb/Encoder.h>
#include <cstdint>

extern "C" {
#include <libavcodec/avcodec.h>
}

struct h264_t {
    AVCodecContext *ctx;
    AVFrame *frame;
    AVPacket pkt;
};

namespace rfb {
    class KasmVideoEncoder : public Encoder {
    public:
        explicit KasmVideoEncoder(SConnection *conn);

        ~KasmVideoEncoder() override = default;

        bool isSupported() override;

        void writeRect(const PixelBuffer *pb, const Palette &palette) override;

        virtual void writeSkipRect();

        void writeSolidRect(int width, int height,
                            const PixelFormat &pf,
                            const rdr::U8 *colour) override;

    protected:
        static void writeCompact(rdr::U32 value, rdr::OutStream *os);

    private:
        bool init{false};
        uint32_t sw{0}, sh{0};

        h264_t h264{};
    };
}
#endif
