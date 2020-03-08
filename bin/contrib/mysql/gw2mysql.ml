(* Copyright (c) 2020 Ludovic LEDIEU *)

open Mysql
open Geneweb
open Def
open Gwdb

let string_of_sex = function
| Male -> "M"
| Female -> "F"
| Neuter -> ""

let string_of_access = function
| IfTitles -> "IfTitles"
| Public -> "Public"
| Private -> "Private"

type gen_record = History_diff.gen_record =
  { date : string;
    wizard : string;
    gen_p : (iper, string) gen_person;
    gen_f : (iper, string) gen_family list;
    gen_c : iper array list }

let insert db debug t v =
  if debug then Printf.printf "%s\n%!" v ;
  ignore (exec db ( "insert into " ^ t ^ " values " ^ v))

let insert_new_text db debug t v =
  insert db debug t (values [
	"null" ;
	ml2rstr db v ;
  ]) ;
  insert_id db

let event base db i_p1 i_p2 t n date place note source reason witnesses =
  let place = sou base place in
  let note = sou base note in
  let source = sou base source in
  (* if date <> Adef.cdate_None || place <> "" || note <> "" || source <> "" then FIXME contrôle utile uniquement en v6 ? *)
    let date = Adef.od_of_cdate date in
    let go_insert d =
	let n_id =
	  if note <> "" then ml642int (insert_new_text db false "notes" note)
	  else "null"
	in
	let s_id =
	  if source <> "" then ml642int (insert_new_text db false "sources" source)
	  else "null"
	in
        insert db false "events" (values [
	  "null" ;
	  ml2rstr db (if t = "Name" then "EVEN" else t) ;
	  ml2rstr db (if t = "EVEN" || t = "FACT" then n else "") ;
	  ml2rstr db (match d with
	  | Some (Dgreg (dmy, _)) ->
		begin match dmy.prec with
		| Sure -> ""
		| About -> "ABT"
		| Maybe -> "Maybe" (* FIXME: mauvais usage dans GeneWeb => comment ajuster ? *)
		| Before -> "BEF"
		| After -> "AFT"
		| OrYear _ -> raise (Failure "OrYear")
		| YearInt _ -> raise (Failure "YearInt")
		end
	  | _ -> ""
	  ) ;
	  ml2rstr db (match d with
	  | Some (Dgreg (_, calendar)) -> 
		begin match calendar with
		| Dgregorian -> "Gregorian"
		| Djulian -> "Julian"
		| Dfrench -> "French"
		| Dhebrew -> "Hebrew"
		end
	  | _ -> "Gregorian"
          ) ;
	  ml2int (match d with
	  | Some (Dgreg (dmy, _)) -> dmy.day
	  | _ -> 0
	  ) ;
	  ml2int (match d with
	  | Some (Dgreg (dmy, _)) -> dmy.month
	  | _ -> 0
	  ) ;
	  ml2int (match d with
	  | Some (Dgreg (dmy, _)) -> dmy.year
	  | _ -> 0
	  ) ;
	  ml2rstr db "Gregorian" ; ml2int 0 ; ml2int 0 ; ml2int 0 ;
	  ml2rstr db (match d with
	  | Some Dtext s -> s
	  | _ -> ""
          ) ;
	  ml2rstr db reason ;
	  ml2rstr db place ;
	  "null" ;
	  n_id ;
	  s_id ;
        ]);
	let e_id = ml642int (insert_id db) in
	insert db false "person_event" (values [
		"null" ;
		e_id ;
	  	ml2int i_p1 ;
		ml2rstr db "Main" ;
	]) ;
	begin match i_p2 with
	| Some i ->
	    insert db false "person_event" (values [
		"null" ;
		e_id ;
	  	ml2int i ;
		ml2rstr db "Main" ;
	    ])
	| _ -> ()
	end ;
	Array.iter (fun (iper, role) ->
	  insert db false "person_event" (values [
		"null" ;
		e_id ;
		ml2int (Adef.int_of_iper iper) ;
		ml2rstr db (match role with
		| Witness -> "Witness"
		| Witness_GodParent -> "Godparent"
		| Witness_Officer -> "Official"
		) ;
	  ])
        ) witnesses
    in
    match date with
    | Some (Dgreg (dmy, calendar)) ->
	begin match dmy.prec with
	| OrYear dmy2 ->
            begin
		go_insert (Some (Dgreg ({dmy with prec = Sure ; day = dmy2.day2 ; month = dmy2.month2 ; year = dmy2.year2}, calendar)));
		go_insert (Some (Dgreg ({dmy with prec = Sure}, calendar)))
	    end
	| YearInt dmy2 ->
            begin
		go_insert (Some (Dgreg ({dmy with prec = Before ; day = dmy2.day2 ; month = dmy2.month2 ; year = dmy2.year2}, calendar)));
		go_insert (Some (Dgreg ({dmy with prec = After}, calendar)))
	    end
	| _ -> go_insert date
	end
    | _ -> go_insert date

let create_group_fix db g_id n_id s_id o =
  insert db false "groups" (values [
	ml2int g_id ;
	n_id ;
	s_id ;
	ml2rstr db o ;
  ])

let populate_group db g_id p_i role seq =
  ignore (insert db false "person_group" (values [
	"null" ;
	ml2int g_id ;
	ml2int p_i ;
        ml2rstr db role ;
	ml2int seq ;
  ]))

