#!/bin/bash

./test.sh 1

for i in $(seq 4 4 70); do

./test.sh $i

done
