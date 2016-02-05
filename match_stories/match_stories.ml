(* Matching from a weakly compressed story to a trace, and
 * from a weakly compressed story with agent identifiers abstracted
 * away to a trace. 
 *
 * At the present, there is no easy user interface to check for 
 * story matching, as there is no format in which a user can
 * easily specify a story. In create_toy_story, we provide an example of 
 * checking weak compression story matching on a sample example
 * provided, in simple.ka.  
 *)
open Printf

module KI = Utilities.S.PH.B.PB.CI.Po.K
module IntMap = Map.Make(struct type t = int let compare = compare end)
module IntPairMap = Map.Make(struct type t = (int * int) let compare = compare end)
module IntPairSet = Set.Make(struct type t = (int * int) let compare = compare end)

(****************************************************************************
* General map helpers 
*)
let map_add_val_to_list map key v = 
	if (IntMap.mem key map) then
		let val_list = IntMap.find key map in 
			IntMap.add key (val_list @ [v]) map
	else IntMap.add key [v] map

let map_rem_head_from_list map key = 
	if IntMap.mem key map then
		let val_list = IntMap.find key map in 
			if (List.length val_list) = 1 then
				IntMap.remove key map
			else
				IntMap.add key (List.tl val_list) map
	else map

let mark_steps_with_id steps = 
	let add_id id_list step = 
		if ((List.length id_list) = 0) then [(0, step)]
		else
			let (cur_int, _) = List.hd id_list in
			([(cur_int + 1, step)] @ id_list) 
	in
	List.fold_left add_id [] steps

let map_rem_from_list_by_id map key n = 
	if IntMap.mem key map then
		let val_list = IntMap.find key map in 
			if (List.length val_list) < n then map
			else if (List.length val_list) = 1 then
				IntMap.remove key map
			else (
				let id_val_list = mark_steps_with_id val_list in
				let id_val_list = 
					List.filter (fun (id, _) -> (id <> n)) id_val_list in
				let get_first first_list new_val = (
					match new_val with
					| (_, add_val) -> first_list @ [add_val] 
				)
				in
				let val_list = 
					List.fold_left get_first [] id_val_list in
				IntMap.add key val_list map
			)
	else map

(****************************************************************************
* Story data structures
* Stories are graphs where nodes are story_events. 
* Story events are represented as a tuple: (unique id, (rule id, instantiation))
* Adjacency lists map a story's unique id to a list of the story_events
* it connects to.
* A story is represented by a tuple: 
* ((forward_edges, backward_edges), starting nodes)
* 
* Note: This structure is used to represent both strong and weakly compressed
* stories. In the matching process, the specific instantiation is not preserved
* for strongly compresssed stories, but distinct instantiations remain
* separate through the matching.
*)
type instantiation_t = Instantiation.concrete Instantiation.event

module StoryEvent =
	struct
		type t = (int * (int * instantiation_t))

		let compare (x: t) y = 
			match (x, y) with 
			| ((x1, _), (y1, _)) -> (
	 			if (x1 < y1) then -1
				else if (x1 > y1) then 1
				else 0
			)
	end;;

(* adjacency_list_t : int -> [StoryEvent] *)
type adjacency_list_t = (StoryEvent.t list) IntMap.t 
type story_t = (adjacency_list_t * adjacency_list_t) * (StoryEvent.t list)

(**************************************************************************
* Create test story for weakly compressed story matching algorithm.
* Eventually we will read this from user input depending on the story 
* the user is searching for. For now, there is no easy format for this
* user input.
*)
let find_id_for_rule env name = 
	let rule_id_list = Environment.nums_of_rule name env in
	if (List.length rule_id_list) = 0 then (
		printf "%s %s" "failed to find rule: " name;
		None
	)
	else (Some ((List.hd rule_id_list) + 1))

(* Creates a map linking a rule to all of its instantiations in a trace. 
 * This will be useful for creating a weakly compressed story for a particular
 * trace as a test. *)
let find_all_applications env steps = 
	let map = IntMap.empty in 
	let find_application env map step = 
		match step with
		| KI.Event ((Causal.RULE (rule)), inst) -> (	
				map_add_val_to_list map rule inst
		)
		| _ -> map
	in
	List.fold_left (find_application env) map steps 

