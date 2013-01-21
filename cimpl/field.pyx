# cython: profile=True
# Imports and boilerplate
import cython
import zlib

ctypedef Py_ssize_t size_t

cdef extern:
    int __builtin_popcountl(size_t)
    int __builtin_popcount(size_t)


cdef extern from "string.h":
    void * memset(void *, int, size_t)
    void * memcpy(void*, void*, size_t)
    int memcmp(void*, void*, size_t)


cdef extern from "unistd.h":
    int getpagesize()


cdef extern from "stdlib.h":
    void *malloc(size_t)
    void *calloc(size_t, size_t)
    void *realloc(void *, size_t)
    void free(void*)


cdef extern from "Python.h":
        object PyString_FromStringAndSize(char *v, int len)
        int PyString_AsStringAndSize(object ob, char **buffer,
                                     Py_ssize_t *length) except -1
        char *PyString_AsString(object string)


### This is such a major missing feature of cython
cdef object safe_char_to_str(char *buffer, size_t length):
    return PyString_FromStringAndSize(buffer, length)

cdef void safe_str_to_char(object string, char **buffer, size_t *length):
    length[0] = len(string)
    buffer[0] = <char *>malloc(length[0] + 1)
    memcpy(buffer[0] , <char*>string, length[0])


#start implementation specific stuff

ctypedef unsigned long usize_t
ctypedef usize_t CHUNK # (Chunk must always be <= usize_t)

cdef usize_t log2(usize_t num):
    cdef usize_t index = 0
    while num:
        num >>= 1
        index += 1
    return index - 1

cpdef usize_t CHUNK_BYTES = cython.sizeof(CHUNK)
cdef usize_t CHUNK_FULL_COUNT = 8 * CHUNK_BYTES # Count of 1s in a full chunk = 32 (assuming 32-bit size_t)
cdef usize_t CHUNK_SHIFT = log2(CHUNK_FULL_COUNT) # Ammount to shift a number to look up which chunk to use
cdef usize_t CHUNK_MASK = (1 << CHUNK_SHIFT) - 1 # When looking up a chunk, only examine the first 5 bits
cpdef usize_t USIZE_MAX = ((((<usize_t>1) << (CHUNK_BYTES * 8 - 1)) - 1)
                            + ((<usize_t>1) << (CHUNK_BYTES * 8 - 1))) # This is a full usize (lots of 11111111)
cdef usize_t CHUNK_BITS = USIZE_MAX

cdef usize_t PAGE_CHUNKS = (getpagesize() / CHUNK_BYTES) # Default one page to several system pages to reduce alloc
cdef usize_t PAGE_FULL_COUNT = CHUNK_FULL_COUNT * PAGE_CHUNKS
cdef usize_t PAGE_BYTES = CHUNK_BYTES * PAGE_CHUNKS

DEF PAGE_EMPTY = 3
DEF PAGE_PARTIAL = 1
DEF PAGE_FULL = 2

cdef CHUNK EMPTY_CHUNK_BITS = 0
cdef CHUNK FULL_CHUNK_BITS = CHUNK_BITS

cdef CHUNK *EMPTY_PAGE_BITS
EMPTY_PAGE_BITS = <CHUNK *>calloc(PAGE_CHUNKS, CHUNK_BYTES)

cdef CHUNK *FULL_PAGE_BITS = <CHUNK *>malloc(PAGE_CHUNKS * CHUNK_BYTES)
memset(FULL_PAGE_BITS, 0xff, PAGE_CHUNKS * CHUNK_BYTES)


def get_all_sizes():
    return dict(
        CHUNK_BYTES=CHUNK_BYTES,
        CHUNK_SHIFT=CHUNK_SHIFT,
        CHUNK_MASK=bin(CHUNK_MASK),
        CHUNK_FULL_COUNT=CHUNK_FULL_COUNT,
        CHUNK_BITS=bin(CHUNK_BITS),
        BITFIELD_MAX=USIZE_MAX,
        PAGE_CHUNKS=PAGE_CHUNKS,
        PAGE_FULL_COUNT=PAGE_FULL_COUNT,
        PAGE_BYTES=PAGE_BYTES,
        PAGE_MAX=PAGE_FULL_COUNT
    )

def get_sizes():
    return CHUNK_BYTES, PAGE_CHUNKS


