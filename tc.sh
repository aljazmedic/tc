#!/bin/bash
#?Usage:
#? tc.sh [-h] [clean] [<tests_path>] <main_c_program> [<included_c_programs> ...]
#?    [-t | -T <n> | -f <s> | -n &ltI> ] 
#? actions:
#?    clean               Delete diff and res files
#? -h, --help             Help on command usage
#? -t, --timed            Display time taken to execute the code
#? -T <n>, --timeout <n>  Larges amount of seconds allowed before
#?                        timeout
#?                        Default: 1
#? -n <I>                 Interval range of tests
#?                        using ~ instead of - selects complement
#?                        a-b   (a, b]
#?                        a-    (a, ...)
#?                         -b   (..., b]
#?                         ~b   (b, ...)
#?                        a~b   (..., a]U(b, ...)
#?                        Default: '-' (all)
#? -f <s>, --format <s>   Format of test data prefix
#?                        Default: 'test'
#? -e <f>, --entry <f>    Default entry function for c file
#?                        Default: 'main'

TC_PATH="."
TESTS=""
ENTRY_FUNCTION="main"
FILE_PREFIX="test"
TIMEOUT_VAL=1 #in seconds
KILL_AFTER=$((TIMEOUT_VAL+2))
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

### CHECKING IF ALL THE PROGRAMS EXIST
REQUIRED_PROGRAMS=("awk" "basename" "bc" "cut" "date" "diff" "find" "grep" "realpath" "sort" "timeout" "$CC")

for PROGRAM in ${REQUIRED_PROGRAMS[@]}; do
    if ! command -v $PROGRAM &> /dev/null; then
        echo "Error: '$PROGRAM' not found, exiting" >&2
        exit 1
    fi
done

function print_help
{
    echo " tc.sh [-h] [clean] [<tests_path>] <main_c_program> [<included_c_programs> ...]"
    echo "    [-t | -T <n> | -f <s> | -n &ltI> ] "
    echo
    echo " actions:"
    echo "    clean               Delete diff and res files"
    echo
    echo " -h, --help             Help on command usage"
    echo " -t, --timed            Display time taken to execute the code"
    echo " -T <n>, --timeout <n>  Larges amount of seconds allowed before"
    echo "                        timeout"
    echo "                        Default: 1"
    echo " -n <I>                 Interval range of tests"
    echo "                        using ~ instead of - selects complement"
    echo "                        a-b   (a, b]"
    echo "                        a-    (a, ...)"
    echo "                         -b   (..., b]"
    echo "                         ~b   (b, ...)"
    echo "                        a~b   (..., a]U(b, ...)"
    echo "                        Default: '-' (all)"
    echo " -f <s>, --format <s>   Format of test data prefix"
    echo "                        Default: 'test'"
    echo " -e <f>, --entry <f>    Default entry function for c file"
    echo "                        Default: 'main'"
}


### ARGUMENT PARSING
POS_PARAMS=""

