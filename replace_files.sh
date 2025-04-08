#!/bin/bash 
# $1: Current Version
# $2: Next Version (Optional)

scriptname=./`basename "$0"`

if [ -z "$1" ]; then
	echo 
	echo "Usage:  $scriptname [test] BRANCH filename"
	echo "           BRANCH: Name of the branch to update or RELEASE to update all release branches."
    echo "           This will replace the specified file in the specified branches with the version from the main branch"	
    echo "           By prefixing the arguments with test, it will be a dry run - NO commits will be made"
	echo "Example:"
	echo "        $scriptname RELEASE Jenkinsfile"
	echo "        $scriptname test zelda Jenkinsfile"
	echo "        $scriptname test zelda v2/"
	echo
    exit 1
fi

echo
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR
#====================  Start functions ============================== 
#Takes in the branch name(which can be RELEASE), the file with the list of branches, and the function to execute
function iterate_branches(){
    BRANCH=$1
    branch_file=$2
    callback=$3
    if [[ $BRANCH == 'RELEASE' ]]; then
        #The ref_branch_list has the list of branches - note the use of file separator when iterating 
        IFS_OLD=$IFS
        IFS=$'\n'
        for i in `cat $branch_file`
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
                echo "Stopping - please deal with your uncommitted changes to main"
                return 2
            fi
            git stash
            return 1
        fi
    fi
    return 0

}

function delete_branches(){
    echo "Do you want to delete all local branches except main (this will speed things up)? "
    read promptval
    promptval=`echo $promptval | tr '[A-Z]' '[a-z]'`
    if [[ "$promptval" = "y" || "$promptval" = "yes" ]]
    then
        git branch | grep -v main | xargs git branch -D
    fi
}

#Pass in 0 or 1 if changes were stashed
function restore_state(){
    stashed=$1
    #Finally switch back to main branch
    git checkout main

    #In test mode, if changes were stashed, recover them
    if [ "$stashed" != "0" ]
    then
        echo "Recovering changes"
        git stash pop
    fi
}


#Pass branch name as argument
function update_branch() {
    git checkout $1
	git pull
    found_files=""
    f=$file
    echo "Updating $f in branch $1 ..."
    rm -Rf $f
    cp -av $main_file $f
    found_files="$found_files $f"
    echo "***************** Diff: " $1 - $f" ********************"
    checkdiff=`git diff $f`
    if [ "$checkdiff" = "" ]
    then
        echo ">>>>>   WARNING: NO DIFF FOUND"
        #Save names of branches that have no diff
        echo "$1" >> ${failed_out}.$f
    fi
    git diff $f
    echo "******************************************************"
    echo

	
    #When testing, the git commands will be noops
	$testprefix git add $found_files
	$testprefix git commit -m "replaced file $file from main"
	$testprefix git push
    if [ "$testprefix" != "" ]
    then
        echo "The git commands above WOULD HAVE BEEN run, but don't worry nothing was pushed to git"
        #Make a backup of the file for debugging later
        for f in $found_files
        do
            saved_file=`echo "$f" | sed "s/\./-$1./"`
            cp $f $diffdir/$saved_file
        done
        echo -n "Finished branch $1 . $pause_str"
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
    #In test mode, you can pause after each branch, but that means hitting enter a lot
    echo "Do you want to pause after changing each branch? "
    read promptval
    promptval=`echo $promptval | tr '[A-Z]' '[a-z]'`
    if [[ "$promptval" = "y" || "$promptval" = "yes" ]]
    then
        pause_str="Press enter to continue... "
    fi
    shift
fi
BRANCH=$1
if [ "$2" = "" ]
then
    echo "You must specify filename to update"
    exit

fi
file=$2
main_file=main_$file

rm -Rf $main_file
cp -av $file $main_file
stash_changes $testprefix
stashed=$?
if [ "$stashed" = "2" ]
then
    exit
fi
git pull
diffdir=output/diff_files
failed_out=output/failed_branches

rm -Rf $diffdir
mkdir -p $diffdir
rm -f ${failed_out}*



iterate_branches $BRANCH "ref_branch_list" "update_branch" 

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
echo "Finished! The diff files for the branches can be found in $diffdir"
