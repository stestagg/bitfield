#!/bin/bash

set -e 

if [ -e bf.so ]; then rm bf.so; fi

cat field_template.pyx | sed s/!!!!/$1/ > bf.pyx

cython -2 bf.pyx -o bf.c

gcc -std=c99 -bundle -Os -undefined dynamic_lookup -Wl,-F. -arch x86_64 bf.c \
	  -I/System/Library/Frameworks/Python.framework/Versions/2.7/include/python2.7 \
	  -dynamic -fno-common -fno-strict-aliasing -fwrapv -mno-fused-madd -o bf.so 2>/dev/null

export PYTHONPATH=.

python test.py
