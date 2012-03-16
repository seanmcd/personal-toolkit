#!/bin/bash

# This script counts out numbers for the FizzBuzz problem. It goes from 1 to
# the number given as the first argument, or 100 if no argument is given.
# c.f. http://www.codinghorror.com/blog/2007/02/why-cant-programmers-program.html

# Pretty much just for kicks - and, amusingly, took far longer than the Python
# version. That's partially because I got a tiny bit fancier, though.

TOP="$1"
TOP=`echo "$TOP" | perl -pe 's/[^0-9]//g;'`
typeset -i TOP
if [[ -z "$TOP" ]]
then
    TOP=101
fi

echo "Fizzing and buzzing from 1 to $TOP."

for i in `seq 1 $TOP`
do
    if [[ `expr $i % 15` -eq 0 ]]
    then
	echo -n "FizzBuzz, "
	continue
    elif [[ `expr $i % 3` -eq 0 ]]
    then
	echo -n "Fizz, "
    elif [[ `expr $i % 5` -eq 0 ]]
    then
	echo -n "Buzz, "
    else
	if [[ $i -eq $TOP ]]
	then
	    echo "$i."
	else
	    echo -n "$i, "
	fi
    fi
done
