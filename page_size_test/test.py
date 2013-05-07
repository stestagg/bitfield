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
    hh = bf.Bitfield()
    for i in xrange(0, 2000000, 2):
        hh.add(i)
    stop = time.clock()
    return stop - start


def out(data):
    sys.stdout.write(str(data))
    sys.stdout.write(", ")
    sys.stdout.flush()


def main():
    chunks = bf.get_all_sizes()["PAGE_CHUNKS"]
    out(chunks)
    num = 0
    tot = 0
    for i in range(8):
        t = test()
        out(t)
        num += 1
        tot += t
        if i == 4:
            time.sleep(0.5)
    out(tot/num)
    print

if __name__ == "__main__":
    main()
