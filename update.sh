#!/bin/bash

# Get next Version:
current="13.11.1-dev"
next=$(git tag | grep $current -a1 | tail -1)

if [ "$current" == "$next" ]; then
    echo "Already up-to-date!"
else
    echo "Please update to $next!"
fi
