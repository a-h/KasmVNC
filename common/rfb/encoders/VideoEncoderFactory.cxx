#include "VideoEncoderFactory.h"

#include "H264SoftwareEncoder.h"
#include "H264VAAPIEncoder.h"

namespace rfb {
    class EncoderBuilder {
    public:
        virtual Encoder *build() = 0;
        virtual ~EncoderBuilder() = default;
    };

    template<typename T>
    class H264EncoderBuilder : public EncoderBuilder {
        FFmpeg &ffmpeg;
        int frame_rate{};
        int bit_rate{};
        SConnection *conn{};
        explicit H264EncoderBuilder(FFmpeg &ffmpeg_) : ffmpeg(ffmpeg_) {}

    public:
        H264EncoderBuilder() = delete;

        static H264EncoderBuilder create(FFmpeg &ffmpeg) {
            return H264EncoderBuilder{ffmpeg};
        }

        H264EncoderBuilder &with_frame_rate(int value) {
            frame_rate = value;

            return *this;
        }

        H264EncoderBuilder &with_bit_rate(int value) {
            bit_rate = value;

            return *this;
        }

        H264EncoderBuilder &with_connection(SConnection *value) {
            conn = value;

            return *this;
        }

        Encoder *build() override {
            if (!conn)
                throw std::runtime_error("Connection is required");

            return new T(ffmpeg, conn, frame_rate, bit_rate);
        }
    };

    using H264VAAPIEncoderBuilder = H264EncoderBuilder<H264VAAPIEncoder>;
    using H264SoftwareEncoderBuilder = H264EncoderBuilder<H264SoftwareEncoder>;

    Encoder *create_encoder(KasmVideoEncoders::Encoder video_encoder, SConnection *conn, uint8_t frame_rate, uint16_t bit_rate) {
        switch (video_encoder) {
            case KasmVideoEncoders::Encoder::h264_vaapi:
                return H264VAAPIEncoderBuilder::create(FFmpeg::get())
                        .with_connection(conn)
                        .with_frame_rate(frame_rate)
                        .with_bit_rate(bit_rate)
                        .build();
            default:
                return H264SoftwareEncoderBuilder::create(FFmpeg::get())
                        .with_connection(conn)
                        .with_frame_rate(frame_rate)
                        .with_bit_rate(bit_rate)
                        .build();
        }
    }
} // namespace rfb
