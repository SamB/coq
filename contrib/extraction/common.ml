(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(*i $Id$ i*)

open Pp
open Names
open Nameops
open Miniml
open Table
open Mlutil
open Extraction
open Ocaml
open Libnames
open Util
open Declare
open Nametab

(*s Modules considerations *)

let current_module = ref (id_of_string "")

let used_modules = ref []

let long_module r = 
  match modpath (kn_of_r r) with 
    | MPfile d -> d
    | _ -> anomaly "TODO: extraction not ready for true modules"

let short_module r = List.hd (repr_dirpath (long_module r))
			    
let check_ml r d = 
  if to_inline r then 
    try 
      find_ml_extraction r 
    with Not_found -> d
  else d

(*s Get all modules names used in one [ml_decl] list. *)

let ast_get_modules m a = 
  let rec get_rec a =
    ast_iter get_rec a;
    match a with 
      | MLglob r -> m := Idset.add (short_module r) !m
      | MLcons (r,l) as a -> 
	  m := Idset.add (short_module r) !m; 
      | MLcase (_,v) as a -> 
	  let r,_,_ = v.(0) in
	  m := Idset.add (short_module r) !m;
      | _ -> ()
  in get_rec a

let mltype_get_modules m t = 
  let rec get_rec = function 
    | Tglob (r,l) -> m := Idset.add (short_module r) !m; List.iter get_rec l
    | Tarr (a,b) -> get_rec a; get_rec b 
    | _ -> () 
  in get_rec t

let decl_get_modules ld = 
  let m = ref Idset.empty in 
  let one_decl = function 
    | Dind (l,_) -> 
	List.iter (fun (_,_,l) -> 
		     List.iter (fun (_,l) -> 
				  List.iter (mltype_get_modules m) l) l) l
    | Dtype (_,_,t) -> mltype_get_modules m t 
    | Dterm (_,a,t) -> ast_get_modules m a; mltype_get_modules m t
    | Dfix(_,c,t) -> Array.iter (ast_get_modules m) c; 
	Array.iter (mltype_get_modules m) t
    | _ -> ()
  in 
  List.iter one_decl ld; 
  !m

(*s Tables of global renamings *)

let keywords = ref Idset.empty
let global_ids = ref Idset.empty

let renamings = Hashtbl.create 97

let cache r f =  
  try Hashtbl.find renamings r 
  with Not_found -> let id = f r in Hashtbl.add renamings r id; id 
    
(*s Renaming issues at toplevel *)

module ToplevelParams = struct
  let globals () = Idset.empty
  let pp_global r _ _ = Printer.pr_global r
end

(*s Renaming issues for a monolithic extraction. *)

module MonoParams = struct

  let globals () = !global_ids
		     
  let rename_global_id id = 
    let id' = rename_id id !global_ids in
    global_ids := Idset.add id' !global_ids; 
    id'

  let rename_global r upper = 
    cache r
      (fun r -> 
	 let id = id_of_global None r in
	 rename_global_id (if upper then uppercase_id id else lowercase_id id))
      
  let pp_global r upper _ = 
    str (check_ml r (string_of_id (rename_global r upper)))
      
end


(*s Renaming issues in a modular extraction. *)

module ModularParams = struct

  let globals () = !global_ids 

  let clash r id = 
    exists_cci (make_path (dirpath (sp_of_global None r)) id)
      
  let rename_global_id r id id' prefix =
    let id' = 
      if (Idset.mem id' !keywords) || (id <> id' && clash r id') then 
	id_of_string (prefix^(string_of_id id))
      else id'
    in 
    if (short_module r) = !current_module then 
      global_ids := Idset.add id' !global_ids; 
    id'

  let rename_global r upper =
    cache r 
      (fun r -> 
	 let id = id_of_global None r in 
	 if upper then
	   rename_global_id r id (uppercase_id id) "Coq_"
	 else rename_global_id r id (lowercase_id id) "coq_")

  let qualify m id ctx = 
    if m = !current_module then false
    else if ctx = None then true 
    else if Idset.mem id (out_some ctx) then true 
    else false 
      
  let pp_global r upper ctx = 
    let id = rename_global r upper in 
    let m = short_module r in
    let s = string_of_id id in 
    let s = 
      if qualify m id ctx then 
	String.capitalize (string_of_id m) ^ "." ^ (string_of_id id)
      else string_of_id id 
    in str (check_ml r s)

end

module ToplevelPp = Ocaml.Make(ToplevelParams)

module OcamlMonoPp = Ocaml.Make(MonoParams)
module OcamlModularPp = Ocaml.Make(ModularParams)

module HaskellMonoPp = Haskell.Make(MonoParams)
module HaskellModularPp = Haskell.Make(ModularParams)

module SchemeMonoPp = Scheme.Make(MonoParams)

let pp_decl modular = match lang(), modular with 
    | Ocaml, false -> OcamlMonoPp.pp_decl
    | Ocaml, _ -> OcamlModularPp.pp_decl
    | Haskell, false -> HaskellMonoPp.pp_decl    
    | Haskell, _ -> HaskellModularPp.pp_decl
    | Scheme, _ -> SchemeMonoPp.pp_decl
    | Toplevel, _ -> ToplevelPp.pp_decl

let pp_comment s = match lang () with 
  | Haskell -> str "-- " ++ s ++ fnl () 
  | Scheme -> str ";" ++ s ++ fnl () 
  | Ocaml | Toplevel -> str "(* " ++ s ++ str " *)" ++ fnl ()

let pp_logical_ind r = 
  pp_comment (Printer.pr_global r ++ str " : logical inductive")

let pp_singleton_ind r = 
  pp_comment (Printer.pr_global r ++ str " : singleton inductive constructor")

let set_globals () = match lang () with 
  | Ocaml -> 
      keywords := Ocaml.keywords; 
      global_ids := Ocaml.keywords
  | Haskell -> 
      keywords := Haskell.keywords;
      global_ids := Haskell.keywords
  | Scheme -> 
      keywords := Scheme.keywords;
      global_ids := Scheme.keywords
  | _ -> ()

(*s Extraction to a file. *)

let extract_to_file f prm decls =
  set_globals ();
  let preamble = match lang () with 
    | Ocaml -> Ocaml.preamble    
    | Haskell -> Haskell.preamble
    | Scheme -> Scheme.preamble
    | _ -> assert false 
  in 
  let pp_decl = pp_decl prm.modular in 
  let print_dummys = 
    (decl_search MLdummy decls, 
     decl_type_search Tdummy decls, 
     decl_type_search Tunknown decls) in 
  cons_cofix := Refset.empty;
  current_module := prm.mod_name;
  used_modules := if prm.modular then 
    let set = (Idset.remove prm.mod_name (decl_get_modules decls))
    in Idset.fold (fun m l -> m :: l) set [] 
  else [];
  Hashtbl.clear renamings;
  let cout = match f with 
    | None -> stdout
    | Some f -> open_out f in
  let ft = Pp_control.with_output_to cout in
  pp_with ft (preamble prm !used_modules print_dummys);
  if not prm.modular then 
    List.iter (fun r -> pp_with ft (pp_logical_ind r)) 
      (List.filter decl_is_logical_ind prm.to_appear); 
  if not prm.modular then 
    List.iter (fun r -> pp_with ft (pp_singleton_ind r)) 
      (List.filter decl_is_singleton prm.to_appear); 
  begin 
    try
      List.iter (fun d -> msgnl_with ft (pp_decl d)) decls
    with e ->
      pp_flush_with ft (); if f <> None then close_out cout; raise e
  end;
  pp_flush_with ft ();
  if f <> None then close_out cout;  

(*i 
  (* DO NOT REMOVE: used when making names resolution *)
  let cout = open_out (f^".ren") in 
  let ft = Pp_control.with_output_to cout in
  Hashtbl.iter 
    (fun r id -> 
       if short_module r = !current_module then 
	 msgnl_with ft (pr_id id ++ str " " ++ pr_sp (sp_of_r r)))
    renamings;
  pp_flush_with ft ();
  close_out cout;
i*)    







