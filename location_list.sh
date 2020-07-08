
# `location_list' is an array of the form
#     line{1}, col{1}, state_id{1}, ..., line{n}, col{n}, state_id{n}
# where the locations are stored from beginning to end.
# Every location corresponds to an end of a already-executed coq command,
# with the associated state_id being the state_id *after* executing the command.
location_list=()

function loclist_add() {
    location_list=("${location_list[@]}" $1 $2 $3)
}

function loclist_pop() {
    location_list=("${location_list[@]:0:(${#location_list[@]} - 3)}")
}

function loclist_clean() {
    location_list=("${location_list[@]:0:3}")
}

# $1: a state_id to backward execution to
# stdout:
#     the line and column (space separated) corresponding to $1, or 1 if none
# side effect:
#     remove all locations after $1 from the location_list
function loclist_cut_at_state_id() {
    local i=${#location_list[@]}
    while [ "$i" -gt 1 ]; do
        local state_id=${location_list[i - 1]}
        local col=${location_list[i - 2]}
        local line=${location_list[i - 3]}
        if [ "$state_id" = "$1" ]; then
            location_list=("${location_list[@]:0:$i}")
            echo $line $col
            return
        fi
        (( i = i - 3 ))
    done
    location_list=""
    echo 1 1
}

# $1, $2: row and column to backward execution to (may not be exact)
# stdout:
#     the latest line, column and state_id *before* $1.$2
# side effect:
#     remove all locations ending after $1.$2
function loclist_cut_at_loc() {
    local line0=$1
    local col0=$2
    local i=${#location_list[@]}
    while [ "$i" -gt 1 ]; do
        local state_id=${location_list[i - 1]}
        local col=${location_list[i - 2]}
        local line=${location_list[i - 3]}
        if [ "$line" -lt "$line0" ] ||
           [ "$line" -eq "$line0" -a "$col" -le "$col0" ];
        then
            location_list=(${location_list[@]:0:$i})
            echo $line $col $state_id
            return
        fi
        (( i = i - 3 ))
    done
    echo ${location_list[0]} ${location_list[1]} ${location_list[2]}
    location_list=()
}

