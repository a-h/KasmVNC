#include "ScreenEncoderManager.h"
#include <cassert>
#include "VideoEncoder.h"
#include "VideoEncoderFactory.h"
#include "rfb/benchmark/benchmark.h"
#include "rfb/encodings.h"

namespace rfb {
    template<int T>
    ScreenEncoderManager<T>::ScreenEncoderManager(const FFmpeg &ffmpeg_, KasmVideoEncoders::Encoder encoder,
                                               const std::vector<KasmVideoEncoders::Encoder> &encoders, SConnection *conn,
                                               VideoEncoderParams params) :
        Encoder(conn, encodingKasmVideo, static_cast<EncoderFlags>(EncoderUseNativePF | EncoderLossy), -1), ffmpeg(ffmpeg_),
        current_params(params), base_video_encoder(encoder), available_encoders(encoders) {}

    template<int T>
    ScreenEncoderManager<T>::~ScreenEncoderManager() {
        for (uint8_t i = 0; i < get_screen_count(); ++i)
            remove_screen(i);
    };

    template<int T>
    Encoder *ScreenEncoderManager<T>::add_encoder(const Screen &layout) const {
        Encoder *encoder{};
        try {
            encoder = create_encoder(layout, &ffmpeg, conn, base_video_encoder, current_params);
        } catch (const std::exception &e) {
            if (base_video_encoder != KasmVideoEncoders::Encoder::h264_software) {
                vlog.error("Attempting fallback to software encoder due to error: %s", e.what());
                try {
                    encoder = create_encoder(layout, &ffmpeg, conn, KasmVideoEncoders::Encoder::h264_software, current_params);
                } catch (const std::exception &exception) {
                    vlog.error("Failed to create software encoder: %s", exception.what());
                }
            } else
                vlog.error("Failed to create software encoder: %s", e.what());
        }

        return encoder;
    }

    template<int T>
    void ScreenEncoderManager<T>::add_screen(uint8_t index, const Screen &layout) {
        printf("SCREEN ADDED: %d (%d, %d, %d, %d)\n", index, layout.dimensions.tl.x, layout.dimensions.tl.y, layout.dimensions.br.x, layout.dimensions.br.y);
        auto *encoder = add_encoder(layout);
        assert(encoder);
        screens[index] = {layout, encoder};
        head = std::min(head, index);
        tail = std::max(tail, index);
    }

    template<int T>
    size_t ScreenEncoderManager<T>::get_screen_count() const {
        return std::max(0, tail - head + 1);
    }

    template<int T>
    void ScreenEncoderManager<T>::remove_screen(uint8_t index) {
        if (screens[index].encoder) {
            delete screens[index].encoder;
            screens[index].encoder = nullptr;
        }
        screens[index].layout = {};
    }

    template<int T>
    void ScreenEncoderManager<T>::sync_layout(const ScreenSet &layout) {
        for (uint8_t i = 0; i < layout.num_screens(); ++i) {
            const auto &screen = layout.screens[i];
            auto id = screen.id;
            if (id > ScreenSet::MAX_SCREENS) {
                assert("Wrong  id");
                id = 0;
            }

            if (!screens[id].layout.dimensions.equals(screen.dimensions)) {
                remove_screen(id);
                add_screen(id, screen);
            }
        }
    }

    template<int T>
    bool ScreenEncoderManager<T>::isSupported() const {
        if (const auto *encoder = screens[head].encoder; encoder)
            return encoder->isSupported();

        return false;
    }

    template<int T>
    void ScreenEncoderManager<T>::writeRect(const PixelBuffer *pb, const Palette &palette) {
        if (auto *encoder = screens[head].encoder; encoder)
            return encoder->writeRect(pb, palette);
    }

    template<int T>
    void ScreenEncoderManager<T>::writeSolidRect(int width, int height, const PixelFormat &pf, const rdr::U8 *colour) {
        if (auto *encoder = screens[head].encoder; encoder)
            encoder->writeSolidRect(width, height, pf, colour);
    }

} // namespace rfb
