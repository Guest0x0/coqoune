
function kak_refresh_processed() {
    line=${location_list[-3]}
    col=${location_list[-2]}
    if [ -n "$line" -a -n "$col" ]; then
        ( printf "evaluate-commands -buffer %%opt{coqoune_buffer} %%{"
          printf " set-option buffer coqoune_processed_highlighters %%val{timestamp}"
          printf " 1.1,$line.$col|coqoune_processed }\n"
        ) | kak -p $session
    fi
}

function kak_refresh_error() {
    s_line=$1
    s_col=$2
    e_line=$3
    e_col=$4
    if [ -n "$s_line" -a -n "$s_col" ] && [ -n "$e_line" -a -n "$e_col" ]; then
        ( printf "evaluate-commands -buffer %%opt{coqoune_buffer} %%{"
          printf " set-option buffer coqoune_processed_highlighters %%opt{coqoune_processed_highlighters}"
          printf " $s_line.$s_col,$e_line.$e_col|error"
        ) | kak -p $session
    fi
}

function kak_refresh_goal() {
    read highlighters
    cat - > $goal_file
    ( printf "execute-keys -buffer '*goal*' %%{
          %%|cat<space>/tmp/coqoune-$session/goal<ret>
      }\n"
      printf "evaluate-commands -buffer '*goal*' %%{
          set-option buffer coqoune_goal_highlighters %%val{timestamp} %s
      }\n" "$highlighters"
    ) | kak -p $session
}

# $1 (optional):
#     -incr : don't erase previous result content
function kak_refresh_result() {
    read highlighters
    if [ "$1" = '-incr' ]; then
        cat - | sed -n 's/\\n/\n/g; p' >>$res_file
    else
        cat - | sed -n 's/\\n/\n/g; p' >$res_file
    fi
    ( printf "execute-keys -buffer '*result*' %%{"
      printf " %%|cat<space>/tmp/coqoune-$session/result<ret> }\n"
      printf "evaluate-commands -buffer '*result*' %%{"
      if [ "$1" = '-incr' ]; then
          printf ' evaluate-commands %%sh{'
          printf ' echo $kak_opt_coqoune_result_highlighters | ('
          printf ' read ts highlighters;'
          printf ' echo "set-option buffer coqoune_result_highlighters'
          printf " %%val{timestamp} \$highlighters $highlighters\""
          printf " ) }}\n"
      else
          printf " set-option buffer coqoune_result_highlighters %%val{timestamp} $highlighters }\n"
      fi
    ) | kak -p $session
}

