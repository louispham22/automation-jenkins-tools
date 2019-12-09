#!/bin/bash
#
# Output tags in git commit in bash array format
#
# Usage $0 <commit> <varname>
#
# default: <commit> is HEAD
#          <varname> is COMMITTAG
#


REV=${1:-HEAD}
VARNAME=${2:-COMMITAG}

echo "declare -A $VARNAME"
git log $REV^! --pretty=full|tac|grep -e "[ ]*[A-Za-z-]*:[^'\"]*$"|sed -s "s/[ ]*\([A-Za-z-]*\):[ ]*\(.*\)/${VARNAME}[\1]='\2'/"
