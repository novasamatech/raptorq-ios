//! iOS FFI bindings for **RaptorQ** decoding from QR‑code frame payloads.
//!
//! Inspired by the FFI style used in `sr25519.c` this file exposes a minimal C
//! interface that can be called directly from Swift/Objective‑C.  The library
//! keeps decoding state in an opaque `RQContext` pointer, so you can feed every
//! scanned QR frame one after another until the original object is fully
//! recovered.
//!
//! ## Usage from Swift
//! ```swift
//! // 1. Create context once you know the object (transfer) length.
//! let ctx = raptorq_ctx_new(totalBytes, maxPayloadPerQR)
//! // 2. Feed every scanned QR frame.
//! if raptorq_ctx_push_frame(ctx, dataPtr, dataLen) {
//!     if raptorq_ctx_is_complete(ctx) {
//!         var outLen: UInt = 0
//!         if let buf = raptorq_ctx_take_result(ctx, &outLen) {
//!             let recovered = Data(bytesNoCopy: buf, count: Int(outLen), deallocator: .free)
//!             // …use `recovered`…
//!         }
//!     }
//! }
//! // 3. When done.
//! raptorq_ctx_free(ctx)
//! ```
//!
//! > **Safety**  All functions catch panics so no Rust unwind can cross the FFI
//! > boundary; on error they return a sentinel value (usually `NULL`/`false`).
//! > The caller is responsible for eventually freeing any heap memory returned
//! > by this library using [`raptorq_free`].

use std::panic::{catch_unwind, AssertUnwindSafe};

use core::{ptr, slice};
use raptorq::{Decoder, EncodingPacket, ObjectTransmissionInformation};

#[repr(C)]
pub struct RQContext {
    oti: ObjectTransmissionInformation,
    decoder: Decoder,
    result: Option<Vec<u8>>, // populated when decoding finished
}

//—‑ helpers ————————————————————————————————————————————————————————————————

#[inline]
fn try_catch_unwind<F: FnOnce() -> R, R>(f: F) -> Option<R> {
    catch_unwind(AssertUnwindSafe(f)).ok()
}

#[inline]
unsafe fn slice_from_raw<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
    if ptr.is_null() || len == 0 {
        &[]
    } else {
        slice::from_raw_parts(ptr, len)
    }
}

//—‑ public C/Swift API ————————————————————————————————————————————————————

/// Build a [`RQContext`] from the raw **12‑byte** OTI header that the encoder
/// usually embeds in its first QR frame.
#[no_mangle]
pub unsafe extern "C" fn raptorq_ctx_from_oti(oti_ptr: *const u8) -> *mut RQContext {
    let oti_bytes = slice_from_raw(oti_ptr, 12);
    if oti_bytes.len() != 12 {
        return ptr::null_mut();
    }
    let mut buf = [0u8; 12];
    buf.copy_from_slice(oti_bytes);
    try_catch_unwind(|| {
        let oti = ObjectTransmissionInformation::deserialize(&buf);
        let decoder = Decoder::new(oti);
        Box::into_raw(Box::new(RQContext { oti, decoder, result: None }))
    })
    .unwrap_or(ptr::null_mut())
}

/// Convenience constructor when you **already know** the transfer length and
/// the maximum payload size of your QR frames.
#[no_mangle]
pub extern "C" fn raptorq_ctx_new(transfer_length: u64, max_payload_size: u16) -> *mut RQContext {
    try_catch_unwind(|| {
        let oti = ObjectTransmissionInformation::with_defaults(transfer_length, max_payload_size);
        let decoder = Decoder::new(oti);
        Box::into_raw(Box::new(RQContext { oti, decoder, result: None }))
    })
    .unwrap_or(ptr::null_mut())
}

/// Push one QR‑frame payload into the decoder.
///
/// Returns `true` **iff** this call finished decoding the whole object.
#[no_mangle]
pub unsafe extern "C" fn raptorq_ctx_push_frame(
    ctx: *mut RQContext,
    payload_ptr: *const u8,
    payload_len: usize,
) -> bool {
    if ctx.is_null() {
        return false;
    }
    let ctx = &mut *ctx;
    let payload = slice_from_raw(payload_ptr, payload_len);
    try_catch_unwind(|| {
        let packet = EncodingPacket::deserialize(payload);
        if let Some(data) = ctx.decoder.decode(packet) {
            ctx.result = Some(data);
            true
        } else {
            false
        }
    })
    .unwrap_or(false)
}

/// Check whether the decoder has recovered enough packets to rebuild the
/// original object.
#[no_mangle]
pub extern "C" fn raptorq_ctx_is_complete(ctx: *const RQContext) -> bool {
    if ctx.is_null() {
        return false;
    }
    unsafe { (*ctx).result.is_some() }
}

/// Move the reconstructed buffer **out** of the context.  Caller assumes
/// ownership and must free it with [`raptorq_free`].  If `len_out` is not
/// `NULL` the function writes the buffer length to it.
#[no_mangle]
pub unsafe extern "C" fn raptorq_ctx_take_result(
    ctx: *mut RQContext,
    len_out: *mut usize,
) -> *mut u8 {
    if ctx.is_null() {
        return ptr::null_mut();
    }
    let ctx = &mut *ctx;
    let data = match ctx.result.take() {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    if !len_out.is_null() {
        *len_out = data.len();
    }
    let boxed = data.into_boxed_slice();
    Box::into_raw(boxed) as *mut u8
}

/// Free a buffer returned by [`raptorq_ctx_take_result`].
#[no_mangle]
pub unsafe extern "C" fn raptorq_free(ptr_: *mut u8, len: usize) {
    if ptr_.is_null() {
        return;
    }
    drop(Box::from_raw(slice::from_raw_parts_mut(ptr_, len)));
}

/// Destroy the decoding context and release all resources.
#[no_mangle]
pub extern "C" fn raptorq_ctx_free(ctx: *mut RQContext) {
    if ctx.is_null() {
        return;
    }
    unsafe { drop(Box::from_raw(ctx)) };
}

//—‑ tests (run with `cargo test --features std`) ————————————————————————

#[cfg(test)]
mod tests {
    use super::*;
    use raptorq::EncoderBuilder;

    #[test]
    fn roundtrip() {
        let data = b"helloMyFountain";
        let enc = EncoderBuilder::new().build(data);
        let ctx = unsafe { raptorq_ctx_from_oti(enc.get_config().serialize().as_ptr()) };
        assert!(!ctx.is_null());
        // feed just enough packets to recover
        for p in enc.get_encoded_packets(0) {
            let s = p.serialize();
            if unsafe { raptorq_ctx_push_frame(ctx, s.as_ptr(), s.len()) } {
                break;
            }
        }
        assert!(raptorq_ctx_is_complete(ctx));
        let mut out_len = 0usize;
        let out_ptr = unsafe { raptorq_ctx_take_result(ctx, &mut out_len) };
        assert_eq!(out_len, data.len());
        let recovered = unsafe { slice::from_raw_parts(out_ptr, out_len) };
        assert_eq!(recovered, data);
        unsafe { raptorq_free(out_ptr, out_len) };
        raptorq_ctx_free(ctx);
    }
}
