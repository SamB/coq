(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(*i $Id$ i*)

(*i*)
open Names
open Topconstr
open Rawterm
(*i*)

(* Syntactic definitions. *)

val declare_syntactic_definition : identifier -> bool -> aconstr -> unit

val search_syntactic_definition : loc -> kernel_name -> rawconstr