let gw_to_mysql base db fname =
  Printf.eprintf "Parsing persons - step 1 :\n%!" ;
  (* For each person *)
  let nb_ind = nb_of_persons base in
  (* iper -> p_id *)
  ProgrBar.start ();
  for i = 0 to nb_ind - 1 do
    ProgrBar.run i nb_ind;
    let p = poi base (Adef.iper_of_int i) in
    let sn = p_surname base p in
    let fn = p_first_name base p in
    let oc = get_occ p in
    let death = get_death p in
    let isDead d =
	match d with
	| NotDead -> "NotDead"
	| Death _ -> "Dead"
	| DeadYoung -> "DeadYoung"
	| DeadDontKnowWhen -> "DeadDontKnowWhen"
	| DontKnowIfDead -> "DontKnowIfDead"
	| OfCourseDead -> "OfCourseDead"
    in
    let n_id =
      let notes = sou base (get_notes p) in
      if notes <> "" then ml642int (insert_new_text db false "notes" notes)
      else "null"
    in
    let s_id =
      let psources = sou base (get_psources p) in
      if psources <> "" then ml642int (insert_new_text db false "sources" psources)
      else "null"
    in
    let consang = get_consang p in
    let consang =
      if consang = Adef.fix (-1) then -1.0
      else Adef.float_of_fix consang *. 100.0
    in
    let pkey =
      (Mutil.tr ' ' '_' (Name.lower fn)) ^ "." ^
      (string_of_int oc) ^ "." ^
      (Mutil.tr ' ' '_' (Name.lower sn))
    in
    insert db false "persons" (values [
	ml2int i ;
	ml2rstr db pkey ;
	ml2rstr db (fn ^ "." ^ (string_of_int oc) ^ " " ^ sn) ;
	ml2int oc ;
	ml2rstr db (isDead death) ;
	n_id ;
	s_id ;
	ml2float consang ;
	ml2rstr db (string_of_sex (get_sex p)) ;
	ml2rstr db (string_of_access (get_access p)) ;
	ml2rstr db (sou base (get_public_name p)) ;
    ]);
    (* Dispatch occupation on events *)
    let insert_occupation p_id r o_start o_end y_start y_end =
      let occu =
        let last = (BatText.length r) - 1 in
        if o_start >= o_end || o_end > last then begin
          Printf.eprintf "\nBUG insert_occupation : (%d) %d-%d-%d %s\n%!" i o_start o_end last (BatText.to_string r) ;
          raise (Failure "insert_occupation")
        end else BatText.to_string (BatText.sub r o_start (o_end-o_start+1))
      in
      insert db false "events" (values [
	  "null" ;
	  ml2rstr db "OCCU" ; ml2rstr db "" ;
	  ml2rstr db (if y_end <> 0 then "FROM-TO" else "") ;
	  ml2rstr db "Gregorian" ; ml2int 0 ; ml2int 0 ; ml2int y_start ;
	  ml2rstr db "Gregorian" ; ml2int 0 ; ml2int 0 ; ml2int y_end ;
	  ml2rstr db "" ; ml2rstr db "" ; ml2rstr db "" ;
	  "null" ; "null" ; "null" ;
      ]);
      let e_id = ml642int (insert_id db) in
      insert db false "occupation_details" (values [
	e_id ;
	ml2rstr db occu ;
	"null" ;
      ]);
      insert db false "person_event" (values [
	"null" ;
	e_id ;
	ml2int p_id ;
	ml2rstr db "Main" ;
      ])
    in
    let my_index_from_opt r pos c =
      try
        let pos1 = BatText.index_from r pos c in
        if pos1 < pos then None (* BUG workarround *)
        else Some pos1
      with
      | Not_found -> None
      | _ -> begin
          Printf.eprintf "\nBUG my_index_from_opt : (%d) %d %s\n%!" i pos (BatText.to_string r) ;
          raise (Failure "my_index_from_opt")
        end
    in
    let parse_period r o_start o_end p_start p_end =
      (* Printf.eprintf "DEBUG period (%d) : %d-%d %d-%d\n%!" i o_start o_end p_start p_end ; *)
      let to_int r pos1 pos2 =
        let last = (BatText.length r) - 1 in
        if pos1 > last || pos2 > last then begin
          Printf.eprintf "\nBUG to_int : (%d) %d-%d %s\n%!" i pos1 pos2 (BatText.to_string r) ;
          raise (Failure "to_int")
        end ;
	if pos1 >= pos2 then 0
        else int_of_string (BatText.to_string (BatText.sub r pos1 (pos2-pos1+1)))
      in
      match my_index_from_opt r p_start (BatUChar.of_char '-') with
      | Some pos when pos <= p_end -> insert_occupation i
          r o_start o_end
          (to_int r p_start (pos-1))
          (to_int r (pos+1) p_end)
      | _ -> insert_occupation i
          r o_start o_end
          (to_int r p_start p_end)
          0
    in
    let rec parse_dates r o_start o_end d_start d_end =
      (* Printf.eprintf "DEBUG dates (%d) : %d-%d %d-%d\n%!" i o_start o_end d_start d_end ; *)
      if (BatText.get r o_start) = (BatUChar.of_char ' ') then parse_dates r (o_start+1) o_end d_start d_end
      else if (BatText.get r o_end) = (BatUChar.of_char ' ') then parse_dates r o_start (o_end-1) d_start d_end
      else if (BatText.get r d_start) = (BatUChar.of_char ' ') then parse_dates r o_start o_end (d_start+1) d_end
      else if o_start >= o_end then
        raise (Failure (Printf.sprintf "Occupation (%d) %d-%d !! : %s\n" i o_start o_end (BatText.to_string r)))
      else
        match my_index_from_opt r d_start (BatUChar.of_char ',') with
        | Some pos when pos <= d_end -> begin
            parse_period r o_start o_end d_start (pos-1) ;
            parse_dates r o_start o_end (pos+1) d_end
          end
        | _ -> parse_period r o_start o_end d_start d_end
    in
    let rec parse_occupation r pos0 =
      (* Printf.eprintf "DEBUG occupation (%d) %d : %s\n%!" i pos0 (BatText.to_string r) ; *)
      let last = (BatText.length r) - 1 in
      if last <= pos0 then ()
      else if (BatText.get r pos0) = (BatUChar.of_char ',') ||
        (BatText.get r pos0) = (BatUChar.of_char ' ') then parse_occupation r (pos0+1)
      else
        let subparse pos1 =
          match my_index_from_opt r pos1 (BatUChar.of_char ')') with
          | Some pos2 -> begin
              begin
                try parse_dates r pos0 (pos1-1) (pos1+1) (pos2-1)
                with Failure _ -> insert_occupation i r pos0 pos2 0 0
              end ;
              parse_occupation r (pos2+1)
            end
          | None -> Printf.eprintf "\nMalformed occupation (%d) : %s\n" i (BatText.to_string r)
        in
        match my_index_from_opt r pos0 (BatUChar.of_char '('),
              my_index_from_opt r pos0 (BatUChar.of_char ',') with
        | Some pos1, None -> subparse pos1
        | Some pos1, Some pos1b when pos1 < pos1b -> subparse pos1
        | _, Some pos1 -> begin
            insert_occupation i r pos0 (pos1-1) 0 0 ;
            parse_occupation r (pos1+1)
          end
        | None, None -> insert_occupation i r pos0 last 0 0
    in parse_occupation (BatText.of_string (sou base (get_occupation p))) 0 ;
    (* FIXME trop simplifié ? *)
    let has_image_file =
      let f = "images/" ^ fname ^ "/" ^ pkey in
      if Sys.file_exists (f ^ ".gif") then Some (f ^ ".gif")
      else if Sys.file_exists (f ^ ".jpg") then Some (f ^ ".jpg")
      else if Sys.file_exists (f ^ ".png") then Some (f ^ ".png")
      else None
    in
    begin match has_image_file with
    | Some f ->
        insert db false "medias" (values [
		"null" ;
		ml2rstr db f ;
	]);
	let m_id = ml642int (insert_id db) in
        insert db false "person_media" (values [
		"null" ;
		ml2int i ;
		m_id ;
	]);
    | None -> ()
    end ;
    if sn <> "?" || fn <> "?" then
    insert db false "names" (values [
	"null" ;
	ml2int i ;
	ml2rstr db "" ;
	ml2rstr db fn ;
	ml2rstr db "" ;
	ml2rstr db "" ;
	ml2rstr db sn ;
	ml2rstr db "" ;
	ml2rstr db "True" ;
    ]);
    List.iter (fun a ->
      insert db false "names" (values [
	"null" ;
	ml2int i ;
	ml2rstr db "" ;
	ml2rstr db (sou base a) ;
	ml2rstr db "" ;
	ml2rstr db "" ;
	ml2rstr db sn ;
	ml2rstr db "" ;
	ml2rstr db "False" ;
      ])
    ) (get_first_names_aliases p) ;
    List.iter (fun a ->
      insert db false "names" (values [
	"null" ;
	ml2int i ;
	ml2rstr db "" ;
	ml2rstr db fn ;
	ml2rstr db "" ;
	ml2rstr db "" ;
	ml2rstr db (sou base a) ;
	ml2rstr db "" ;
	ml2rstr db "False" ;
      ])
    ) (get_surnames_aliases p) ;
    List.iter (fun a ->
      insert db false "names" (values [
	"null" ;
	ml2int i ;
	ml2rstr db "" ;
	ml2rstr db (sou base a) ;
	ml2rstr db "" ;
	ml2rstr db "" ;
	ml2rstr db "" ;
	ml2rstr db "" ;
	ml2rstr db "False" ;
      ])
    ) (get_aliases p) ;
    List.iter (fun a ->
      insert db false "names" (values [
	"null" ;
	ml2int i ;
	ml2rstr db "" ;
	ml2rstr db fn ;
	ml2rstr db (sou base a) ;
	ml2rstr db "" ;
	ml2rstr db "" ;
	ml2rstr db "" ;
	ml2rstr db "False" ;
      ])
    ) (get_qualifiers p) ;
    (* titles FIXME rework needed *)
    let get_dmy2 d =
      match d with
      | Some (Dgreg (dmy, _)) ->
	begin match dmy.prec with
	| OrYear dmy2 -> Some dmy2
	| YearInt dmy2 -> Some dmy2
	| _ -> None
	end
      | _ -> None
    in
    List.iter (fun t ->
      let d_start = Adef.od_of_cdate t.t_date_start in
      let d_start_dmy2 = get_dmy2 d_start in
      let d_end = Adef.od_of_cdate t.t_date_end in
      let d_end_dmy2 = get_dmy2 d_end in
      insert db false "events" (values [
	  "null" ;
	  ml2rstr db "TITL" ;
	  ml2rstr db "" ;
	  ml2rstr db (match d_start, d_end with
	  | None, None -> ""
          | Some _, None -> "FROM"
          | None, Some _ -> "TO"
          | Some _, Some _ -> "FROM-TO"
	  ) ;
	  ml2rstr db (match d_start with
	  | Some (Dgreg (_, calendar)) -> 
		begin match calendar with
		| Dgregorian -> "Gregorian"
		| Djulian -> "Julian"
		| Dfrench -> "French"
		| Dhebrew -> "Hebrew"
		end
	  | _ -> "Gregorian"
          ) ;
	  ml2int (match d_start with
	  | Some (Dgreg (dmy, _)) -> dmy.day
	  | _ -> 0
	  ) ;
	  ml2int (match d_start with
	  | Some (Dgreg (dmy, _)) -> dmy.month
	  | _ -> 0
	  ) ;
	  ml2int (match d_start with
	  | Some (Dgreg (dmy, _)) -> dmy.year
	  | _ -> 0
	  ) ;
	  ml2rstr db (match d_end with
	  | Some (Dgreg (_, calendar)) -> 
		begin match calendar with
		| Dgregorian -> "Gregorian"
		| Djulian -> "Julian"
		| Dfrench -> "French"
		| Dhebrew -> "Hebrew"
		end
	  | _ -> "Gregorian"
          ) ;
	  ml2int (match d_end with
	  | Some (Dgreg (dmy, _)) -> dmy.day
	  | _ -> 0
	  ) ;
	  ml2int (match d_end with
	  | Some (Dgreg (dmy, _)) -> dmy.month
	  | _ -> 0
	  ) ;
	  ml2int (match d_end with
	  | Some (Dgreg (dmy, _)) -> dmy.year
	  | _ -> 0
	  ) ;
	  ml2rstr db "" ;
	  ml2rstr db "" ;
	  ml2rstr db "" ;
	  "null" ;
	  "null" ;
	  "null" ;
        ]);
	let e_id = ml642int (insert_id db) in
	insert db false "title_details" (values [
		e_id ;
		ml2rstr db (sou base t.t_ident) ;
		ml2rstr db (sou base t.t_place) ;
	  	ml2int t.t_nth ;
		ml2rstr db (match t.t_name with
                | Tmain -> "True"
                | _ -> "False"
                ) ;
		ml2rstr db (match t.t_name with
                | Tname n -> sou base n
                | _ -> ""
                ) ;
	        ml2rstr db (match d_start with
	        | Some (Dgreg (dmy, _)) ->
		  begin match dmy.prec with
		  | Sure -> ""
		  | About -> "ABT"
		  | Maybe -> "Maybe"
		  | Before -> "BEF"
		  | After -> "AFT"
		  | OrYear _ -> "OrYear"
		  | YearInt _ -> "YearInt"
		  end
	        | _ -> ""
	        ) ;
	        ml2rstr db (match d_start with
	        | Some (Dgreg (_, calendar)) -> 
		  begin match calendar with
		  | Dgregorian -> "Gregorian"
		  | Djulian -> "Julian"
		  | Dfrench -> "French"
		  | Dhebrew -> "Hebrew"
		  end
	        | _ -> "Gregorian"
                ) ;
	        ml2int (match d_start with
	        | Some (Dgreg (dmy, _)) -> dmy.day
	        | _ -> 0
	        ) ;
	        ml2int (match d_start with
	        | Some (Dgreg (dmy, _)) -> dmy.month
	        | _ -> 0
	        ) ;
	        ml2int (match d_start with
	        | Some (Dgreg (dmy, _)) -> dmy.year
	        | _ -> 0
	        ) ;
	        ml2int (match d_start_dmy2 with
	        | Some dmy -> dmy.day2
	        | _ -> 0
	        ) ;
	        ml2int (match d_start_dmy2 with
	        | Some dmy -> dmy.month2
	        | _ -> 0
	        ) ;
	        ml2int (match d_start_dmy2 with
	        | Some dmy -> dmy.year2
	        | _ -> 0
	        ) ;
	        ml2rstr db (match d_start with
	        | Some Dtext s -> s
	        | _ -> ""
                ) ;
	        ml2rstr db (match d_end with
	        | Some (Dgreg (dmy, _)) ->
		  begin match dmy.prec with
		  | Sure -> ""
		  | About -> "ABT"
		  | Maybe -> "Maybe"
		  | Before -> "BEF"
		  | After -> "AFT"
		  | OrYear _ -> "OrYear"
		  | YearInt _ -> "YearInt"
		  end
	        | _ -> ""
	        ) ;
	        ml2rstr db (match d_end with
	        | Some (Dgreg (_, calendar)) -> 
		  begin match calendar with
		  | Dgregorian -> "Gregorian"
		  | Djulian -> "Julian"
		  | Dfrench -> "French"
		  | Dhebrew -> "Hebrew"
		  end
	        | _ -> "Gregorian"
                ) ;
	        ml2int (match d_end with
	        | Some (Dgreg (dmy, _)) -> dmy.day
	        | _ -> 0
	        ) ;
	        ml2int (match d_end with
	        | Some (Dgreg (dmy, _)) -> dmy.month
	        | _ -> 0
	        ) ;
	        ml2int (match d_end with
	        | Some (Dgreg (dmy, _)) -> dmy.year
	        | _ -> 0
	        ) ;
	        ml2int (match d_end_dmy2 with
	        | Some dmy -> dmy.day2
	        | _ -> 0
	        ) ;
	        ml2int (match d_end_dmy2 with
	        | Some dmy -> dmy.month2
	        | _ -> 0
	        ) ;
	        ml2int (match d_end_dmy2 with
	        | Some dmy -> dmy.year2
	        | _ -> 0
	        ) ;
	        ml2rstr db (match d_end with
	        | Some Dtext s -> s
	        | _ -> ""
                ) ;
	]) ;
    ) (get_titles p) ;
    (* Initilise family group / parent link *)
    Array.iteri (fun seq ifam ->
      let g_id = (Adef.int_of_ifam ifam) in
      let cpl = foi base ifam in
      let i_father = Adef.int_of_iper (get_father cpl) in
      let i_mother = Adef.int_of_iper (get_mother cpl) in
      if (i = i_father && i_father < i_mother) ||
         (i = i_mother && i_mother < i_father) then begin
        let n_id =
          let note = sou base (get_comment cpl) in
          if note <> "" then ml642int (insert_new_text db false "notes" note)
          else "null"
        in
        let s_id =
          let source = sou base (get_fsources cpl) in
          if source <> "" then ml642int (insert_new_text db false "sources" source)
          else "null"
        in
        create_group_fix db g_id n_id s_id (sou base (get_origin_file cpl))
      end ;
      populate_group db g_id i "Parent" seq
    ) (get_family p) ;
    (* Ces événements sont en doublon dans pevents en v7 / à conserver pour la v6
    event base db i "BIRT" "" (get_birth p) (get_birth_place p) (get_birth_note p) (get_birth_src p) "" [];
    event base db i "BAPM" "" (get_baptism p) (get_baptism_place p) (get_baptism_note p) (get_baptism_src p) "" [];
    begin match death with
    | Death (r, d) ->
	let reason = match r with
          | Killed -> "Killed"
          | Murdered -> "Murdered"
          | Executed -> "Executed"
          | Disappeared -> "Disappeared"
          | Unspecified -> ""
	in
        event base db i "DEAT" "" d (get_death_place p) (get_death_note p) (get_death_src p) reason [];
    | _ -> ()
    end ;
    begin match get_burial p with
    | Buried d ->
        event base db i "BURI" "" d (get_burial_place p) (get_burial_note p) (get_burial_src p) "" [];
    | Cremated d ->
        event base db i "CREM" "" d (get_burial_place p) (get_burial_note p) (get_burial_src p) "" [];
    | UnknownBurial -> ()
    end ;
    *)
  done ;
  ProgrBar.finish ();
  (* For each person - step 2 (constraint person_event.p_id) *)
  Printf.eprintf "Parsing persons - step 2 :\n%!" ;
  ProgrBar.start ();
  for i = 0 to nb_ind - 1 do
    ProgrBar.run i nb_ind;
    let p = poi base (Adef.iper_of_int i) in
    let insert_person_event opt_p e_id role =
      match opt_p with
      | Some iper ->
          insert db false "person_event" (values [
		"null" ;
		e_id ;
		ml2int (Adef.int_of_iper iper) ;
		ml2rstr db role ;
          ])
      | None -> ()
    in
    let as_an_event e_t e_n r s_id role =
      let e_id =
        insert db false "events" (values [
	      "null" ;
	      ml2rstr db e_t ; ml2rstr db e_n ;
	      ml2rstr db "" ;
	      ml2rstr db "Gregorian" ; ml2int 0 ; ml2int 0 ; ml2int 0 ;
	      ml2rstr db "Gregorian" ; ml2int 0 ; ml2int 0 ; ml2int 0 ;
	      ml2rstr db "" ;
	      ml2rstr db "" ;
	      ml2rstr db "" ; "null" ;
	      "null" ;
	      s_id ;
        ]) ;
        ml642int (insert_id db)
      in
      insert_person_event (Some (Adef.iper_of_int i)) e_id "Main" ;
      insert_person_event r.r_fath e_id role ;
      insert_person_event r.r_moth e_id role
    in
    List.iter (fun r ->
      let s_id = (* Only populated from API ! *)
        let source = sou base r.r_sources in
        if source <> "" then ml642int (insert_new_text db false "sources" source)
        else "null"
      in
      match r.r_type with
      | Adoption -> as_an_event "ADOP" "" r s_id "AdoptionParent"
      | Recognition -> as_an_event "EVEN" "Recognition" r s_id "RecognitionParent"
      | CandidateParent -> as_an_event "FACT" "CandidateParent" r s_id "CandidateParent"
      | GodParent -> as_an_event "BAPM" "" r s_id "GodParent"
      | FosterParent -> as_an_event "EVEN" "FosterParent" r s_id "FosterParent"
    ) (get_rparents p) ;
    let death = get_death p in
    List.iter (fun evt ->
	let (e_t, e_n) =
	  match evt.epers_name with
	  | Epers_Birth -> "BIRT", ""
	  | Epers_Baptism -> "BAPM", ""
	  | Epers_Death -> "DEAT", ""
	  | Epers_Burial -> "BURI", ""
	  | Epers_Cremation -> "CREM", ""
	  | Epers_Accomplishment -> "EVEN", "Accomplishment"
	  | Epers_Acquisition -> "EVEN", "Acquisition"
	  | Epers_Adhesion -> "EVEN", "Membership"
	  | Epers_BaptismLDS -> "BAPM", "" (* BAPL removed from GEDCOM 5.5.5 *)
	  | Epers_BarMitzvah -> "BARM", ""
	  | Epers_BatMitzvah -> "BASM", ""
	  | Epers_Benediction -> "EVEN", "BLES" (* BLES removed from GEDCOM 5.5.5 *)
	  | Epers_ChangeName -> "EVEN", "Change name"
	  | Epers_Circumcision -> "EVEN", "Circumcision"
	  | Epers_Confirmation -> "CONF", ""
	  | Epers_ConfirmationLDS -> "CONF", "" (* CONL removed from GEDCOM 5.5.5 *)
	  | Epers_Decoration -> "EVEN", "Award"
	  | Epers_DemobilisationMilitaire -> "EVEN", "Military discharge"
	  | Epers_Diploma -> "EVEN", "Degree"
	  | Epers_Distinction -> "EVEN", "Distinction"
	  | Epers_Dotation -> "EVEN", "ENDL" (* ENDL removed from GEDCOM 5.5.5 *)
	  | Epers_DotationLDS -> "EVEN", "DotationLDS"
	  | Epers_Education -> "EDUC", ""
	  | Epers_Election -> "EVEN", "Election"
	  | Epers_Emigration -> "EMIG", ""
	  | Epers_Excommunication -> "EVEN", "Excommunication"
	  | Epers_FamilyLinkLDS -> "EVEN", "Family link LDS"
	  | Epers_FirstCommunion -> "FCOM", ""
	  | Epers_Funeral -> "EVEN", "Funeral"
	  | Epers_Graduate -> "GRAD", ""
	  | Epers_Hospitalisation -> "EVEN", "Hospitalization"
	  | Epers_Illness -> "EVEN", "Illness"
	  | Epers_Immigration -> "IMMI", ""
	  | Epers_ListePassenger -> "EVEN", "Passenger list"
	  | Epers_MilitaryDistinction -> "EVEN", "Military distinction"
	  | Epers_MilitaryPromotion -> "EVEN", "Military promotion"
	  | Epers_MilitaryService -> "EVEN", "Military service"
	  | Epers_MobilisationMilitaire -> "EVEN", "Military mobilization"
	  | Epers_Naturalisation -> "NATU", ""
	  | Epers_Occupation -> "OCCU", ""
	  | Epers_Ordination -> "EVEN", "ORDN" (* ORDN removed from GEDCOM 5.5.5 *)
	  | Epers_Property -> "PROP", ""
	  | Epers_Recensement -> "CENS", ""
	  | Epers_Residence -> "RESI", ""
	  | Epers_Retired -> "RETI", ""
	  | Epers_ScellentChildLDS -> "EVEN", "SLGC" (* SLGC removed from GEDCOM 5.5.5 *)
	  | Epers_ScellentParentLDS -> "EVEN", "Scellent parent LDS"
	  | Epers_ScellentSpouseLDS -> "EVEN", "SLGS" (* SLGS removed from GEDCOM 5.5.5 *)
	  | Epers_VenteBien -> "EVEN", "Property sale"
	  | Epers_Will -> "WILL", ""
	  | Epers_Name s -> "EVEN", (sou base s)
        in
	let reason = (* do not use evt.epers_reason (empty !) *)
	  if e_t = "DEAT" then
	    match death with
	    | Death (r, _) -> begin match r with
	        | Killed -> "Killed"
	        | Murdered -> "Murdered"
	        | Executed -> "Executed"
	        | Disappeared -> "Disappeared"
	        | Unspecified -> ""
	        end
	    | _ -> ""
	  else ""
	in
	event base db i None e_t e_n evt.epers_date evt.epers_place evt.epers_note evt.epers_src reason evt.epers_witnesses
    ) (get_pevents p) ;
  done ;
  ProgrBar.finish () ;
  (* For each family *)
  Printf.eprintf "Parsing families :\n%!" ;
  let nb_fam = nb_of_families base in
  (* ifam -> g_id *)
  ProgrBar.start ();
  for i = 0 to nb_fam - 1 do
    ProgrBar.run i nb_fam;
    let fam = foi base (Adef.ifam_of_int i) in
    if is_deleted_family fam then ()
    else begin
      let ip_father = Adef.int_of_iper (get_father fam) in
      let ip_mother = Adef.int_of_iper (get_mother fam) in
      Array.iteri
        (fun seq c -> populate_group db i (Adef.int_of_iper c) "Child" seq)
        (get_children fam) ;
      List.iter (fun evt ->
	let (e_t, e_n) =
	  match evt.efam_name with
          | Efam_Marriage -> "MARR", ""
          | Efam_NoMarriage -> "EVEN", "unmarried" (* FIXME not an event ! *)
          | Efam_NoMention -> "EVEN", "nomen" (* FIXME not an event ! *)
          | Efam_Engage -> "ENGA", ""
          | Efam_Divorce -> "DIV", ""
          | Efam_Separated -> "EVEN", "SEP"
          | Efam_Annulation -> "ANUL", ""
          | Efam_MarriageBann -> "MARB", ""
          | Efam_MarriageContract -> "MARC", ""
          | Efam_MarriageLicense -> "MARL", ""
          | Efam_PACS -> "EVEN", "pacs"
          | Efam_Residence -> "RESI", ""
          | Efam_Name n -> "EVEN", (sou base n)
        in
	event base db ip_father (Some ip_mother) e_t e_n evt.efam_date evt.efam_place evt.efam_note evt.efam_src "" evt.efam_witnesses
      ) (get_fevents fam)
    end
  done ;
  ProgrBar.finish () ;
  Printf.eprintf "Parsing linked notes :\n%!" ;
  let insert_linked_note ln_type ln_key ln_iper ln_ifam (list_nt, list_ind) =
    insert db false "linked_notes" (values [
	"null" ;
	ml2rstr db ln_type ;
	ml2rstr db ln_key ;
	ln_iper ;
	ln_ifam ;
    ]) ;
    let ln_id = ml642int (insert_id db) in
    List.iter (fun nt ->
      insert db false "linked_notes_nt" (values [
	"null" ;
	ln_id ;
	ml2rstr db nt ;
      ])
    ) list_nt ;
    List.iter (fun ((fn, sn, oc), { NotesLinks.lnTxt = text ; NotesLinks.lnPos = pos } ) ->
      insert db false "linked_notes_ind" (values [
	"null" ;
	ln_id ;
	ml2rstr db (fn ^ "." ^ (string_of_int oc) ^ "." ^ sn) ;
        begin match text with
        | Some s -> ml2rstr db s
        | None -> "null"
        end ;
	ml2int pos ;
      ])
    ) list_ind ;
  in
  List.iter (function
    | NotesLinks.PgInd iper, l -> insert_linked_note "PgInd" "" (ml2int (Adef.int_of_iper iper)) "null" l
    | NotesLinks.PgFam ifam, l -> insert_linked_note "PgFam" "" "null" (ml2int (Adef.int_of_ifam ifam)) l
    | NotesLinks.PgNotes, l -> insert_linked_note "PgNotes" "" "null" "null" l
    | NotesLinks.PgMisc s, l -> insert_linked_note "PgMisc" s "null" "null" l
    | NotesLinks.PgWizard s, l -> insert_linked_note "PgWizard" s "null" "null" l
  ) (NotesLinks.read_db (fname ^ ".gwb/"))

