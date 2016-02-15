(** Main entry to the story machinery *)

type secret_log_info
type secret_step = Utilities.S.PH.B.PB.CI.Po.K.refined_step

(** {6 Build} *)

val init_secret_log_info :
  unit -> secret_log_info
val secret_store_event :
  secret_log_info ->
  Causal.event_kind *
    Instantiation.concrete Instantiation.event * unit Mods.simulation_info ->
  secret_step list -> secret_log_info * secret_step list
val secret_store_obs :
  secret_log_info ->
  (Causal.event_kind *
     Instantiation.concrete Instantiation.test list *
     unit Mods.simulation_info) ->
  secret_step list -> secret_log_info * secret_step list

(** {6 Use} *)

val compress_and_print :
  Format.formatter -> Environment.t -> secret_log_info ->
  secret_step list -> unit
