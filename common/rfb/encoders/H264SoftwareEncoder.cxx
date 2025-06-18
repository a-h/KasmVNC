#include "H264SoftwareEncoder.h"
extern "C" {
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
}
#include "KasmVideoConstants.h"
#include "rfb/LogWriter.h"
#include "rfb/SConnection.h"
#include "rfb/ServerCore.h"
#include "rfb/encodings.h"
#include "rfb/ffmpeg.h"

static rfb::LogWriter vlog("H264SoftwareEncoder");

namespace rfb {
    H264SoftwareEncoder::H264SoftwareEncoder(SConnection *conn, uint8_t frame_rate_, uint16_t bit_rate_) :
        Encoder(conn, encodingKasmVideo, static_cast<EncoderFlags>(EncoderUseNativePF | EncoderLossy), -1),
        frame_rate(frame_rate_), bit_rate(bit_rate_) {
        codec = avcodec_find_encoder(AV_CODEC_ID_H264);
        if (!codec)
            throw std::runtime_error("Could not find H264 encoder");

        auto *ctx = avcodec_alloc_context3(codec);
        if (!ctx) {
            throw std::runtime_error("Cannot allocate AVCodecContext");
        }
        ctx_guard.reset(ctx);

        auto *frame = av_frame_alloc();
        if (!frame) {
            throw std::runtime_error("Cannot allocate AVFrame");
        }
        frame_guard.reset(frame);

        ctx->time_base = {1, frame_rate};
        ctx->framerate = {frame_rate, 1};
        ctx->gop_size = GroupOfPictureSize; // interval between I-frames
        ctx->pix_fmt = AV_PIX_FMT_YUV420P;
        ctx->max_b_frames = 0; // No B-frames for immediate output

        av_opt_set(ctx->priv_data, "tune", "zerolatency", 0);
        av_opt_set(ctx->priv_data, "preset", "ultrafast", 0);

        auto *pkt = av_packet_alloc();
        if (!pkt)
            throw std::runtime_error("Could not allocate packet");

        pkt_guard.reset(pkt);
    }

    bool H264SoftwareEncoder::isSupported() {
        return conn->cp.supportsEncoding(encodingKasmVideo);
    }

    void H264SoftwareEncoder::writeRect(const PixelBuffer *pb, const Palette &palette) {
        // compress
        int stride;
        const auto rect = pb->getRect();
        const auto *buffer = pb->getBuffer(rect, &stride);

        const int width = rect.width();
        const int height = rect.height();
        auto *frame = frame_guard.get();

        const bool is_keyframe = frame->width != static_cast<int>(width) || frame->height != static_cast<int>(height);
        if (is_keyframe)
            init(width, height);

        frame->key_frame = is_keyframe;

        const uint8_t *src_data[1] = {buffer};
        const int src_line_size[1] = {width * 3}; // RGB has 3 bytes per pixel

        // TODO:  fix return
        sws_scale(sws_guard.get(), src_data, src_line_size, 0, height, frame->data, frame->linesize);

        int ret = avcodec_send_frame(ctx_guard.get(), frame);
        if (ret < 0) {
            vlog.error("Error sending frame to codec");
            return;
        }

        auto *pkt = pkt_guard.get();

        ret = avcodec_receive_packet(ctx_guard.get(), pkt);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
            // Trying one more time
            ret = avcodec_receive_packet(ctx_guard.get(), pkt);
        }

        if (ret < 0) {
            vlog.error("Error receiving packet from codec");
            return;
        }

        if (pkt->flags & AV_PKT_FLAG_KEY)
            vlog.info("Key frame %ld", frame->pts);

        auto *os = conn->getOutStream(conn->cp.supportsUdp);
        os->writeU8(kasmVideoH264 << 4);
        write_compact(os, pkt->size + 1);
        os->writeBytes(&pkt->data[0], pkt->size);

        ++frame->pts;
        av_packet_unref(pkt);
    }

    void H264SoftwareEncoder::writeSolidRect(int width, int height, const PixelFormat &pf, const rdr::U8 *colour) {}

    void H264SoftwareEncoder::writeSkipRect() {
        auto *os = conn->getOutStream(conn->cp.supportsUdp);
        os->writeU8(kasmVideoSkip << 4);
    }

    void H264SoftwareEncoder::write_compact(rdr::OutStream *os, int value) {
        auto b = value & 0x7F;
        if (value <= 0x7F) {
            os->writeU8(b);
        } else {
            os->writeU8(b | 0x80);
            b = value >> 7 & 0x7F;
            if (value <= 0x3FFF) {
                os->writeU8(b);
            } else {
                os->writeU8(b | 0x80);
                os->writeU8(value >> 14 & 0xFF);
            }
        }
    }

    void H264SoftwareEncoder::init(int width, int height) {
        auto *sws_ctx = sws_getContext(width,
                                       height,
                                       AV_PIX_FMT_RGB24,
                                       width,
                                       height,
                                       AV_PIX_FMT_YUV420P,
                                       SWS_BILINEAR,
                                       nullptr,
                                       nullptr,
                                       nullptr);

        sws_guard.reset(sws_ctx);

        ctx_guard->width = width;
        ctx_guard->height = height;

        auto *frame = frame_guard.get();
        frame->format = ctx_guard->pix_fmt;
        frame->width = width;
        frame->height = height;

        if (av_frame_get_buffer(frame, 0) < 0) {
            throw std::runtime_error("Could not allocate frame data");
        }

        if (avcodec_open2(ctx_guard.get(), codec, nullptr) < 0) {
            throw std::runtime_error("Failed to open codec");
        }
    }
} // namespace rfb
