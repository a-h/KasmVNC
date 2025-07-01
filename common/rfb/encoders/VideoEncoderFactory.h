#pragma once

#include <cstdint>
#include "EncoderProbe.h"
#include "rfb/Encoder.h"

namespace rfb {
    Encoder *create_encoder(const FFmpeg &ffmpeg, KasmVideoEncoders::Encoder video_encoder, SConnection *conn, uint8_t frame_rate,
                            uint16_t bit_rate);

} // namespace rfb
