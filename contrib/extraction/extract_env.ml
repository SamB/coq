(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(*i $Id$ i*)

open Pp
open Util
open Names
open Term
open Lib
open Extraction
open Miniml
open Table
open Mlutil
open Vernacinterp

(*s Recursive computation of the global references to extract. 
    We use a set of functions visiting the extracted objects in
    a depth-first way ([visit_type], [visit_ast] and [visit_decl]).
    We maintain an (imperative) structure [extracted_env] containing
    the set of already visited references and the list of 
    references to extract. The entry point is the function [visit_reference]:
    it first normalizes the reference, and then check it has already been 
    visisted; if not, it adds it to the set of visited references, then
    recursively traverses its extraction and finally adds it to the 
    list of references to extract. *) 

type extracted_env = {
  mutable visited : Refset.t;
  mutable to_extract : global_reference list 
}

let empty () = { visited = ml_extractions (); to_extract = [] }

let rec visit_reference eenv r =
  let r' = match r with
    | ConstructRef ((sp,_),_) -> IndRef (sp,0)
    | IndRef (sp,i) -> if i = 0 then r else IndRef (sp,0)
    | _ -> r
  in
  if not (Refset.mem r' eenv.visited) then begin
    (* we put [r'] in [visited] first to avoid loops in inductive defs *)
    eenv.visited <- Refset.add r' eenv.visited;
    visit_decl eenv (extract_declaration r);
    eenv.to_extract <- r' :: eenv.to_extract
  end

and visit_type eenv t =
  let rec visit = function
    | Tglob r -> visit_reference eenv r
    | Tapp l -> List.iter visit l
    | Tarr (t1,t2) -> visit t1; visit t2
    | Tvar _ | Tprop | Tarity -> ()
  in
  visit t

and visit_ast eenv a =
  let rec visit = function
    | MLglob r -> visit_reference eenv r
    | MLapp (a,l) -> visit a; List.iter visit l
    | MLlam (_,a) -> visit a
    | MLletin (_,a,b) -> visit a; visit b
    | MLcons (r,l) -> visit_reference eenv r; List.iter visit l
    | MLcase (a,br) -> 
	visit a; Array.iter (fun (r,_,a) -> visit_reference eenv r; visit a) br
    | MLfix (_,_,l) -> Array.iter visit l
    | MLcast (a,t) -> visit a; visit_type eenv t
    | MLmagic a -> visit a
    | MLrel _ | MLprop | MLarity | MLexn _ -> ()
  in
  visit a

and visit_inductive eenv inds =
  let visit_constructor (_,tl) = List.iter (visit_type eenv) tl in
  let visit_ind (_,_,cl) = List.iter visit_constructor cl in
  List.iter visit_ind inds

and visit_decl eenv = function
  | Dtype (inds,_) ->
      visit_inductive eenv inds
  | Dabbrev (_,_,t) ->
      visit_type eenv t
  | Dglob (_,a) ->
      visit_ast eenv a
  | Dcustom _ -> ()

(*s Recursive extracted environment for a list of reference: we just
    iterate [visit_reference] on the list, starting with an empty
    extracted environment, and we return the reversed list of 
    references in the field [to_extract]. *)

let extract_env rl =
  let eenv = empty () in
  List.iter (visit_reference eenv) rl;
  List.rev eenv.to_extract

(*s Extraction in the Coq toplevel. We display the extracted term in
    Ocaml syntax and we use the Coq printers for globals. The
    vernacular command is \verb!Extraction! [term]. Whenever [term] is
    a global, its definition is displayed. *)

module ToplevelParams = struct
  let rename_global r = Names.id_of_string (Global.string_of_global r)
  let pp_type_global = Printer.pr_global
  let pp_global = Printer.pr_global
  let cofix_warning = false
end

module Pp = Ocaml.Make(ToplevelParams)

let refs_set_of_list l = List.fold_right Refset.add l Refset.empty 

let decl_of_refs refs =
  List.map extract_declaration (extract_env refs) 

let local_optimize refs = 
  let prm = 
    { strict = true ; modular = false ; 
      module_name = "" ; to_appear = refs} in
  optimize prm (decl_of_refs refs)

let print_user_extract r = 
  mSGNL [< 'sTR "User defined extraction:"; 'sPC; 'sTR (find_ml_extraction r) ; 'fNL>]

let extract_reference r =
  if is_ml_extraction r then
    print_user_extract r 
  else
    mSGNL (Pp.pp_decl (list_last (local_optimize [r])))

let _ = 
  vinterp_add "Extraction"
    (function 
       | [VARG_CONSTR ast] ->
	   (fun () -> 
	      let c = Astterm.interp_constr Evd.empty (Global.env()) ast in
	      match kind_of_term c with
		(* If it is a global reference, then output the declaration *)
		| IsConst sp -> extract_reference (ConstRef sp)
		| IsMutInd ind -> extract_reference (IndRef ind)
		| IsMutConstruct cs -> extract_reference (ConstructRef cs)
		(* Otherwise, output the ML type or expression *)
		| _ ->
		    match extract_constr (Global.env()) [] c with
		      | Emltype (t,_,_) -> mSGNL (Pp.pp_type t)
		      | Emlterm a -> mSGNL (Pp.pp_ast (normalize a)))
       | _ -> assert false)

(*s Recursive extraction in the Coq toplevel. The vernacular command is
    \verb!Recursive Extraction! [qualid1] ... [qualidn]. We use [extract_env]
    to get the saturated environment to extract. *)

let _ = 
  vinterp_add "ExtractionRec"
    (fun vl () ->
       let rl = refs_of_vargl vl in 
       let ml_rl = List.filter is_ml_extraction rl in
       let rl = List.filter (fun x -> not (is_ml_extraction x)) rl in 
       let dl = decl_of_refs rl in
       List.iter print_user_extract ml_rl ;
       List.iter (fun d -> mSGNL (Pp.pp_decl d)) dl)

(*s Extraction parameters. *)

let strict_language = function
  | "ocaml" -> true
  | "haskell" -> false
  | _ -> assert false

(*s Extraction to a file (necessarily recursive). 
    The vernacular command is \verb!Extraction "file"! [qualid1] ... [qualidn].
    We just call [extract_to_file] on the saturated environment. *)

let extract_to_file = function
  | "ocaml" -> Ocaml.extract_to_file 
  | "haskell" -> Haskell.extract_to_file
  | _ -> assert false

let _ = 
  vinterp_add "ExtractionFile"
    (function 
       | VARG_STRING lang :: VARG_VARGLIST o :: VARG_STRING f :: vl ->
	   (fun () -> 
	      let refs = refs_of_vargl vl in
	      let prm = {strict=strict_language lang;
			 modular=false;
			 module_name="";
			 to_appear= refs} in 
	      let decls = decl_of_refs refs in 
	      let decls = add_ml_decls prm decls in 
	      let decls = optimize prm decls in
	      extract_to_file lang f prm decls)
       | _ -> assert false)

(*s Extraction of a module. The vernacular command is \verb!Extraction Module!
    [M]. We build the environment to extract by traversing the segment of
    module [M]. We just keep constants and inductives, and we remove
    those having an ML extraction. *)

let extract_module m =
  let m = Nametab.locate_loaded_library (Nametab.make_short_qualid m) in
  let seg = Library.module_segment (Some m) in
  let get_reference = function
    | sp, Leaf o ->
	(match Libobject.object_tag o with
	   | "CONSTANT" | "PARAMETER" -> ConstRef sp
	   | "INDUCTIVE" -> IndRef (sp,0)
	   | _ -> failwith "caught")
    | _ -> failwith "caught"
  in
  Util.map_succeed get_reference seg

let decl_mem rl = function 
  | Dglob (r,_) -> List.mem r rl 
  | Dabbrev (r,_,_) -> List.mem r rl 
  | Dtype ((_,r,_)::_, _) -> List.mem r rl
  | Dtype ([],_) -> false
  | Dcustom (r,s) ->  List.mem r rl 

let file_suffix = function
  | "ocaml" -> ".ml"
  | "haskell" -> ".hs"
  | _ -> assert false

let _ = 
  vinterp_add "ExtractionModule"
    (function 
       | [VARG_STRING lang; VARG_VARGLIST o; VARG_IDENTIFIER m] ->
	   (fun () -> 
	      Ocaml.current_module := Some m;
	      let ms = Names.string_of_id m in
	      let f = (String.uncapitalize ms) ^ (file_suffix lang) in
	      let prm = {strict=strict_language lang;
			 modular=true;
			 module_name= Names.string_of_id m;
			 to_appear= []} in 
	      let rl = extract_module m in 
	      let decls = optimize prm (decl_of_refs rl) in
	      let decls = add_ml_decls prm decls in 
	      let decls = List.filter (decl_mem rl) decls in
	      extract_to_file lang f prm decls)
       | _ -> assert false)
