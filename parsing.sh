#!/bin/sh


# $1: a line number for generating `range-specs' for highlighting,
# -line_var (optional): a variable to feedback line number
# -default (optional): a default face to use for unhighlighted text
# stdin: a `<richpp>...</richpp>' node returned by Coq
#        (escaped properly to let xmllint admit)
#        (single line)
# stdout:
#     (second line) A kakoune `range-specs' list (without timestamp) for highlighting the goal buffer
#     (third line) The text of the richpp node
function parse_richpp() {
    local line=$1
    local col=1
    

    shift 1
    while [ ! -z "$1" ]; do
        case "$1" in
            ( '-line_var' )
                local line_var=$2
                shift 2
                ;;
            ( '-default' )
                local default_hl=$2
                shift 2
                ;;
        esac
    done

    # don't escape '\'
    read -r pp_text
    # trim '<richpp><pp><_>' and '</_></pp></richpp>'
    pp_text=${pp_text:15:-18}

    # sed command to unescape the text
    unescape_cmd='s/&amp;nbsp;/ /g; s/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; p'

    output=""
    highlighters=""

    # Coq's richpp output may contains:
    #     1. pure text, without any highlighting (`untagged')
    #     2. highlighted text, wrapped in a xml child node indicating
    #        how it is highlighted (`tagged')
    echo $pp_text | sed -n 's|\\n|<newline/>|g; p' | while [ 1 ]; do

        read -r -d '<' untagged_text
        if [ -n "$default_hl" -a -n "$untagged_text" ]; then
            highlighters="$highlighters $line.$col+${#untagged_text}|$default_hl"
        fi
        (( col = col + ${#untagged_text} ))

        read -r -d '>' tag
        if [ "${tag:(-1):1}" = "/" ]; then
            if [ "$tag" = '<newline/' ]; then
                output="$output\n"
                (( line = line + 1, col = 1 ))
            fi
            continue
        fi
        read -r -d '<' tagged_text
        read -r -d '>'
        case $tag in
            # TODO: check Coq's source code for a more complete list
            # TODO: use custom faces
            ( 'constr.keyword' )
                highlighters="$highlighters $line.$col+${#tagged_text}|keyword"
                ;;
            ( 'constr.variable' )
                highlighters="$highlighters $line.$col+${#tagged_text}|variable"
                ;;
            ( 'constr.reference' )
                highlighters="$highlighters $line.$col+${#tagged_text}|variable"
                ;;
            ( 'constr.notation' )
                highlighters="$highlighters $line.$col+${#tagged_text}|operator"
                ;;
            ( 'constr.type' )
                highlighters="$highlighters $line.$col+${#tagged_text}|type"
                ;;
            ( 'constr.path' )
                highlighters="$highlighters $line.$col+${#tagged_text}|module"
                ;;
        esac
        (( col = col + ${#tagged_text} ))

        output="$output$untagged_text$tagged_text"

        if [ -z "$untagged_text" -a -z "$tag" -a -z "$tagged_text" ]; then
            if [ -n "$line_var" ]; then
                export $line_var=$line
            fi
            printf "%s\n%s\n" "$highlighters" "$output" | sed -n "$unescape_cmd"
            break
        fi
    done
}



# stdin: goal output from coq (single line), of the form '<value>...</value>'
# stdout:
#     1. (first line) A kakoune `range-specs' list (without timestamp) for highlighting the goal buffer
#     2. (rest) The content of text to be displayed in the goal buffer (properly formatted, decoration added)
function parse_goals() {
    if local all_goals=($(xmllint --xpath '/value/option[@val="some"]/goals/child::list' - 2>/dev/null));
    then
        local goals=""
        local highlighters=""
        if goals=($(echo "${all_goals[0]}" | xmllint --xpath '/list/child::goal/child::*' - 2>/dev/null));
        then # There are current goals available, display them only
            local goal_content="$((${#goals[@]} / 3)) goals:"
        else # There are no current goals, display the nearest layer of background goals
            local background_goals=($(echo ${all_goals[1]} | xmllint --xpath '/list/child::pair' - 2>/dev/null))
            for goal_stack in ${background_goals[@]}; do
                goals=($(echo "$goal_stack" | xmllint --xpath '/pair/list/goal/child::*' - 2>/dev/null)) \
                && break
            done
            # Current proof is already completed
            if [ ${#goals[@]} -eq 0 ]; then
                local message="There are no goals left."
                printf "\n%s\n" "$message"
                return
            fi
            local goal_content="There are no current goals left."
            local goal_content="$goal_content But there are $((${#goals[@]} / 3)) background goals:"
        fi

        local index=0
        local goal_id=1

        # parse all hypotheses and goals altogether, inserting proper decorations
        # To properly calculate line number, this process is done in three steps:
        #     1. (the first sub-shell) merge all hypotheses, goals and decorations into
        #        one big '<richpp>...</richpp>' node (input of $parse_richpp)
        #     2. let $parse_richpp parse the whole goal contents
        #     3. (last sub-shell) output the result
        ( printf '<richpp><pp><_>'
          printf '%s\\n\\n' "$goal_content"
          while [ "$index" -lt "${#goals[@]}" ]; do
              for hyp in $(echo ${goals[index + 1]} | xmllint --xpath '/list/child::richpp' - 2>/dev/null); do
                  printf '%s\\n' "${hyp:15:-18}"
              done

              # trim `<string>...</string>'
              # local goal_id=${goals[index]:8:-9}
              printf -- '-------------------------------(%s)\\n' "$goal_id"
              (( goal_id = goal_id + 1 ))

              printf '%s\\n' "${goals[index + 2]:15:-18}"
              (( index = $index + 3 ))
          done
          printf '</_></pp></richpp>'
        ) | parse_richpp 1 | (
            read highlighters
            read -r content
            printf "%s\n" "$highlighters"
            printf "$content"
        )
    else # We are not inside a proof at all
        printf "\n\n"
    fi
}

