open Proof_type;;
open Tacmach;;


val dad_rule_names : unit -> string list;;
val start_dad : unit -> unit;;
val dad_tac : (Tacexpr.raw_tactic_expr -> 'a) -> int list -> int list -> goal sigma ->
                  goal list sigma * validation;;
val add_dad_rule : string -> Ctast.t -> (int list) -> (int list) ->
                   int -> (int list) -> Tacexpr.raw_atomic_tactic_expr -> unit;;