(* Check for two neighboring events in our test story that the agents
 * affected by the first event's action are those that are tested 
 * by the second event. This creates a story that involves links
 * between the same instantiations of events. 
 * Currently, this test only works for the specific story created here.
 *)
let check_test_action_matches env first_event second_event = 
	match (first_event, second_event) with
	| (_, (_, (_, (actions, _,_)))), (_, (_, (tests, _))) -> (
		let add_agents_to_list agent_list action = (
			match action with
			| Instantiation.Bind (((id_1, name_1), _), ((id_2, name_2), _)) -> (
				(agent_list @ [(id_1, name_1)]) @ [(id_2, name_2)]
			)
	  	| Instantiation.Bind_to (((id_1, name_1), _), ((id_2, name_2), _)) -> (
				(agent_list @ [(id_1, name_1)]) @ [(id_2, name_2)]
			)
	  	| _ -> agent_list
	  ) in
	  let filter_agents_by_match agent_list test = (
	  	match test with 
			| Instantiation.Is_Bound_to (((id_1, name_1), _), ((id_2, name_2), _)) -> (
				(List.mem (id_1, name_1) agent_list) && 
					(List.mem (id_2, name_2) agent_list)
			)
			| _ -> false
	  ) in
	  let agent_list = List.fold_left add_agents_to_list [] actions in
	  let filtered_tests = List.filter (filter_agents_by_match agent_list) tests in
	  (List.length filtered_tests) <> 0
	)

(* Creates a toy story for simple.ka *)
(* Here we show an example of creating a weakly compressed story for 
 * the set of rules outlined in simple.ka. 
 * We find the rule id corresponding to the events we would like to link, 
 * make sure that the instantiations of these rules are present in our
 * trace and correspond to the same agents, and finally create
 * the adjacency lists that specify a story. 
 *)
let create_toy_story env steps = 
	let get_rand_element l = List.nth l (Random.int (List.length l)) in
	let map = find_all_applications env steps in
	let x_id_option = (find_id_for_rule env "A.B") in
	let y_id_option = (find_id_for_rule env "AB.C") in
	match (x_id_option, y_id_option) with 
	| (Some x_id, Some y_id) -> (
		match ((IntMap.mem x_id map), (IntMap.mem y_id map)) with
		| (true, true) -> (
			let rec get_events () = (
				let x_event : StoryEvent.t = 
					(0, (x_id, get_rand_element (IntMap.find x_id map))) in 
				let y_event : StoryEvent.t = 
					(1, (y_id, get_rand_element (IntMap.find y_id map))) in
				if check_test_action_matches env x_event y_event then
					(x_event, y_event)
				else get_events ()
			) in
			let (x_event, y_event) = get_events () in 
			let forward_list : adjacency_list_t = IntMap.singleton 0 [y_event] in
			let reverse_list : adjacency_list_t = IntMap.singleton 1 [x_event] in
			let start_events = [x_event] in
			printf "Created test story A.B -> AB.C \n ";
			Some ((forward_list, reverse_list), start_events)
		)
		| _ -> None
	)
	| _ -> None

(******************************************************************************
* Algorithm for matching weakly compressed stories to a trace 
*)
let add_story_events_to_map map story_events = 
	let add_story_event_to_map map story_event = 
		let (_, (rule, _)) = story_event in
		map_add_val_to_list map rule story_event
	in 
	List.fold_left add_story_event_to_map map story_events

(*
 * For each event in the trace, update our map linking story events to their
 * counterparts in the trace. If the set of remaining events in the story that we
 * need to map (with current next steps represented in the work queue) is 
 * is empty, we mark our matching as done, which is passed on to runs of this
 * function on future steps of the trace.
 *)
