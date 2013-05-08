#!/bin/bash

set -e 

if [ -e bf.so ]; then rm bf.so; fi

#cat field_template.pyx | sed s/!!!!/$1/ > bf.pyx
cat ../cimpl/field.h | sed "s:PAGE_CHUNKS [0-9]*:PAGE_CHUNKS $1:" > ./field.h
cp ../cimpl/field.pyx bf.pyx

cython -2 bf.pyx -o bf.c

if [ $(uname) = "Linux" ]; then
gcc -pthread -shared -fno-strict-aliasing -DNDEBUG -g -fwrapv -O2\
    -Wstrict-prototypes -fPIC -I/usr/include/python2.7\
    -Wl,-O1 -Wl,-Bsymbolic-functions -Wl,-Bsymbolic-functions -Wl,-z,relro\
    bf.c -o bf.so -g
else
clang  -bundle -Os -undefined dynamic_lookup -Wl,-F. -arch x86_64 bf.c \
          -I/System/Library/Frameworks/Python.framework/Versions/2.7/include/python2.7 \
          -dynamic -fno-common -fno-strict-aliasing -fwrapv -mno-fused-madd -o bf.so 2>/dev/null
fi

rm ./field.h
rm ./bf.pyx
rm ./bf.c

export PYTHONPATH=.

python test.py