cdef class PageIter:
    cdef usize_t chunk
    cdef usize_t bit_index
    cdef usize_t number
    cdef IdsPage page

    def __cinit__(self, IdsPage page):
        self.page = page
        self.chunk = 0
        self.bit_index = 0
        self.number = 0

    cdef usize_t _advance(self):
        cdef usize_t number = self.number
        self.number += 1
        self.bit_index += 1
        if self.bit_index >= CHUNK_FULL_COUNT:
            self.bit_index = 0
            self.chunk += 1
        return number

    def __next__(self):
        if self.chunk >= PAGE_CHUNKS:
                raise StopIteration()
        if self.page.page_state == PAGE_EMPTY:
            raise StopIteration()
        elif self.page.page_state == PAGE_FULL:
            return self._advance()
        while 1:
            if self.chunk >= PAGE_CHUNKS:
                raise StopIteration()
            test = (self.page.data[self.chunk] & ((<usize_t>1) << self.bit_index))
            if test:
                return self._advance()
            self._advance()           


cdef class BitfieldIterator:
    """
    Performs correctly when bitfields are mutating during iteration.
    """

    cdef Bitfield bitfield
    cdef object current_iter
    cdef usize_t current_page
    cdef usize_t offset

    def __cinit__(self, Bitfield bitfield):
        self.bitfield = bitfield
        self.current_page = 0
        self.current_iter = None
        self.offset = 0

    cdef _next_iter(self):
        if self.current_page >= len(self.bitfield.pages):
            raise StopIteration()
        self.current_iter = iter(self.bitfield.pages[self.current_page])

    def __next__(self):
        if self.current_iter is None:
            self._next_iter()
        while True:
            try:
                return self.current_iter.next() + self.offset
            except StopIteration:
                self.current_page += 1
                self.offset += PAGE_FULL_COUNT
                self._next_iter()


