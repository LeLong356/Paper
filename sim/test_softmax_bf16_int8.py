import math
import unittest

from softmax_bf16_int8 import decode_bf16, encode_bf16, quantize_int8, softmax_bf16_int8, vexp_bf16
from softmax_golden import softmax


class Bf16Int8Tests(unittest.TestCase):
    def test_bf16_roundtrip_all_patterns(self):
        for bits in range(65536):
            expected = 0x7FC0 if bits & 0x7F80 == 0x7F80 and bits & 127 else bits
            self.assertEqual(encode_bf16(decode_bf16(bits)), expected)

    def test_bf16_ties_and_specials(self):
        self.assertEqual(encode_bf16(1 + 1/256), 0x3F80)
        self.assertEqual(encode_bf16(1 + 3/256), 0x3F82)
        self.assertEqual(encode_bf16(2**-134), 0)
        self.assertEqual(encode_bf16(3 * 2**-134), 2)
        self.assertEqual(encode_bf16(2**128), 0x7F80)
        self.assertEqual(encode_bf16(-0.0), 0x8000)

    def test_vexp_known_cases(self):
        for bits, expected in ((0,0x3F80),(0x8000,0x3F80),(1,0x3F80),(0x807F,0x3F80),
                               (0xBF80,0x3EBD),(0x7F80,0x7F80),(0xFF80,0),(0x7FC1,0x7FC0)):
            self.assertEqual(vexp_bf16(bits), expected)

    def test_quantization(self):
        self.assertEqual(quantize_int8(0), 0)
        self.assertEqual(quantize_int8(1), 127)
        self.assertEqual(quantize_int8(0.5), 64)
        self.assertEqual(quantize_int8(1/2048), 0)
        self.assertEqual(quantize_int8(-0.1), 0)
        self.assertEqual(quantize_int8(1.1), 127)

    def test_known_row(self):
        result = softmax_bf16_int8([2,1,0])
        self.assertEqual(result["input_bf16"], [0,0xBF80,0xC000])
        self.assertEqual(result["output_int8"], [84,31,11])
        for actual, expected in zip(result["decoded_output"], softmax([2,1,0])):
            self.assertLess(abs(actual-expected), 0.005)

    def test_offset_scale_and_int33(self):
        expected = softmax_bf16_int8([2,1,0])["output_int8"]
        self.assertEqual(softmax_bf16_int8([2147483647,2147483646,2147483645])["output_int8"], expected)
        self.assertEqual(softmax_bf16_int8([256,128,0],scale=1/128)["output_int8"], expected)
        result = softmax_bf16_int8([2147483647,-2147483648])
        self.assertEqual(result["differences_int33"], [0,-4294967295])
        self.assertEqual(result["output_int8"], [127,0])

    def test_equal_rows_and_singleton(self):
        self.assertEqual(softmax_bf16_int8([-9])["output_int8"], [127])
        self.assertEqual(softmax_bf16_int8([0,0,0])["output_int8"], [42]*3)
        result = softmax_bf16_int8([0]*32)
        self.assertEqual(result["probabilities_fp32"], [1/32]*32)
        self.assertEqual(result["output_int8"], [4]*32)

    def test_validation(self):
        for row in ([],[0]*33,[1.5],[math.nan],[2147483648],[-2147483649]):
            with self.assertRaises(ValueError):
                softmax_bf16_int8(row)
        for scale in (0,-1,math.inf,math.nan):
            with self.assertRaises(ValueError):
                softmax_bf16_int8([1], scale=scale)


if __name__ == "__main__":
    unittest.main()
