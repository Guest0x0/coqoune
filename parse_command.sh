#!/bin/sh

# $1, $2: start line number and column offset
# read from stdin a buffer (with complete first line), parse it and output it by commands.
# stdout (loop until buffer end):
#     (first line) space-separated line and column of the end position
#     (second line) the command itself, with newlines escaped

line=$1
# The start column offset of input
col_offset=$2

# [buffer] is a cached line of input.
# For performance, input is read lazily.
IFS='' read -r buffer

# the current parsing offset for [buffer]
(( i = col_offset - 1 ))

output=""

# an array tracking current parsing state.
# the first element (if any) corresponds to the nearest scope.
# "s": inside a string
# "c": inside a comment (can be nested)
# "e": at the beginnig of an expression.
# "-" "*" "+": bullets
# nothing: inside a expression, but not at its beginning.
state_list=("e")

# fetch the next line, if the current one is processed.
function ask_more_input() {
    # since the command may not contain the last line in complete,
    # every line is put into output until it is completely parsed.
    content="${buffer:(col_offset - 1)}"
    if [ -n "$output" ]; then
        output="$output\n$content"
    else
        output="$content"
    fi
    # new lines are read from the first column.
    # skip empty lines
    while IFS='' read -r buffer; do
        (( line = line + 1 ))
        if [ -n "$buffer" ]; then
            col_offset=1
            i=0
            break
        fi
    done
}

function output() {
    echo $line $i
    [ -n "$output" ] && printf "%s%s" "$output" "\n"
    [ "$i" -gt 0 ] && printf "%s" "${buffer:(col_offset - 1):(i + 1 - col_offset)}"
    printf "\n"

    (( col_offset = i + 1 ))
    # if '.' is followed by '\n', the previous line will be appended
    # to [output], hence clean output after this.
    [ "$i" -ge "${#buffer}" ] && ask_more_input
    output=""
}

while [ 1 ]; do
    [ "$i" -ge "${#buffer}" ] && ask_more_input
    # no more input, but parsing not done yet.
    if [ -z "$buffer" ]; then
        exit 0
    fi
    case ${state_list[0]} in
        ( 's' ) # inside a string
            if [ "${buffer:i:2}" = '""' ]; then
                (( i = i + 2 ))
            elif [ "${buffer:i:1}" = '"' ]; then
                state_list=(${state_list[@]:1})
                (( i = i + 1 ))
            else
                (( i = i + 1 ))
            fi
            ;;
        ( 'c' ) # inside a comment
            if [ "${buffer:i:1}" = '"' ]; then
                state_list=("s" ${state_list[@]})
                (( i = i + 1 ))
            elif [ "${buffer:i:2}" = '(*' ]; then
                state_list=("c" ${state_list[@]})
                (( i = i + 2 ))
            elif [ "${buffer:i:2}" = '*)' ]; then
                state_list=(${state_list[@]:1})
                (( i = i + 2 ))
            else
                (( i = i + 1 ))
            fi
            ;;
        ( '-' | '*' | '+' ) # bullets
            if [ "${buffer:i:1}" = "${state_list[0]}" ]; then
                (( i = i + 1 ))
            else
                output
                state_list=("e" ${state_list[@]:1})
            fi
            ;;
        ( * ) # inside expr
            if [ "${buffer:i:1}" = '"' ]; then
                state_list=("s" ${state_list[@]})
                (( i = i + 1 ))
            elif [ "${buffer:i:2}" = '(*' ]; then
                state_list=("c" ${state_list[@]})
                (( i = i + 2 ))
            elif [ "${buffer:i:1}" = '.' ]; then
                (( i = i + 1 ))
                # '.' marks the end of a command, iff it is followed by blank characters.
                case "${buffer:i:1}" in
                    ( " " | "\t" | "" )
                        output
                        if [ -z "${state_list[0]}" ]; then
                            state_list=("e" ${state_list[@]})
                        fi
                        ;;
                    ( * )
                        (( i = i + 1 ))
                        ;;
                esac
            # special care for beginning of expressions
            elif [ "${state_list[0]}" = 'e' ]; then
                case "${buffer:i:1}" in
                    ( " " | "\t" | "" )
                        (( i = i + 1 ))
                        ;;
                    ( '-' | '*' | '+' )
                        state_list=("${buffer:i:1}" ${state_list[@]})
                        (( i = i + 1 ))
                        ;;
                    ( '{' | '}' )
                        (( i = i + 1 ))
                        output
                        ;;
                    ( * )
                        state_list=(${state_list[@]:1})
                        (( i = i + 1 ))
                        ;;
                esac
            else
                (( i = i + 1 ))
            fi
            ;;
    esac
done
