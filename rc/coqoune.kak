

declare-option -hidden str coqoune_path %sh{
    echo ${kak_source%/*/*}
}

declare-option str coqoune_goal_buffer_name "goal@[%%s]"
declare-option str coqoune_result_buffer_name "result@[%%s]"

# source syntax file
source "%opt{coqoune_path}/rc/syntax.kak"

define-command coq-start -params 0 %{
    evaluate-commands %sh{
        if [ "$kak_opt_coqoune_buffer" = "$kak_bufname" ]; then
            echo 'fail "coqoune already started in this buffer"'
        fi
    }

    declare-option -hidden str coqoune_buffer %val{bufname}
    declare-option -hidden str coqoune_working_dir %sh{ mktemp -d }

# init the coqoune scripts
    nop %sh{
        mkfifo $kak_opt_coqoune_working_dir/input
        tail -n +1 -f $kak_opt_coqoune_working_dir/input 2>/dev/null \
        | $kak_opt_coqoune_path/_build/coqoune $kak_opt_coqoune_working_dir \
              $kak_session $kak_opt_coqoune_buffer 1>/dev/null 2>/$kak_opt_coqoune_working_dir/log &
    }

    # create goal & result buffers
    declare-option -hidden str coqoune_goal_buffer %sh{
        printf "$kak_opt_coqoune_goal_buffer_name" "$kak_opt_coqoune_buffer"
    }
    declare-option -hidden str coqoune_result_buffer %sh{
        printf "$kak_opt_coqoune_result_buffer_name" "$kak_opt_coqoune_buffer"
    }

    evaluate-commands -draft %{
        edit -scratch %opt{coqoune_goal_buffer}
        edit -scratch %opt{coqoune_result_buffer}
    }

    evaluate-commands -draft -buffer %opt{coqoune_goal_buffer} %{
        set-option buffer filetype coq-goal
    }

    evaluate-commands -draft -buffer %opt{coqoune_result_buffer} %{
        set-option buffer filetype coq-result
    }

# set up highlighters.
    # highlighter for marking commands already processed
    # `coqoune_processed' should contain only one region
    declare-option -hidden range-specs coqoune_processed_range %val{timestamp}
    declare-option -hidden range-specs coqoune_error_range     %val{timestamp}
    evaluate-commands -buffer %opt{coqoune_buffer} %{
        add-highlighter buffer/coqoune_processed ranges coqoune_processed_range
        add-highlighter buffer/coqoune_error     ranges coqoune_error_range
    }

    # face for marking processed commands
    set-face buffer coqoune_added     default,default+u
    set-face buffer coqoune_processed default,default+s


    # semantic highlighters based on coq's output
    declare-option -hidden range-specs coqoune_goal_highlighters %val{timestamp}
    evaluate-commands -buffer %opt{coqoune_goal_buffer} %{
        add-highlighter buffer/coqoune_goal ranges coqoune_goal_highlighters
    }

    declare-option -hidden range-specs coqoune_result_highlighters %val{timestamp}
    evaluate-commands -buffer %opt{coqoune_result_buffer} %{
        add-highlighter buffer/coqoune_result ranges coqoune_result_highlighters
    }


# hooks for cleanup
    hook -group coqoune buffer BufClose .* %{
        try %{ delete-buffer %opt{coqoune_goal_buffer} }
        try %{ delete-buffer %opt{coqoune_result_buffer} }
        nop %sh{
            echo "<Quit/>" >$kak_opt_coqoune_working_dir/input
            rm -R $kak_opt_coqoune_working_dir
        }
    }

# callback for Coqoune
    define-command -hidden coqoune-refresh-goal -params 0 %{
        execute-keys -buffer %opt{coqoune_goal_buffer} %sh{
            printf "%%|cat %s/goal<ret>" "$kak_opt_coqoune_working_dir"
        }
        evaluate-commands -buffer %opt{coqoune_goal_buffer} %sh{
            printf "set-option buffer coqoune_goal_highlighters %s " "%val{timestamp}"
            cat $kak_opt_coqoune_working_dir/goal_highlighter
        }
    }

    define-command -hidden coqoune-refresh-result -params 0 %{
        execute-keys -buffer %opt{coqoune_result_buffer} %sh{
            printf "%%|cat %s/result<ret>" "$kak_opt_coqoune_working_dir"
        }
        evaluate-commands -buffer %opt{coqoune_result_buffer} %sh{
            printf "set-option buffer coqoune_result_highlighters %s " "%val{timestamp}"
            cat $kak_opt_coqoune_working_dir/result_highlighter
        }
    }

    define-command -hidden coqoune-set-error-range -params 4 %{
        evaluate-commands -draft %{
            execute-keys %sh{
                row_s=$1
                col_s=$2
                offset_start=$3
                printf "%s" "${row_s}ggh"
                tot_offset=$((col_s + offset_start - 1))
                if [ "$tot_offset" -gt 0 ]; then
                    printf "%s" "${tot_offset}l"
                fi
            }
            set-option buffer coqoune_error_range %val{timestamp} %sh{
                err_len=$(($4 - $3))
                printf "%s.%s+%d|Error" \
                    "$kak_cursor_line" "$kak_cursor_column" "$err_len"
            }
        }
    }

    define-command -hidden coqoune-unset-error-range -params 0 %{
        set-option buffer coqoune_error_range %val{timestamp}
    }

# user interaction
    # receive a movement command ('next', 'back' or 'to') and send it to coqoune
    define-command -hidden coq-move-command -params 1 %{
        nop %sh{ echo "<User_React/>" >$kak_opt_coqoune_working_dir/input }
        execute-keys -draft %sh{
            echo $kak_opt_coqoune_processed_range | (
                read -d ' ' # timestamp
                read -d ' ' # processed part
                read -d '.' # start line (should be beginning of buffer)
                read -d ',' # end line (should be beginning of buffer)
                read -d '.' line0 || line0=1
                read -d '|' col0  || col0=1
                keys="${line0}ggh"
                if [ "$line0" -ne 1 -o "$col0" -ne 1 ]; then
                    keys="${keys}${col0}l"
                fi
                keys="${keys}Ge<a-;>"
                case $1 in
                    ( 'next' ) 
                        keys="$keys<a-|>$kak_opt_coqoune_path/_build/parse_expr"
                        keys="$keys \$kak_cursor_line \$kak_cursor_column >"
                        keys="$keys$kak_opt_coqoune_working_dir/input<ret>"
                        ;;
                    ( 'to' )
                        if [ "$line0" -gt "$kak_cursor_line" ] || \
                           [ "$line0" -eq "$kak_cursor_line" -a "$col0" -ge "$kak_cursor_column" ];
                        then
                            keys="$keys;:nop %sh{"
                            keys="${keys}echo \"<lt>Back_To<gt><lt>pair<gt>"
                            keys="$keys<lt>int<gt>$kak_cursor_line<lt>/int<gt>"
                            keys="$keys<lt>int<gt>$kak_cursor_column<lt>/int<gt>"
                            keys="$keys<lt>/pair<gt><lt>/Back_To<gt>\""
                            keys="$keys >$kak_opt_coqoune_working_dir/input }<ret>"
                        else
                            keys="$keys<a-|>$kak_opt_coqoune_path/_build/parse_expr"
                            keys="$keys \$kak_cursor_line \$kak_cursor_column $kak_cursor_line $kak_cursor_column"
                            keys="$keys >$kak_opt_coqoune_working_dir/input<ret>"
                        fi
                        ;;
                    ( 'back' )
                        keys="$keys;:nop %sh{"
                        keys="${keys}echo \"<lt>Back/<gt>\""
                        keys="$keys >$kak_opt_coqoune_working_dir/input }<ret>"
                        ;;
                esac
                echo "$keys<ret>" | sed -n 's/ /<space>/g; p'
            )
        }
        nop %sh{ echo "<Goal/>" >$kak_opt_coqoune_working_dir/input }
    }

    define-command coq-next \
        -docstring "send the next command to coq" \
        -params 0 %{
            coq-move-command next
        }
    define-command coq-back \
        -docstring "undo the last sent command" \
        -params 0 %{
            coq-move-command back
        }
    define-command coq-to-cursor \
        -docstring "move processed area boundary to main cursor, sending or undoing commands if necessary" \
        -params 0 %{
            coq-move-command to
        }


    define-command coq-query \
        -docstring "send the first argument as a query to coqoune" \
        -params 1 %{
            nop %sh{
                echo "<User_React/>" >$kak_opt_coqoune_working_dir/input
                ( printf "<Query><string>"
                  printf "%s" "$1" | sed -n "s/&/&amp;/g; s/\"/&quot;/g; s/'/&apos;/g; s/</&lt;/g; s/>/&gt;/g; p"
                  printf "</string></Query>" )  >$kak_opt_coqoune_working_dir/input
            }
        }

    define-command coq-dump-log \
        -docstring "dump internal log to a file for debugging" \
        -params 1 %{
            nop %sh{
                cp $kak_opt_coqoune_working_dir/log $1
            }
        }


    # automatically backward execution on text change 
    define-command -hidden coq-on-text-change -params 0 %{
        nop %sh{
            compare_cursor() {
                line1=$1
                col1=$2
                line2=$3
                col2=$4
                if [ "$line1" -gt "$line2" ]; then
                    echo 1
                elif [ "$line1" -lt "$line2" ]; then
                    echo -1
                elif [ "$col1" -gt "$col2" ]; then
                    echo 1
                elif [ "$col1" -lt "$col2" ]; then
                    echo -1
                else
                    echo 0
                fi
            }
            echo $kak_opt_coqoune_processed_range | (
                    read -d ' ' # timestamp
                    read -d ' ' # processed region
                    read -d '.'
                    read -d ','
                    read -d '.' line0 || line0=1
                    read -d '|' col0  || col0=1
                    earliest_line=99999999
                    earliest_col=99999999
                    echo $kak_selections_desc | (
                        # find the earliest selection
                        while read -d '.'; read -d ','; do
                            read -d '.' line
                            read -d ' ' col
                            if [ "$(compare_cursor $earliest_line $earliest_col $line $col)" -gt 0 ]; then
                                earliest_line=$line
                                earliest_col=$col
                            fi
                        done
                        # if (any part of) the edit happens inside processed region, backward execution
                        if [ "$(compare_cursor $earliest_line $earliest_col $line0 $col0)" -lt 0 ]; then
                            echo "<User_React/>" >$kak_opt_coqoune_working_dir/input
                            printf "<Back_To><pair><int>%s</int><int>%s</int></pair></Back_To>" \
                                "$earliest_line" "$earliest_col" >$kak_opt_coqoune_working_dir/input
                            printf "<Goal/>" >$kak_opt_coqoune_working_dir/input
                        fi
                    )
            )
        }
    }

    hook -group coqoune buffer InsertChar   .* coq-on-text-change
    hook -group coqoune buffer InsertDelete .* coq-on-text-change

}
