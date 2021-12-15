
module Unix = UnixLabels

module SMap = Map.Make(String)
(* map Coq' Pp.t pretty printed expression tags to
 * kakoune faces.
 * The list comes from [coq/vernac/topfmt.ml] in Coq's repo *)
let highlighter_map = SMap.of_seq @@ List.to_seq
        [ "constr.keyword"   , "keyword"
        ; "module.keyword"   , "keyword"
        ; "tactic.keyword"   , "keyword"
        ; "constr.variable"  , "variable"
        ; "constr.reference" , "variable"
        ; "constr.evar"      , "value"
        ; "tactic.string"    , "string"
        ; "constr.notation"  , "operator"
        ; "constr.type"      , "type"
        ; "constr.path"      , "module"
        ; "module.definition", "function"
        ; "tactic.primitive" , "function"
        (* for internal use *)
        ; "value"            , "value"
        ; "error"            , "error"
        ; "warning"          , "warning" ]


let render_pretty ~content_file ~highlighter_file ?start_from pretty =
    let open_flags, init_row =
        match start_from with
        | Some init_row -> 
            ( [Open_append; Open_creat], init_row )
        | None ->
            ( [Open_wronly; Open_creat; Open_trunc], 1 )
    in
    let content     = open_out_gen open_flags 0o640 content_file in
    let highlighter = open_out_gen open_flags 0o640 highlighter_file in

    let update_loc (row, col) str =
        let rec loop (row, col) i =
            if i >= String.length str
            then (row, col)
            else if str.[i] = '\n'
            then loop (row + 1, 1) (i + 1)
            else loop (row, col + 1) (i + 1)
        in
        loop (row, col) 0
    in

    pretty |> List.fold_left begin fun (row, col) block ->
        output_string content block.Data.content;
        begin match SMap.find_opt block.Data.highlighter highlighter_map with
        | Some hl ->
            output_string highlighter " ";
            output_string highlighter (string_of_int row);
            output_string highlighter ".";
            output_string highlighter (string_of_int col);
            output_string highlighter "+";
            output_string highlighter (string_of_int @@ String.length block.Data.content);
            output_string highlighter "|";
            output_string highlighter hl
        | None ->
            ()
        end;
        update_loc (row, col) block.Data.content
    end (init_row, 1)
    |> fun (row_e, col_e) ->
    let row_e =
        if col_e <> 1
        then ( output_string content "\n"; row_e + 1 )
        else row_e
    in
    close_out content;
    close_out highlighter;
    row_e


let render_goals working_dir goals =
    render_pretty
        ~content_file:(working_dir ^ "/goal")
        ~highlighter_file:(working_dir ^ "/goal_highlighter")
    @@
    match goals with
    | None ->
        Data.[ { content = "there are no goals left."
               ; highlighter = "" } ]
    | Some Data.{ fg; bg; shelved; given_up } ->
        let n_shelved  = List.length shelved in
        let n_given_up = List.length given_up in
        let n_bg_before, n_bg_after, n_bg_layer = List.fold_left
                (fun (n_bg_before, n_bg_after, n_bg_layer) (bf, af) ->
                                ( n_bg_before + List.length bf
                                , n_bg_after  + List.length af
                                , n_bg_layer  + 1 ))
                (0, 0, 0) bg
        in
        begin match n_shelved, n_given_up with
        | 0, 0 -> []
        | n, 0 ->
            Data.[ { content = string_of_int n
                   ; highlighter = "value" }
                 ; { content = " shelved goals\n"
                   ; highlighter = ""} ]
        | 0, n ->
            Data.[ { content = string_of_int n
                   ; highlighter = "value" }
                 ; { content = " given up goals\n"
                   ; highlighter = ""} ]
        | m, n ->
            Data.[ { content = string_of_int m
                   ; highlighter = "value" }
                 ; { content = " shelved goals, "
                   ; highlighter = ""}
                 ; { content = string_of_int n
                   ; highlighter = "value" }
                 ; { content = " given up goals\n"
                   ; highlighter = ""} ]
        end
        @
        begin match n_bg_before, n_bg_after, n_bg_layer with
        | 0, 0, 0 -> []
        | b, a, n ->
            Data.[ { content = "current goal is in a focus stack of depth "
                   ; highlighter = "" }
                 ; { content = string_of_int n
                   ; highlighter = "value" }
                 ; { content = ".\nthere are "
                   ; highlighter = "" }
                 ; { content = string_of_int b
                   ; highlighter = "value" }
                 ; { content = " goals before focus, "
                   ; highlighter = "" }
                 ; { content = string_of_int a
                   ; highlighter = "value" }
                 ; { content = " goals after focus.\n"
                   ; highlighter = "" } ]
        end
        @ Data.[ { content = "=================================\n"
                 ; highlighter = "constr.keyword" } ]
        @
        begin match fg with
        | [] ->
            Data.[ { content = "there are no focused goal left.\n"
                   ; highlighter = "" } ]
        | _ ->
            Data.[ { content = "there are "
                   ; highlighter = "" }
                 ; { content = string_of_int (List.length fg)
                   ; highlighter = "value" }
                 ; { content = " focused goals left:\n\n"
                   ; highlighter = "" } ]
            @ List.concat_map begin fun goal ->
                    List.concat_map
                        (fun hyp -> hyp @ Data.[{content="\n"; highlighter=""}])
                        goal.Data.goal_hyp
                    @
                    Data.[ { content = "----------------------------("
                           ; highlighter = "" }
                         ; { content = goal.Data.goal_id
                           ; highlighter = "value" }
                         ; { content = ")\n"
                           ; highlighter = "" } ]
                    @ goal.Data.goal_ccl
                    @ Data.[ { content = "\n\n"; highlighter = "" } ]
                end fg
        end


let render_result ?start_from working_dir pretty =
    render_pretty
        ?start_from
        ~content_file:(working_dir ^ "/result")
        ~highlighter_file:(working_dir ^ "/result_highlighter")
        pretty




type kak_connnection =
    { session    : string
    ; main_buf   : string
    ; goal_buf   : string
    ; result_buf : string }


let run_kak_cmd session cmd =
    let open Unix in
    let (rd, wr) = pipe ~cloexec:true () in
    let null = openfile "/dev/null" ~mode:[O_WRONLY] ~perm:0o640 in
    ignore @@ create_process ~prog:"kak"
        ~args:[| "kak"; "-p"; session |]
        ~stdin:rd ~stdout:null ~stderr:Unix.stderr;
    ignore @@ Unix.write_substring wr ~buf:cmd ~pos:0 ~len:(String.length cmd);
    Unix.close null; Unix.close wr; Unix.close rd


let kak_refresh_goal session buf =
    run_kak_cmd session @@ String.concat " "
        [ "evaluate-commands"; "-buffer"; buf
        ; "%{ coqoune-refresh-goal }" ]

let kak_refresh_result session buf =
    run_kak_cmd session @@ String.concat " "
        [ "evaluate-commands"; "-buffer"; buf
        ; "%{ coqoune-refresh-result }" ]


let kak_set_processed_range =
    let last_update_time = ref (Unix.time()) in
    fun ?(force=false) session buf (added_row, added_col) (processed_row, processed_col) ->
        let t = Unix.time() in
        if force || t -. !last_update_time > 0.5 then begin
            last_update_time := t;
            let ar = string_of_int added_row in
            let ac = string_of_int added_col in
            let pr = string_of_int processed_row in
            let pc = string_of_int processed_col in
            run_kak_cmd session @@ String.concat " "
                [ "evaluate-commands"; "-buffer"; buf
                ; "%{ set-option buffer coqoune_processed_range"
                ; "%val{timestamp}"
                ; String.concat ""
                        [ "1.1,"; pr; "."   ; pc
                        ; "|coqoune_processed" ]
                ; String.concat ""
                        [ pr; "."; pc
                        ; ","; ar; "."; ac
                        ; "|coqoune_added" ]
                ; "}" ]
        end
