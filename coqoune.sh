#!/bin/sh

coqoune_path=${0%/*}

session=""
case $1 in
    ( '-s' )
        shift 1
        if [ -z $1 ]; then
            echo "No session specified." >&2
            exit 1
        fi
        session=$1
        shift 1 ;;
    ( * ) ;;
esac

if [ -z $session ]; then
    echo "No session specified." >&2
    exit 1
fi

in_pipe="/tmp/coqoune-$session/in"

if [ -z "$1" ]; then
    exit 0
fi


# stdin:
#     (first line) space-separated line and column number, marking end of command
#     (rest) the command itself
function add() {
    read line col
    read -r command
    printf "add:%s.%s %s\n" "$line" "$col" "$command" >$in_pipe
}

case $1 in
    ( 'init' )
        if [ -n "$2" ]; then
            $2 $coqoune_path/event_loop.sh -s $session
            echo $1 >$in_pipe
        fi
        ;;
    ( 'user-input' | 'quit' | 'goal' | 'back' | back-to:* | 'hints' )
        echo $1 >$in_pipe
        ;;
    ( 'add' )
        while read line col; read -r command; do
            printf "add:%s.%s %s\n" "$line" "$col" "$command" >$in_pipe
        done
        ;;
    ( 'query' )
        shift 1
        if [ -n "$1" ]; then
            echo "query $1" >$in_pipe
        fi
        ;;
esac
