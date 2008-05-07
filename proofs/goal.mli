(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(* $Id: goal.mli aspiwack $ *)

(* This module implements the abstract interface to goals *)

(* arnaud: repasser sur les commentaires *)

type goal

(*arnaud: virer build quand on aura trouvé une meilleure primitive
          pour Proofview.init. *)
val build : Evd.evar -> goal 

val is_defined : Evd.evar_map -> goal -> bool


(* arnaud: mieux commenter *)
(* arnaud: ça sert à imprimer apparemment, c'est marrant que imprimer soit
   hacky *)
(* invariant : [e] must exist in [em] *)
val content : Evd.evar_map -> goal -> Evd.evar_info


(*** Goal tactics ***)


(* return type of the execution of goal tactics *)
(* it contains the new subgoals to produce, and the definitions of
   the evars to instantiate *)
(* arnaud: réfléchir à le faire "private" *)
(* arnaud: private ne marche probablement pas, puisqu'on va en construire
   avec Proofview.*)
(* arnaud: probablement commenter pourquoi c'est là. *)
type proof_step = { subgoals: goal list ;
                    new_defs: Evd.evar_defs}

(* type of the base elements of the goal API.*)
type +'a sensitive


(* type of constr with holes manipulated by the API *)
type open_constr
(* arnaud: à commenter ainsi que dans le .ml *)
val constr_of_open_constr: open_constr -> Term.constr
val open_of_closed : Term.constr -> open_constr

val run : 'a sensitive -> Environ.env -> Evd.evar_defs -> goal -> 'a

(* This is a tactic which does nothing. It's main purpose
   is to enforce a full duality betweens [Proofview.tactic]-s
   and [Goal.tactic]-s.
   Indeed, given this [null] tactic, [Proofview. will know
   how to transform its tactics to [Goal.tactic].*)
val null : proof_step sensitive

(*arnaud: à commenter/déplacer tout ça *)
val open_constr_of_raw : bool -> Rawterm.rawconstr -> open_constr sensitive
(*arnaud: ça aussi *)
val process_apply_case_metas : open_constr -> Term.types -> open_constr sensitive
(*arnaud: à commenter ? idéalement à virer *)
val make_open_constr : Term.constr -> Evd.evar list ->  open_constr
(* This function takes an [constr] with metas, and introduces
   a evar for each meta. The metas must be casted and 
   pairwise distinct. *)
val process_typed_metas : Term.constr -> open_constr sensitive

(* arnaud: à commenter un brin (comme le .ml quoi) *)
val refine : open_constr -> proof_step sensitive


(*arnaud: commenter plus sans doute. Pareil dans le .ml *)
(* Implements the clear tactics *)
val clear : Names.identifier list -> proof_step sensitive


(*arnaud: quelques mots ne feront pas de mal*)
(* Implements the clearbody tactic *)
val clear_body : Names.identifier list -> proof_step sensitive

(* Changes an hypothesis of the goal with a convertible type and body.
   Checks convertibility if the boolean argument is true. *)
val convert_hyp : bool -> Term.named_declaration -> proof_step sensitive

(* Changes the conclusion of the goal with a convertible type and body.
   Checks convertibility if the boolean argument is true. *)
val convert_concl : bool -> Term.constr -> proof_step sensitive

(* arnaud: commenter. *)
val move_hyp : bool -> 
               Names.identifier -> 
               Names.identifier -> 
               proof_step sensitive

(*** Sensitive expressions & Tacticals ***)


(* The following combinators allow to construct tactical expressions 
   for reasoning abstractly on subgoals. As one can see in the 
   [run] function, only the tactics are extractible.
   This allows intermediate values never to be exposed, and
   hopefully prevent the implementation details from leaking inside 
   the code. *)
(* Note that this naturally builds a monad (see Haskell wiki for tutorial).
   There is pa_monad camlp4 extension which gives syntax facilities
   for monads, if using camlp4 in Coq's source code becomes an opportunity
   then it could be an idea to integrate pa_monad. *)


(* if then else on expressions *)
val cond : bool sensitive -> thn:'a sensitive -> 
  els:'a sensitive ->  'a sensitive

(* monadic bind on expressions *)
val bind : 'a sensitive -> ('a -> 'b sensitive) -> 'b sensitive

(* monadic return on expressions *)
val return : 'a -> 'a sensitive

(* changes a list of expressions into an list expression *)
val sensitive_list : 'a sensitive list -> 'a list sensitive

(* arnaud : à virer ? (ainsi que dans le .ml) 
(* map combinator which may usefully complete [bind] *)
   val map : ('a -> 'b) -> 'a sensitive -> 'b sensitive

(* binary map combinator *)
   val map2 : ('a -> 'b -> 'c) -> 'a sensitive -> 'b sensitive -> 'c sensitive
*)

(* [concl] is the conclusion of the current goal *)
val concl : Term.constr sensitive

(* [hyps] is the [named_context_val] representing the hypotheses
   of the current goal *)
val hyps : Environ.named_context_val sensitive

(* [env] is the current [Environ.env] containing both the 
   environment in which the proof is ran, and the goal hypotheses *)
val env : Environ.env sensitive

(* [defs] is the [Evd.evar_defs] at the current evaluation point *)
val defs : Evd.evar_defs sensitive


(*** Tag related things ***)

(* The [Goal.freeze] primitive is the main component of the tactic monad's 
   (from the Proofview module) [Proofview.freeze].
   Precisely [Goal.freeze gl] returns a pair [ ( g' , i ) ], where [g'] is
   a goal identical to [gl] except that it has an additional hereditary
   internal tag [i].*)
val freeze : goal -> goal * int

(* A [has_itag i] is a [bool Goal.sensitive] which is true inside
   the goals which have the internal tag [i]. *)
val has_itag : int -> bool sensitive


(*** Useful sensitive constant ***)

(* The following few constants, despite being definable, are very
   commonly used, sharing them from here, improves memory and 
   speed *)

(* [Goal.strue] is [Goal.return true] *)
val strue : bool sensitive

(* [Goal.sfalse] is [Goal.return false] *)
val sfalse : bool sensitive

(* [Goal.sNone] is [Goal.return None] *)
val sNone : 'a option sensitive

(* [Goal.sNil] is [Goal.return []] *)
val sNil : 'a list sensitive
