(**
  * algebraic_construction.ml
  * openkappa
  * Jérôme Feret, projet Abstraction/Antique, INRIA Paris-Rocquencourt
  * 
  * Creation: September, the 27th of 2015 
  * Last modification: September, the 27th of 2015
  * * 
  * algebraic check for the influence map.
  *  
  * Copyright 2015 Institut National de Recherche en Informatique et   
  * en Automatique.  All rights reserved.  This file is distributed     
  * under the terms of the GNU Library General Public License *)

let warn parameters mh message exn default = 
     Exception.warn parameters mh (Some "algebraic_construction.sig") message exn (fun () -> default) 

exception False of Exception.method_handler 
	    
let check parameters error handler mixture1 mixture2 (i,j) =
  let add (n1,n2) error to_do (inj1,inj2) =
    let error,im1 = Quark_type.IntSet_and_map.find_map_option parameters error n1 inj1 in
    match im1
    with
    | Some n2' when n2=n2' -> error,Some (to_do,inj1,inj2)
    | Some _ -> error,None
    | None ->
       begin
	 let error,im2 = Quark_type.IntSet_and_map.find_map_option parameters error n2 inj2 in
	 match im2
	 with Some _ -> error,None
	    | None ->
	       let error,inj1 = Quark_type.IntSet_and_map.add_map parameters error n1 n2 inj1 in
	       let error,inj2 = Quark_type.IntSet_and_map.add_map parameters error n2 n1 inj2 in
	       error,Some ((n1,n2)::to_do,inj1,inj2)
       end 
  in
  let rec check_agent error to_do already_done =
  match to_do with
  | [] -> error,true
  | (h1,h2)::t when h1<0 || h2<0 -> check_agent error t already_done
  | (h1,h2)::t ->
     begin
       (* check agent type *)
       let error,view1 = Int_storage.Quick_Nearly_inf_Imperatif.get parameters error h1 mixture1.Cckappa_sig.views in
       let error,view2 = Int_storage.Quick_Nearly_inf_Imperatif.get parameters error h2 mixture2.Cckappa_sig.views in
       let error,bonds1 = Int_storage.Quick_Nearly_inf_Imperatif.unsafe_get parameters error h1 mixture1.Cckappa_sig.bonds in 
       let error,bonds2 = Int_storage.Quick_Nearly_inf_Imperatif.unsafe_get parameters error h2 mixture2.Cckappa_sig.bonds in 
       check_interface error view1 view2 bonds1 bonds2 t already_done 
     end
  and check_interface error ag1 ag2 bonds1 bonds2 to_do already_done =
    let error,(bool,(to_do,already_done)) =
      match
	ag1,ag2
      with
      | None,_ | _,None ->
		  let _ = Printf.fprintf stderr "EMPTY AGENT\n" in
		  warn parameters error (Some "Should not scan empty agents...") Exit (true,(to_do,already_done))
      | Some ag1,Some ag2 ->
	 begin
	   match ag1,ag2
	   with 
	   | Cckappa_sig.Ghost,_ | _,Cckappa_sig.Ghost ->
				    warn parameters error (Some "Should not scan ghost agents...") Exit (true,(to_do,already_done))
	   | Cckappa_sig.Agent ag1 , Cckappa_sig.Agent ag2 ->
	      begin 
		let bonds1 =
		  match bonds1 with Some bonds1 -> bonds1 | None -> Cckappa_sig.Site_map_and_set.empty_map
		in 
		let bonds2 =
		  match bonds2 with Some bonds2 -> bonds2 | None -> Cckappa_sig.Site_map_and_set.empty_map
		in 
		let error,bool = 
		  try
		    let error = 
		      Cckappa_sig.Site_map_and_set.iter2_map_sparse
			parameters error
			(fun _ port1 port2 error ->
			 let range1 = port1.Cckappa_sig.site_state in
			 let range2 = port2.Cckappa_sig.site_state in 
			 if not (range1.Cckappa_sig.max < range2.Cckappa_sig.min || range2.Cckappa_sig.max < range1.Cckappa_sig.min)
			 then error
			 else raise (False error))
			ag1.Cckappa_sig.agent_interface
			ag2.Cckappa_sig.agent_interface
		    in error,true 
		  with
		    False error -> error,false
		in
		if bool 
		then
		  try
		    let error,(to_do,already_done)
		      =
		      Cckappa_sig.Site_map_and_set.fold2_map_sparse parameters error 
			(fun _ port1 port2 (error,(to_do,already_done)) ->
			 if port1.Cckappa_sig.site = port2.Cckappa_sig.site
			 then
			   match
			     add
			       (port1.Cckappa_sig.agent_index,
				port2.Cckappa_sig.agent_index)
			       error
			       to_do
			       already_done
			   with
			   | error,None -> raise (False error)
			   | error,Some (todo,inj1,inj2) -> (error,(todo,(inj1,inj2)))
			 else
			   raise (False error) 
			)
			bonds1
			bonds2
			(to_do,already_done)
		    in error,(true,(to_do,already_done))
		  with
		    False error -> error,(false,(to_do,already_done))
		else
		  error,(bool,(to_do,already_done))
	      end
	 end
    in
    if bool
    then
      check_agent error to_do already_done
    else
      error,false
  in
  let error,ouput = add (i,j) error [] (Quark_type.IntSet_and_map.empty_map,Quark_type.IntSet_and_map.empty_map) in
  match ouput
  with
     None -> warn parameters error (Some "Missing rule") Exit (raise Exit)
   | Some(todo,inj1,inj2) -> check_agent error [i,j] (inj1,inj2)
		 
		 
