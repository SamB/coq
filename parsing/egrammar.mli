(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(*i $Id$ i*)

(*i*)
open Topconstr
open Ast
open Coqast
open Vernacexpr
open Extend
open Rawterm
(*i*)

type all_grammar_command =
  | Notation of
      (int * Gramext.g_assoc option * notation * prod_item list *
      int list option)
  | Grammar of grammar_command
  | TacticGrammar of (string * (string * grammar_production list) * Tacexpr.raw_tactic_expr) list

val extend_grammar : all_grammar_command -> unit

(* Add grammar rules for tactics *)
type grammar_tactic_production =
  | TacTerm of string
  | TacNonTerm of loc * (Token.t Gramext.g_symbol * Genarg.argument_type) * string option

val extend_tactic_grammar :
  string -> (string * grammar_tactic_production list) list -> unit

val extend_vernac_command_grammar :
  string -> (string * grammar_tactic_production list) list -> unit

val get_extend_tactic_grammars :
 unit -> (string * (string * grammar_tactic_production list) list) list
val get_extend_vernac_grammars :
 unit -> (string * (string * grammar_tactic_production list) list) list
val reset_extend_grammars_v8 : unit -> unit

val subst_all_grammar_command :
  Names.substitution -> all_grammar_command -> all_grammar_command

val interp_entry_name : string -> string -> 
  entry_type * Token.t Gramext.g_symbol
