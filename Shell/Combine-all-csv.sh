#!/bin/bash

OUTPUTFILE="some-output-filename.csv"

createfile() {
  touch $OUTPUTFILE
}

listallfiles() {
  listoffiles=($(find -f /<location-of-folder>/ | grep .csv))
}

combineallfiles() {
  echo $headline>$OUTPUTFILE
  # Header of csv can be the fiest word of the 1st row to match
  awk '
    FNR==1 && NR!=1 { while (/^<HEADER-OF-CSV>/) getline; }
    1 {print}
  ' ${listoffiles[@]} >>$OUTPUTFILE
}

main() {
  createfile
  listallfiles
  combineallfiles
}

main
