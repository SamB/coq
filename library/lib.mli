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
open Libnames
open Libobject
open Summary
(*i*)

(*s This module provides a general mechanism to keep a trace of all operations
   and to backtrack (undo) those operations. It provides also the section
   mechanism (at a low level; discharge is not known at this step). *)

type node = 
  | Leaf of obj
  | CompilingModule of object_prefix
  | OpenedModule of object_prefix * Summary.frozen
  | OpenedModtype of object_prefix * Summary.frozen
  | OpenedSection of object_prefix * Summary.frozen
  | ClosedSection of bool * dir_path * library_segment
  | FrozenState of Summary.frozen

and library_entry = object_name * node

and library_segment = library_entry list


val open_segment : int -> library_segment -> unit
val load_segment : int -> library_segment -> unit
val subst_segment : 
  object_prefix -> substitution -> library_segment -> library_segment
val classify_segment : 
  library_segment -> library_segment * library_segment * library_segment

(*s Adding operations (which calls the [cache] method, and getting the
  current list of operations (most recent ones coming first). *)

val add_leaf : identifier -> obj -> object_name
val add_leaves : library_segment -> identifier -> obj -> object_name
val add_absolutely_named_leaf : object_name -> obj -> unit
val add_anonymous_leaf : obj -> unit
val add_frozen_state : unit -> unit
val mark_end_of_command : unit -> unit

(*s The function [contents_after] returns the current library segment, 
  starting from a given section path. If not given, the entire segment
  is returned. *)

val contents_after : object_name option -> library_segment


(*s Opening and closing a section. *)

val open_section : identifier -> object_prefix

val close_section : export:bool -> identifier -> 
  object_prefix * library_segment * Summary.frozen

val sections_are_opened : unit -> bool

val make_path : identifier -> section_path
val make_kn : identifier -> kernel_name

val cwd : unit -> dir_path
val sections_depth : unit -> int
val is_section_p : dir_path -> bool

(*s Compilation units *)

val start_compilation : dir_path -> module_path -> unit
val end_compilation : dir_path -> object_prefix * library_segment

val module_dp : unit -> dir_path

(*s Modules and module types *)

val start_module : module_ident -> module_path -> Summary.frozen -> unit
val end_module : module_ident 
  -> object_name * object_prefix * Summary.frozen * library_segment

val start_modtype : module_ident -> module_path -> Summary.frozen -> unit
val end_modtype : module_ident 
  -> object_name * object_prefix * Summary.frozen * library_segment

(* Lib.add_frozen_state must be called after all of the above functions *)

val current_prefix : unit -> module_path * dir_path

(*s Backtracking (undo). *)

val reset_to : object_name -> unit
val reset_name : identifier -> unit
val back : int -> unit

(*s We can get and set the state of the operations (used in [States]). *)

type frozen

val freeze : unit -> frozen
val unfreeze : frozen -> unit

val init : unit -> unit

val declare_initial_state : unit -> unit
val reset_initial : unit -> unit
