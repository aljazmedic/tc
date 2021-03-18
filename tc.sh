#!/bin/bash
#?Usage:
#? tc.sh [-h] [<pot_do_testov>] <glavni_c_program> [<dodatni_c_program_1> ...]
#?  [-t | -T <n> | -f <s>]
#?
#? -h, --help             Help
#? -t, --timed            Display running time
#? -T <n>, --timeout <n>  Specify max timeout time 
#?                        Default: '1'
#? -f <s>, --format <s>   Format for testing files
#?                        Default: 'test'

TC_PATH="."
FILE_PREFIX="test"
TIMEOUT_VAL=1 #in seconds
hardTimeoutValue=$((TIMEOUT_VAL+2))
TIMED=0

### CONSTANTS, inspired by FRI Makefile
CC="gcc"
CCFLAGS="-std=c99 -pedantic -Wall"
LIBS="-lm"
DIFF_TIMEOUT=0.5
LOG="/dev/null"

TIMEOUT_SIGNAL=124
SHELL="/bin/bash"
OK_STRING="\033[1;32mOK\033[0;38m"
FAILED_STRING="\033[1;31mfailed\033[0;38m"
TIMEOUT_STRING="\033[1;35mtimeout\033[0;38m"

### ARGUMENT PARSING
INCLUDE_FILES="" #Additional files to get compiled
POS_PARAMS=""

while (( "$#" )); do
  case "$1" in
    -h|--help)
        echo " tc.sh [-h] [<pot_do_testov>] <glavni_c_program> [<dodatni_c_program_1> ...]"
        echo "    [-t | -T <n> | -f <s>] "
        echo " -h, --help             Pomoč"
        echo " -t, --timed            Izpis časa"
        echo " -T <n>, --timeout <n>  Največje dovoljeno število sekund"
        echo "                        izvajanja programa"
        echo "                        Privzeto: '1'"
        echo " -f <s>, --format <s>   Format datotek za testiranje."
        echo "                        Privzeto: 'test'"
      exit 0
      ;;
    -t|--timed)
      TIMED=1
      shift
      ;;
    -T|--timeout)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        TIMEOUT_VAL=$2
        shift 2
      else
        echo "Error: Manjka vrednost za $1" >&2
        exit 1
      fi
      ;;
    -f|--format)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        FILE_PREFIX=$2
        shift 2
      else
        echo "Error: Manjka vrednost za $1" >&2
        exit 1
      fi
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Nepricakovan argument $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      POS_PARAMS="$POS_PARAMS $1"
      shift
      ;;
  esac
done
# set positional arguments in their proper place
eval set -- "$POS_PARAMS"

# Check for action
ACTION="$1"
case "${ACTION^^}" in
    CLEAN)  #
        shift #consume action arg
        if [ $# -ge 1 ]; then
            TC_PATH="$1"
        else
            TC_PATH="."
        fi
    ;;
    *) #default is to test
        if [ $# -gt 1 ]; then
            # [<path>] <main> [<additional> ...]
            TC_PATH="$1"
            shift
        fi
        # main_file
        MAIN_FILE="$1"
        shift
        INCLUDE_FILES="$@"
     ;;
esac

# absolute path for safety
TC_PATH=$(realpath "$TC_PATH")



### HELPER FUNCTIONS

function remove_leading_dotslash { echo "$@" | sed -e "s/^\.\///g"; }
function get_test_num { echo "$1" | grep -Po '(?<=test)([0-9]+)(?=.c)'; }
function rm_extension { echo "$1" | grep -Po '(.*)(?=\.)'; }
function get_base_name { rm_extension $(basename "$1"); }



### CLEANING


if [[ ${ACTION^^} = "CLEAN" ]]; then
    file_matches=$(find $TC_PATH -maxdepth 1 -type f | grep -E $FILE_PREFIX[0-9]+\.\(res\|diff\) ) # Search for tests
    
    echo "$file_matches"
    if [ $(echo "$file_matches" | wc -w) = "0" ]; then
        echo "Nothing to remove"
        exit 0
    fi
    read -p "Remove all [y/n]? " ans
    if [ ${ans^^}  = "Y" ]; then
        #rm "$file_matches"
        for f in "$file_matches"; do
            rm $(remove_leading_dotslash "$f")
        done
    fi
    exit 0
fi


### OS-specific

function get_os_type
{
    case "$OSTYPE" in
        #solaris*) echo "SOLARIS" ;;
        darwin*)  echo "OSX" ;; #
        linux*)   echo "LINUX" ;; #
        #bsd*)     echo "BSD" ;;
        msys*)    echo "WINDOWS" ;;
        *)        echo "UNSUPPORTED" ;;
    esac
}

os_type=$(get_os_type)
if [ "$os_type" = "LINUX" ]; then
    get_exe() { r=$(realpath $1); chmod +x $r; echo "$r"; }
elif [ "$os_type" = "OSX" ]; then # TODO: gdate, gdiff, gtimeout?
    get_exe() { r=$(realpath $1); chmod +x $r; echo "$r"; }
