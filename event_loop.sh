#!/bin/sh

coqoune_path=${0:0:(-14)}

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

# The structure of coqoune event loop is as follows:
# 1. all events, either from the user or from coqidetop's reply, are sent to the fifo $in_pipe
#    (after some pre-processing) and handled in the first while loop below. All commands,
#    together with all attached data, must be in a single line, so that writing the command
#    to $in_pipe would be atomic.
in_pipe="$tmpdir/in"
mkfifo $in_pipe
exec 3<> $in_pipe

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

# 4. synchronization is done by $sent_timestamp and $done_timestamp. When coqoune
#    receives a user command from $in_pipe state, the $sent_timestamp should be incremented.
#    When the reply of that command is processed, $done_timestamp should be incremented.
#    Synchronization is done as long as $sent_timestamp and $done_timestamp are equal,
#    i.e. there are no commands sent but not yet processed.
#
#    When a command is put into $todo_list, $sent_timestamp when the command is
#    received is stored, too. That is, this command should be sent only if any commands
#    before $sent_timestamp have their reply processed, resulting in a state when this
#    command is intended to be sent.
sent_timestamp=0
done_timestamp=0

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

# 6. information about coq commands sent to coqoune is recorded in $location_list.
#    $location_list is an array of the form:
#        index:    i    i + 1    i + 2
#        content: line   col   state_id
#    where $line and $col mark the end position of an added coq command, and $state_id is the
#    coq state_id *after* the command is added.
#
#    $location_list should be in increasing order of locations.
source $coqoune_path/location_list.sh

# 7. the goal and message output of coq are repectively stored in $goal_file and $res_file
#    (both are regular files).
#
#    to distinguish feedback messages and clean the result file properly, each command with
#    potential useful feedback (e.g. 'query') should use $sent_timestamp as the route. The
#    variable $res_route tracks feedback from which route the current result file is containing.
#    If the route from a new feedback message differs from $res_route, the result file should be
#    cleaned.
goal_file="$tmpdir/goal"
res_file="$tmpdir/result"
log_file="$tmpdir/log"

res_route=$sent_timestamp


source $coqoune_path/parsing.sh
source $coqoune_path/kak_util.sh


# queue a received command in $todo_list
function enqueue_command() {
    todo_list=("${todo_list[@]}" "$sent_timestamp" "$1" "$2")
    (( sent_timestamp = sent_timestamp + 1 ))
}

