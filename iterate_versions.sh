#!/bin/bash 
# $1: Current Version
# $2: Next Version (Optional)

if [ -z "$1" ]; then
	echo 
	echo "Usage:  ./iterate_version.sh [test] BRANCH CUR_VERSION NEW_VERSION"
	echo "           BRANCH: Name of the branch to update or RELEASE to update all release branches, or INF for all inf branches."
	echo "           CUR_VERSION: Current Release Version."
	echo "           NEW_VERSION: (Optional) Next Release Version."
    echo "           By prefixing the arguments with test, it will be a dry run - NO commits will be made"
	echo
	echo "Example:"
	echo "    E.g. if 1.25 is released and we are releasing 1.26 then you can specify either:"
	echo "        ./iterate_version.sh RELEASE 1.25 1.26"
	echo "    or"
	echo "        ./iterate_version.sh RELEASE 1.25"
	echo
	echo "    E.g. if 1.25 is released and we are releasing 2.0 then you can specify either:"
	echo "        ./iterate_version.sh RELEASE 1.25 2.0"
	echo
	echo
	echo "NOTE: This does not support hotfix releases"
	exit 1
fi

echo
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR
curr_branch=`git rev-parse --abbrev-ref HEAD`
#Keep track of all the inf environments
inf_file=ref_inf_list
inf_envs=`cat $inf_file`
#====================  Start functions ============================== 
#Takes in the branch name(which can be RELEASE), the file with the list of branches, and the function to execute
function iterate_branches(){
    BRANCH=$1
    branch_file=$2
    callback=$3
    if [[ $BRANCH == 'INF' ]]; then
        branch_file=
        BRANCH=RELEASE
    fi
    if [[ $BRANCH == 'RELEASE' ]]; then
        #The ref_branch_list has the list of branches - note the use of file separator when iterating 
        IFS_OLD=$IFS
        IFS=$'\n'
        for i in `cat $branch_file $inf_file`
        do
            IFS=$IFS_OLD
            #skip blank lines and comments
            if [[ "$i" != "" && "${i:0:1}" != "#" ]]
            then
                $callback $i
            fi
            IFS=$'\n'
        done
        IFS=$IFS_OLD
    else
        #User specified branch - only update that
        $callback $BRANCH
    fi

}

#Will stash changes - returns 0 if no changes, 1 if changes were stashed, 2 if user refused to stash changes
function stash_changes(){
    testprefix=$1
    if [ "$testprefix" != "" ]
    then
        checklocal=`git diff`
        if [ "$checklocal" != "" ]
        then
            #In test mode, you can make changes to this script, which will be stashed so you don't have to commit them
            echo "Found local changes, stash them? "
            read promptval
            promptval=`echo $promptval | tr '[A-Z]' '[a-z]'`
            if [[ "$promptval" = "n" || "$promptval" = "no" ]]
            then
                echo "Stopping - please deal with your uncommitted changes to $curr_branch"
                return 2
            fi
            git stash
            return 1
        fi
    fi
    return 0

}

function delete_branches(){
    echo "Do you want to delete all local branches except $curr_branch (this will speed things up)? "
    read promptval
    promptval=`echo $promptval | tr '[A-Z]' '[a-z]'`
    if [[ "$promptval" = "y" || "$promptval" = "yes" ]]
    then
        git branch | grep -v main | grep -v $curr_branch | xargs git branch -D
    fi
}

