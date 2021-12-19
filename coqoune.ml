
module Unix = UnixLabels


type state =
    { kak_session    : string
    ; kak_main_buf   : string
    ; working_dir    : string

    ; mutable coq_version : int * int
    ; mutable status : [`Ok | `Error]
    ; queued         : Usercmd.unfilled Usercmd.t Queue.t
    ; waiting        : Usercmd.filled   Usercmd.t Queue.t

    ; mutable added  : ((int * int) * Data.state_id) list
    ; mutable processed : (int * int)
    ; mutable err_loc   : Data.location_offset option

    ; mutable route_id : int

    ; mutable result_next_row : int
    ; mutable result_route_id : int }




let compare_loc (row1, col1) (row2, col2) =
    match Int.compare row1 row2 with
    | 0 -> Int.compare col1 col2
    | n -> n

let fill_usercmd state (cmd : Usercmd.unfilled Usercmd.t) =
    let open Usercmd in
    match cmd with
    | Init      -> Some Init
    | About     -> Some About
    | Quit      -> Some Quit
    | Goal      -> Some Goal
    | User_React -> Some User_React
    | AddE(loc_e, src) ->
        let loc_s, state_id = List.hd state.added in
        Some(AddF(state_id, loc_s, loc_e, src))
    | Back_To_Prev ->
        begin match state.added with
        | _ :: (_, state_id) :: _ ->
            Some(Back_To_State state_id)
        | _ ->
            None
        end
    | Back_To_Loc loc ->
        let rec find_state locs =
            match locs with
            | [] ->
                None
            | (loc', state_id) :: _
                when compare_loc loc' loc < 0 ->
                Some state_id
            | _ :: locs' ->
                find_state locs'
        in
        find_state state.added |> Option.map
            (fun state_id -> Back_To_State state_id)
    | Back_To_State sid ->
        Some(Back_To_State sid)
    | QueryE query ->
        let _, state_id = List.hd state.added in
        state.route_id <- state.route_id + 1;
        let route_id = Data.{ route_id = state.route_id } in
        Some(QueryF(state_id, route_id, query))



exception Quit

let log str =
    Printf.eprintf "%s\n" str;
    flush stderr



let show_error_msg state err_msg =
    let err_msg =
        Data.{ content = "[error]"; highlighter = "error" }
        :: Data.{ content = " "; highlighter = "" }
        :: err_msg
    in
    state.result_next_row <- Interface.render_result
            state.working_dir err_msg;
    Interface.kak_refresh_result state.kak_session state.kak_main_buf

let handle_error state (err_loc, safe_locs, err_msg) =
    state.status <- `Error;
    Queue.clear state.queued;
    (* Queue.clear state.waiting; *)
    state.added <- safe_locs;
    let safe_loc, safe_sid = List.hd safe_locs in
    Queue.add (Usercmd.Back_To_State safe_sid) state.queued;

    show_error_msg state err_msg;

    begin match err_loc with
    | Some _ ->
        state.err_loc <- err_loc;
        Interface.kak_set_error_range
            state.kak_session state.kak_main_buf
            safe_loc err_loc
    | None ->
        ()
    end;

    if compare_loc safe_loc state.processed < 0 then
        state.processed <- safe_loc;
    Interface.kak_set_processed_range ~force:true
        state.kak_session state.kak_main_buf safe_loc state.processed


let process_cmd state cmd =
    let open Data in
    match cmd with
    | Feedback { fb_route_id = { route_id }
               ; fb_state_id = { state_id = err_sid }
               ; fb_content = Message("error", err_loc, err_msg) } ->
        begin match List.partition
                (fun (_, { state_id }) -> state_id >= err_sid)
                state.added
        with
        | [], _ ->
            ()
        | ((row, col), _) :: _, safe_locs ->
            log @@ String.concat ""
                [ "[Coqoune] entering error state due to process failure at ("
                ; string_of_int row; ", "; string_of_int col; ")" ];
            handle_error state (err_loc, safe_locs, err_msg)
        end

    | Value(Good data) ->
        begin match Queue.pop state.waiting with
        | Usercmd.User_React ->
            failwith "impossible"
        | Usercmd.Init ->
            let sid = extract_data T_State_Id data in
            log ("[Coqoune] init state_id " ^ string_of_int sid.state_id);
            state.added <- [(1, 1), sid]
        | Usercmd.About ->
            let info = extract_data T_Coq_Info data in
            Scanf.sscanf info.version "%d.%d.%d" begin fun major minor _ ->
                state.coq_version <- (major, minor)
            end;
            log ("[Coqoune] Coq version: " ^ info.version);
            log ("[Coqoune] Coq release: " ^ info.release_date);
            ignore info
        | Usercmd.Quit ->
            raise Quit
        | Usercmd.Back_To_State { state_id = sid } ->
            let rec pop_locs () =
                match state.added with
                | [] ->
                    failwith "process_cmd: empty state list"
                | (loc, { state_id }) :: _ when state_id = sid ->
                    loc
                | _ :: rest ->
                    state.added <- rest;
                    pop_locs ()
            in
            let (row, col) = pop_locs () in
            log @@ String.concat ""
                [ "[Coqoune] jump back to ("
                ; string_of_int row; ", "; string_of_int col; ")" ];
            if compare_loc (row, col) state.processed < 0 then
                state.processed <- (row, col);
            Interface.kak_set_processed_range
                state.kak_session state.kak_main_buf (row, col) state.processed;
            if state.status = `Ok then begin
                state.result_route_id <- (-1);
                ignore @@ Interface.render_result state.working_dir [];
                Interface.kak_refresh_result state.kak_session state.kak_main_buf;
            end;

            begin match state.err_loc with
            | Some _ when state.status = `Ok ->
                state.err_loc <- None;
                Interface.kak_set_error_range
                    state.kak_session state.kak_main_buf
                    (row, col) None
            | _ ->
                ()
            end
        | _ when state.status = `Error ->
            ()
        | Usercmd.AddF(_, _, ((row, col) as loc_e), src) ->
            let (state_id, new_state_id) =
                match Data.compare_version state.coq_version (8, 16) with
                | n when n < 0 ->
                    extract_data
                        (T_Pair(T_State_Id, T_Pair(
                                            T_Union(T_Unit, T_State_Id),
                                            T_String
                                            )))
                        data
                    |> fun (state_id, (new_state_id, _)) ->
                    (state_id, new_state_id)
                | _ ->
                    extract_data
                        (T_Pair(T_State_Id, T_Union(T_Unit, T_State_Id)))
                        data
            in
            log @@ String.concat ""
                [ "[Coqoune] added expr: ("
                ; string_of_int row; ", "; string_of_int col; ")" ];

            begin match new_state_id with
            | Inl () ->
                state.added <- (loc_e, state_id) :: state.added
            | Inr new_state_id ->
                state.added <- (loc_e, new_state_id) :: state.added
            end;

            Interface.kak_set_processed_range
                state.kak_session state.kak_main_buf (row, col) state.processed;

            if state.result_route_id >= 0 then begin
                ignore @@ Interface.render_result state.working_dir [];
                Interface.kak_refresh_result state.kak_session state.kak_main_buf
            end;
            state.result_route_id <- (-1);

            begin match state.err_loc with
            | Some _ ->
                state.err_loc <- None;
                Interface.kak_set_error_range
                    state.kak_session state.kak_main_buf
                    loc_e None
            | None ->
                ()
            end;

        | Goal ->
            let goals = extract_data (T_Option T_Goals) data in
            ignore @@ Interface.render_goals state.working_dir goals;
            Interface.kak_refresh_goal state.kak_session state.kak_main_buf;
            Interface.kak_set_processed_range ~force:true
                state.kak_session state.kak_main_buf
                (fst @@ List.hd state.added) state.processed
        | QueryF _ ->
            ()
        end

    | Value(Fail(err_loc, { state_id = safe_sid }, err_msg)) ->
        begin match Queue.pop state.waiting with
        | _ when state.status = `Error ->
            ()
        | Usercmd.Init ->
            ignore @@ Interface.render_result state.working_dir
                [ Data.{ content = "failed to init coqidetop. exiting"
                       ; highlighter = "" } ];
            Interface.kak_refresh_result state.kak_session state.kak_main_buf;
            raise Quit
        | Usercmd.QueryF _ ->
            log("[Coqoune] query failed");
            show_error_msg state err_msg
        | _ ->
            log("[Coqoune] entering error state due to command failure");
            handle_error state (err_loc, state.added, err_msg)
        end

    | _ when state.status = `Error ->
        ()

    | Feedback { fb_route_id = { route_id }
               ; fb_state_id = { state_id }
               ; fb_content  = Message(level, _, content) } ->
        if state_id = (snd @@ List.hd state.added).state_id then begin
            let content =
                match level with
                | "warning" ->
                    Data.{ content = "[warning] "
                         ; highlighter = "warning" }
                    :: content
                | _ ->
                    content
            in
            let start_from =
                match Int.compare route_id state.result_route_id with
                | 0 ->
                    Some(Some state.result_next_row)
                | ord when ord >= 0 ->
                    Some None
                | _ ->
                    None
            in
            start_from |> Option.iter begin fun start_from ->
                state.result_next_row <- Interface.render_result
                        ?start_from state.working_dir content;
                state.result_route_id <- route_id;
                Interface.kak_refresh_result
                    state.kak_session state.kak_main_buf
            end
      end
    | Feedback { fb_route_id = { route_id }
               ; fb_state_id = { state_id = processed_sid }
               ; fb_content  = Processed } ->
        List.find_opt
            (fun (_, { state_id }) -> state_id = processed_sid)
            state.added
        |> Option.iter (fun (loc, _) ->
            if compare_loc loc state.processed > 0 then begin
                log @@ String.concat ""
                    [ "[Coqoune] updating processed range to ("
                    ; string_of_int (fst loc); ", "
                    ; string_of_int (snd loc); ")" ];
                state.processed <- loc;
                Interface.kak_set_processed_range
                    state.kak_session state.kak_main_buf
                    (fst @@ List.hd state.added) loc
            end)
    | Unknown ->
        ()




let _ =
    if Array.length Sys.argv < 4 then
        exit 1;

    let state =
        { kak_session  = Sys.argv.(2)
        ; kak_main_buf = Sys.argv.(3)
        ; working_dir  = Sys.argv.(1)

        ; coq_version = (0, 0)

        ; status      = `Ok
        ; queued      = Queue.create ()
        ; waiting     = Queue.create ()

        ; added       = []
        ; processed   = (1, 1)
        ; err_loc     = None

        ; route_id    = 0

        ; result_next_row = 1
        ; result_route_id = -1 }
    in

    let (from_coq, coq_to_here) = Unix.pipe ~cloexec:true () in
    let (coq_from_here, to_coq) = Unix.pipe ~cloexec:true () in
    let coqidetop_pid = Unix.create_process
            ~prog:"coqidetop"
            ~args:[|"coqidetop"; "-main-channel"; "stdfds"|]
            ~stdin:coq_from_here ~stdout:coq_to_here ~stderr:Unix.stderr
    in
    log (string_of_int coqidetop_pid);

    Sys.[ sigterm; sigabrt; sigint; sigquit ]
    |> List.iter begin fun signal ->
        Sys.set_signal signal @@ Sys.Signal_handle(fun _ ->
            Unix.kill ~pid:coqidetop_pid ~signal:Sys.sigkill)
    end;

    let reply_input = Xml.make_input 200 from_coq in
    let stdin_input = Xml.make_input 200 Unix.stdin in

    Queue.add Usercmd.Init  state.queued;
    Queue.add Usercmd.About state.queued;

    let rec loop () =
        let can_read =
            if reply_input#really_can_read
            then [from_coq] 
            else if stdin_input#really_can_read
            then [Unix.stdin]
            else
                let (can_read, _, _) = Unix.select
                        ~read:[from_coq; Unix.stdin] ~write:[] ~except:[]
                        ~timeout:(-1.)
                in can_read
        in
        if List.mem from_coq can_read || reply_input#really_can_read then begin
            Xml.read_element reply_input
            |> Data.reply_of_xml
            |> process_cmd state
        end;
        if List.mem Unix.stdin can_read || stdin_input#really_can_read then begin
            Xml.read_element stdin_input
            |> Usercmd.of_xml
            |> Option.iter @@ fun cmd ->
            match state.status, cmd with
            | _, Usercmd.User_React ->
                state.status <- `Ok
            | `Ok, cmd ->
                Queue.add cmd state.queued
            | `Error, _ ->
                ()
        end;
        if Queue.is_empty state.waiting
        && not (Queue.is_empty state.queued) then begin
            fill_usercmd state (Queue.pop state.queued)
            |> Option.iter (fun cmd ->
                Queue.add cmd state.waiting;
                let xml = Usercmd.to_xml state.coq_version cmd in
                Xml.output_element to_coq xml)
        end;
        loop ()
    in
    begin try loop () with
    | End_of_file ->
        log "EOF"
    | Quit ->
        log "user quit"
    | Xml.Syntax_Error msg ->
        log("Xml syntax error: " ^ msg);
    | Failure msg ->
        log ("failure: " ^ msg)
    | Unix.Unix_error(err, func, msg) ->
        log ("unix error " ^ Unix.error_message err ^ ": " ^ func ^ ": " ^ msg)
    end