cdef class IdsPage:
    cdef int page_state
    cdef usize_t _count
    cdef CHUNK* data

    def __cinit__(self):
        self.page_state = PAGE_EMPTY
        self._count = 0
        self.data = NULL

    def __dealloc__(self):
        self._dealloc(PAGE_EMPTY)

    cdef void _fill(self, CHUNK value):
        cdef usize_t current
        for current in range(PAGE_CHUNKS):
            self.data[current] = value

    cdef void set_full(self):
        self._dealloc(PAGE_FULL)

    cdef void set_empty(self):
        self._dealloc(PAGE_EMPTY)

    cdef void _alloc(self, int fill=0):
        assert(self.data == NULL)
        self.page_state = PAGE_PARTIAL
        self.data = <CHUNK *>malloc(sizeof(CHUNK) * PAGE_CHUNKS)
        if fill:
            self._count = PAGE_FULL_COUNT
            self._fill(CHUNK_BITS)
        else:
            self._count = 0
            self._fill(0)     

    cdef void _dealloc(self, int new_state):
        assert new_state != PAGE_PARTIAL
        self.page_state = new_state
        self._count = 0 if new_state == PAGE_EMPTY else PAGE_FULL_COUNT
        if self.data != NULL:
            free(self.data)
            self.data = NULL

    def __iter__(self):
        if self.page_state == PAGE_EMPTY:
            return iter(set())
        return PageIter(self)

    cdef void calc_length(self):
        cdef CHUNK *chunk
        cdef usize_t chunk_index
        cdef usize_t bits = 0
        if self.page_state != PAGE_PARTIAL:
            return
        else:    
            for chunk_index in range(PAGE_CHUNKS):
                bits += __builtin_popcountl(self.data[chunk_index])
            if bits == 0:
                self._dealloc(PAGE_EMPTY)
            elif bits == PAGE_FULL_COUNT:
                self._dealloc(PAGE_FULL)
            else:
                self._count = bits

    property count:
        def __get__(self):
            return self._count

    def __contains__(self, usize_t number):
        cdef usize_t chunk_index = number >> CHUNK_SHIFT
        cdef usize_t chunk_bit = (<usize_t>1) << (number & CHUNK_MASK)
        if (chunk_index >= PAGE_CHUNKS or chunk_index < 0):
            raise AssertionError("Cannot test for %i in a page (overflow)" % number)
        if self.page_state == PAGE_FULL:
            return True
        if self.page_state == PAGE_EMPTY:
            return False
        return self.data[chunk_index] & chunk_bit != 0


    cpdef add(self, usize_t number):
        cdef usize_t chunk_index = number >> CHUNK_SHIFT
        cdef usize_t chunk_bit = (<usize_t>1) << (number & CHUNK_MASK)

        if (chunk_index >= PAGE_CHUNKS or chunk_index < 0):
            raise AssertionError("Cannot add %i to a page (overflow)" % number)

        if self.page_state == PAGE_FULL:
            return
        if self.page_state == PAGE_EMPTY:
            self._alloc()

        if self.data[chunk_index] & chunk_bit:
            return

        self.data[chunk_index] |= chunk_bit
        self._count += 1
        if self._count == PAGE_FULL_COUNT:
            self._dealloc(PAGE_FULL)
        return number

    cpdef remove(self, usize_t number):
        cdef usize_t chunk_index = number >> CHUNK_SHIFT
        cdef usize_t chunk_bit = (<usize_t>1) << (number & CHUNK_MASK)

        if (chunk_index >= PAGE_CHUNKS or chunk_index < 0):
            raise AssertionError("Cannot remove %i from a page (overflow)" % number)

        if self.page_state == PAGE_EMPTY:
            return
        if self.page_state == PAGE_FULL:
            self._alloc(True)

        if not self.data[chunk_index] & chunk_bit:
            return

        self.data[chunk_index] &= ~chunk_bit
        self._count -= 1
        if self._count == 0:
            self._dealloc(PAGE_EMPTY)
        return number

    cpdef update(self, IdsPage other):
        if other.page_state == PAGE_EMPTY:
            return
        if self.page_state == PAGE_FULL:
            return
        if other.page_state == PAGE_FULL:
            self._dealloc(PAGE_FULL)
            return
        if self.page_state == PAGE_EMPTY:
            self._alloc()
        for chunk_index in range(PAGE_CHUNKS):
            self.data[chunk_index] |= other.data[chunk_index]
        self.calc_length()

    cpdef intersection_update(self, IdsPage other):
        if other.page_state == PAGE_EMPTY:
            self._dealloc(PAGE_EMPTY)
        elif other.page_state == PAGE_FULL:
            return
        elif other.page_state == PAGE_PARTIAL:
            if self.page_state == PAGE_EMPTY:
                return
            elif self.page_state == PAGE_FULL:
                self._dealloc(PAGE_EMPTY)
                memcpy(self.data, other.data, CHUNK_BYTES * PAGE_CHUNKS)
                self.calc_length()
                return
            elif self.page_state == PAGE_PARTIAL:
                for chunk_index in range(PAGE_CHUNKS):
                    self.data[chunk_index] &= other.data[chunk_index]
                self.calc_length()
            else:
                raise AssertionError("Invalid page state")
        else:
            raise AssertionError("Invalid page state")

    cpdef difference_update(self, IdsPage other):
        if other.page_state == PAGE_EMPTY:
            return
        if self.page_state == PAGE_FULL:
            self._alloc(True)
        if other.page_state == PAGE_FULL:
            self._dealloc(PAGE_EMPTY)
            return
        if self.page_state == PAGE_EMPTY:
            return
        for chunk_index in range(PAGE_CHUNKS):
            self.data[chunk_index] &= ~other.data[chunk_index]
        self.calc_length()

    cdef _state(self):
        if self.page_state == PAGE_EMPTY:
            return "EMPTY"
        if self.page_state == PAGE_FULL:
            return "FULL"
        if self.page_state == PAGE_PARTIAL:
            return "PARTIAL"
        return "ERROR"

    cpdef symmetric_difference_update(self, IdsPage other):
        cdef usize_t chunk_index
        if self.page_state == PAGE_EMPTY:
            if other.page_state == PAGE_EMPTY:
                return
            elif other.page_state == PAGE_FULL:
                self._dealloc(PAGE_FULL)
                return
            elif other.page_state == PAGE_PARTIAL:
                self._alloc(PAGE_EMPTY)
                memcpy(self.data, other.data, CHUNK_BYTES * PAGE_CHUNKS)
        elif self.page_state == PAGE_FULL:
            if other.page_state == PAGE_EMPTY:
                return
            elif other.page_state == PAGE_FULL:
                self._dealloc(PAGE_EMPTY)
                return
            elif other.page_state == PAGE_PARTIAL:
                self._alloc(PAGE_FULL)
                for chunk_index in range(PAGE_CHUNKS):
                    self.data[chunk_index] = ~other.data[chunk_index]
        elif self.page_state == PAGE_PARTIAL:
            if other.page_state == PAGE_EMPTY:
                return
            elif other.page_state == PAGE_FULL:
                for chunk_index in range(PAGE_CHUNKS):
                    self.data[chunk_index] = ~self.data[chunk_index]
            elif other.page_state == PAGE_PARTIAL:
                for chunk_index in range(PAGE_CHUNKS):
                    self.data[chunk_index] ^= other.data[chunk_index]                
        self.calc_length()

    cpdef IdsPage clone(self):
        new_page = IdsPage()
        new_page.page_state = self.page_state

        if self.page_state == PAGE_PARTIAL:
            new_page._alloc()
            memcpy(new_page.data, self.data, CHUNK_BYTES * PAGE_CHUNKS)
        new_page._count = self._count
        return new_page

    def __richcmp__(IdsPage a,IdsPage b, operator):
        cdef usize_t current
        if operator == 2:
            if a.count != b.count: # cheap
                return False
            if a.page_state != b.page_state:
                return False
            if a.page_state != PAGE_PARTIAL:
                return True
            for current in range(PAGE_CHUNKS):
                if a.data[current] != b.data[current]:
                    return False
            return True
        elif operator == 3:
            return not a == b
        raise NotImplementedError()

    cdef CHUNK *get_bits(self):
        if self.page_state == PAGE_EMPTY:
            return EMPTY_PAGE_BITS
        if self.page_state == PAGE_FULL:
            return FULL_PAGE_BITS
        return self.data

    cdef char *set_bits(self, char *start, char *end):
        cdef usize_t bytes_to_read = min(PAGE_BYTES, (end - start)+1)
        self._alloc()
        memcpy(self.data, start, bytes_to_read)
        self.calc_length()
        return start + bytes_to_read