let gw_history_to_mysql db fname =
  let load_person_history fname =
    let history = ref [] in
    begin match
      (try Some (Secure.open_in_bin fname) with Sys_error _ -> None)
    with
      Some ic ->
        begin try
          while true do
            let v : gen_record = input_value ic in history := v :: !history
          done
        with End_of_file -> ()
        end;
        close_in ic
    | None -> ()
    end;
    !history
  in
  Printf.eprintf "Parsing history...\n%!" ;
  let rec list_remove_same d_old d_new =
    match d_old, d_new with
    | [], l_new -> [], l_new
    | l_old, [] -> l_old, []
    | e_old :: l_old, e_new :: l_new ->
        if e_old = e_new then list_remove_same l_old l_new
        else
          let old_in_new = List.mem e_old l_new in
          let new_in_old = List.mem e_new l_old in
          let l_old = List.filter (fun e -> e <> e_new) l_old in
          let l_new = List.filter (fun e -> e <> e_old) l_new in
          let l1, l2 = list_remove_same l_old l_new in
          begin match old_in_new, new_in_old with
          | true, true -> l1, l2
          | false, true -> e_old :: l1, l2
          | true, false -> l1, e_new :: l2
          | false, false -> e_old :: l1, e_new :: l2
          end
  in
  let rec loop dir =
    Array.iter (fun f ->
      let dir = dir ^ "/" ^ f in
      if Sys.is_directory dir then loop dir
      else
        let insert_history r =
          insert db false "history" (values [
	    "null" ;
	    ml2rstr db r.date ;
	    ml2rstr db r.wizard ;
	    "null" ;
	    ml2rstr db f ;
          ]) ;
          ml642int (insert_id db)
        in
        let insert_history_detail h_id data d_old d_new =
          ignore (insert db false "history_details" (values [
	    "null" ;
            h_id ;
	    ml2rstr db data ;
	    ml2rstr db d_old ;
	    ml2rstr db d_new ;
          ]))
        in
        let rec loop =
          function
          | [] -> ()
          | [r] ->
              ignore (insert_history r)
          | new_r :: old_r :: l ->
              begin
                let h_id = insert_history new_r in
	        if old_r.gen_p.first_name <> new_r.gen_p.first_name then
                  insert_history_detail h_id "first_name" old_r.gen_p.first_name new_r.gen_p.first_name ;
	        if old_r.gen_p.surname <> new_r.gen_p.surname then
                  insert_history_detail h_id "surname" old_r.gen_p.surname new_r.gen_p.surname ;
	        if old_r.gen_p.occ <> new_r.gen_p.occ then
                  insert_history_detail h_id "occ" (string_of_int old_r.gen_p.occ) (string_of_int new_r.gen_p.occ) ;
	        if old_r.gen_p.image <> new_r.gen_p.image then
                  insert_history_detail h_id "image" old_r.gen_p.image new_r.gen_p.image ;
	        if old_r.gen_p.public_name <> new_r.gen_p.public_name then
                  insert_history_detail h_id "public_name" old_r.gen_p.public_name new_r.gen_p.public_name ;
	        if old_r.gen_p.qualifiers <> new_r.gen_p.qualifiers then begin
                  let d_old, d_new = list_remove_same old_r.gen_p.qualifiers new_r.gen_p.qualifiers in
                  insert_history_detail h_id "qualifiers" (String.concat "\n" d_old) (String.concat "\n" d_new)
                end ; (* FIXME *)
	        if old_r.gen_p.aliases <> new_r.gen_p.aliases then begin
                  let d_old, d_new = list_remove_same old_r.gen_p.aliases new_r.gen_p.aliases in
                  insert_history_detail h_id "aliases" (String.concat "\n" d_old) (String.concat "\n" d_new)
                end ; (* FIXME *)
	        if old_r.gen_p.first_names_aliases <> new_r.gen_p.first_names_aliases then begin
                  let d_old, d_new = list_remove_same old_r.gen_p.first_names_aliases new_r.gen_p.first_names_aliases in
                  insert_history_detail h_id "first_names_aliases" (String.concat "\n" d_old) (String.concat "\n" d_new)
                end ; (* FIXME *)
	        if old_r.gen_p.surnames_aliases <> new_r.gen_p.surnames_aliases then begin
                  let d_old, d_new = list_remove_same old_r.gen_p.surnames_aliases new_r.gen_p.surnames_aliases in
                  insert_history_detail h_id "surnames_aliases" (String.concat "\n" d_old) (String.concat "\n" d_new)
                end ; (* FIXME *)
	        if old_r.gen_p.titles <> new_r.gen_p.titles then begin
                  let d_old, d_new = list_remove_same old_r.gen_p.titles new_r.gen_p.titles in
                  insert_history_detail h_id "titles" ("Nbr" ^ (string_of_int (List.length d_old))) ("Nbr" ^ (string_of_int (List.length d_new)))
		end ; (* FIXME *)
	        if old_r.gen_p.occupation <> new_r.gen_p.occupation then
                  insert_history_detail h_id "occupation" old_r.gen_p.occupation new_r.gen_p.occupation ;
	        if old_r.gen_p.sex <> new_r.gen_p.sex then
                  insert_history_detail h_id "sex" (string_of_sex old_r.gen_p.sex) (string_of_sex new_r.gen_p.sex) ;
	        if old_r.gen_p.pevents <> new_r.gen_p.pevents then begin
                  let d_old, d_new = list_remove_same old_r.gen_p.pevents new_r.gen_p.pevents in
                  insert_history_detail h_id "pevents" ("Nbr" ^ (string_of_int (List.length d_old))) ("Nbr" ^ (string_of_int (List.length d_new)))
                end ; (* FIXME *)
	        if old_r.gen_p.notes <> new_r.gen_p.notes then
                  insert_history_detail h_id "notes" old_r.gen_p.notes new_r.gen_p.notes ;
	        if old_r.gen_p.psources <> new_r.gen_p.psources then
                  insert_history_detail h_id "psources" old_r.gen_p.psources new_r.gen_p.psources ;
	        if old_r.gen_f <> new_r.gen_f then begin
                  let d_old, d_new = list_remove_same old_r.gen_f new_r.gen_f in
                  match d_old, d_new with
                  | [e_old], [e_new] -> begin
                       if e_old.fevents <> e_new.fevents then begin
                         let d_old, d_new = list_remove_same e_old.fevents e_new.fevents in
                         insert_history_detail h_id "fevents" ("Nbr" ^ (string_of_int (List.length d_old))) ("Nbr" ^ (string_of_int (List.length d_new)))
                       end ; (* FIXME *)
                       if e_old.comment <> e_new.comment then
                         insert_history_detail h_id "comment" e_old.comment e_new.comment ;
                       if e_old.fsources <> e_new.fsources then
                         insert_history_detail h_id "fsources" e_old.comment e_new.comment ;
                    end
                  | _, _ -> insert_history_detail h_id "families" ("Nbr" ^ (string_of_int (List.length d_old))) ("Nbr" ^ (string_of_int (List.length d_new)))
		end ; (* FIXME *)
	        if old_r.gen_c <> new_r.gen_c then begin
                  let d_old, d_new = list_remove_same old_r.gen_c new_r.gen_c in
                  insert_history_detail h_id "children" ("Nbr" ^ (string_of_int (List.length d_old))) ("Nbr" ^ (string_of_int (List.length d_new)))
		end ; (* FIXME *)
                loop (old_r :: l)
              end
        in
        loop (load_person_history dir)
    ) (Sys.readdir dir)
  in
  loop (fname ^ ".gwb/history_d")

(* main *)

let fname = ref ""

let current = ref true

let history = ref true

let errmsg = "usage: " ^ Sys.argv.(0) ^ " [options] <database>"

let speclist = [
 ("-nolock", Arg.Set Lock.no_lock_flag, ": do not lock data base");
 ("-noCurrent", Arg.Clear current, ": do not export current data");
 ("-noHistory", Arg.Clear history, ": do not export history data")
]

let anonfun s =
  if !fname = "" then fname := s
  else raise (Arg.Bad "Cannot treat several data bases")

let main () =
  Argl.parse speclist anonfun errmsg;
  if !fname = "" then begin
    Printf.eprintf "Missing file name\n";
    Printf.eprintf "Use option -help for usage\n";
    flush stderr;
    exit 2
  end
  else
    let base = open_base !fname in
    let db = quick_connect ~database:"geneweb" ~user:"gw" ~password:"gw_pw" () in
    set_charset db "utf8" ;
    if !current then begin
      let () = load_strings_array base in
      let () = load_ascends_array base in
      let () = load_couples_array base in
      let () = load_descends_array base in
      gw_to_mysql base db !fname
    end ;
    if !history then begin gw_history_to_mysql db !fname end ;
    disconnect db

let _ = Printexc.catch main ()
