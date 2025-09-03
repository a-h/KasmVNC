#include "EncoderProbe.h"
#include <fcntl.h>
#include <string>
#include <unistd.h>
#include <vector>
#include "KasmVideoConstants.h"

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavutil/hwcontext.h>
}
#include "rfb/ffmpeg.h"

namespace rfb::video_encoders {
    const std::vector<KasmVideoEncoders::Encoder>& available_encoders = EncoderProbe::get(FFmpeg::get()).get_available_encoders();
    const KasmVideoEncoders::Encoder best_encoder = EncoderProbe::get(FFmpeg::get()).select_best_encoder();
    const std::string_view drm_device_path = EncoderProbe::get(FFmpeg::get()).get_drm_device_path();

    struct EncoderCandidate {
        KasmVideoEncoders::Encoder encoder;
        AVCodecID codec_id;
        AVHWDeviceType hw_type;
    };

    static std::array<EncoderCandidate, 3> candidates = {
            {//{KasmVideoEncoders::Encoder::h264_nvenc, AV_CODEC_ID_H264, AV_HWDEVICE_TYPE_VAAPI}
                {KasmVideoEncoders::Encoder::h264_vaapi, AV_CODEC_ID_H264, AV_HWDEVICE_TYPE_VAAPI},
             {KasmVideoEncoders::Encoder::h264_software, AV_CODEC_ID_H264, AV_HWDEVICE_TYPE_NONE}}};

    EncoderProbe::EncoderProbe(FFmpeg &ffmpeg_) : ffmpeg(ffmpeg_) {
        if (ffmpeg.is_available()) {
            for (const auto &encoder_candidate: candidates) {
                const AVCodec *codec = ffmpeg.avcodec_find_encoder_by_name(KasmVideoEncoders::to_string(encoder_candidate.encoder).data());
                if (!codec)
                    continue;

                if (encoder_candidate.hw_type != AV_HWDEVICE_TYPE_NONE) {
                    FFmpeg::BufferGuard hw_ctx_guard;
                    AVBufferRef *hw_ctx{};
                    hw_ctx_guard.reset(hw_ctx);

                    for (auto &drm_dev_path: drm_device_paths) {
                        const auto err = ffmpeg.av_hwdevice_ctx_create(&hw_ctx, encoder_candidate.hw_type, drm_dev_path.data(), nullptr, 0);
                        if (err < 0) {
                            puts((ffmpeg.get_error_description(err) + '\n').c_str());
                        } else {
                            drm_device_path = drm_dev_path;

                            available_encoders.push_back(encoder_candidate.encoder);

                            break;
                        }
                    }
                }
            }
        } else {
            available_encoders.push_back(KasmVideoEncoders::Encoder::unavailable);
        }

        available_encoders.push_back(KasmVideoEncoders::Encoder::h264_software);
        available_encoders.shrink_to_fit();
        best_encoder = available_encoders.front();
    }

    /*bool EncoderProbe::is_acceleration_available() {
        if (access(render_path, R_OK | W_OK) != 0)
            return false;

        const int fd = open(render_path, O_RDWR);
        if (fd < 0)
            return false;

        close(fd);

        return true;
    }*/
} // namespace rfb::video_encoders
