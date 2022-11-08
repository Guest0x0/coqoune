
type state_id =
    { state_id : int }

type route_id =
    { route_id : int }

type ('a, 'b) union =
    | Inl of 'a
    | Inr of 'b


type coq_info =
    { version      : string
    ; release_date : string }

let compare_version (m1, n1) (m2, n2) =
    match Int.compare m1 m2 with
    | 0 -> Int.compare n1 n2
    | n -> n


type location_offset =
    { start : int
    ; stop  : int }


type pretty_block =
    { content     : string
    ; highlighter : string }

type pretty_expr = pretty_block list

type goal =
    { goal_id   : string
    ; goal_hyp  : pretty_expr list
    ; goal_ccl  : pretty_expr }

type goals =
    { fg       : goal list
    ; bg       : (goal list * goal list) list
    ; shelved  : goal list
    ; given_up : goal list }



type data =
    | D_Unit
    | D_Bool     of bool
    | D_Int      of int
    | D_String   of string
    | D_State_Id of int
    | D_Route_Id of int
    | D_Coq_Info of coq_info
    | D_Location of location_offset
    | D_Pretty   of pretty_expr
    | D_Goal     of goal
    | D_Goals    of goals

    | D_Option   of data option
    | D_Union    of (data, data) union
    | D_Pair     of data * data
    | D_List     of data list

type _ data_type =
    | T_Unit     : unit            data_type
    | T_Bool     : bool            data_type
    | T_Int      : int             data_type
    | T_String   : string          data_type
    | T_State_Id : state_id        data_type
    | T_Route_Id : route_id        data_type
    | T_Coq_Info : coq_info        data_type
    | T_Location : location_offset data_type
    | T_Pretty   : pretty_expr     data_type
    | T_Goal     : goal            data_type
    | T_Goals    : goals           data_type

    | T_Option : 'a data_type -> 'a option data_type
    | T_List   : 'a data_type -> 'a list   data_type
    | T_Union  : 'a data_type * 'b data_type -> ('a, 'b) union data_type
    | T_Pair   : 'a data_type * 'b data_type -> ('a * 'b) data_type



