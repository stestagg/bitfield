import bf
import time
import sys


def timed(fun):
    def wrapper():
        num = 0
        start = time.clock()
        end = start
        while end - start < 0.5:
            fun()
            end = time.clock()
            num += 1
        return (end - start) / num
    return wrapper


RANGES = ((1, 100), (102, 10000), (1000000, 2000000))
EVIL = range(0, 100000, 2)


@timed
def test():
    ff = bf.Bitfield(RANGES)
    for i in xrange(0, 3000000, 10000):
        ff.add(i)
    gg = eval(repr(ff))
    assert len(gg - ff) == 0
    for i in ff:
        gg.discard(i)
    aa = bf.Bitfield(EVIL)
    cc = ff - aa
    assert cc
    hh = bf.Bitfield()
    for i in xrange(0, 2000000, 2):
        hh.add(i)


@timed
def test_small():
    aa = bf.Bitfield()
    bb = bf.Bitfield()
    cc = bf.Bitfield()
    for i in xrange(0, 100, 3):
        aa.add(i)
        bb.add(i + 1)
        cc.add(i + 2)
    assert len(aa) == len(bb) == len(cc)
    assert len(aa | bb | cc) == 102
    dd = bf.Bitfield(((500, 700),)) | (aa ^ bb ^ cc)
    for i in dd:
        i in aa
        i in bb
        i in cc
        dd.remove(i)



ONE_MILLION = 1000000
SIZE = ONE_MILLION * 1000


@timed
def test2():
    field1 = bf.Bitfield([[0, SIZE]])
    field2 = bf.Bitfield([[SIZE, SIZE * 2]])
    assert len(field1) == SIZE
    assert len(field2) == SIZE
    field3 = field1 | field2
    assert len(field3) == SIZE * 2


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
        out(test_small())
        print

if __name__ == "__main__":
    main()
