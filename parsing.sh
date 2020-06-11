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

    function update_loc() {
        text=$1
        local line_count=$(echo -e "$text" | wc -l)
        local last_line=$(echo -e "$text" | tail -n 1)
        if [ "$line_count" -eq 1 ]; then
            (( col = col + ${#last_line} ))
        else
            (( line = line + line_count - 1, col = ${#last_line} + 1 ))
        fi
    }

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
    echo $pp_text | while [ 1 ]; do

        read -r -d '<' untagged_text
        untagged_text=$(echo $untagged_text | sed -n "$unescape_cmd")
        if [ -n "$default_hl" -a -n "$untagged_text" ]; then
            highlighters="$highlighters $line.$col+${#untagged_text}|$default_hl"
        fi
        update_loc "$untagged_text"

        read -r -d '>' tag
        if [ "${tag:(-1):1}" = "/" ]; then
            continue
        fi
        read -r -d '<' tagged_text
        read -r -d '>'
        tagged_text=$(echo $tagged_text | sed -n "$unescape_cmd")
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
        update_loc "$tagged_text"

        output="$output$untagged_text$tagged_text"

        if [ -z "$untagged_text" -a -z "$tag" -a -z "$tagged_text" ]; then
            if [ -n "$line_var" ]; then
                export $line_var=$line
            fi
            printf "%s\n%s\n" "$highlighters" "$output"
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
        # The frist line is already used to display number of goals
        local linenum=2

        # parse all hypotheses and goals altogether, inserting proper decorations
        # every line in the goal buffer corresponds to three lines here:
        #     1. new line number
        #     2. highlighters
        #     3. text
        while [ "$index" -lt "${#goals[@]}" ]; do
            # Goals are separated by one newline
            printf "\n\n"
            (( linenum = linenum + 1 ))

            for hyp in $(echo ${goals[index + 1]} | xmllint --xpath '/list/child::richpp' - 2>/dev/null); do
                echo $hyp | parse_richpp $linenum -line_var linenum
                (( linenum = linenum + 1 ))
            done

            # trim `<string>...</string>'
            local goal_id=${goals[index]:8:-9}
            echo "$linenum.32+1|operator $linenum.33+${#goal_id}|value $linenum.$((33 + ${#goal_id}))+1|operator"
            echo "-------------------------------($goal_id)"
            (( linenum = linenum + 1 ))

            echo ${goals[index + 2]}| parse_richpp $linenum -line_var linenum
            (( linenum = linenum + 1 ))

            (( index = $index + 3 ))
        done | ( # join all the outputs
            while read highlighters_delta;
                  read -r line;
            do
                 [ -n "$highlighters_delta" ] && highlighters="$highlighters $highlighters_delta"
                 local goal_content="$goal_content\n$line"
            done
            printf "%s\n" "$highlighters"
            echo -e $goal_content
        )
    else # We are not inside a proof at all
        echo ""
        echo ""
    fi
}