#Pass in 0 or 1 if changes were stashed
function restore_state(){
    stashed=$1
    #Finally switch back to original branch
    git checkout $curr_branch

    #In test mode, if changes were stashed, recover them
    if [ "$stashed" != "0" ]
    then
        echo "Recovering changes"
        git stash pop
    fi
}
function update_file(){
    local file=$1
    local curr_branch=$2
    is_inf=
    future_version=$FUT_VERSION
    #If this is an INF branch, then update SNAPSHOTS to next release
    if [[ $inf_envs =~ $curr_branch ]]
    then
        is_inf="(INF)"
        future_version=$NEW_VERSION
    fi
    file_bk=${file}.bk
    # Replace all instacnes of XX.XX-SNAPSHOT; include SNAPSHOT to make sure we don't get false positives
    echo "Replacing $NEW_VERSION-SNAPSHOT with ${future_version} in $file $is_inf"
	sed s_$NEW_VERSION\-SNAPSHOT_${future_version}_g < $file > $file_bk; cp $file_bk $file
	sed s_$NEW_ALT_VERSION\-SNAPSHOT_${future_version}_g < $file > $file_bk; cp $file_bk $file

	# The release version is less unique so we look for known locations
	# In an assginement; E.g. blueprint-version: 1.29
    # There could be hotfix versions, so replace those as well
    # Need to replace a literal dot
    base_version=`echo ${CUR_VERSION} | sed 's/\./[.]/'`
    hotfix=
    #We are replacing the versions twice
    #once replacing the current version (like 1.29) with the new version(like 1.30) (ignore the hotfix variable below)
    #Then again where any hotfix versions (like 1.29.2) are replaced with the new version (like 1.30)
    for i in `seq 1 2`
    do
        echo "Replacing ${base_version}${hotfix} with ${NEW_VERSION} in $file"
        sed s_\:\ *${base_version}${hotfix}_\:\ ${NEW_VERSION}_g < $file > $file_bk; cp $file_bk $file
        # In an assginment; E.g. blueprint-version: "1.29"
        sed s_\:\ *\"${base_version}${hotfix}\"_\:\ \"${NEW_VERSION}\"_g < $file > $file_bk; cp $file_bk $file
        # In an assginment; E.g. blueprint-version=1.29
        sed s_\=\ *${base_version}${hotfix}_\=${NEW_VERSION}_g < $file > $file_bk; cp $file_bk $file
        # In an assginment; E.g. blueprint-version="1.29"
        sed s_\=\ *\"${base_version}${hotfix}\"_\=\"${NEW_VERSION}\"_g < $file > $file_bk; cp $file_bk $file
        #Assume that base version is just first 2 numbers
        base_version=`echo ${CUR_VERSION} | awk -F. '{print $1 "." $2}'`
        hotfix="\\.[0-9]"
    done

	# In an include path; E.g. include "s3://dev-dp-artifact/contract/1.29/dp.conf
	sed s_\/${CUR_VERSION}\/_\/${NEW_VERSION}\/_g < $file > $file_bk; cp $file_bk $file

	rm -f $file_bk

}

#Pass branch name as argument
function update_branch() {
    local curr_branch=$1
    git checkout $curr_branch
	git pull
    found_files=""
    firstdiff=1
    for f in `ls *.conf`
    do
        echo "Updating $f in branch $curr_branch ..."
        update_file $f $curr_branch
        found_files="$found_files $f"
        echo "***************** Diff: " $curr_branch - $f" ********************"
        checkdiff=`git diff $f`
        if [ "$checkdiff" = "" ]
        then
            echo ">>>>>   WARNING: NO DIFF FOUND"
            #Save names of branches that have no diff
            echo "$curr_branch" >> ${failed_out}.$f
        else
            #Get all diff output in one file
            if [ "$firstdiff" = "1" ]
            then
                echo "#================" >> $fulldiff
                echo "#====== $curr_branch   =====" >> $fulldiff
                echo "#================" >> $fulldiff
            fi
            echo "$checkdiff" >> $fulldiff
            firstdiff=0
        fi
        git diff $f
        echo "******************************************************"
        echo
    done

	
    #When testing, the git commands will be noops
	$testprefix git add $found_files
	$testprefix git commit -m "updated versions for "$NEW_VERSION" release"
	$testprefix git push
    if [ "$testprefix" != "" ]
    then
        echo "The git commands above WOULD HAVE BEEN run, but don't worry nothing was pushed to git"
        #Make a backup of the file for debugging later
        for f in $found_files
        do
            saved_file=`echo "$f" | sed "s/\./-$curr_branch./"`
            cp $f $diffdir/$saved_file
        done
        echo -n "Finished branch $curr_branch . $pause_str"
        if [ "$pause_str" != "" ]
        then
            read -s proceed
        else
            echo
            echo "----"
        fi
        git checkout .
    fi
}
#====================  end functions ====================================== 
#====================  Main code starts here ============================== 

