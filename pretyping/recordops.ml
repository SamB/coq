(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(* $Id$ *)

open Util
open Pp
open Names
open Libnames
open Nametab
open Term
open Termops
open Typeops
open Libobject
open Library
open Classops
open Mod_subst

(*s Une structure S est un type inductif non r�cursif � un seul
   constructeur (de nom par d�faut Build_S) *)

(* Table des structures: le nom de la structure (un [inductive]) donne
   le nom du constructeur, le nombre de param�tres et pour chaque
   argument r�els du constructeur, le noms de la projection
   correspondante, si valide *)

type struc_typ = {
  s_CONST : identifier; 
  s_PARAM : int;
  s_PROJ : constant option list }

let structure_table = ref (Indmap.empty : struc_typ Indmap.t)
let projection_table = ref Cmap.empty

let option_fold_right f p e = match p with Some a -> f a e | None -> e

let cache_structure (_,(ind,struc)) =
  structure_table := Indmap.add ind struc !structure_table;
  projection_table := 
    List.fold_right (option_fold_right (fun proj -> Cmap.add proj struc))
      struc.s_PROJ !projection_table

let subst_structure (_,subst,((kn,i),struc as obj)) = 
  let kn' = subst_kn subst kn in
  let proj' =
   (* invariant: struc.s_PROJ is an evaluable reference. Thus we can take *)
   (* the first component of subst_con.                                   *)
   list_smartmap 
    (option_smartmap (fun kn -> fst (subst_con subst kn)))
    struc.s_PROJ
  in
    if proj' == struc.s_PROJ && kn' == kn then obj else
      (kn',i),{struc with s_PROJ = proj'}

let (inStruc,outStruc) =
  declare_object {(default_object "STRUCTURE") with 
                    cache_function = cache_structure;
		    load_function = (fun _ o -> cache_structure o);
                    subst_function = subst_structure;
		    classify_function = (fun (_,x) -> Substitute x);
		    export_function = (function x -> Some x)  }

let add_new_struc (s,c,n,l) = 
  Lib.add_anonymous_leaf (inStruc (s,{s_CONST=c;s_PARAM=n;s_PROJ=l}))

let find_structure indsp = Indmap.find indsp !structure_table

let find_projection_nparams = function
  | ConstRef cst -> (Cmap.find cst !projection_table).s_PARAM
  | _ -> raise Not_found

(*s Un "object" est une fonction construisant une instance d'une structure *)

(* Table des definitions "object" : pour chaque object c,

  c := [x1:B1]...[xk:Bk](Build_R a1...am t1...t_n)

  avec ti = (ci ui1...uir)

  Pour tout ci, et Li, la i�me projection de la structure R (si
  d�finie), on d�clare une "coercion"

    o_DEF = c
    o_TABS = B1...Bk
    o_PARAMS = a1...am
    o_TCOMP = ui1...uir
*)

type obj_typ = {
  o_DEF : constr;
  o_TABS : constr list;    (* dans l'ordre *)
  o_TPARAMS : constr list; (* dans l'ordre *)
  o_TCOMPS : constr list } (* dans l'ordre *)

let subst_obj subst obj =
  let o_DEF' = subst_mps subst obj.o_DEF in
  let o_TABS' = list_smartmap (subst_mps subst) obj.o_TABS in    
  let o_TPARAMS' = list_smartmap (subst_mps subst) obj.o_TPARAMS in 
  let o_TCOMPS' = list_smartmap (subst_mps subst) obj.o_TCOMPS in 
    if o_DEF' == obj.o_DEF
      && o_TABS' == obj.o_TABS    
      && o_TPARAMS' == obj.o_TPARAMS 
      && o_TCOMPS' == obj.o_TCOMPS 
    then 
      obj
    else
      { o_DEF = o_DEF' ;
	o_TABS = o_TABS' ;    
	o_TPARAMS = o_TPARAMS' ; 
	o_TCOMPS = o_TCOMPS' }

let object_table =
  (ref [] : ((global_reference * global_reference) * obj_typ) list ref)

let cache_canonical_structure (_,(cst,lo)) =
  List.iter (fun (o,_ as x) ->
    if not (List.mem_assoc o !object_table) then
      object_table := x :: (!object_table)) lo

let subst_object subst ((r1,r2),o as obj) = 
  (* invariant: r1 and r2 are evaluable references. Thus subst_global   *)
  (* cannot instantiate them. Hence we can use just the first component *)
  (* of the answer.                                                     *)
  let r1',_ = subst_global subst r1 in
  let r2',_ = subst_global subst r2 in
  let o' = subst_obj subst o in
  if r1' == r1 && r2' == r2 && o' == o then obj
  else (r1',r2'),o'

let subst_canonical_structure (_,subst,(cst,lo as obj)) =
  (* invariant: cst is an evaluable reference. Thus we can take *)
  (* the first component of subst_con.                                   *)
  let cst' = fst (subst_con subst cst) in
  let lo' = list_smartmap (subst_object subst) lo in
  if cst' == cst & lo' == lo then obj else (cst',lo')

let (inCanonStruc,outCanonStruct) =
  declare_object {(default_object "CANONICAL-STRUCTURE") with 
    open_function = (fun i o -> if i=1 then cache_canonical_structure o);
    cache_function = cache_canonical_structure;
    subst_function = subst_canonical_structure;
    classify_function = (fun (_,x) -> Substitute x);
    export_function = (function x -> Some x) }

let add_canonical_structure x = Lib.add_anonymous_leaf (inCanonStruc x)

let outCanonicalStructure x = fst (outCanonStruct x)

let canonical_structure_info o = List.assoc o !object_table

let freeze () =
  !structure_table, !projection_table, !object_table

let unfreeze (s,p,o) = 
  structure_table := s; projection_table := p; object_table := o

let init () =
  structure_table := Indmap.empty; projection_table := Cmap.empty;
  object_table:=[]

let _ = init()

let _ = 
  Summary.declare_summary "objdefs"
    { Summary.freeze_function = freeze;
      Summary.unfreeze_function = unfreeze;
      Summary.init_function = init;
      Summary.survive_module = false;
      Summary.survive_section = false }