let filter_influence parameters error handler compilation map bool =
  let nrules = Handler.nrules parameters error handler in
  let get_var v =
    match snd (v.Cckappa_sig.e_variable) 
    with 
    | Ast.KAPPA_INSTANCE(mixture),_ -> error,mixture
    | _ -> warn parameters error (Some "Composite observable") Exit (raise Exit)
  in 
  let get_lhs r = r.Cckappa_sig.e_rule_c_rule.Cckappa_sig.rule_lhs in
  let get_rhs r = r.Cckappa_sig.e_rule_c_rule.Cckappa_sig.rule_rhs in
  let get_bool = if bool then get_rhs else get_lhs in 
  let check_influence_rule_mixt error rule1 mixt  pos =
    check parameters error handler (get_bool rule1) mixt pos
  in
  Quark_type.Int2Set_and_map.fold_map
    (fun (a,b) couple (error,map') ->
     let error,rule1 = Int_storage.Nearly_inf_Imperatif.get parameters error a compilation.Cckappa_sig.rules in
     let error,r1 =
       match rule1
       with
       | None -> warn parameters error (Some "Missing rule") Exit (raise Exit)
       | Some r -> error,r
     in
     let error,mixt =
       if
	 b<nrules
       then
	 begin
	 let error,rule2 = Int_storage.Nearly_inf_Imperatif.get parameters error b compilation.Cckappa_sig.rules in 
	 match rule2 with
	 | None -> warn parameters error (Some "Missing rule") Exit (raise Exit)
	 | Some r -> error,get_lhs r
	 end
       else
	 begin
	   let error,var = Int_storage.Nearly_inf_Imperatif.get parameters error (b-nrules) compilation.Cckappa_sig.variables in
	   match var with
	   | None ->  warn parameters error (Some "Missing var") Exit (raise Exit)
	   | Some v -> get_var v
	 end
     in 
     let error,couple' =
       try
	 let error,couple' =
	   Quark_type.Labels.filter_couple
	     parameters
	     error
	     handler 
	     (fun error a b  ->
	      check_influence_rule_mixt error r1 mixt (a,b) )
	     couple
	 in
	 error,couple'
       with Exit -> error,couple
     in 
     if Quark_type.Labels.is_empty_couple couple'
     then  error,map'
     else Quark_type.Int2Set_and_map.add_map parameters error (a,b) couple' map'
    )
    map 
    (error,Quark_type.Int2Set_and_map.empty_map)
	      