while (( "$#" )); do
  case "$1" in
    -h|--help)
      print_help
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
        echo "Error: Missing value for $1" >&2
        print_help
        exit 1
      fi
      ;;
    -e|--entry)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        ENTRY_FUNCTION=$2
        shift 2
      else
        echo "Error: Missing value for $1" >&2
        print_help
        exit 1
      fi
      ;;
    -f|--format)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        FILE_PREFIX=$2
        shift 2
      else
        echo "Error: Missing value for $1" >&2
        print_help
        exit 1
      fi
      ;;
    -n)
        if [ -n "$2" ]; then
            if [[ $2 =~ ^([1-9][0-9]*)?(\-|\~)([1-9][0-9]*)?$ ]]; then
                if [[ ${#2} -le 1 ]]; then # CASE '-n -'' or '-n ~' 
                    TESTS=""
                else
                    TESTS=$2
                fi
                shift 2
            else
                echo "Error: Invalid value for $1" >&2
                print_help
                exit 1
            fi
        else
            echo "Error: Missing value for $1" >&2
            print_help
            exit 1
        fi
    ;;
    -*|--*=) # unsupported flags
      echo "Error: Unexpected argument $1" >&2
      print_help
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

# Check for action/-s
ACTION="$1"
case "${ACTION^^}" in
    CLEAN)  #
        shift # consume action arg
        if [ $# -gt 1 ]; then
            echo "Invalid number of arguments" >&2
            print_help
            exit 1
        elif [ $# -eq 1 ]; then
            TC_PATH="$1" # CASE tc clean <path>
        else
            TC_PATH="."  # CASE tc clean
        fi
    ;;
    *) #default is to test
        if [ $# -gt 1 ]; then
            TC_PATH="$1" # CASE tc [<path>] <main> [<additional> ...]
            shift
        fi
        # main_file
        MAIN_FILE="$1"
        shift
        INCLUDE_FILES="$@" # Additional files to get compiled
     ;;
esac


### VALIDATE

## Validate path

if [ ! -d "$TC_PATH" ]; then
    echo "Error: '$TC_PATH' is not a directory" >&2
    print_help
    exit 1
fi
# absolute path for safety
TC_PATH=$(realpath "$TC_PATH")


### HELPER FUNCTIONS

function remove_leading_dotslash { echo "$@" | sed -e "s/^\.\///g"; }
function get_test_num {
    echo "$@" | grep -Po "(?<=$FILE_PREFIX)([0-9]+)(?=.c)";
    }
function rm_extension { echo "$@" | grep -Po "(.*)(?=\.)"; }
function get_base_name { rm_extension $(basename "$1"); }



### CLEANING


if [[ ${ACTION^^} = "CLEAN" ]]; then
    file_matches=$(find $TC_PATH -maxdepth 1 -type f | grep -E $FILE_PREFIX[0-9]+\.\(res\|diff\) | sort) # Search for tests
    
    if [ $(echo "$file_matches" | wc -w) = "0" ]; then
        echo "Nothing to remove"
        exit 0
    fi
    echo "$file_matches"
    echo "Remove all [y/n]?"
    read -p "> " ans
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
    echo "Unsupported OS" >&2 #
    exit 1
fi

### COMPILING FUNCTION

function compile_cc {
    abs_target=$(realpath "$1")
    base_name=$(rm_extension $abs_target)
    base_target=$(basename "$1")
    # echo "$CC $CCFLAGS $INCLUDE_FILES $abs_target -o $base_name $LIBS --entry=$ENTRY_FUNCTION"
    $CC $CCFLAGS $INCLUDE_FILES $abs_target -o $base_name $LIBS --entry=$ENTRY_FUNCTION
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo -e "Compiling file $base_target $FAILED_STRING, exiting" >&2
        exit 1
    fi
    echo "Compiled $base_target"
}


### DETECTING TYPE OF TESTING

test_c_files=$(find $TC_PATH -maxdepth 1 -type f | grep -E $FILE_PREFIX[0-9]+\.c  | sort ) # Search for tests
test_in_files=$(find $TC_PATH -maxdepth 1 -type f | grep -E $FILE_PREFIX[0-9]+\.in  | sort ) # Search for tests

test_c_n=$(echo "$test_c_files" | wc -w | bc)
test_in_n=$(echo "$test_in_files" | wc -w | bc)

if [ $test_c_n -eq 0 ] && [ $test_in_n -eq 0 ];then
    echo "No tests found in $TC_PATH." >&2
    exit 1
elif [ $test_in_n -eq 0  ]; then
    echo "Using $test_c_n $FILE_PREFIX.c files."
    type_testing=2
elif [ $test_c_n -eq 0  ]; then
    echo "Using $test_in_n $FILE_PREFIX.in files."
    if [ -z $MAIN_FILE ]; then
        echo "Missing main c file!" >&2
        exit 1
    fi
    type_testing=1
else
    echo "Found differend tests. Select type of testing"
    echo "[1] #$test_in_n $FILE_PREFIX.in files"
    echo "[2] #$test_c_n  $FILE_PREFIX.c files?"
    read -p "> " type_testing
    if [ "$type_testing" != "1" ] && [ "$type_testing" != "2" ];then
        echo "Invalid option: \"$type_testing\", exiting." >&2
        exit 1  
    fi
fi

if [ "$type_testing" == "1" ];then
    test_cases="$test_in_files"
elif [ "$type_testing" == "2" ]; then
    test_cases="$test_c_files"
fi


### FILTER TEST CASES

if [ ! -z "$TESTS" ]; then
    CUT_FLAGS=""
    if [[ $TESTS == *"~"* ]];then
        CUT_FLAGS="$CUT_FLAGS --complement"
        TESTS=${TESTS/"~"/"-"} # Replace compliment
    fi
    # echo "$CUT_FLAGS $TESTS"
    test_cases=$(echo "$test_cases" | cut -d$'\n' -f$TESTS $CUT_FLAGS)
    unset CUT_FLAGS
fi
# echo "$test_cases"



### CONDITIONAL COMPILING

echo " == COMPILING =="

if [ "$type_testing" == "1" ];then
    compile_cc "$MAIN_FILE"
    exe_name=$(get_exe $(rm_extension $MAIN_FILE))
elif [ "$type_testing" == "2" ]; then
    INCLUDE_FILES="$MAIN_FILE $INCLUDE_FILES" # Main file is just an include
    for file in $test_cases; do
        compile_cc "$file"
    done
fi


all_tests=0
ok_tests=0
echo
echo " == TESTING =="
for test_case in $test_cases
do
    # Get variables for this case
    base_name=$(rm_extension "$test_case")
    file_name=$(basename $base_name)
    #i=$(get_test_num $file_name)
    #echo "$i $file_name"
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
            timeout -k $KILL_AFTER $TIMEOUT_VAL $exe_name > $cbase_name.res 2> /dev/null
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
            timeout -k $KILL_AFTER $TIMEOUT_VAL $exe_name < $in_file > $cbase_name.res 2> /dev/null
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
