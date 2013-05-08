import bitfield
import sys

if __name__ == "__main__":
    one_million = 1000000
    size = one_million * 1000

    field1 = bitfield.Bitfield([[0, size]])
    field2 = bitfield.Bitfield([[size, size * 2]])
    assert len(field1) == size
    assert len(field2) == size
    field3 = field1 | field2
    assert len(field3) == size * 2