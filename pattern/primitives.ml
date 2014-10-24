type 'a variable =
    CONST of 'a
  | VAR of
      ((int -> Nbr.t) -> (int -> Nbr.t) -> float ->
       int -> int -> float -> (int -> Nbr.t) -> 'a)

type id = FRESH of int | KEPT of int
type port = id * int
type action =
    BND of (port * port)
  | FREE of (port * bool)
  | MOD of (port * int)
  | DEL of int
  | ADD of (int * int)

module IdMap = MapExt.Make (struct type t = id let compare = compare end)
module PortMap = MapExt.Make (struct type t = port let compare = compare end)
module ActionSet = Set.Make(struct type t=action let compare = compare end)

module Causality :
sig
  type t
  val is_link_tested : t -> bool
  val is_link_modif : t -> bool
  val is_link_something : t -> bool
  val is_internal_tested : t -> bool
  val is_internal_modif : t -> bool
  val is_internal_something : t -> bool
  val create : bool -> bool -> t
  val add_internal_modif : t -> t
  val add_link_modif : t -> t
  val to_int : t -> int
end = struct
  type t = int
  let _INTERNAL_TESTED = 8
  let _INTERNAL_MODIF = 4
  let _LINK_TESTED = 2
  let _LINK_MODIF = 1

  let is i c = (i land c <> 0)
  let is_link_tested = is _LINK_TESTED
  let is_link_modif = is _LINK_MODIF
  let is_link_something = is (_LINK_MODIF lor _LINK_TESTED)
  let is_internal_tested = is _INTERNAL_TESTED
  let is_internal_modif = is _INTERNAL_MODIF
  let is_internal_something = is (_INTERNAL_MODIF lor _INTERNAL_TESTED)
  let create i_t l_t =
    if i_t then _INTERNAL_TESTED else 0 +
    if l_t then _LINK_TESTED else 0
  let add_internal_modif c = c lor _INTERNAL_MODIF
  let add_link_modif c = c lor _LINK_MODIF
  let to_int c = c
end

type rule = {
  k_def : Nbr.t variable; (** standard kinetic constant *)
  k_alt : Nbr.t variable option * Nbr.t variable option;
  (** Possible unary kinetic rate *)
  over_sampling : float option;
  (** Boosted kinetic rate for Bologna technique *)
  script : action list;
  balance : (int * int * int);	(** #deleted,#preserved,#removed *)
  kappa: string;
  lhs : Mixture.t;
  rhs : Mixture.t;
  refines: int option; (** mixture id that is refined by lhs *)
  r_id : int;
  added : Mods.IntSet.t;
  (*side_effect : bool ;*)
  modif_sites : Mods.Int2Set.t IdMap.t;
  pre_causal : Causality.t PortMap.t;
  is_pert: bool;
  cc_impact :
    (Mods.IntSet.t Mods.IntMap.t * Mods.IntSet.t Mods.IntMap.t *
       Mods.IntSet.t Mods.IntMap.t) option;
  add_token : (Nbr.t variable * int) list;
  rm_token : (Nbr.t variable * int) list
}
(*connect: cc_i(lhs) -> {cc_j(lhs),...} if cc_i and cc_j are connected by rule application*)
(*disconnect: cc_i(rhs) -> {cc_j(rhs),...} if cc_i and cc_j are disconnected by rule application*)
(*side_effect: ag_i -> {site_j,...} if one should check at runtime the id of the agent connected to (ag_i,site_j) and build its cc after rule application*)

type modification =
    INTRO of Nbr.t variable * Mixture.t
  | DELETE of Nbr.t variable * Mixture.t
  | UPDATE_RULE of int * Nbr.t variable
  | UPDATE_VAR of int * Nbr.t variable
  | UPDATE_TOK of int * Nbr.t variable
  | SNAPSHOT of Ast.mixture Ast.print_expr Term.with_pos list
  | STOP of Ast.mixture Ast.print_expr Term.with_pos list
  | CFLOW of int
  | FLUX of Ast.mixture Ast.print_expr Term.with_pos list
  | FLUXOFF of Ast.mixture Ast.print_expr Term.with_pos list
  | CFLOWOFF of int
  | PRINT of
      (Ast.mixture Ast.print_expr Term.with_pos list *
	 Ast.mixture Ast.print_expr Term.with_pos list)

type perturbation =
    { precondition: bool variable;
      effect : (rule option * modification) list;
      abort : bool variable option;
      flag : string;
      stopping_time : Nbr.t option
    }