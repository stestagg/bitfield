#!/bin/bash

#./test.sh 1
#./test.sh 2

set -e

for i in $(seq 4 16 4096); do

./test.sh $i

done
