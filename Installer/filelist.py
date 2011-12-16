#!/usr/bin/env python

import os, sys

filefd = open("layout/var/spire/files.txt", "w")
dirfd = open("layout/var/spire/dirs.txt", "w")

# this requires the siri files to be in a sirifiles/ directory here
# that (obviously) cannot be included, so you'll have to get it yourself
# or just use the file and directory lists that I've provided
os.chdir("sirifiles")

for root, dirs, files in os.walk(".", topdown=True):
    # use [2:] to remove the ./ at the start of the path
    for dir in dirs:
        dirfd.write(os.path.join(root, dir)[2:] + "\n")
    for file in files:
        filefd.write(os.path.join(root, file)[2:] + "\n")


