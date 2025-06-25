#include <cstdarg>
#include <cstdint>
#include <cstdlib>
#include <new>

template<typename T>
struct Option;

template<typename T>
struct Vec;

struct RQContext {
  ObjectTransmissionInformation oti;
  Decoder decoder;
  Option<Vec<uint8_t>> result;
};

extern "C" {

/// Destroy the decoding context and release all resources.
void raptorq_ctx_free(RQContext *ctx);

/// Build a [`RQContext`] from the raw **12‑byte** OTI header that the encoder
/// usually embeds in its first QR frame.
RQContext *raptorq_ctx_from_oti(const uint8_t *oti_ptr);

/// Check whether the decoder has recovered enough packets to rebuild the
/// original object.
bool raptorq_ctx_is_complete(const RQContext *ctx);

/// Convenience constructor when you **already know** the transfer length and
/// the maximum payload size of your QR frames.
RQContext *raptorq_ctx_new(uint64_t transfer_length, uint16_t max_payload_size);

/// Push one QR‑frame payload into the decoder.
///
/// Returns `true` **iff** this call finished decoding the whole object.
bool raptorq_ctx_push_frame(RQContext *ctx, const uint8_t *payload_ptr, uintptr_t payload_len);

/// Move the reconstructed buffer **out** of the context.  Caller assumes
/// ownership and must free it with [`raptorq_free`].  If `len_out` is not
/// `NULL` the function writes the buffer length to it.
uint8_t *raptorq_ctx_take_result(RQContext *ctx, uintptr_t *len_out);

/// Free a buffer returned by [`raptorq_ctx_take_result`].
void raptorq_free(uint8_t *ptr_, uintptr_t len);

} // extern "C"
