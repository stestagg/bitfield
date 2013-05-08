
typedef size_t usize_t;
typedef usize_t CHUNK;

#define CHUNK_BYTES sizeof(usize_t)  // Say: CHUNK_BYTES = 2  <>  CHUNK_BYTES = 8
#define CHUNK_FULL_COUNT 8 * CHUNK_BYTES // Count of 1s in a full chunk = 32 (assuming 32-bit size_t)
	//Then: CHUNK_FULL_COUNT = 11111111 11111111 = 16  <> CHUNK_FULL_COUNT = ... = 64

// 15 can be stored in 4 bytes  <> 63 can be stored in 6 bytes
#define CHUNK_SHIFT (CHUNK_BYTES==1?3:(CHUNK_BYTES==2?4:(CHUNK_BYTES==4?5:(CHUNK_BYTES==8?6:(CHUNK_BYTES==16?7:0)))))

#define CHUNK_MASK (1 << CHUNK_SHIFT) - 1 // When looking up a chunk, only examine the first 5 bits
#define USIZE_MAX (((((usize_t)1) << (CHUNK_BYTES * 8 - 1)) - 1)\
                               + (((usize_t)1) << (CHUNK_BYTES * 8 - 1))) // This is a full usize (lots of 11111111)
#define CHUNK_BITS USIZE_MAX

#define PAGE_CHUNKS 16
#define PAGE_FULL_COUNT (CHUNK_FULL_COUNT * PAGE_CHUNKS)
#define PAGE_BYTES (CHUNK_BYTES * PAGE_CHUNKS)

#define EMPTY_CHUNK_BITS 0;
#define FULL_CHUNK_BITS CHUNK_BITS;