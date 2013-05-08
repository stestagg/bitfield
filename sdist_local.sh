#!/bin/bash

VERSION=$(env PYTHONPATH=. python -c 'import setup; print(setup.VERSION)')

TEMP_DIR=$(mktemp -d)
./setup.py sdist -d $TEMP_DIR

ls $TEMP_DIR

cp $TEMP_DIR/bitfield-$VERSION.tar.gz ./package.tar.gz