let rec extract_data : 'a. 'a data_type -> data -> 'a
    = fun (type a) (ty : a data_type) data : a ->
        match ty, data with
        | T_Unit    , D_Unit        -> ()
        | T_Bool    , D_Bool     b  -> b
        | T_Int     , D_Int      i  -> i
        | T_String  , D_String   s  -> s
        | T_State_Id, D_State_Id id -> { state_id = id }
        | T_Route_Id, D_Route_Id id -> { route_id = id }
        | T_Coq_Info, D_Coq_Info i  -> i
        | T_Location, D_Location l  -> l
        | T_Pretty  , D_Pretty   pe -> pe
        | T_Goal    , D_Goal     g  -> g
        | T_Goals   , D_Goals    gs -> gs

        | T_Option ty', D_Option opt ->
            Option.map (extract_data ty') opt
        | T_List   ty', D_List   lst ->
            List.map (extract_data ty') lst

        | T_Union(ty', _), D_Union(Inl value') ->
            Inl(extract_data ty' value')
        | T_Union(_, ty'), D_Union(Inr value') ->
            Inr(extract_data ty' value')

        | T_Pair(ty1, ty2), D_Pair(v1, v2) ->
            ( extract_data ty1 v1, extract_data ty2 v2 )

        | _ ->
            failwith "extract_data"


(*
let rec pack_data : 'a. 'a data_type -> 'a -> data
    = fun (type a) (ty : a data_type) (value : a) ->
        match ty, value with
        | T_Unit    , () -> D_Unit
        | T_Bool    , b  -> D_Bool b
        | T_Int     , i  -> D_Int i
        | T_String  , s  -> D_String s
        | T_State_Id, id -> D_State_Id id.state_id
        | T_Route_Id, id -> D_Route_Id id.route_id
        | T_Pretty  , pe -> D_Pretty pe
        | T_Goal    , g  -> D_Goal g
        | T_Goals   , gs -> D_Goals gs

        | T_Option ty', opt -> D_Option(Option.map (pack_data ty') opt)
        | T_List   ty', lst -> D_List(List.map (pack_data ty') lst)

        | T_Union(ty', _), Inl value' -> D_Union(Inl(pack_data ty' value'))
        | T_Union(_, ty'), Inr value' -> D_Union(Inr(pack_data ty' value'))

        | T_Pair(ty1, ty2), (v1, v2) ->
            D_Pair(pack_data ty1 v1, pack_data ty2 v2)
*)



let rec xml_of_data data =
    let open Xml in
    match data with
    | D_Unit ->
        { tag = "unit"; attrs = []; body = [] }
    | D_Bool b ->
        { tag = "bool"; body = []
        ; attrs = ["val", if b then "true" else "false"] }
    | D_Int i ->
        { tag = "int"; attrs = []
        ; body = [Xml_Str(string_of_int i)] }
    | D_String s ->
        { tag = "string"; attrs = []
        ; body = [Xml_Str s] }
    | D_State_Id id ->
        { tag = "state_id"; body = []
        ; attrs = ["val", string_of_int id] }
    | D_Route_Id id ->
        { tag = "route_id"; body = []
        ; attrs = ["val", string_of_int id] }

    | D_Coq_Info _ | D_Location _ | D_Pretty _ | D_Goal _ | D_Goals _ ->
        (* there is no need to serialize these in this plugin *)
        failwith "xml_of_data"

    | D_Option None ->
        { tag = "option"; attrs = ["val", "none"]
        ; body = [] }
    | D_Option(Some data') ->
        { tag = "option"; attrs = ["val", "some"]
        ; body = [Xml_Elem(xml_of_data data')] }

    | D_Union(Inl data') ->
        { tag = "union"; attrs = ["val", "in_l"]
        ; body = [Xml_Elem(xml_of_data data')] }
    | D_Union(Inr data') ->
        { tag = "union"; attrs = ["val", "in_r"]
        ; body = [Xml_Elem(xml_of_data data')] }

    | D_Pair(fst, snd) ->
        { tag = "pair"; attrs = []
        ; body = [Xml_Elem(xml_of_data fst); Xml_Elem(xml_of_data snd)] }
    | D_List lst ->
        { tag = "list"; attrs = []
        ; body = List.map (fun d -> Xml_Elem(xml_of_data d)) lst }



let pretty_expr_of_xml xml =
    let open Xml in
    match xml.tag, xml.attrs, xml.body with
    | "_", [], [Xml_Elem { tag = "pp"; attrs = []; body }] ->
        let rec content_to_blocks outer_tag xml_content =
            match xml_content with
            | Xml_Str content ->
                [{ content; highlighter = outer_tag }]
            | Xml_Elem { tag; body } ->
                List.concat_map (content_to_blocks tag) body
        in
        List.concat_map (content_to_blocks "") body
    | _ ->
        failwith "pretty_expr_of_xml"


let rec data_of_xml xml =
    let open Xml in
    match xml.tag, xml.attrs, xml.body with
    | "unit", [], [] ->
        D_Unit
    | "bool", ["val", "true"], [] ->
        D_Bool true
    | "bool", ["val", "false"], [] ->
        D_Bool false
    | "int", [], [Xml_Str i] ->
        D_Int(int_of_string i)
    | "string", [], [Xml_Str s] ->
        D_String s
    | "string", [], [] ->
        D_String ""
    | ("state_id" | "edit_id"), ["val", id], [] ->
        D_State_Id(int_of_string id)
    | "route_id", ["val", id], [] ->
        D_Route_Id(int_of_string id)
    | "coq_info", [], [Xml_Elem ver; _; Xml_Elem date; _] ->
        D_Coq_Info {
            version      = extract_data T_String (data_of_xml ver);
            release_date = extract_data T_String (data_of_xml date)
        }
    | "loc", ["start", start; "stop", stop], [] ->
        D_Location { start = int_of_string start
                   ; stop  = int_of_string stop }
    | "richpp", [], [Xml_Elem pp] ->
        D_Pretty(pretty_expr_of_xml pp)
    | "goal", [], [Xml_Elem id; Xml_Elem hyp; Xml_Elem ccl]
    (* From Coq 8.14, there's a [string option] field for user-defined goal name.
       See [https://github.com/coq/coq/pull/14523] *)
    | "goal", [], [Xml_Elem id; Xml_Elem hyp; Xml_Elem ccl; _] ->
        D_Goal {
            goal_id  = extract_data T_String          (data_of_xml id);
            goal_hyp = extract_data (T_List T_Pretty) (data_of_xml hyp);
            goal_ccl = extract_data T_Pretty          (data_of_xml ccl)
        }
    | "goals", []
    , [Xml_Elem fg; Xml_Elem bg; Xml_Elem shelved; Xml_Elem given_up] ->
        D_Goals {
            fg = extract_data (T_List T_Goal) (data_of_xml fg);
            bg = data_of_xml bg |> extract_data @@
                T_List(T_Pair(T_List T_Goal, T_List T_Goal));
            shelved  = extract_data (T_List T_Goal) (data_of_xml shelved);
            given_up = extract_data (T_List T_Goal) (data_of_xml given_up)
        }

    | "option", ["val", "none"], [] ->
        D_Option None
    | "option", ["val", "some"], [Xml_Elem data'] ->
        D_Option(Some(data_of_xml data'))

    | "union", ["val", "in_l"], [Xml_Elem data'] ->
        D_Union(Inl(data_of_xml data'))
    | "union", ["val", "in_r"], [Xml_Elem data'] ->
        D_Union(Inr(data_of_xml data'))

    | "pair", [], [Xml_Elem fst; Xml_Elem snd] ->
        D_Pair(data_of_xml fst, data_of_xml snd)

    | "list", [], contents ->
        D_List(contents |> List.map @@ function
            | Xml_Elem elem -> data_of_xml elem
            | _             -> failwith "data_of_xml")

    | tag, _, _ ->
        failwith ("data_of_xml: " ^ tag)



type value =
    | Good of data
    | Fail of location_offset option * state_id * pretty_expr

type feedback_content =
    | Message of string * location_offset option * pretty_expr
    | Processed

type feedback =
    { fb_route_id : route_id
    ; fb_state_id : state_id
    ; fb_content  : feedback_content }


type coq_reply =
    | Value    of value
    | Feedback of feedback
    | Unknown



let reply_of_xml xml =
    let open Xml in
    match xml.tag, xml.attrs, xml.body with
    | "value", ["val", "good"], [Xml_Elem elem] ->
        Value(Good(data_of_xml elem))
    | "value", ["val", "fail"], [Xml_Elem sid; Xml_Elem err_msg] ->
        let state_id = extract_data T_State_Id (data_of_xml sid) in
        let err_msg  = extract_data T_Pretty   (data_of_xml err_msg) in
        Value(Fail(None, state_id, err_msg))
    | "value", ["val", "fail"; "loc_s", loc_s; "loc_e", loc_e]
    , [Xml_Elem sid; Xml_Elem err_msg] ->
        let state_id = extract_data T_State_Id (data_of_xml sid) in
        let err_msg  = extract_data T_Pretty   (data_of_xml err_msg) in
        let start = int_of_string loc_s in
        let stop  = int_of_string loc_e in
        Value(Fail(Some { start; stop }, state_id, err_msg))
    | "feedback", ["object", "state"; "route", route]
    , [ Xml_Elem sid
      ; Xml_Elem { tag = "feedback_content"
                 ; attrs = ["val", feedback_type]
                 ; body } ] ->
        let route_id = { route_id = int_of_string route } in
        let state_id = extract_data T_State_Id (data_of_xml sid) in
        begin match feedback_type, body with
        | "message"
        , [ Xml_Elem { tag = "message"; attrs = []
                     ; body =
                           [ Xml_Elem { tag = "message_level"
                                      ; attrs = ["val", level]
                                      ; body = [] }
                           ; Xml_Elem loc
                           ; Xml_Elem msg_content ]
                    } ] ->
            Feedback {
                fb_route_id = route_id;
                fb_state_id = state_id;
                fb_content = Message(
                    level, 
                    extract_data (T_Option T_Location) (data_of_xml loc),
                    extract_data T_Pretty (data_of_xml msg_content)
                )
            }
        | "processed", [] ->
            Feedback {
                fb_route_id = route_id;
                fb_state_id = state_id;
                fb_content = Processed
            }
        | _ ->
            Unknown
        end
    | _ ->
        Unknown
