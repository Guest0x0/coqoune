#!/bin/sh

function kak_refresh_processed() {
    line=${location_list[-3]}
    col=${location_list[-2]}
    if [ -n "$line" -a -n "$col" ]; then
        ( printf "evaluate-commands -buffer %%opt{coqoune_buffer} %%{"
          printf " set-option buffer coqoune_executed_highlighters %%val{timestamp}"
          printf " 1.1,$line.$col|coqoune_executed }\n"
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
          printf " set-option buffer coqoune_executed_highlighters %%opt{coqoune_executed_highlighters}"
          printf " $s_line.$s_col,$e_line.$e_col|error"
        ) | kak -p $session
    fi
}

function kak_refresh_goal() {
    read highlighters
    cat - > $goal_file
    ( printf "execute-keys -buffer '*goal*' %%{"
      printf " %%|cat<space>/tmp/coqoune-$session/goal<ret> }\n"
      printf "evaluate-commands -buffer '*goal*' %%{"
      printf " set-option buffer coqoune_goal_highlighters %%val{timestamp} $highlighters }\n"
    ) | kak -p $session
}

function kak_refresh_result() {
    read highlighters
    cat - > $res_file
    ( printf "execute-keys -buffer '*result*' %%{"
      printf " %%|cat<space>/tmp/coqoune-$session/result<ret> }\n"
      printf "evaluate-commands -buffer '*result' %%{"
      printf " set-option buffer coqoune_result_highlighters %%val{timestamp} $highlighters }\n"
    ) | kak -p $session
}

