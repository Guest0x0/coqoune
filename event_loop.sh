#!/bin/sh

session=""
while [ ! -z $1 ]; do
    case $1 in
        ( '-s' )
            shift 1
            if [ -z $1 ]; then
                echo "No session specified." >&2
                exit 1
            fi
            session=$1
            shift 1 ;;
        ( * )
            echo "Unknown option $1" >&2
            exit 1 ;;
    esac
done

if [ -z $session ]; then
    echo "No session specified." >&2
    exit 1
fi


tmpdir="/tmp/coqoune-$session"
if [ -e "$tmpdir" ]; then
    echo "an coqoune instance for kakoune session $session is already running."
    exit 1
fi
mkdir $tmpdir
in_pipe="$tmpdir/in"
goal_file="$tmpdir/goal"
res_file="$tmpdir/result"

mkfifo $in_pipe
exec 3<> $in_pipe


# $location_list is an array of the form:
#     index:    i    i + 1    i + 2
#     content: line   col   state_id
# where $line and $col mark the end position of an added coq command, and $state_id is the
# coq state_id *after* the command is added.
#
# $location_list should be in increasing order of locations.
source ./location_list.sh


# The structure of coqoune event loop is as follows:
# 1. all events, either from the user or from coqidetop's reply, are sent to $in_pipe
#    (after some pre-processing) and handled in the first while loop below. All commands,
#    together with all attached data, must be in a single line, so that writing the command
#    to $in_pipe would be atomic.
#
# 2. commands that are received, but not yet sent to coqidetop, are stored in $todo_list,
#    from earliest to latest, in the form:
#        index:       i      i + 1  i + 2
#        content: timestamp command  xml
#    one command should be removed from $todo_list after it is sent.
#
# 3. commands that are already sent to coqidetop, but whose reply is not yet received
#    and processed, are stored in $sent_list. Only the name of the command is stored.
#    A command should be removed from $sent_list after its reply is processed.
todo_list=()
sent_list=()

# 4. synchronization is done by $timestamp_sent and $timestamp_done. When coqoune
#    receives a user command from $in_pipe state, the $sent_timestamp should be incremented.
#    When the reply of that command is processed, $done_timestamp should be incremented.
#    Synchronization is done as long as $sent_timestamp and $done_timestamp are equal,
#    i.e. there are no commands sent but not yet processed.
#
#    When a command is put into $todo_list, $sent_timestamp when the command is
#    received is stored, too. That is, this command should be sent only if any commands
#    before $sent_timestamp have their reply processed, resulting in a state when this
#    command is intended to be sent.
timestamp_sent=0
timestamp_done=0

# 5. when coqidetop reports an error, it is possible that some other command, unaware of
#    the error, has been received by coqoune and has been put into $todo_list (but they
#    could never be sent, thanks to the sync mechanism), and some other commands may have
#    not yet been, but will be, received by coqoune (for example, add commands that are at
#    the stage of parsing source file). Continue sending these commands as if there is no
#    error at all would result in more errors, hence the $state variable is here.
#
#    $state can be either "error" or "ok". When $state is "ok", everything works normally
#    and there is no error known. When an error occurs, the "error" command is sent to
#    $in_pipe. Commands in $in_pipe before the command, if any, won't be sent until "error"
#    is received, because of the sync mechanism. When the error command is received, $state
#    is set to "error" and $todo_list is cleaned. Hence no command after the command that
#    produces error could be sent. Because of 'not yet received' commands mentioned above,
#    all commands received when $state is "error" will be ignored, and $todo_list should
#    always be empty, with the exception of the "user-input" command, which will turn $state
#    to "ok". "user-input" indicates an explicit input from the user, and indicates that
#    the user is aware of the error here.
state=ok


source ./parsing.sh
source ./kak_util.sh

function queue_command() {
    todo_list=("${todo_list[@]}" "$timestamp_sent" "$1" "$2")
    (( timestamp_sent = timestamp_sent + 1 ))
}

