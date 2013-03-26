import bitfield
import sys

if __name__ == "__main__":
	b = bitfield.Bitfield()
	b.add(1)
	b.add(1000000)
        print repr(b.pickle())
