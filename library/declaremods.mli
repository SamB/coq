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
open Entries
open Environ
open Libnames
open Libobject
open Lib
   (*i*)

(*s This modules provides official functions to declare modules and
  module types *)


(*s Modules *)

(* [declare_module interp_modtype interp_modexpr id fargs typ expr]
   declares module [id], with type constructed by [interp_modtype]
   from functor arguments [fargs] and [typ] and with module body
   constructed by [interp_modtype] from functor arguments [fargs] and
   by [interp_modexpr] from [expr]. At least one of [typ], [expr] must
   be non-empty.
   
   The [bool] in [typ] tells if the module must be abstracted [true]
   with respect to the module type or merely matched without any
   restriction [false].
*)

val declare_module : 
  (env -> 'modtype -> module_type_entry) -> (env -> 'modexpr -> module_expr) ->
  identifier -> 
  (identifier list * 'modtype) list -> ('modtype * bool) option -> 
  'modexpr option -> unit
 
val start_module : (env -> 'modtype -> module_type_entry) -> 
  identifier -> 
  (identifier list * 'modtype) list -> ('modtype * bool) option -> 
  unit

val end_module : identifier -> unit



(*s Module types *)

val declare_modtype : (env -> 'modtype -> module_type_entry) -> 
  identifier -> (identifier list * 'modtype) list -> 'modtype -> unit

val start_modtype : (env -> 'modtype -> module_type_entry) -> 
  identifier -> (identifier list * 'modtype) list -> unit

val end_modtype : identifier -> unit


(*s Objects of a module. They come in two lists: the substitutive ones
  and the other *)

val module_objects : module_path -> library_segment


(*s Libraries i.e. modules on disk *)

type library_name = dir_path

type library_objects

val register_library : 
  library_name -> 
    Safe_typing.compiled_library -> library_objects -> Digest.t -> unit

val start_library : library_name -> unit

val export_library :
  library_name -> Safe_typing.compiled_library * library_objects


(* [import_module mp] opens the module [mp] (in a Caml sense). 
   It modifies Nametab and performs the "open_object" function 
   for every object of the module. *)

val import_module : module_path -> unit

(* [export_module mp] is similar, but is run when the module
   containing it is imported *)

val export_module : module_path -> unit

(*s [fold_all_segments] and [iter_all_segments] iterate over all
    segments, the modules' segments first and then the current
    segment. Modules are presented in an arbitrary order. The given
    function is applied to all leaves (together with their section
    path). The boolean indicates if we must enter closed sections. *)

val fold_all_segments : bool -> ('a -> object_name -> obj -> 'a) -> 'a -> 'a
val iter_all_segments : bool -> (object_name -> obj -> unit) -> unit


val debug_print_modtab : unit -> Pp.std_ppcmds

(*val debug_print_modtypetab : unit -> Pp.std_ppcmds*)

(* For translator *)
val process_module_bindings : module_ident list ->
  (mod_bound_id * module_type_entry) list -> unit
