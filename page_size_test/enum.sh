#!/bin/bash

./test.sh 1
./test.sh 2

for i in $(seq 4 4 512); do

./test.sh $i

done
