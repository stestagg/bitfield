import bf
import time
import sys


def test():
    ranges = ((1, 100), (102, 10000), (1000000, 2000000))
    evil = range(0, 100000, 2)

    start = time.clock()
    ff = bf.Bitfield(ranges)
    for i in xrange(0, 3000000, 10000):
        ff.add(i)
    gg = eval(repr(ff))
    assert len(gg - ff) == 0
    for i in ff:
        gg.discard(i)
    aa = bf.Bitfield(evil)
    cc = ff - aa
    assert cc
    hh = bf.Bitfield()
    for i in xrange(0, 2000000, 2):
        hh.add(i)
    stop = time.clock()
    return stop - start


ONE_MILLION = 1000000
SIZE = ONE_MILLION * 1000


def test2():
    start = time.clock()
    field1 = bf.Bitfield([[0, SIZE]])
    field2 = bf.Bitfield([[SIZE, SIZE * 2]])
    assert len(field1) == SIZE
    assert len(field2) == SIZE
    field3 = field1 | field2
    assert len(field3) == SIZE * 2
    end = time.clock()
    return end - start


def out(a):
    sys.stdout.write(str(a))
    sys.stdout.write(", ")
    sys.stdout.flush()


def main():
    chunks = bf.get_all_sizes()["PAGE_CHUNKS"]
    for i in range(3):
        out(chunks)
        out(test())
        out(test2())
        print

if __name__ == "__main__":
    main()
