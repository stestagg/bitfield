
#if defined(__MINGW32__)
#else

typedef unsigned int usize_t;

int __builtin_popcountl(usize_t v) {
	v = v - ((v >> 1) & (usize_t)~(usize_t)0/3);                           // temp
	v = (v & (usize_t)~(usize_t)0/15*3) + ((v >> 2) & (usize_t)~(usize_t)0/15*3);      // temp
	v = (v + (v >> 4)) & (usize_t)~(usize_t)0/255*15;                      // temp
	return (usize_t)(v * ((usize_t)~(usize_t)0/255)) >> (sizeof(usize_t) - 1) * CHAR_BIT; // count
}

#endif