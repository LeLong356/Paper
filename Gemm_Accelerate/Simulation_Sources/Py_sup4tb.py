import numpy as np

N = 32 

matrix_A = np.random.randint(-128, 128, size=(N, N), dtype=np.int8)
matrix_B = np.random.randint(-128, 128, size=(N, N), dtype=np.int8)

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


write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Source_code\matrix_A.hex", matrix_A, 8)
write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Source_code\matrix_B.hex", matrix_B, 8)
write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Source_code\matrix_C.hex", matrix_C,32)



small_a = np.random.randint(-128,128, size=(N), dtype=np.int8)
small_b = np.random.randint(-128,128, size=(N), dtype=np.int8)
small_prevc = np.random.randint(-128,128, size=(N,N), dtype=np.int32)

small_c = np.outer(small_a.astype(np.int32), small_b.astype(np.int32)) + small_prevc ;

write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Source_code\small_a.hex", [small_a], 8)
write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Source_code\small_b.hex", [small_b], 8)
write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Source_code\small_c.hex", small_c,32)
write_file_hex(r"E:\BKU\SoC_Design\Edge_AI\Source_code\small_prevc.hex", small_prevc,32)