testprefix=""
pause_str=""
delete_branches
if [ "$1" = "test" ]
then
    testprefix="echo "
    shift
    if [[ "$1" = "RELEASE" || "$1" = "INF" ]]
    then
        #In test mode, you can pause after each branch, but that means hitting enter a lot
        echo "Do you want to pause after changing each branch? "
        read promptval
        promptval=`echo $promptval | tr '[A-Z]' '[a-z]'`
        if [[ "$promptval" = "y" || "$promptval" = "yes" ]]
        then
            pause_str="Press enter to continue... "
        fi
    fi
fi
BRANCH=$1
CUR_VERSION=$2
echo CUR_VERSION: $CUR_VERSION
CUR_VERSION_MINOR=$(echo $CUR_VERSION| cut -d'.' -f 2)
CUR_VERSION_MAJOR=$(echo $CUR_VERSION| cut -d'.' -f 1)

NEW_VERSION=${3:-$(echo $CUR_VERSION_MAJOR.$(expr $CUR_VERSION_MINOR + 1))}
echo NEW_VERSION: $NEW_VERSION
PATCH_VERSION=$(echo $NEW_VERSION| cut -d'.' -f 3)
if [ "$PATCH_VERSION" != "" ]
then
    PATCH_VERSION=".${PATCH_VERSION}"
fi
NEW_VERSION_MINOR=$(echo $NEW_VERSION| cut -d'.' -f 2)
NEW_VERSION_MAJOR=$(echo $NEW_VERSION| cut -d'.' -f 1)

FUT_VERSION=$(echo $NEW_VERSION_MAJOR.$(expr $NEW_VERSION_MINOR + 1))"-SNAPSHOT"
echo FUT_VERSION: $FUT_VERSION
NEW_ALT_VERSION=$(echo $CUR_VERSION_MAJOR.$(expr $CUR_VERSION_MINOR + 1))
echo NEW_ALT_VERSION: $NEW_ALT_VERSION

NEW_VERSION_MINOR=$(echo $NEW_VERSION| cut -d'.' -f 2)
NEW_VERSION_MAJOR=$(echo $NEW_VERSION| cut -d'.' -f 1)

echo 'Map '$NEW_VERSION'-xxx-SNAPSHOT to '$FUT_VERSION''
if [[ $NEW_ALT_VERSION != $NEW_VERSION ]]; then
	echo 'Map '$NEW_ALT_VERSION'-xxx-SNAPSHOT to '$FUT_VERSION''
fi
echo 'Map '$CUR_VERSION' to '$NEW_VERSION'.'

if [ "$BRANCH_LIST" = "" ]
then
    BRANCH_LIST=ref_branch_list
else
    #Do not include inf if custom branches provided
    inf_file=
fi
echo "Default branch list is $BRANCH_LIST (set BRANCH_LIST to override), inf included=$inf_file"

echo "Hit enter to continue (or ctrl c to exit)"
read prompt_ignore

stash_changes $testprefix
stashed=$?
if [ "$stashed" = "2" ]
then
    exit
fi
git pull
diffdir=output/diff_files
fulldiff=output/full_diff.diff
failed_out=output/failed_branches

rm -Rf $diffdir
mkdir -p $diffdir
rm -f ${failed_out}*
rm -f $fulldiff


iterate_branches $BRANCH "$BRANCH_LIST" "update_branch" 

restore_state $stashed

#Output any branches that had no diffs
for f in `ls ${failed_out}*`
do
    outfile=`echo $f | sed "s#${failed_out}.##"`
    echo "****** WARNING ****"
    echo "The following branches had no diffs for $outfile"
    cat $f
    echo "*******************"
done
echo "Finished! The diff for the branches can be found in $fulldiff (files in $diffdir) "
