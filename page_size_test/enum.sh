#!/bin/bash

./test.sh 4

set -e

for i in $(seq 64 64 4096); do

./test.sh $i

done
