#pragma once
#include <vector>
#include "KasmVideoConstants.h"
#include "VideoEncoder.h"
#include "rfb/Encoder.h"
#include "rfb/ffmpeg.h"

namespace rfb {
    template<int T = ScreenSet::MAX_SCREENS>
    class ScreenEncoderManager final : public Encoder {
        struct screen_t {
            Screen layout{};
            Encoder *encoder{};
        };

        uint8_t head{};
        uint8_t tail{};

        std::array<screen_t, T> screens{};
        const FFmpeg &ffmpeg;
        VideoEncoderParams current_params;

        KasmVideoEncoders::Encoder base_video_encoder;
        std::vector<KasmVideoEncoders::Encoder> available_encoders;
        const char *dri_node{};

        Encoder *add_encoder(const Screen &layout) const;
        void add_screen(uint8_t index, const Screen &layout);
        [[nodiscard]] size_t get_screen_count() const;
        void remove_screen(uint8_t index);

    public:
        // Iterator
        using iterator = typename std::array<screen_t, T>::iterator;
        using const_iterator = typename std::array<screen_t, T>::const_iterator;

        iterator begin() {
            return screens.begin();
        }
        iterator end() {
            return screens.end();
        }

        [[nodiscard]] const_iterator cbegin() const {
            return screens.begin();
        }
        [[nodiscard]] const_iterator cend() const {
            return screens.end();
        }

        explicit ScreenEncoderManager(const FFmpeg &ffmpeg_, KasmVideoEncoders::Encoder encoder,
            const std::vector<KasmVideoEncoders::Encoder> &encoders, SConnection *conn, const char *dri_node, VideoEncoderParams params);
        ~ScreenEncoderManager() override;

        ScreenEncoderManager(const ScreenEncoderManager &) = delete;
        ScreenEncoderManager &operator=(const ScreenEncoderManager &) = delete;
        ScreenEncoderManager(ScreenEncoderManager &&) = delete;
        ScreenEncoderManager &operator=(ScreenEncoderManager &&) = delete;

        void sync_layout(const ScreenSet &layout);

        KasmVideoEncoders::Encoder get_encoder() const { return base_video_encoder; }

        // Encoder
        bool isSupported() const override;

        void writeRect(const PixelBuffer *pb, const Palette &palette) override;
        void writeSolidRect(int width, int height, const PixelFormat &pf, const rdr::U8 *colour) override;
    };

    template class ScreenEncoderManager<>;
} // namespace rfb
