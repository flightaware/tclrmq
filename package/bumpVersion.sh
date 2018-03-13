#!/usr/bin/env zsh

# Need the current version
CUR_VER=`git tag | tail -1 | cut --complement -c 1`
echo "Bumping version from ${CUR_VER} to $1"

# TODO: make sure valid version bump

# Handle all the scripts
FILES="Channel.tcl 
Connection.tcl  
constants.tcl  
decoders.tcl  
encoders.tcl  
Login.tcl"
for file in $FILES
do
    echo $file
    sed "s/\(package provide rmq\) \(${CUR_VERSION}\)/\1 $1/g" $file
done

# Deal with pkgIndex separately
sed "s/\(package ifneeded rmq\) \(${CUR_VERSION}\)/\1 $1/g" pkgIndex.tcl
