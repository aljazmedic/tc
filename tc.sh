#!/usr/bin/bash
#?Usage:
#? .in/.out
#? test.sh <ime_datoteke_c> [<dodatna_c1> <dodatna_c2> ...]
#?
#? .c/.out
#? test.sh [<dodatna_c1> <dodatna_c2> ...]

if [ "$1" = "-h" ]; then
    echo "Uporaba:"
    echo ".in/.out"
    echo "test.sh <ime_datoteke_c> [<dodatna_c1> <dodatna_c2> ...]"
    echo 
    echo ".c/.out"
    echo "test.sh [<dodatna_c1> <dodatna_c2> ...]"
    exit 0
fi

file_prefix="test"
timeoutValue=1
hardTimeoutValue=$((timeoutValue+2))

if [ "$1" = "clean" ]; then
    generated=$(find . -maxdepth 1 -type f | grep -E $file_prefix[0-9]+\.\(res\|diff\) ) # Search for tests
    read -p "Remove [y/n]?"  
    echo "$generated"
    exit 0
fi

### Constants, inspired by fri Makefile
CC="gcc"
CFLAGS="-std=c99 -pedantic -Wall"
LIBS="-lm"

DIFF_TIMEOUT=0.5

TIMEOUT_SIGNAL=124
SHELL="/bin/bash"
OK_STRING="\033[1;32mOK\033[0;38m"
FAILED_STRING="\033[1;31mfailed\033[0;38m"
TIMEOUT_STRING="\033[1;35mtimeout\033[0;38m"

function remove_leading_dotslash { echo "$@" | sed -e "s/^\.\///g"; }
function get_test_num { echo "$1" | grep -Po '(?<=test)([0-9]+)(?=.c)'; }
function get_base_name { echo "$1" | grep -Po '(.*)(?=\.)'; }
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

### OS-specific
os_type=$(get_os_type)
if [ "$os_type" = "LINUX" ]; then
    get_exe() { chmod +x $1; echo "./$1"; }
elif [ "$os_type" = "OSX" ]; then # TODO: gdate, gdiff, gtimeout?
    get_exe() { chmod +x $1; echo "./$1.sh"; }
elif [ "$os_type" = "WINDOWS" ]; then
    get_exe() { echo "./$1.exe"; }
else 
    echo "Unsupported os."
    exit 0
fi

function compile_cc {
    files=$(remove_leading_dotslash "$@")
    base_name=$(get_base_name $(remove_leading_dotslash "$1"))
    #echo "$CC $CCFLAGS $@ -o $base_name $LIBS"
    $CC $CCFLAGS $@ -o $base_name $LIBS
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo -e "Compiling files $files $FAILED_STRING, exiting."
        exit 1
    fi
    echo "Compiled ($exit_code) $base_name"
}


## DETECTING TYPE OF TESTING
test_c_files=$(find . -type f | grep -E $file_prefix[0-9]+\.c) # Search for tests
test_in_files=$(find . -type f | grep -E $file_prefix[0-9]+\.in) # Search for tests

test_c_n=$(echo "$test_c_files" | wc -w | bc)
test_in_n=$(echo "$test_in_files" | wc -w | bc)

if [ $test_c_n -eq 0 ] && [ $test_in_n -eq 0 ];then
    echo "No tests found."
    exit 1
elif [ $test_in_n -eq 0  ]; then
    echo "Using $test_c_n .c files."
    type_testing=2
elif [ $test_c_n -eq 0  ]; then
    echo "Using $test_in_n .in files."
    type_testing=1
else
    echo "Select type of testing"
    echo "[1] ($test_in_n) .in files"
    echo "[2] ($test_c_n)  .c files?"
    read -p "> " type_testing
    if [ "$type_testing" != "1" ] && [ "$type_testing" != "2" ];then
        echo "Invalid option: \"$type_testing\", exiting."
        exit 1  
    fi
fi

if [ "$type_testing" == "1" ];then
    main_name="$1"
fi


echo " == COMPILING =="

# conditional compiling
if [ "$type_testing" == "1" ];then
    compile_cc "$main_name"
    test_cases="$test_in_files"
elif [ "$type_testing" == "2" ]; then
    for file in $test_c_files; do
        compile_cc "$file $@"
    done
    test_cases="$test_c_files"
fi

all_tests=0
ok_tests=0
echo
echo " == TESTING =="
for test_case in $test_cases
do
    i=$(get_test_num "$test_case")
    base_name=$(get_base_name "$test_case")
    cbase_name=$(remove_leading_dotslash "$base_name")
    out_file="$base_name.out"

    # Check if .out exists
    if ! [ -f  "$out_file" ]; then
        echo "Missing $out_file for $test_case"
        continue
    else
        if [ "$type_testing" == "2" ];then
            # Testing .c .out
            exe_name=$(get_exe $cbase_name)
            start_time=$(date +%s.%N)
            timeout -k $hardTimeoutValue $timeoutValue $exe_name > $cbase_name.res 2> /dev/null
            exit_code=$?
            end_time=$(date +%s.%N)
        else
            # Testing .in, .out
            in_file="$cbase_name.in"
            if ! [ -f  "$in_file" ]; then
                echo "Missing $in_file for $test_case"
                continue
            fi
            exe_name=$(get_exe $(get_base_name $main_name))
            start_time=$(date +%s.%N)
            timeout -k $hardTimeoutValue $timeoutValue $exe_name < $in_file > $cbase_name.res 2> /dev/null
            exit_code=$?
            end_time=$(date +%s.%N)
        fi
        if [[ $exit_code == $TIMEOUT_SIGNAL ]]; then
            echo -e "$cbase_name -- $TIMEOUT_STRING [> $timeoutValue s]"
        else
            timeDifference=$(echo "scale=2; $end_time - $start_time" | bc | awk '{printf "%.2f\n", $0}')
            timeout -k $DIFF_TIMEOUT $DIFF_TIMEOUT diff --ignore-trailing-space $base_name.out $base_name.res > $base_name.diff
            exit_code=$?
            if [[ $exit_code == $TIMEOUT_SIGNAL ]]; then
                echo -e "$cbase_name -- $FAILED_STRING (diff errored) [$timeDifference s]"
            elif [ -s "$base_name.diff" ]; then
                echo -e "$cbase_name -- $FAILED_STRING [$timeDifference s]"
            else
                echo -e "$cbase_name -- $OK_STRING [$timeDifference s]"
                ((ok_tests+=1))
            fi
        fi
        ((all_tests+=1))
    fi
done

echo "Rezultat $ok_tests/$all_tests"
