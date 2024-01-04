bitfield
========

A Cython implemented fast positive integer set implementation, optimised for sets of sequential numbers.

__WARNING__ : The serialisation mechanism is not currently portable,  This will be fixed soon

Installation
---------

```
$ sudo easy_install bitfield
```

Usage
-----

```python
>>> import bitfield
>>> field = bitfield.Bitfield()
>>> field.add(100)
>>> print list(field)
[100L]
>>> second = bitfield.Bitfield([2, 100])
>>> list(field | second)
[2L, 100L]

>>> second.add(10000)
>>> second.pickle()
'BZ:x\x9cca@\x00\x01\x86Q0\nF\xc1(\x18N\x80\x11\x00e\xe0\x00\x16'

>>> large=bitfield.Bitfield(random.sample(xrange(1000000), 500000)) # 500,000 items, randomly distributed
>>> len(large)
500000
>>> len(large.pickle())
125049  # 122KB

>>> large=bitfield.Bitfield(xrange(1000000)) # 1 million items, all sequential
>>> len(large)
1000000
>>> len(large.pickle())
36 # <40 bytes
```

Bitfields support most of the same operations/usage as regular sets, see the tests for examples.

Design
------

Bitfield was designed to efficiently handle tracking large sets of items.

The main design goals were:
 * Space-efficient serialisation format
 * Fast membership tests and set differences

Internally, bitfield achieves this using a page-compressed 1-d bitmap.  

Within a page, a number is recorded as being present in the set by setting the n-th bit to 1.
I.e. the set([1]) is recorded as ...00000010b, while set([1,4]) would be ...00010010b.

This works well for small sets, but the size of the bitfield tends towards (highest set member)/8 bytes as the largest number in the set increases. 

To counter this, the bit field is split into chunks of 1 page (usually 4k).  If a particular page is empty(no set members in that range) or full, 
then the bitfield is discarded, and represented by an EMPTY or FULL flag.

To improve lookup times and simplify set comparison, the bitfield always indexes items from 0.  
Therefore, a set with a single item of 1,000,000,000 isn't going to be as fast as it could be.  This was an intentional design decision.
