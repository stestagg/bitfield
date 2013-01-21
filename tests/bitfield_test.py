#!/usr/bin/python

# For coverage script
import bitfield

import cPickle
import pickle

try:
    # Python 2.6 support
    import unittest2 as unittest
except ImportError:
    import unittest


class BitfieldTest(unittest.TestCase):

    def test_repr_eval(self):
        b = bitfield.Bitfield()
        b.add(100)
        c = eval(repr(b))
        self.assertEqual(b, c)
        for i in range(0, 1000, 13):
            b.add(i)
        c = eval(repr(b))
        self.assertEqual(b, c)

    def test_count(self):
        b = bitfield.Bitfield()
        self.assertEqual(b.count, 0)
        b.add(0)
        self.assertEqual(b.count, 1)
        b.add(10000)
        self.assertEqual(b.count, 2)
        self.assertEqual(len(b), 2)

    def test_mutating_while_iterating(self):
        b = bitfield.Bitfield([[0, 1000]])
        count = len(b)
        for num in b:
            self.assertIn(num, b)
            b.remove(num)
            count -= 1
            self.assertEqual(len(b), count)
            self.assertNotIn(num, b)
        self.assertEqual(count, 0)

    def test_membership(self):
        b = bitfield.Bitfield()
        b.add(0)
        b.add(1)
        b.add(2)
        self.assertTrue(1 in b)
        self.assertFalse(3 in b)
        self.assertEqual(list(b), [0, 1, 2])

    def test_filling_page(self):
        p = bitfield.IdsPage()
        self.assertEqual(p.count, 0)
        chunk_bytes, page_chunks = bitfield.get_sizes()
        bits_per_chunk = page_chunks * chunk_bytes * 8
        for i in range(bits_per_chunk):
            p.add(i)
        with self.assertRaises(AssertionError):
            p.add(i+1)

    def test_add_remove(self):
        b = bitfield.Bitfield()
        self.assertEqual(list(b), [])
        for i in xrange(0, 1000000, 881):            
            b.add(i)
            self.assertEqual(list(b), [i])
            b.remove(i)

    def test_merging(self):
        a = bitfield.Bitfield()
        b = bitfield.Bitfield()
        a.add(0)
        b.add(0)
        a.update(b)
        self.assertEqual(list(a), [0])
        a.add(1000)
        b.add(1000000)
        b.update(a)
        self.assertEqual(list(b), [0, 1000, 1000000])

    def test_in(self):
        a = bitfield.Bitfield()
        for i in range(0, 100, 13):
            a.add(i)
        self.assertIn(13, a)
        self.assertIn(0, a)
        self.assertIn(26, a)
        self.assertNotIn(27, a)
        self.assertIn(39, a)
        self.assertNotIn(1000000, a)
        a.add(1000000)
        self.assertIn(1000000, a)

    def test_clone(self):
        a = bitfield.Bitfield()
        a.add(1)
        a.add(10)
        a.add(5000000)
        b = a.clone()
        self.assertEqual(a, b)
        b.add(45)
        self.assertNotEqual(a, b)

    def test_symmetric_difference(self):
        field = bitfield.Bitfield
        a = field()
        b = field()
        a.add(1)
        self.assertEqual(a.symmetric_difference(b), field([1]))
        self.assertEqual(a ^ b, a)
        b.add(2)
        self.assertEqual(list(a ^ b), list(field([1,2])))

        full = field([[1, 100000]]) 
        full_set = set(range(1, 100000))
        self.assertEqual(set(full), full_set)
        self.assertEqual(set(full ^ a), full_set - set([1]))

        odds = field(range(1, 90000, 2))
        evens = field(range(0, 90000, 2))
        full = odds ^ evens
        self.assertEqual(list(full), range(90000))
        self.assertEqual(len(full), len(odds) + len(evens))
        self.assertEqual(len((odds ^ odds) | (evens ^ evens)), 0)

    def test_creating_large_field(self):
        # This is a strange test, the idea is to create a large set, then do something with it
        # provided the test completes in a 'reasonable' timescale, then it should be fine
        one_million = 1000000
        size = one_million * 1000

        field1 = bitfield.Bitfield([[0, size]])
        field2 = bitfield.Bitfield([[size, size*2]])
        self.assertEqual(len(field1), size)
        self.assertEqual(len(field2), size)
        self.assertEqual(len(field1 | field2), size * 2)


class SetEqualityTest(unittest.TestCase):

    def _test_field_result(self, a, b, func):
        set_a = set(a)
        set_b = set(b)
        bitfield_result = func(a, b)
        set_result = func(set_a, set_b)
        set_as_list = sorted(set_result)
        self.assertEqual(list(bitfield_result), set_as_list)

    def _test_simple_result(self, a, b, func):
        set_a = set(a)
        set_b = set(b)
        bitfield_result = func(a, b)
        set_result = func(set_a, set_b)
        self.assertEqual(bitfield_result, set_result)        

    def _test_methods(self, a, b):
        a_pure = a.copy()
        b_pure = b.copy()
        self._test_field_result(a, b, lambda x, y: x | y)
        self._test_field_result(a, b, lambda x, y: x ^ y)
        self._test_field_result(a, b, lambda x, y: x & y)
        self._test_field_result(a, b, lambda x, y: x - y)
        self._test_field_result(a, b, lambda x, y: x.union(y))
        self._test_simple_result(a, b, lambda x, y: x.isdisjoint(y))
        self._test_simple_result(a, b, lambda x, y: x.issubset(y))
        self._test_simple_result(a, b, lambda x, y: x < y)
        self._test_simple_result(a, b, lambda x, y: x <= y)
        self._test_simple_result(a, b, lambda x, y: x == y)
        self._test_simple_result(a, b, lambda x, y: x != y)
        self._test_simple_result(a, b, lambda x, y: x >= y)
        self._test_simple_result(a, b, lambda x, y: x > y)

        a_2, b_2 = pickle.loads(cPickle.dumps([a, b]))
        self.assertEqual(a_2, a)
        self.assertEqual(b_2, b)
        self.assertEqual(a_pure, a)
        self.assertEqual(b_pure, b)

    def test_empty(self):
        self._test_methods(bitfield.Bitfield(), bitfield.Bitfield())

    def test_simple(self):
        self._test_methods(bitfield.Bitfield([1, 2, 3]), bitfield.Bitfield([1, 2, 3]))
        self._test_methods(bitfield.Bitfield([1, 2, 3]), bitfield.Bitfield([1, 2]))
        self._test_methods(bitfield.Bitfield([1, 2, 3]), bitfield.Bitfield([3, 4, 5]))
        self._test_methods(bitfield.Bitfield([1]), bitfield.Bitfield([1, 3, 4, 5]))

    def test_multi_page(self):
        def nums(*numbers):
            return list([page_numbers[n] for n in numbers])
        page_max = bitfield.get_all_sizes()["PAGE_MAX"]
        page_numbers = [5 + (page_max * i ) for i in range(10)]
        a = bitfield.Bitfield(nums(0, 2))
        b = bitfield.Bitfield(nums(1, 3))
        self._test_methods(a, b)
        self._test_methods(b, a)

    def test_empty_full(self):
        page_max = bitfield.get_all_sizes()["PAGE_MAX"]
        page_numbers = [5 + (page_max * i ) for i in range(10)]
        a = bitfield.Bitfield([[0, page_max]])
        b = bitfield.Bitfield()
        self._test_methods(a, b)
        self._test_methods(b, a)
        

if __name__ == "__main__":
    unittest.main()