let step_weak_algorithm (s : story_t) (wq, result_map, is_done) mark_step = 
	if is_done then (wq, result_map, is_done)
	else 
		let (step_id, step) = mark_step in
		let ((forward_edges, backward_edges), _) = s in
		match step with
		| KI.Event (Causal.RULE (rule), trace_inst) -> (
			(* Here we have found that this trace contains instantiations of the 
			 * story's rule. *)
			if IntMap.mem rule wq then (
				(* Require the story's and trace's instantiation of this rule
				 * to be identical for weak compression story matching. *)
				let filtered = 
					List.filter 
						(fun ((_, (_, story_inst)) : StoryEvent.t) -> (story_inst = trace_inst)) 
						(IntMap.find rule wq) in
				if ((List.length filtered) > 0) then (  
					(* Here we've matched trace event to a story event *)
					let (story_event_id, (rule_id, story_inst)) = List.hd filtered in
					(* Update result set with new mapping *)
					let result_map = IntMap.add story_event_id step_id result_map in
					(* Remove matched story instance from wq *)
					let wq = map_rem_head_from_list wq rule in
					(* Add new elements from story to wq *)
					let might_add = (match IntMap.mem story_event_id forward_edges with
					| true -> IntMap.find story_event_id forward_edges 
					| false -> []) in
					(* Only add if all predecessors have been handled *)
					let all_pred_handled ((story_event_id, _) : StoryEvent.t) = (
						let pred_handled prev_handled (pred_id, _) = 
							(prev_handled && (IntMap.mem pred_id result_map))
						in
						(* All events encountered in alg have backward edges *)
						List.fold_left pred_handled true (IntMap.find story_event_id backward_edges)
					) in
					let to_add = List.filter all_pred_handled might_add in
					let wq = add_story_events_to_map wq to_add in
					(wq, result_map, IntMap.is_empty wq)
				)
				else (wq, result_map, is_done)  (* No matching instantiation *)
			)
			else (wq, result_map, is_done)  (* No matching rule *)
			)
		| _ -> (wq, result_map, is_done)

(* Create test story, initialize work queue, and begin stepping through the trace
 * starting from the first event, running the step weak algorithm function.
*) 
let check_weak_story_embeds env steps = 
	let s_option = (create_toy_story env steps) in
	match s_option with
	| Some s -> (
		let ((_, _), start_events) = s in
		let wq = IntMap.empty in (* wq is map from rule id to story_events *)
		let result_map = IntMap.empty in (* result_map maps story_event ids to trace id *)
		let wq = add_story_events_to_map wq start_events in (* Initialize wq *)
		let param = (wq, result_map, false) in
		let (_, _, is_done) = 
			List.fold_left (step_weak_algorithm s) param (mark_steps_with_id steps)
		in
		if is_done then (printf "%s " "matches")
		else (printf "%s " "doesn't match") 
	)
	| None -> (printf "%s" "could not load test story")  

(******************************************************************************
* Strong compression algorithm
* This strong compression matching algorithm matches a particular type of 
* abstract stories to the trace it might represent. In particular, a strong 
* compression matching is valid if there is some mapping from the story's 
* agents in its instantiations to the trace's agents such that the 
* instantiations are valid. 
* This matching algorithm is a nondeterministic backwards version of the
* matching algorithm above. When a story's event can potentially be mapped
* to a trace's event, a version of the current state (wq, result_map, is_done)
* is created to represent this mapping, and another version is maintained that
* does not make this mapping.
* When a mapping is made, mappings between agents from the story and agents 
* from the trace that were made in previous steps must be maintained. To 
* achieve this, we maintain an additional data structure capturing the
* current agent identifier concretization, and make sure each step of the
* algorithm preserves that.
*)

(* 
 * Useful data structures to create: 
 * Map A of agent name to (map of agent ids to (list of tests / actions))
 * Need for both trace and story. 
 * Set A of (agent name, agent id) for the story. 
 *
 * Need to add throughout: 
 * trace_concretized... all the trace's agent name, id pairs that have been
 * assigned already to the story's agents.
 *)

(* 
 * Maintain list of visited (agent name, agent id) pairs from story
 * Pick a new story agent id (choose from Set A above), and check that it's not visited,
 * and mark as visited.
 * Check if it is in the mapping. If so, run check_id_match; if fail return None.
 * Else for each matching trace agent id (from Map A) that is not in trace_concretized,
 * check for match via check_id_match
 * check_id_match: For each story test that includes this agent id (from Map A), 
 * check for match in trace (from Map A), and check that there were no extra 
 * trace tests including this agent id. For pair, it is compatible if the other 
 * story agent id is in the mapping and maps to the right thing, or if both story 
 * and trace agent ids are not in the mapping.
 * If no matches, return None. 
 * For each possible assignment, apply the mapping and recurse. 
 *)
type 'a test_action_list = Tests of 'a test list
												| Actions of 'a action list
type 'a test_action = Test of 'a test | Action of 'a action

let add_to_agent_name_id_map agent_name agent_id test_action map =
	if IntMap.mem agent_name map then (
		let agent_id_map = IntMap.find agent_name map in
		if IntMap.mem agent_id agent_id_map then 
			let test_action_list = IntMap.find agent_id agent_id_map in
			let agent_id_map = 
				IntMap.add agent_id (test_action_list @ [test_action]) agent_id_map in
			IntMap.add agent_name agent_id_map map
		else 
			let agent_id_map = IntMap.add agent_id [test_action] agent_id_map in
			IntMap.add agent_name agent_id_map map
	)
	else 
		let single_map = IntMap.singleton agent_id [test_action] in
		IntMap.add agent_name single_map map

let make_agent_id_to_test inst_list = 
	let add_to_map agent_name_map test = 
		match test with 
	  | Instantiation.Is_Here (agent_id, agent_name) ->
	  	add_to_agent_name_id_map agent_name agent_id test agent_name_map
	  | Instantiation.Has_Internal (((agent_id, agent_name), _), _) ->
	  	add_to_agent_name_id_map agent_name agent_id test agent_name_map	  	
	  | Instantiation.Is_Free ((agent_id, agent_name), _) ->
	  	add_to_agent_name_id_map agent_name agent_id test agent_name_map
	  | Instantiation.Is_Bound ((agent_id, agent_name), _) ->
	  	add_to_agent_name_id_map agent_name agent_id test agent_name_map
	  | Instantiation.Has_Binding_type (((agent_id, agent_name), _), _) ->
	  	add_to_agent_name_id_map agent_name agent_id test agent_name_map
	  | Instantiation.Is_Bound_to (((id_1, name_1), _), ((id_2, name_2), _)) -> (
	  	let mapping = 
	  		add_to_agent_name_id_map name_1 id_1 test agent_name_map
 			in
	  	add_to_agent_name_id_map name_1 id_1 test mapping
	  )
  in
	List.fold_left add_to_map IntMap.empty inst_list

let make_agent_id_to_action inst_list = 
	let add_to_map agent_name_map action = 
		match action with 
		| Instantiation.Create ((agent_id, agent_name), _) ->
	  	add_to_agent_name_id_map agent_name agent_id action agent_name_map
  	| Instantiation.Mod_internal (((agent_id, agent_name), _), _) ->
	  	add_to_agent_name_id_map agent_name agent_id action agent_name_map
  	| Instantiation.Bind (((id_1, name_1), _), ((id_2, name_2), _)) -> (
	  	let mapping = 
	  		add_to_agent_name_id_map name_1 id_1 action agent_name_map
 			in
	  	add_to_agent_name_id_map name_1 id_1 action mapping
	  )
  	| Instantiation.Bind_to (((id_1, name_1), _), ((id_2, name_2), _)) -> (
	  	let mapping = 
	  		add_to_agent_name_id_map name_1 id_1 action agent_name_map
 			in
	  	add_to_agent_name_id_map name_1 id_1 action mapping
	  )
  	| Instantiation.Free ((agent_id, agent_name), _) ->
	  	add_to_agent_name_id_map agent_name agent_id action agent_name_map
  	| Instantiation.Remove (agent_id, agent_name) ->
	  	add_to_agent_name_id_map agent_name agent_id action agent_name_map
	in 
	List.fold_left add_to_map IntMap.empty inst_list

let make_agent_id_to_test_action inst_list = 
	match inst_list with
	| Tests test_list -> (make_agent_id_to_test test_list)
	| Actions action_list -> (make_agent_id_to_action action_list)

let get_structs_for_concretization story_inst_list trace_inst_list = 
	let story_map = make_agent_id_to_test_action story_inst_list in
	let trace_map = make_agent_id_to_test_action trace_inst_list in
	let add_agent_names agent_name agent_id_map cur_set = 
		let add_agent_ids agent_id check_list cur_name_set = 
			Set.add (agent_name, agent_id) cur_name_set
	  in
		Map.fold add_agent_ids agent_id_map cur_set 
	in
	let story_set =
		Map.fold (Map.fold []) story_map Set.empty
	in
	(story_map, trace_map, story_set)

let pair_matches_help story_agent_id trace_agent_id mapping = 
	let (story_concretized, trace_concretized) = mapping in
	let (story_name, story_id) = story_agent_id in 
	let (trace_name, trace_id) = trace_agent_id in
	if IntPairMap.mem story_agent_id story_concretized then (
		if not story_name = trace_name then false 
		else ((IntPairMap.find story_agent_id story_concretized) = trace_id) 
	)
	else (not IntPairMap.mem trace_agent_id trace_concretized) 

let pair_matches story_bind trace_bind agent_name story_id trace_id mapping =
	let (story_bind_1, story_bind_2) = story_bind in
	let (trace_bind_1, trace_bind_2) = trace_bind in
	let ((story_id_1, story_name_1), story_site_1) = story_bind_1 in
	let ((story_id_2, story_name_2), story_site_2) = story_bind_2 in
	let ((trace_id_1, trace_name_1), trace_site_1) = trace_bind_1 in
	let ((trace_id_2, trace_name_2), trace_site_2) = trace_bind_2 in
	if (((((story_site_1 = trace_site_1) && (story_name_1 = agent_name)) && 
			(trace_name_1 = agent_name)) && (story_id_1 = story_id)) && (trace_id_1 = trace_id))
	then
		((story_site_2 = trace_site_2) && 
			(pair_matches_help (story_name_2, story_id_2) (trace_name_2, trace_id_2) mapping))
 	else if (((((story_site_1 = trace_site_2) && (story_name_1 = agent_name)) && 
			(trace_name_2 = agent_name)) && (story_id_1 = story_id)) && (trace_id_2 = trace_id))
 	then
		((story_site_2 = trace_site_1) && 
			(pair_matches_help (story_name_2, story_id_2) (trace_name_1, trace_id_1) mapping))
	else if (((((story_site_2 = trace_site_1) && (story_name_2 = agent_name)) && 
			(trace_name_1 = agent_name)) && (story_id_2 = story_id)) && (trace_id_1 = trace_id))
	then
		((story_site_1 = trace_site_2) && 
			(pair_matches_help (story_name_1, story_id_1) (trace_name_2, trace_id_2) mapping))
	else if (((((story_site_2 = trace_site_2) && (story_name_2 = agent_name)) && 
			(trace_name_2 = agent_name)) && (story_id_2 = story_id)) && (trace_id_2 = trace_id))
	then
		((story_site_1 = trace_site_1) && 
			(pair_matches_help (story_name_1, story_id_1) (trace_name_1, trace_id_1) mapping))

let check_match_test story_item trace_item story_agent_id trace_id mapping = 
	let (agent_name, story_id) = story_agent_id in
	match (story_item, trace_item) with 
  | (Instantiation.Is_Here _, Instantiation.Is_Here _) -> true
  | (Instantiation.Has_Internal (((_, _), story_site), story_state), 
   	 Instantiation.Has_Internal (((_, _), trace_site), trace_state)) ->
   	 ((story_site = trace_site) && (story_state = trace_state))
  | (Instantiation.Is_Free ((_, _), story_site), 
  	Instantiation.Is_Free ((_, _), trace_site)) -> (story_site = trace_site)
  | (Instantiation.Is_Bound ((_, _), story_site), 
  	Instantiation.Is_Bound ((_, _), trace_site)) -> (story_site = trace_site)
  | (Instantiation.Has_Binding_type (((_, _), story_site), story_state),
  	Instantiation.Has_Binding_type (((_, _), trace_site), trace_state)) ->
   	 ((story_site = trace_site) && (story_state = trace_state))
  | (Instantiation.Is_Bound_to story_bind,
  	 Instantiation.Is_Bound_to trace_bind) ->
		pair_matches story_bind trace_bind agent_name story_id trace_id mapping  
  | (_, _) -> false

let check_match_action story_item trace_item story_agent_id trace_id mapping = 
	let (agent_name, story_id) = story_agent_id in
	match (story_item, trace_item) with 
	| (Instantiation.Create ((_, _), story_state),
		 Instantiation.Create ((_, _), trace_state)) -> (story_state = trace_state)
	| (Instantiation.Mod_internal (((_, _), story_site), story_state),
		Instantiation.Mod_internal (((_, _), trace_site), trace_state)) ->
		((story_site = trace_site) && (story_state = trace_state))
	| (Instantiation.Bind story_bind, Instantiation.Bind trace_bind) -> 
		pair_matches story_bind trace_bind agent_name story_id trace_id mapping  
	| (Instantiation.Bind_to story_bind, Instantiation.Bind_to trace_bind) -> 
		pair_matches story_bind trace_bind agent_name story_id trace_id mapping  	
	| (Instantiation.Free ((_, _), story_site), 
		Instantiation.Free ((_, _), trace_site)) -> (story_site = trace_site)
	| (Instantiation.Remove (_, _), Instantiation.Remove (_, _)) -> true
	| (_, _) -> false

let check_match_test_action story_item trace_item story_agent_id trace_id mapping = 
	match (story_item, trace_item) with
	| (Test story_test, Test trace_test) -> 
		check_match_test story_test trace_test mapping
	| (Action story_action, Test story_action) -> 
		check_match_action story_action trace_action mapping

let story_trace_agent_id_matches story_agent_id trace_id structs mapping = 
	let (story_map, trace_map, story_set) = structs in
	let (agent_name, story_id) = story_agent_id in
	let (story_concretized, trace_concretized) = mapping in
	if not IntMap.mem agent_name story_map then false
	else let story_agent_id_map = IntMap.find agent_name story_map in 
	if not IntMap.mem story_id story_agent_id_map then false
	else let story_items = IntMap.find story_id story_agent_id_map in 
	if not IntMap.mem agent_name trace_map then false
	else let trace_agent_id_map = IntMap.find agent_name trace_map in 
	if not IntMap.mem trace_id trace_agent_id_map then false
	else let trace_items = IntMap.find trace_id trace_agent_id_map in
	let check_matches (trace_items_left, matches_so_far) next_story_item =
		if not matches_so_far then (trace_items_left, false)
		else (
			let find_match cur_match trace_item = 
				match cur_match with
				| Some _ -> cur_match
				| None -> 
			  	if check_match_test_action next_story_item trace_item 
			  		story_agent_id trace_id mapping
					then Some trace_item else None
		  in
			let matched_trace_item = List.fold_left find_match None trace_items_left in
			match matched_trace_item with
			| Some matched_item -> 
				List.filter (fun trace_item -> (trace_item <> matched_item)) trace_items_left
			| None -> (trace_items_left, false)
		)
	in
	let (trace_items_left, matches) = 
		List.fold_left check_matches (trace_items, true) story_items in
	if (((List.length trace_items_left) = 0) && matches) then true 
	else false

let find_concretization_helper story_inst_list trace_inst_list mapping = 
	let find_concretization_rec structs mapping = 
		let (story_name_to_ids, trace_name_to_ids, story_agent_ids) = structs in
		if (Set.cardinal story_agent_ids = 0) then Some [mapping];
		let story_agent_id = Set.choose story_agent_ids in
		let story_agent_ids = Set.remove story_agent_id story_agent_ids in
		let new_structs = (story_name_to_ids, trace_name_to_ids, story_agent_ids) in
		let (story_to_trace_id, trace_concretized) = mapping in
		if IntPairMap.mem story_agent_id story_to_trace_id then (
			(* This agent id is already concretized *)
			let trace_id = IntPairMap.find story_agent_id story_to_trace_id in
			if story_trace_agent_id_matches story_agent_id trace_id structs mapping
			then find_concretization_rec new_structs mapping
			else None
		)
		else (
			let (s_agent_name, s_agent_id) = story_agent_id in
		  if IntMap.mem s_agent_name trace_name_to_ids then (
		  	let potential_trace_ids = IntMap.find s_agent_name trace_name_to_ids in
				let check_id_match trace_id trace_val cur_mappings = 
					(* Check that trace id not in concretization *)
					if not (Set.mem (s_agent_name, trace_id) trace_concretized) then
					if story_trace_agent_id_matches story_agent_id trace_id structs mapping
					then (
						let new_s_to_t = IntPairMap.add story_agent_id trace_id story_to_trace_id in
						let new_t_concrete = 
							Set.add (s_agent_name, trace_id) trace_concretized in
						cur_mappings @ [(new_s_to_t, new_t_concrete)]
					)
			  in
		  	let new_mappings = IntMap.fold check_id_match potential_trace_ids [] in
		  	if (List.length new_mappings) = 0 then None
		  	else 
		  	(* Recursive call for each of new_mappings, to assemble full output *)
		  	let assemble_potential_mappings cur_completed_mappings partial_mapping = 
		  		match (find_concretization_rec new_structs partial_mapping) with
		  		| Some completed_mapping -> cur_completed_mappings @ [completed_mapping]
		  		| None -> cur_completed_mappings
		  	in
		  	let completed_mappings = 
		  		List.fold_left assemble_potential_mappings [] new_mappings in
		  	if (List.length completed_mappings) = 0 then None
		  	else Some completed_mappings
		  )
			else None
		) 
	in
	let structs = 
		get_structs_for_concretization story_inst_list trace_inst_list in
	find_concretization_rec structs mapping


let find_concretization mapping story_inst trace_inst = 
	let (story_tests, (story_actions, _, _)) = story_inst in
	let (trace_tests, (trace_actions, _, _)) = trace_inst in
	let test_mappings_option = 
		find_concretization_helper story_tests trace_tests true mapping in
	match test_mappings_option with
	| Some test_mappings -> (
		let action_fun mappings_so_far test_mapping = 
		 	let action_mappings_option = 
		 		find_concretization_helper story_actions trace_actions false test_mapping
		 	in
		 	match action_mappings_option with
		 	| Some action_mappings -> mappings_so_far @ action_mappings
		 	| None -> mappings_so_far
		in
		let mappings_to_add = List.fold_left action_fun [] test_mappings in
		Some mappings_to_add
	)
	| None -> None

(* Returns a list of (match_loc, match_event, mappings_to_add) plus an updated count
* append to the current list of the matchings *)
let find_abstract mapping trace_inst (matches_so_far, count) cur_abstract =
	(* This count is used to figure out which rule application we've decided 
	   to try to concretize *) 
	let count = count + 1 in (* need to add recursive things here *)
	let (_, (_, story_inst)) = cur_abstract in
	let option_mappings_to_add =
	 	find_concretization mapping story_inst trace_inst in
	match option_mappings_to_add with
	| Some mappings_to_add -> (
		let add_one_mapping cur_matches mapping_to_add = 
			cur_matches @ [(count, cur_abstract, mapping_to_add)]
		in
		let matches_so_far = 
			List.fold_left add_one_mapping matches_so_far mappings_to_add in
		(matches_so_far, count)
	)
	| None -> (matches_so_far, count)

(* Returns list of (match_loc, match_event, mappings_to_add)
 * mapping is a IntPairMap
 * Mappings_to_add is a list of (agent_name, story_id, trace_id).
 *)
let find_rule_application mapping trace_inst potential_abstract =
	let (matchings, _) = 
		List.fold_left (find_abstract mapping trace_inst) ([], 0) potential_abstract
	in 
	if ((List.length matchings) <> 0) then Some matchings
	else None

let update_states_list s step_id rule (state_list, all_done) match_info = 
	if (all_done) then (state_list, all_done) 
	else (
		let ((forward_edges, backward_edges), _) = s in
		let (match_loc, match_event, new_mapping) = match_info in
		let (wq, result_map, mapping, is_done) = List.hd state_list in
		let (story_event_id, (rule_id, story_inst)) = match_event in
		(* Update result set with new mapping *)
		let new_result_map = IntMap.add story_event_id step_id result_map in
		(* Remove matched story instance from wq *)
		let new_wq = map_rem_from_list_by_id wq rule match_loc in
		(* Add new elements from story to wq *)
		let might_add = (match IntMap.mem story_event_id backward_edges with
		| true -> IntMap.find story_event_id backward_edges 
		| false -> []) in
		(* Only add if all predecessors have been handled *)
		let all_succ_handled ((story_event_id, _) : StoryEvent.t) = (
			let succ_handled next_handled (succ_id, _) = 
				(next_handled && (IntMap.mem succ_id result_map))
			in
			(* all events encountered in alg have backward edges *)
			List.fold_left succ_handled true (IntMap.find story_event_id forward_edges)
		) in
		let to_add = List.filter all_succ_handled might_add in
		let new_wq = add_story_events_to_map new_wq to_add in
		let is_done = IntMap.is_empty new_wq in
		(state_list @ [(new_wq, new_result_map, new_mapping, is_done)], is_done)
	)

let step_state_strong_algorithm s mark_step (states_list, all_is_done) (state) = 
	if all_is_done then (states_list, all_is_done)
	else 
		let (step_id, step) = mark_step in
		match step with
		| KI.Event (Causal.RULE (rule), trace_inst) -> (
			let (wq, _, mapping, _) = state in
			if IntMap.mem rule wq then (
				(* See if any rule application is applicable given current mapping. Returns
				* location of match in the list, updated mapping *)
				let potential_abstract = IntMap.find rule wq in
				let match_option = 
					find_rule_application mapping trace_inst potential_abstract in
				match match_option with
				| Some match_infos -> (
					List.fold_left (update_states_list s step_id rule) ([state], false) match_infos
				)
				| None -> (states_list @ [state], all_is_done)  (* No matching instantiation *)
			)
			else (states_list @ [state], all_is_done)  (* No matching rule *)
		)
		| _ -> (states_list @ [state], all_is_done) (* Not a trace event step *)

(*
 * Step through all possible states (all possible story event to trace event
 * mappings), at each state attempting to add an additional story event to trace event
 * mapping based on the current trace step mark_step, and returning the 
 * new set of possible states of the algorithm.  
 *)
let step_states_strong_algorithm s (states_list, all_is_done) mark_step = 
	if all_is_done then (states_list, all_is_done)
	else 
		List.fold_left (step_state_strong_algorithm s mark_step) ([], false) states_list

(* 
 * The entry point for the strongly compressed story matching algorithm. 
 * Nondeterministically tries to assign events of the story to the trace, walking
 * through the trace and story backwards from the event of interest.
 *)
let check_strong_story_embeds env steps = 
	let s_option = (create_toy_story env steps) in
	match s_option with
	| Some s -> (
		let ((_, _), last_events) = s in
		let wq = IntMap.empty in (* wq is map from rule id to story_events *)
		let result_map = IntMap.empty in (* result_map maps story_event ids to trace id *)
		let mapping = (IntPairMap.empty, IntPairSet.empty) in (* mapping captures the current concretization of agents *)
		(* mapping stores this: {(Story's agent name, story's agent id): trace's agent id} *)
		let wq = add_story_events_to_map wq last_events in (* Initialize wq *)
		let param = [(wq, result_map, mapping, false)] in
		let (_,is_done) = 
			List.fold_left (step_states_strong_algorithm s) 
				(param, false) (mark_steps_with_id (List.rev steps))
		in
		if is_done then (printf "%s " "matches")
		else (printf "%s " "doesn't match") 
	)
	| None -> (printf "%s" "could not load test story")  

(***********************************************************************
* Printing traces for debugging
*)
let print_trace env steps = 
  Format.eprintf "@[<v>%a@]" (Pp.list Pp.space KI.print_refined_step) steps

let print_rule env f step = 
	match step with 
	| KI.Event (Causal.RULE (rule), _) ->
		Environment.print_rule ~env:env Format.err_formatter rule
	| _ -> ()

let print_rules env steps =
	Format.eprintf "@[<v>%a@]" (Pp.list Pp.space (print_rule env)) steps