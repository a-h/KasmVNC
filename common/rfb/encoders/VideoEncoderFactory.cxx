#include "VideoEncoderFactory.h"

#include "H264VAAPIEncoder.h"
#include "H264SoftwareEncoder.h"

namespace rfb {
    class EncoderBuilder {
    public:
        virtual Encoder *build() = 0;
        virtual ~EncoderBuilder() = default;
    };

    class H264VAAPIEncoderBuilder final : public EncoderBuilder {
        int frame_rate{};
        int bit_rate{};
        SConnection *conn{};
        H264VAAPIEncoderBuilder() = default;

    public:
        static H264VAAPIEncoderBuilder create() {
            return {};
        }

        H264VAAPIEncoderBuilder &with_frame_rate(int value) {
            frame_rate = value;

            return *this;
        }

        H264VAAPIEncoderBuilder &with_bit_rate(int value) {
            bit_rate = value;

            return *this;
        }

        H264VAAPIEncoderBuilder &with_connection(SConnection *value) {
            conn = value;

            return *this;
        }

        Encoder *build() override {
            if (!conn)
                throw std::runtime_error("Connection is required");

            return new H264VAAPIEncoder(conn, frame_rate, bit_rate);
        }
    };

    Encoder *create_encoder(KasmVideoEncoders::Encoder video_encoder, SConnection *conn, uint8_t frame_rate,
                                    uint16_t bit_rate) {
        switch (video_encoder) {
            case KasmVideoEncoders::Encoder::h264_vaapi:
                return H264VAAPIEncoderBuilder::create()
                        .with_connection(conn)
                        .with_frame_rate(frame_rate)
                        .with_bit_rate(bit_rate)
                        .build();
            default:
                return new H264SoftwareEncoder(conn, frame_rate, bit_rate);
        }
    }
} // namespace rfb
