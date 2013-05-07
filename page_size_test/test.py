import bf
import time


def main():

    ranges = ((1, 100), (102, 10000), (1000000, 2000000))
    evil = range(0, 100000, 2)

    start = time.clock()
    ff = bf.Bitfield(ranges)
    for i in xrange(0, 3000000, 10000):
        ff.add(i)
    gg = eval(repr(ff))
    assert len(gg - ff) == 0
    for i in ff:
        gg.remove(i)
    aa = bf.Bitfield(evil)
    cc = ff - aa

    stop = time.clock()
    chunks = bf.get_all_sizes()["PAGE_CHUNKS"]
    print chunks, ",", stop - start


if __name__ == "__main__":
    main()