elif [ "$os_type" = "WINDOWS" ]; then
    get_exe() {  r=$(realpath $1); echo "$r.exe"; }
else 
    echo "Unsupported os :(" >&2 #)
    exit 1
fi

### COMPILING FUNCTION

function compile_cc {
    abs_target=$(realpath "$1")
    base_name=$(rm_extension $abs_target)
    #echo "$CC $CCFLAGS $INCLUDE_FILES $abs_target -o $base_name $LIBS"
    $CC $CCFLAGS $INCLUDE_FILES $abs_target -o $base_name $LIBS
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo -e "Compiling files $files $FAILED_STRING, exiting." >&2
        exit 1
    fi
    echo "Compiled $(basename "$1")"
}


### DETECTING TYPE OF TESTING

test_c_files=$(find $TC_PATH -maxdepth 1 -type f | grep -E $FILE_PREFIX[0-9]+\.c) # Search for tests
test_in_files=$(find $TC_PATH -maxdepth 1 -type f | grep -E $FILE_PREFIX[0-9]+\.in) # Search for tests

test_c_n=$(echo "$test_c_files" | wc -w | bc)
test_in_n=$(echo "$test_in_files" | wc -w | bc)

if [ $test_c_n -eq 0 ] && [ $test_in_n -eq 0 ];then
    echo "No tests found." >&2
    exit 1
elif [ $test_in_n -eq 0  ]; then
    echo "Using $test_c_n .c files."
    type_testing=2
elif [ $test_c_n -eq 0  ]; then
    echo "Using $test_in_n .in files."
    if [ -z $MAIN_FILE ]; then
        echo "Missing main c file!" >&2
        exit 1
    fi
    type_testing=1
else
    echo "Found differend tests. Select type of testing"
    echo "[1] #$test_in_n .in files"
    echo "[2] #$test_c_n  .c files?"
    read -p "> " type_testing
    if [ "$type_testing" != "1" ] && [ "$type_testing" != "2" ];then
        echo "Invalid option: \"$type_testing\", exiting." >&2
        exit 1  
    fi
fi

### CONDITIONAL COMPILING

echo " == COMPILING =="

if [ "$type_testing" == "1" ];then
    compile_cc "$MAIN_FILE"
    exe_name=$(get_exe $(rm_extension $MAIN_FILE))
    test_cases="$test_in_files"
elif [ "$type_testing" == "2" ]; then
    INCLUDE_FILES="$MAIN_FILE $INCLUDE_FILES" #Main file is just an include
    for file in $test_c_files; do
        compile_cc "$file"
    done
    test_cases="$test_c_files"
fi

all_tests=0
ok_tests=0
echo
echo " == TESTING =="
for test_case in $test_cases
do
    # Get variables for this case
    i=$(get_test_num "$test_case")
    base_name=$(rm_extension "$test_case")
    file_name=$(basename $base_name)
    #echo "$base_name $test_case $file_name"
    cbase_name=$(realpath "$base_name")
    out_file="$base_name.out"

    # Check if .out exists
    if ! [ -f  "$out_file" ]; then
        echo "Missing $out_file for $test_case"
        continue
    else
        if [ "$type_testing" == "2" ];then
            ### TESTING .c .out
            exe_name=$(get_exe $cbase_name)
            start_time=$(date +%s.%N)
            timeout -k $hardTimeoutValue $TIMEOUT_VAL $exe_name > $cbase_name.res 2> /dev/null
            exit_code=$?
            end_time=$(date +%s.%N)
        else
            ### TESTING .in, .out
            in_file="$cbase_name.in"
            if ! [ -f  "$in_file" ]; then
                echo "Missing $in_file for $test_case"
                continue
            fi
            start_time=$(date +%s.%N)
            timeout -k $hardTimeoutValue $TIMEOUT_VAL $exe_name < $in_file > $cbase_name.res 2> /dev/null
            exit_code=$?
            end_time=$(date +%s.%N)
        fi
        if [[ $exit_code == $TIMEOUT_SIGNAL ]]; then
            echo -e "$filenname -- $TIMEOUT_STRING [> $TIMEOUT_VAL s]"
        else
            if [ $TIMED -eq 1 ]; then
                timeDifference=" [$(echo "scale=2; $end_time - $start_time" | bc | awk '{printf "%.2f\n", $0}') s]"
            else
                timedDifference=""
            fi
            timeout -k $DIFF_TIMEOUT $DIFF_TIMEOUT diff --ignore-trailing-space $base_name.out $base_name.res > $base_name.diff
            exit_code=$?
            if [[ $exit_code == $TIMEOUT_SIGNAL ]]; then
                echo -e "${file_name^} -- $FAILED_STRING (diff errored)$timeDifference"
            elif [ -s "$base_name.diff" ]; then
                echo -e "${file_name^} -- $FAILED_STRING$timeDifference"
            else
                echo -e "${file_name^} -- $OK_STRING$timeDifference"
                ((ok_tests+=1))
            fi
        fi
        ((all_tests+=1))
    fi
done

echo "Result $ok_tests/$all_tests"