# flush $todo_list, send commands to coqidetop, if possible
function flush_todo_list() {
     if [ "${#todo_list[@]}" -gt 0 ] && [ "${todo_list[0]}" = "$done_timestamp" ]; then
         local cmd="${todo_list[1]}"
         printf "to be sent: %s\n" "$cmd" >&2
         # Though ugly, these must be put here.
         # 1. if we change $location_list on receiving these commands, then commands
         #    *received* before these but not yet *sent* when receiving these, will
         #    use the wrong state_id when being sent
         #
         # 2. if we change $location_list on receiving the reply of these commands,
         #    then we can't find the suitable state_id for 'Edit_at' here.
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
         local xml="${todo_list[2]}"
         if [ "${#location_list[@]}" -gt 0 ]; then
             printf "$xml\n" "${location_list[-1]}"
         else
             printf "$xml\n"
         fi
         sent_list=(${sent_list[@]} "$cmd")
         todo_list=("${todo_list[@]:3}")
     fi
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
# init:
#     init coqidetop
        ( 'init' )
            if [ -z "${location_list[@]}" ]; then
                enqueue_command 'init' '<call val="Init"><option val="none"/></call>'
            fi
            ;;
# quit:
#     quit coqoune
        ( 'quit' )
            printf '<call val="Quit"><unit/></call>\n'
            break
            ;;
# add:$line.$col:
#     execute a coq command. The command should end at source location $line.$col.
        ( add:* )
#     The text of the coq command itself should follow "add" in $in_pipe, separated by a space.
#     The text should have newlines escaped.
            code=$arg
            if [ -n "$code" ]; then
                xml='<call val="Add"><pair>'
                xml="$xml<pair><string>$code</string>"
                xml="$xml<int>2</int></pair>"
                xml="$xml<pair><state_id val=\"%s\"/>"
                xml="$xml<bool val=\"true\"/></pair>"
                xml="$xml</pair></call>"
                enqueue_command "$cmd" "$xml"
            fi
            ;;
# back:
#     undo the last added command
        ( 'back' )
#     As an optimization, if the last received, but not sent command is 'add', it
#     can be removed.
            if [ "${todo_list[0]:0:3}" = "add" ]; then
                todo_list=("${todo_list[@]:1}")
            else
                enqueue_command 'back' '<call val="Edit_at"><state_id val="%s"/></call>'
            fi
            ;;
# back-to:$line.$col:
#     undo added commands until before the location $line.$col
        (  back-to:* )
            loc0=($(echo ${cmd:3} | tr '.' ' '))
            line0=${loc0[0]}
            col0=${loc0[1]}
            (( i = ${#todo_list[@]} - 3 ))
#     As an optimization, some 'add' commands in $todo_list can be cleaned, if they
#     would be eventually undone.
            while [ "$i" -gt 0 ] && [ "$i" -lt "${#todo_list[@]}" ]; do
                todo_cmd=${todo_list[i + 1]}
                if [ "${todo_cmd:0:3}" = "add" ]; then
                    loc=($(echo ${todo_cmd:3} | tr '.' ' '))
                    line=${loc[0]}
                    col=${loc[1]}
                    if [ "$line" -gt "$line0" ] || [ "$line" -eq "$line0" -a "$col" -gt "$col0" ]; then
                        todo_list=("${todo_list[@]:0:i}" "${todo_list[@]:(i + 3)}")
                        (( sent_timestamp = sent_timestamp - 1 ))
                        continue
                    fi
                fi
#     However, if some other commands are after the 'add' commands, they may have
#     desired visual effect (e.g. goal and queue) that depends on the 'add' commands.
#     So the optimization should stop here.
                break
            done
            enqueue_command "$cmd" '<call val="Edit_at"><state_id val="%s"/></call>'
            ;;
# query:
#     send a query to coq, i.e. execute coq commands without changing the state
        ( 'query' )
#     the query command should follow 'query', separated by a space
            query=$arg
            if [ -n "$query" ]; then
                xml='<call val="Query"><pair>'
                xml="$xml<route_id val=\"$sent_timestamp\"/>"
                xml="$xml<pair><string>$query</string>"
                xml="$xml<state_id val=\"%s\"/></pair>"
                xml="$xml</pair></call>"
                printf "%s\n" "$xml" >&2
                enqueue_command 'query' "$xml"
            fi
            ;;
# hints:
#     ask for hints at current tip.
        ( 'hints' )
            enqueue_command 'hints' '<call val="Hints"><unit/></call>'
            ;;
# goal:
#     query for goals
        ( 'goal' )
            enqueue_command 'goal' '<call val="Goal"><unit/></call>'
            ;;
# error:
#     sent from coqoune itself when an error is reported by coqidetop. triggers
#     error handling.
        ( 'error' )
#     After a space in $in_pipe, following "error", should be the xml error message from coqidetop,
            error=$arg
            echo "$error" \
                | xmllint --xpath '/value[@val="fail"]/richpp' - \
                | parse_richpp 1 \
                | kak_refresh_result
            case "${sent_list[0]}" in
#     When 'add' commands or 'goal' commands trigger an error, the last added commands is the cause,
#     hence undo it.
                ( add:* | 'goal' )
                    loclist_pop
                    state="error"
                    todo_list=()
                    xml='<call val="Edit_at"><state_id val="%s"/></call>'
                    printf "$xml\n" "${location_list[-1]}"
                    sent_list=("${sent_list[@]:1}" "error")
#     Timestamps will be reset, too. As some commands to be sent that will change
#     timestamps are now cancelled.
            (( done_timestamp = sent_timestamp ))
            (( sent_timestamp = sent_timestamp + 1 ))
                    ;;
#     When the last command is 'query', which is irrelevant with the state, simply ignores the error.
                ( 'query' )
                    continue
                    ;;
            esac
            ;;
# value:
#     sent from coqoune itself when coqidetop gives a successful '<value val="good">...</value>' reply.
        ( 'value' )
#     Following "value", separated by a space, should be the xml output
#     The xml output should have newline characters escaped, so that it fits in one line
            output=$arg
            cmd="${sent_list[0]}"
            printf "command processed: %s\n" "$cmd" >&2
            (( done_timestamp = done_timestamp + 1 ))
#     If a state-changing or result-changing command has returned successfully, clean and refresh the result buffer.
            case "$cmd" in
                ( 'init' | add:* | 'back' | back-to* )
                    printf "\n" | kak_refresh_result
                    ;;
            esac
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
                ( 'query' )
                    ;;
                ( 'hints' )
                    printf "Hints:\n%s\n" "$output" >&2
                    printf "%s\n" "$output" \
                        | xmllint --xpath '/value/option/pair/list/pair/string/child::text()' - \
                        | sed -n 's/&amp;nbsp;/ /g; p' \
                        | ( printf "\n"; cat - ) \
                        | kak_refresh_result
                    ;;
                ( 'goal' )
                    printf "%s\n" "$output" | parse_goals | kak_refresh_goal
                    ;;
            esac
            sent_list=("${sent_list[@]:1}")
            ;;
# feedback:
#     same as "value", but for '<feedback>...</feedback>' outputs.
        ( 'feedback' )
            feedback=$arg
            route=$(echo "$feedback" | xmllint --xpath '/feedback/attribute::route' - 2>/dev/null)
            route=${route:8:-1}
#     If the route id has changed, a new group of feedbacks is being received, so clean the result buffer.
            if [ "$route" != "$res_route" ]; then
                res_route=$route
                printf "\n" | kak_refresh_result
            fi
            type=$(echo "$feedback" | xmllint --xpath '/feedback/feedback_content/attribute::val' - 2>/dev/null)
            case "${type:6:-1}" in
                ( 'message' )
                    line_count=($(wc -l $res_file))
                    line_count=$(( ${line_count[0]} + 1 ))
                    echo "$feedback" \
                          | xmllint --xpath '/feedback/feedback_content/message/child::richpp' - 2>/dev/null \
                          | parse_richpp $line_count \
                          | kak_refresh_result -incr
                    ;;
            esac
            ;;
    esac
    flush_todo_list
done | coqidetop -main-channel stdfds | while read -r -d '>' content; do
    # escape possible newlines
    content=$(echo "$content" \
        | sed -n 's/&nbsp;/\&amp;nbsp;/g; s/\\/\\\\/g; p' \
        | while read line; do
            printf "%s" "$line\\n"
        done)
    # remove the last one
    content="${content:0:-2}"
    output="$output$content>"
    if [ "${content:(-7):7}" = "</value" ]; then
        printf "coqidetop: value: %s\n" "$output" >&2
        if [ "${output:12:4}" = 'good' ];then
            printf "value %s\n" "$output" >$in_pipe
        else
            printf "error %s\n" "$output" >$in_pipe
        fi
        output=""
    elif [ "${content:(-10):10}" = "</feedback" ]; then
        printf "coqidetop: feedback: %s\n" "$output" >&2
        printf "feedback %s\n" "$output" >$in_pipe
        output=""
    fi
done

rm $in_pipe $goal_file $res_file $log_file
rmdir $tmpdir
) 2>>$log_file &
