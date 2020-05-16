#!/bin/sh

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
    ./event_loop.sh -s $session 2>>./log
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
    # coq will say `Assertion failure' on empty add
    if [ -n "$command" ]; then
        req='<call val="Add"><pair>'
        req="$req<pair><string>$command</string>"
        req="$req<int>-1</int></pair>"
        req="$req<pair><state_id val=\"%s\"/>"
        req="$req<bool val=\"false\"/></pair>"
        req="$req</pair></call>"
        echo "add:$line.$col $req" > $in_pipe
    fi
}

case $1 in
    ( 'user-input' )
        echo "user-input" > $in_pipe
        ;;
    ( 'init' )
        echo 'init <call val="Init"><option val="none"/></call>' > $in_pipe
        ;;
    ( 'quit' )
        echo 'quit <call val="Quit"><unit/></call>' > $in_pipe
        ;;
    ( 'goal' )
        echo 'goal <call val="Goal"><unit/></call>' > $in_pipe
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
            ./parse_command.sh $1 $2 | add
        fi
        ;;
    ( 'back' )
        echo back > $in_pipe
        ;;
    ( 'to' )
        shift 1
        if [ ${#@} -ge 4 ]; then
            line=$1
            col=$2
            end_line=$3
            end_col=$4
            if [ "$line" -lt "$end_line" ] || [ "$line" -eq "$end_line" -a "$col" -ge "$end_col" ]; then
                ./parse_command.sh $line $col |
                    while [ "$line" -lt "$end_line" ] || [ "$line" -eq "$end_line" -a "$col" -ge "$end_col" ]; do
                        read line col
                        read -r command
                        ( echo $line $col; echo "$command" ) | add
                    done
            else
                echo "back-to:$end_line.$end_col" > $in_pipe
            fi
        fi
        ;;
esac
