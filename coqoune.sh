#!/bin/sh

coqoune_path=${0:0:(-11)}

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

if [ ! -e "$in_pipe" ]; then
    echo "spawning ..."
    $coqoune_path/event_loop.sh -s $session
fi

if [ -z "$1" ]; then
    exit 0
fi


# stdin:
#     (first line) space-separated line and column number, marking end of command
#     (rest) the command itself
function add() {
    read line col
    read -r command
    command=$(echo "$command" | sed -n 's/</\&lt;/g ; s/>/\&gt;/g ; p')
    printf "add:%s.%s %s\n" "$line" "$col" "$command" >$in_pipe
}

case $1 in
    ( 'user-input' | 'init' | 'quit' | 'goal' | 'back' | 'back-to' )
        echo $1 >$in_pipe
        ;;
    ( 'add' )
        shift 1
        if [ ${#@} -ge 2 ]; then
            ( echo $1 $2; cat - ) | add
        fi
        ;;
    ( 'next' )
        shift 1
        if [ ${#@} -ge 2 ]; then
            $coqoune_path/parse_command.sh $1 $2 | add
        fi
        ;;
    ( 'to' )
        shift 1
        if [ ${#@} -ge 4 ]; then
            line=$1
            col=$2
            end_line=$3
            end_col=$4
            if [ "$line" -lt "$end_line" ] || [ "$line" -eq "$end_line" -a "$col" -lt"$end_col" ]; then
                $coqoune_path/parse_command.sh $line $col |
                    while [ "$line" -lt "$end_line" ] || [ "$line" -eq "$end_line" -a "$col" -lt "$end_col" ]; do
                        read line col
                        read -r command
                        ( echo $line $col; echo "$command" ) | add
                    done
            else
                echo "back-to:$end_line.$end_col" > $in_pipe
            fi
        fi
        ;;
    ( 'query' )
        shift 1
        if [ -n "$1" ]; then
            echo "query $1" >$in_pipe
        fi
        ;;
    ( 'hints' )
        echo "hints" >$in_pipe
        ;;
esac