function flush_todo_list() {
    printf "%s, %s\n" "$timestamp_sent" "$timestamp_done" >&2
    local i=0
    while [ "$i" -lt "${#todo_list[@]}" ]; do
        local timestamp="${todo_list[i]}"
        if [ "$timestamp" -le "$timestamp_done" ]; then
            local cmd="${todo_list[i + 1]}"
            printf "to be sent: %s\n" "$cmd" >&2
            case "$cmd" in
                ( 'back' )
                    loclist_pop
                    ;;
                ( back-to:* )
                    local loc=($(echo ${cmd:8} | tr '.' ' '))
                    local line="${loc[0]}"
                    local col="${loc[1]}"
                    loclist_cut_at_loc "$line" "$col" 1>/dev/null
                    ;;
            esac
            local xml="${todo_list[i + 2]}"
            if [ "${#location_list[@]}" -gt 0 ]; then
                printf "$xml\n" "${location_list[-1]}"
            else
                printf "$xml\n"
            fi
            sent_list=(${sent_list[@]} "$cmd")
            (( i = i + 3 ))
        else
            break
        fi
    done
    todo_list=("${todo_list[@]:i}")
}

(
while read -r cmd arg <$in_pipe; do
    printf "cmd: %s\n" "$cmd" >&2
    if [ "$state" = "error" ]; then
# Index of coqoune commands:
# 1. user-input
#     indicates an explicit user input. Terminates "error" state
        if [ "$cmd" = "user-input" ]; then
            state=ok
        elif [ "$cmd" != "value" ]; then
            todo_list=()
            continue
        fi
    fi
    case "$cmd" in
# 2. init
#     init coqidetop
        ( 'init' )
            if [ -z "${location_list[@]}" ]; then
                queue_command 'init' '<call val="Init"><option val="none"/></call>'
            fi
            ;;
# 3. quit
#     quit coqoune
        ( 'quit' )
            printf '<call val="Quit"><unit/></call>\n'
            break
            ;;
# 4. add:$line.$col
#     execute a coq command. The command should end at source location $line.$col.
        ( add:* )
#     The text of the coq command itself should follow "add" in $in_pipe, separated
#     by a space.
#     The text should have newlines escaped.
            code=$arg
            if [ -n "$code" ]; then
                xml='<call val="Add"><pair>'
                xml="$xml<pair><string>$code</string>"
                xml="$xml<int>-1</int></pair>"
                xml="$xml<pair><state_id val=\"%s\"/>"
                xml="$xml<bool val=\"true\"/></pair>"
                xml="$xml</pair></call>"
                queue_command "$cmd" "$xml"
            fi
            ;;
# 5. back
#     undo the last added command
        ( 'back' )
            queue_command 'back' '<call val="Edit_at"><state_id val="%s"/></call>'
            ;;
# 6. back-to:$line.$col
#     undo added commands until before the location $line.$col
        (  back-to:* )
            queue_command "$cmd" '<call val="Edit_at"><state_id val="%s"/></call>'
            loc0=($(echo ${cmd:3} | tr '.' ' '))
            line0=${loc0[0]}
            col0=${loc0[1]}
            (( i = ${#todo_list[@]} - 3 ))
#     As an optimization, some 'add' commands in $todo_list can be cleaned, if they
#     would be eventually undone.
            while [ "$i" -lt "${#todo_list[@]}" ]; do
                todo_cmd=${#todo_list[i + 1]}
                if [ "${todo_cmd:0:3}" = "add" ]; then
                    loc=($(echo ${todo_cmd:3} | tr '.' ' '))
                    line=${loc[0]}
                    col=${loc[1]}
                    if [ "$line" -gt "$line0" ] || [ "$line" -eq "$line0" -a "$col" -gt "$col0" ]; then
                        todo_list=("${todo_list[@]:0:i}" "${todo_list[@]:(i + 3)}")
                        (( timestamp_sent = timestamp_sent - 1 ))
                        continue
                    fi
                fi
#     However, if some other commands are after the 'add' commands, they may have
#     desired visual effect (e.g. goal and queue) that depends on the 'add' commands.
#     So the optimization should stop here.
                break
            done
            ;;
# 7. goal
#     query for goals
        ( 'goal' )
            queue_command 'goal' '<call val="Goal"><unit/></call>'
            ;;
# 8. error
#     sent from coqoune itself when an error is reported by coqidetop. triggers
#     error handling.
        ( 'error' )
#     After a space in $in_pipe, following "error", should be the xml error message from coqidetop,
            error=$arg
            echo "Error!" >&2
            printf "%s\n" "$error" >&2
            state="error"
            todo_list=()
#     On error, the last added command will be undone.
            loclist_pop
            xml='<call val="Edit_at"><state_id val="%s"/></call>'
            printf "$xml\n" "${location_list[-1]}"
            sent_list=("${sent_list[@]:1}" "error")
#     Timestamps will be reset, too. As some commands to be sent that will change
#     timestamps are now cancelled.
            (( timestamp_done = timestamp_sent ))
            (( timestamp_sent = timestamp_sent + 1 ))
            echo "$error" | xmllint --xpath '/value[@val="fail"]/richpp' - | parse_richpp | kak_refresh_result
            ;;
# 9. value
#     sent from coqoune itself when coqidetop gives a successful '<value val="good">...</value>' reply.
        ( 'value' )
#     Following "value", separated by a space, should be the xml output
            output=$arg
            cmd="${sent_list[0]}"
            printf "command processed: %s\n" "$cmd" >&2
            (( timestamp_done = timestamp_done + 1 ))
#     A command has returned successfully, clean and refresh the result buffer.
            ( echo ""; echo "" ) | kak_refresh_result
            case "$cmd" in
                ( 'init' )
                    state_id=$(echo "$output" | xmllint --xpath '/value/state_id/attribute::val' - 2>/dev/null)
                    printf "get new state_id: %s\n" "${state_id:6:-1}" >&2
                    loclist_add 1 1 "${state_id:6:-1}"
                    kak_refresh_processed
                    ;;
                ( add:* )
                    loc=($(echo ${cmd:4} | tr '.' ' '))
                    line="${loc[0]}"
                    col="${loc[1]}"
                    state_id=$(echo "$output" | xmllint --xpath '/value/pair/state_id/attribute::val' - 2>/dev/null)
                    printf "get new state_id: %s\n" "${state_id:6:-1}" >&2
                    loclist_add "$line" "$col" "${state_id:6:-1}"
                    kak_refresh_processed
                    ;;
                ( 'back' | back-to:* | 'error' )
                    kak_refresh_processed
                    ;;
                ( 'goal' )
                    printf "%s\n" "$output" | parse_goals | kak_refresh_goal
                    printf "%s\n" "$output" | parse_goals >&2
                    ;;
            esac
            sent_list=("${sent_list[@]:1}")
            ;;
# 10. feedback
#     same as "value", but for '<feedback>...</feedback>' outputs.
        ( 'feedback' )
            feedback=$arg
            printf "feedback:\n%s\n" "$feedback" >&2
            ;;
    esac
    flush_todo_list
done | coqidetop -main-channel stdfds | while read -r -d '>' content; do
    content=$(echo "$content" | sed -n 's/&nbsp;/\&amp;nbsp;/g; p')
    output="$output$content>"
    if [ "${content:(-7):7}" = "</value" ]; then
        if [ "${output:12:4}" = 'good' ];then
            printf "value %s\n" "$output" >$in_pipe
        else
            printf "error %s\n" "$output" >$in_pipe
        fi
        output=""
    elif [ "${content:(-10):10}" = "</feedback" ]; then
        printf "feedback %s\n" "$output" >$in_pipe
        output=""
    fi
done

rm $in_pipe $goal_file $res_file
rmdir $tmpdir
) &
