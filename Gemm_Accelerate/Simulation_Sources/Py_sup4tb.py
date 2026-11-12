import numpy as np

TILE = 32 
N = 64
K = 768
M = 256

matrix_A = np.random.randint(-128, 128, size=(TILE, TILE), dtype=np.int8)
matrix_B = np.random.randint(-128, 128, size=(TILE, TILE), dtype=np.int8)
matrix_C = matrix_A.astype(np.int32) @ matrix_B.astype(np.int32) 

def write_file_hex (filename, matrix, bit_width):
    with open(filename, 'w') as f:
        for row in matrix: 
            for val in row:
                # mask the value to handle negative number
                mask = (1 << bit_width) -1 
                hex_val = format(int(val) & mask, f'0{bit_width//4}x')
                f.write(f"{hex_val}\n")
    print(f"Save {filename}")


write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Paper\Gemm_Accelerate\Simulation_Sources\Gemm_test_hexfile\matrix_A.hex", matrix_A, 8)
write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Paper\Gemm_Accelerate\Simulation_Sources\Gemm_test_hexfile\matrix_B.hex", matrix_B, 8)
write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Paper\Gemm_Accelerate\Simulation_Sources\Gemm_test_hexfile\matrix_C.hex", matrix_C,32)



small_a = np.random.randint(-128,128, size=(TILE), dtype=np.int8)
small_b = np.random.randint(-128,128, size=(TILE), dtype=np.int8)
small_c = np.outer(small_a.astype(np.int32), small_b.astype(np.int32)) ;

write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Paper\Gemm_Accelerate\Simulation_Sources\Gemm_test_hexfile\small_a.hex", [small_a], 8)
write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Paper\Gemm_Accelerate\Simulation_Sources\Gemm_test_hexfile\small_b.hex", [small_b], 8)
write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Paper\Gemm_Accelerate\Simulation_Sources\Gemm_test_hexfile\small_c.hex", small_c,32)

bram_a = np.random.randint(-128,128, size=(N, K), dtype=np.int8)
bram_b = np.random.randint(-128,128, size=(K, M), dtype=np.int8)
bram_c = bram_a.astype(np.int32) @ bram_b.astype(np.int32) 

write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Paper\Gemm_Accelerate\Simulation_Sources\top_test_hexfile\bram_a.hex", bram_a, 8)
write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Paper\Gemm_Accelerate\Simulation_Sources\top_test_hexfile\bram_b.hex", bram_b, 8)
write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Paper\Gemm_Accelerate\Simulation_Sources\top_test_hexfile\bram_c.hex", bram_c, 32)

small_bram_a = np.random.randint(-128,128, size=(32, 64), dtype=np.int8)
small_bram_b = np.random.randint(-128,128, size=(64, 48), dtype=np.int8)
small_bram_c = small_bram_a.astype(np.int32) @ small_bram_b.astype(np.int32) 

write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Paper\Gemm_Accelerate\Simulation_Sources\top_test_hexfile\small_bram_a.hex", small_bram_a, 8)
write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Paper\Gemm_Accelerate\Simulation_Sources\top_test_hexfile\small_bram_b.hex", small_bram_b, 8)
write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Paper\Gemm_Accelerate\Simulation_Sources\top_test_hexfile\small_bram_c.hex", small_bram_c, 32)