# Markers must be the same length
cdef str PICKLE_MARKER = "BF:"
cdef str PICKLE_MARKER_zlib = "BZ:"

cdef class Bitfield:
    """Efficient storage, and set-like operations on groups of positive integers
    Currently, all integers must be in the range 0 >= x >= bitfield.get_all_sizes()["BITFIELD_MAX"].
    Note this does not take into consideration memory limits, which may become a factor in extreme cases.

    The bitfield is designed to handle sets of numbers incrementing from 0.  Adding arbitrary, large numbers
    to the set will not be efficient."""

    cdef list pages

    def __cinit__(self, _data=None):
        self.pages = list()
        if _data is not None:
            self.load(_data)

    cdef _ensure_page_exists(self, usize_t page):
        while page >= len(self.pages):
            new_page = IdsPage()
            self.pages.append(new_page)

    cdef _cleanup(self):
        while len(self.pages) > 0 and self.pages[-1].count == 0:
            self.pages.pop()

    cpdef add(self, usize_t number):
        """Add a positive integer to the bitfield"""
        cdef usize_t page = number / PAGE_FULL_COUNT
        cdef usize_t page_index = number % PAGE_FULL_COUNT
        self._ensure_page_exists(page)
        self.pages[page].add(page_index)

    cpdef remove(Bitfield self, usize_t number):
        """Remove a positive integer from the bitfield
        If the integer does not exist in the field, raise a KeyError"""
        cdef usize_t page = number / PAGE_FULL_COUNT
        cdef usize_t page_index = number % PAGE_FULL_COUNT
        if page >= len(self.pages):
            raise KeyError()
        if page_index not in self.pages[page]:
            raise KeyError()
        self.pages[page].remove(page_index)

    cpdef discard(Bitfield self, usize_t number):
        """Remove a positive integer from the bitfield if it is a member.
        If the element is not a member, do nothing."""
        cdef usize_t page = number / PAGE_FULL_COUNT
        cdef usize_t page_index = number % PAGE_FULL_COUNT
        if page >= len(self.pages):
            return
        self.pages[page].remove(page_index)

    property count:
        """The number of integers in the field"""
        def __get__(self):
            cdef usize_t num = 0
            for page in self.pages:
                num += page.count
            return num

    def __len__(self):
        """The number of integers in the field"""
        return self.count

    def __contains__(self, number):
        """Returns true if number is present in the field"""
        cdef usize_t page = number / PAGE_FULL_COUNT
        cdef usize_t page_index = number % PAGE_FULL_COUNT
        if page >= len(self.pages):
            return False
        return page_index in self.pages[page]

    def __iter__(self):
        """Iterate over all integers in the field"""
        return BitfieldIterator(self)

    def __richcmp__(Bitfield a,Bitfield b, operator):
        cdef usize_t current_pageent
        if operator == 0:
            return (b != a) and (a.issubset(b))
        if operator == 1:
            return a.issubset(b)
        if operator == 2:
            a._cleanup()
            b._cleanup()
            if len(a.pages) != len(b.pages):
                return False
            for current in range(len(a.pages)):
                if a.pages[current] != b.pages[current]:
                    return False
            return True
        if operator == 3:
            return not a == b
        if operator == 4:
            return (a != b) and (b.issubset(a))
        if operator == 5:
            return b.issubset(a)
        raise NotImplementedError()

    def __or__(Bitfield x, Bitfield y):
        """Return a new object that is the union of two bitfields"""
        cdef Bitfield new
        new = x.clone()
        new.update(y)
        return new

    def __ior__(Bitfield x, Bitfield y):
        return x.update(y)

    def union(Bitfield self, Bitfield other):
        return self | other

    def __add__(Bitfield x, usize_t y):
        """Return a new field with the integer added"""
        cdef Bitfield new
        new = x.clone()
        new.add(y)
        return new

    def __iadd__(Bitfield x, usize_t y):
        """Add a positive integer to the field"""
        x.add(y)
        return x

    def __sub__(Bitfield x, Bitfield y):
        cdef Bitfield new
        new = x.clone()
        new.difference_update(y)
        return new

    def __isub__(Bitfield x, Bitfield y):
        return x.difference_update(y)

    def __isub__(Bitfield x, Bitfield y):
        return x.difference_update(y)

    def __xor__(Bitfield self, Bitfield other):
        return self.symmetric_difference(other)

    def __ixor__(Bitfield self, Bitfield other):
        return self.symmetric_difference_update(other)

    def __and__(Bitfield self, Bitfield other):
        return self.intersection(other)

    def __iand__(Bitfield self, Bitfield other):
        return self.intersection_update(other)

    cpdef update(self, Bitfield other):
        """Add all integers in 'other' to this bitfield"""
        cdef usize_t current_page
        self._ensure_page_exists(len(other.pages))
        for current_page in range(len(other.pages)):
            self.pages[current_page].update(other.pages[current_page])

    cpdef difference_update(self, Bitfield other):
        """Remove all integers in 'other' from this bitfield"""
        cdef usize_t current_page
        cdef usize_t affected_pages = min(len(self.pages), len(other.pages))
        for current_page in range(affected_pages):
            self.pages[current_page].difference_update(other.pages[current_page])        

    cpdef symmetric_difference_update(self, Bitfield other):
        """Update this bitfield to only contain items present in self or other, but not both    """
        cdef usize_t current_page
        cdef usize_t other_pages = 0
        cdef usize_t affected_pages = min(len(self.pages), len(other.pages))
        if affected_pages < len(other.pages):
            other_pages = len(other.pages) - affected_pages

        for current_page in range(affected_pages):
            self.pages[current_page].symmetric_difference_update(other.pages[current_page])
        if affected_pages < len(other.pages):
            for current_page in range(affected_pages, len(other.pages)):
                self.pages.append(other.pages[current_page].clone())

    cpdef symmetric_difference(self, Bitfield other):
        cdef Bitfield new = self.clone()
        new.symmetric_difference_update(other)
        return new

    cpdef intersection_update(self, Bitfield other):
        """Update the bitfield, keeping only integers found in it and 'other'."""
        cdef IdsPage page
        cdef usize_t current_page
        cdef usize_t affected_pages = min(len(self.pages), len(other.pages))
        for current_page in range(affected_pages):
            self.pages[current_page].intersection_update(other.pages[current_page])
        if len(self.pages) > affected_pages:
            for current_page in range(affected_pages, len(self.pages)):
                page = self.pages[current_page]
                page.set_empty()

    cpdef intersection(Bitfield self, Bitfield other):
        """Return a new bitfield with integers common to both this field, and 'other'."""
        cdef Bitfield new = self.clone()
        new.intersection_update(other)
        return new

    cpdef isdisjoint(Bitfield self, Bitfield other):
        """Return True if the bitfield has no integers in common with other. 
        Bitfields are disjoint if and only if their intersection is the empty set."""
        return len(self.intersection(other)) == 0

    cpdef issubset(Bitfield self, Bitfield other):
        return len(self - other) == 0

    cpdef issuperset(Bitfield self, Bitfield other):
        return other.issubset(self)

    cpdef copy(self):
        """Create a copy of the bitfield"""
        return self.clone()

    cpdef clone(self):
        """Create a copy of the bitfield"""
        new = Bitfield()
        for page in self.pages:
            new.pages.append(page.clone())
        return new

    cdef str get_bits(self):
        cdef IdsPage page
        cdef char *buffer
        cdef char * offset
        cdef CHUNK *page_buffer
        cdef str string
        cdef usize_t length = len(self.pages) * PAGE_BYTES

        string = PyString_FromStringAndSize(NULL, length)
        buffer = PyString_AsString(string)
        for i in range(len(self.pages)):
            page = self.pages[i]
            page_buffer = page.get_bits()
            offset = &buffer[i * PAGE_BYTES]
            memcpy(offset, page_buffer, PAGE_BYTES)
        return string

    def pickle(self, compress=True):
        """Return a string representation of the bitfield"""
        cdef str base = self.get_bits().rstrip("\00")
        cdef str marker = PICKLE_MARKER
        if compress:
            base = zlib.compress(base)
            marker = PICKLE_MARKER_zlib
        return "%s%s" % (marker, base)

    @classmethod
    def unpickle(cls, str data):
        """Read a bitfield object from a string created by Bitfield.piclke"""
        cdef Bitfield new = Bitfield()
        new.load_from_string(data)
        return new

    def __reduce__(self):
        return (unpickle_bitfield, (self.pickle(), ))

    cdef load(Bitfield self, data):
        if isinstance(data, basestring):
            return self.load_from_string(data)
        for item in data:
            if isinstance(item, (int, long)):
                self.add(item)
            else:
                low, high = item
                self.fill_range(low, high)

    cdef load_from_string(self, data):
        cdef str marker = data[:len(PICKLE_MARKER)]
        data = data[len(PICKLE_MARKER):]
        if marker != PICKLE_MARKER and marker != PICKLE_MARKER_zlib:
            raise ValueError("Could not unpickle data")
        if marker == PICKLE_MARKER_zlib:
            data = zlib.decompress(data)
        cdef usize_t length = len(data)
        cdef char *buffer = PyString_AsString(data)
        cdef char *buffer_end = &buffer[length]
        cdef char *current = buffer
        cdef IdsPage page
        while current <= buffer_end:
            page = IdsPage()
            self.pages.append(page)
            current = page.set_bits(current, buffer_end)

    cdef fill_range(self, low, high):
        """Add all numbers in range(low, high) to the bitfield, optimising the case where large
        ranges are supplied"""
        cdef IdsPage page = None
        # start by allocating all the pages we need
        self.add(high-1)
        # Find if there are any whole pages that can be allocated in one go
        lower_page_boundary = (low // PAGE_FULL_COUNT)
        if lower_page_boundary * PAGE_FULL_COUNT != low:
            lower_page_boundary += 1
        upper_page_boundary = high // PAGE_FULL_COUNT
        assert upper_page_boundary >= lower_page_boundary
        for page_num in range(lower_page_boundary, upper_page_boundary):
            page = self.pages[page_num]
            page.set_full()
        for num in range(low, lower_page_boundary * PAGE_FULL_COUNT):
            self.add(num)
        for num in range(upper_page_boundary * PAGE_FULL_COUNT, high):
            self.add(num)

    @classmethod
    def from_intervals(type cls, list):
        """Given a list of ranges in the form:  [[low1, high1], [low2, high2], ...]
        Construct a bitfield in which every integer in each range is present"""
        cdef Bitfield new = Bitfield()
        for (low, high) in list:
            new.fill_range(low, high)
        return new

    def __str__(self):
        return "Bitfield(len=%i, range=0 > ~%i)" % (len(self), len(self.pages) * PAGE_FULL_COUNT)

    def __repr__(self):
        cls = type(self)
        return "%s.%s(%r)" % (cls.__module__, cls.__name__, self.pickle())

    def clear(self):
        self.pages = []


cpdef unpickle_bitfield(str data):
    return Bitfield.unpickle(data)
