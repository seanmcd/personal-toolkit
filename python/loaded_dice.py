#!/usr/bin/python
#-*- coding: utf-8 -*-

""" I was thinking about chance and dice, and wondered how to simulate a loaded
    die. Then I generalized a little. The meat of this file is a function that
    takes a list of (name, value) tuples and returns one of the names with a
    likelihood governed by the values. For example, when the input is the list

    >>> [("lion", 1.0), ("tiger", 5.0), ("bear", 1.5)]

    then the function will return "bear" 50% more often than it returns "lion",
    and will return "tiger" five times as often as it returns "lion".
"""

import random

def vet_list(input_list):
    """Basic sanity checks."""
    if len(input_list) < 1:
        print "Error: zero length list."
        return None

    for item in input_list:
        try:
            if (len(item) != 2) or (float(item[1]) != item[1]):
                print "Error: list items must be (name, value) pairs"
                return None
        except ValueError:
            print "Error: value must be amenable to numeric representation"
            return None
        if item[1] <= 0:
            print "Error: value must be > 0"
            return None
    return input_list

def roll_die(input_list):
    if not vet_list(input_list):
        print "Can't roll the dice."

    all_weights = sum(value for name,value in input_list)
    # print "Total of weights: {}".format(all_weights)
    honest_roll = random.uniform(0, all_weights)
    # print "Roll was: {}".format(honest_roll)
    roll_progress = 0

    for name, value in input_list:
        if roll_progress + value > honest_roll:
            return name
        roll_progress += value

if __name__ == '__main__':
    my_list = [("two", 1.0/36.0),
               ("three", 2.0/36.0),
               ("four", 3.0/36.0),
               ("five", 4.0/36.0),
               ("six", 5.0/36.0),
               ("seven", 6.0/36.0),
               ("eight", 5.0/36.0),
               ("nine", 4.0/36.0),
               # High numbers twice as likely.
               ("ten", 2*3.0/36.0),
               ("eleven", 2*2.0/36.0),
               ("twelve", 2*1.0/36.0 ),
               ]
    results = { "two": 0,
                "three": 0,
                "four": 0,
                "five": 0,
                "six": 0,
                "seven": 0,
                "eight": 0,
                "nine": 0,
                "ten": 0,
                "eleven": 0,
                "twelve": 0,
                }
    weights = [ x[1]/sum([ y[1] for y in my_list ]) for x in my_list ]

    for n in range(10000):
        roll = roll_die(my_list)
        results[roll] += 1

    print "\n".join([
            "+--------+----------+--------+--------+",
            "| Result | Weighted | Honest | Rolled |",
            "+--------+----------+--------+--------+",
            "| two    | {:.4f}   | {:.4f} | {:>6d} |".format(weights[0], my_list[0][1], results["two"]),
            "| three  | {:.4f}   | {:.4f} | {:>6d} |".format(weights[1], my_list[1][1], results["three"]),
            "| four   | {:.4f}   | {:.4f} | {:>6d} |".format(weights[2], my_list[2][1], results["four"]),
            "| five   | {:.4f}   | {:.4f} | {:>6d} |".format(weights[3], my_list[3][1], results["five"]),
            "| six    | {:.4f}   | {:.4f} | {:>6d} |".format(weights[4], my_list[4][1], results["six"]),
            "| seven  | {:.4f}   | {:.4f} | {:>6d} |".format(weights[5], my_list[5][1], results["seven"]),
            "| eight  | {:.4f}   | {:.4f} | {:>6d} |".format(weights[6], my_list[6][1], results["eight"]),
            "| nine   | {:.4f}   | {:.4f} | {:>6d} |".format(weights[7], my_list[7][1], results["nine"]),
            "| ten    | {:.4f}   | {:.4f} | {:>6d} |".format(weights[8], my_list[8][1]/2.0, results["ten"]),
            "| eleven | {:.4f}   | {:.4f} | {:>6d} |".format(weights[9], my_list[9][1]/2.0, results["eleven"]),
            "| twelve | {:.4f}   | {:.4f} | {:>6d} |".format(weights[10], my_list[10][1]/2.0, results["twelve"]),
            "+--------+----------+--------+--------+",
            ])
