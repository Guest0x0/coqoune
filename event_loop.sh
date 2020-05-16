#!/bin/sh

session=""
while [ ! -z $1 ]; do
    case $1 in
        '-s' )
            shift 1
            if [ -z $1 ]; then
                echo "No session specified." >&2
                exit 1
            fi
            session=$1
            shift 1 ;;
        * )
            echo "Unknown option $1" >&2
            exit 1 ;;
    esac
done

if [ -z $session ]; then
    echo "No session specified." >&2
    exit 1
fi


tmpdir="/tmp/coqoune-$session"
postfix=0
while [ -e "$tmpdir" ]; do
    tmpdir="$tmpdir-$postfix"
    (( postfix = $postfix + 1 ))
done
mkdir $tmpdir
in_pipe="$tmpdir/in"
reply_pipe="$tmpdir/reply"
goal_file="$tmpdir/goal"
res_file="$tmpdir/result"

for pipe in $in_pipe $reply_pipe; do
    mkfifo $pipe
done
exec 3<> $in_pipe
exec 4<> $reply_pipe

# Error status of coqoune. Possible values are:
# 1. "ok"    : no error
# 2. "unwind": error has occured, now unwinding all inputs submitted before the error.
# 3. "wait"  : unwinding is done, now wait for the next user command.
#
# "unwind" is used with the special command "error", marking when the error occur.
# "wait" is used along with a special command "user-input" indicating a user-input,
# as a user-side command may correspond to many coqoune commands internally.
state="ok"

source ./location_list.sh
source ./parsing.sh

function input_loop() {
    while [ 1 ]; do
        read -r cmd xml < $in_pipe
        echo "state: $state" >&2
        echo "state_id: ${location_list[-1]}" >&2
        echo "cmd: $cmd" >&2
        if [ "$cmd" = 'quit' ]; then
            echo $xml
            break
        fi
        case $state in
            ( 'ok' )
                case $cmd in
                    ( 'user-input' )
                        continue
                        ;;
                    ( back-to:* )
                        location=($(echo ${cmd:8} | tr '.' ' '))
                        line=${location[0]}
                        col=${location[1]}
                        loclist_cut_at_loc $line $col
                        xml='<call val="Edit_at"><state_id val="%s"/></call>'
                        ;;
                    ( 'back' )
                        loclist_pop
                        xml='<call val="Edit_at"><state_id val="%s"/></call>'
                        ;;
                esac
                ;;
            ( 'unwind' )
                if [ "$cmd" = "error" ]; then
                    state="wait"
                    xml='<call val="Edit_at"><state_id val="%s"/></call>'
                fi
                ;;
            ( 'wait' )
                [ "$cmd" = "user-input" ] && state="ok"
                continue
                ;;
        esac

        printf "input:\n$xml\nend.\n" ${location_list[-1]} >&2
        printf "$xml\n" ${location_list[-1]}

        reply=""
        while [ 1 ]; do
            read -r -d '>' tag < $reply_pipe
            [ -n "$tag" ] && reply="$reply$tag>"
            if [ "${tag:(-7):7}" = "</value" ]; then
                break
            elif [ "${tag:(-10):10}" = "</feedback" ]; then
                # TODO: support feedback
                reply=""
            fi
        done
        reply=$(echo $reply | sed -n 's/&nbsp;/\&amp;nbsp;/g ; p')
#        echo "reply: $reply" >&2

        if value=$(echo $reply | xmllint --xpath '/value[@val="good"]/child::*' - 2>/dev/null); then
            case $cmd in
                ( 'init' )
                    result=$(echo $value | xmllint --xpath '/state_id/attribute::val' - 2>/dev/null)
                    location_list=(1 1 ${result:6:-1}) # trim `val="' and `"'
                    ;;
                ( add:*\.*  )
                    result=$(echo $value | xmllint --xpath '/pair/state_id/attribute::val' -)
                    loc=($(echo ${cmd:4} | tr '.' ' '))
                    line=${loc[0]}
                    col=$((${loc[1]} + 1))
                    loclist_add $line $col ${result:6:-1}
                    ( echo "evaluate-commands -buffer %opt{coqoune_buffer} %{"
                      echo -n  "set-option buffer coqoune_executed_highlighters %val{timestamp}"
                      echo         "1.1,$line.$col|coqoune_executed"
                      echo "}"
                    ) | kak -p $session
                    ;;
                ( back-to:* | 'back' )
                    line=${location_list[-3]}
                    col=${location_list[-2]}
                    ( echo "evaluate-commands -buffer %opt{coqoune_buffer} %{"
                      echo -n  "set-option buffer coqoune_executed_highlighters %val{timestamp}"
                      echo         "1.1,$line.$col|coqoune_executed"
                      echo "}"
                    ) | kak -p $session
                    ;;
                ( 'goal' )
                    echo $value | parse_goals | (
                        read highlighters
                        cat - > $goal_file
                        echo "coq-refresh-goal" | kak -p $session
                        ( echo "evaluate-commands -buffer '*goal*' %{"
                          echo    "set-option buffer coqoune_goal_highlighters %val{timestamp} $highlighters"
                          echo "}" ) | kak -p $session
                     )
                    ;;
                ( * ) ;;
            esac
        else
            state="unwind"
            rm $in_pipe
            mkfifo $in_pipe
            echo "error" > $in_pipe &
            loclist_pop
            error_msg=$(echo $reply | xmllint --xpath '/value[@val="fail"]/richpp' - 2>/dev/null)
            echo $error_msg | parse_richpp 1 | (
                read highlighters
                cat - > $res_file
                ( echo "coq-refresh-result"
                  echo "evaluate-commands -buffer %opt{coqoune_buffer} %{"
                  echo -n  "set-option buffer coqoune_executed_highlighters %val{timestamp} "
                  echo         "1.1,${location_list[-3]}.${location_list[-2]}|coqoune_executed"
                  echo "}"
                  echo "evaluate-commands -buffer '*result*' %{"
                  echo     "set-option buffer coqoune_result_highlighters %val{timestamp} $highlighters"
                  echo "}" ) | kak -p $session
            )
        fi

    done | coqidetop -main-channel stdfds > $reply_pipe

    # cleanup
    rm $in_pipe $reply_pipe $goal_file $res_file
    rmdir $tmpdir
    exec 3>&-
    exec 4>&-
}

input_loop &
