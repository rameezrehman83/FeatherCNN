#include <common.h>

// N = 4, 8, or 16, which is the channel group size. 
__kernel void convolution(__global const DATA_TYPE* restrict input,   /* [ih, iw, ic] */
                          __global const DATA_TYPE* restrict weights, /* [oc/N, kh, kw, [ic, N, 1]] */
#ifdef BIAS
                          __global const DATA_TYPE* restrict bias,    /* [oc] */
#endif
                          __global DATA_TYPE* restrict output,        /* [oh, ow, oc] */
                          __private const int input_channels,         /* a multiple of 4 */
                          __private const int output_channels,        /* a multiple of 4 */
                          __private const int input_height,
                          __private const int input_width,
                          __private const int output_height,
                          __private const int output_width,
                          __private const int kernel_height,
                          __private const int kernel_width,
                          __private const int stride_height,
                          __private const int stride_width,
                          __private const int padding_top,
                          __private const int padding_left) {
  const int out_height_idx = get_global_id(0);
  const int out_width_idx = get_global_id(1);
  if (out_height_idx >= output_height || out_width_idx >= output_width) return;
  const int out_channel_idx = get_global_id(2) * N;

  const int in_height_beg = mad24(out_height_idx, stride_height, -padding_top);
  const int in_height_end = in_height_beg + kernel_height;
  const int in_width_beg = mad24(out_width_idx, stride_width, -padding_left);
  const int in_width_end = in_width_beg + kernel_width;
  const int kernel_width_size = input_channels * N;
  const int kernel_height_size = mul24(kernel_width, kernel_width_size);
  int kernel_val_idx = mul24(out_channel_idx, mul24(mul24(kernel_height, kernel_width), input_channels));

  DATA_TYPEN in_val, kernel_val;
#ifdef BIAS
  DATA_TYPEN out_val = VLOADN(0, &bias[out_channel_idx]);
#else
  DATA_TYPEN out_val = 0;
#endif
  for (int in_height_idx = in_height_beg; in_height_idx != in_height_end; ++in_height_idx) {
    if (in_height_idx < 0 || in_height_idx >= input_height) {
      kernel_val_idx += kernel_height_size;
      continue;
    }

    const int in_val_base_width_idx = mul24(mul24(in_height_idx, input_width), input_channels);
    for (int in_width_idx = in_width_beg; in_width_idx != in_width_end; ++in_width_idx) {
      if (in_width_idx < 0 || in_width_idx >= input_width) {
        kernel_val_idx += kernel_width_size;
        continue;
      }

      const int in_val_beg = mad24(in_width_idx, input_channels, in_val_base_width_idx);
      const int in_val_end = in_val_beg + input_channels;
      for (int in_val_idx = in_val_beg; in_val_idx < in_val_end; in_val_idx += N) {
        in_val = VLOADN(0, &input[in_val_idx]);

#define LOAD_KERNEL_AND_CALC(i)                           \
        kernel_val = VLOADN(0, &weights[kernel_val_idx]); \
        out_val = mad(in_val.s##i, kernel_val, out_val);  \
        kernel_val_idx += N;

        LOAD_KERNEL_AND_CALC(0);
        LOAD_KERNEL_AND_CALC(1);
        LOAD_KERNEL_AND_CALC(2);
        LOAD_KERNEL_AND_CALC(3);
#if N == 8 || N == 16
        LOAD_KERNEL_AND_CALC(4);
        LOAD_KERNEL_AND_CALC(5);
        LOAD_KERNEL_AND_CALC(6);
        LOAD_KERNEL_AND_CALC(7);
#if N == 16
        LOAD_KERNEL_AND_CALC(8);
        LOAD_KERNEL_AND_CALC(9);
        LOAD_KERNEL_AND_CALC(a);
        LOAD_KERNEL_AND_CALC(b);
        LOAD_KERNEL_AND_CALC(c);
        LOAD_KERNEL_AND_CALC(d);
        LOAD_KERNEL_AND_CALC(e);
        LOAD_KERNEL_AND_CALC(f);
#endif
#endif

#undef LOAD_KERNEL_AND_CALC
      }
    }
  }

#if defined(USE_RELU)
  out_val = fmax(out_val, (DATA_TYPE)0);
#endif

  int out_val_idx = mad24(mad24(out_height_idx, output_width, out_width_idx), output_channels, out_channel_idx);
  VSTOREN(out_val, 0, &output[out_val_idx]);
}
