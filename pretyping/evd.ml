(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(* $Id$ *)

open Pp
open Util
open Names
open Nameops
open Term
open Termops
open Sign
open Environ
open Libnames
open Mod_subst

(* The type of mappings for existential variables *)

type evar = existential_key

type evar_body =
  | Evar_empty 
  | Evar_defined of constr

type evar_info = {
  evar_concl : constr;
  evar_hyps : named_context_val;
  evar_body : evar_body}

let evar_context evi = named_context_of_val evi.evar_hyps

let eq_evar_info ei1 ei2 =
  ei1 == ei2 || 
    eq_constr ei1.evar_concl ei2.evar_concl && 
    eq_named_context_val (ei1.evar_hyps) (ei2.evar_hyps) &&
    ei1.evar_body = ei2.evar_body

module Evarmap = Intmap

type evar_map1 = evar_info Evarmap.t

let empty = Evarmap.empty

let to_list evc = Evarmap.fold (fun ev x acc -> (ev,x)::acc) evc []
let dom evc = Evarmap.fold (fun ev _ acc -> ev::acc) evc []
let map evc k = Evarmap.find k evc
let rmv evc k = Evarmap.remove k evc
let remap evc k i = Evarmap.add k i evc
let in_dom evc k = Evarmap.mem k evc
let fold = Evarmap.fold

let add evd ev newinfo =  Evarmap.add ev newinfo evd

let define evd ev body = 
  let oldinfo =
    try map evd ev
    with Not_found -> error "Evd.define: cannot define undeclared evar" in
  let newinfo =
    { evar_concl = oldinfo.evar_concl;
      evar_hyps = oldinfo.evar_hyps;
      evar_body = Evar_defined body} in
  match oldinfo.evar_body with
    | Evar_empty -> Evarmap.add ev newinfo evd
    | _ -> anomaly "Evd.define: cannot define an isevar twice"
    
let is_evar sigma ev = in_dom sigma ev

let is_defined sigma ev =
  let info = map sigma ev in 
  not (info.evar_body = Evar_empty)

let evar_body ev = ev.evar_body
let evar_env evd = Global.env_of_context evd.evar_hyps

let string_of_existential ev = "?" ^ string_of_int ev

let existential_of_int ev = ev

(*******************************************************************)
(* Formerly Instantiate module *)

let is_id_inst inst =
  let is_id (id,c) = match kind_of_term c with
    | Var id' -> id = id'
    | _ -> false
  in
  List.for_all is_id inst

(* Vérifier que les instances des let-in sont compatibles ?? *)
let instantiate_sign_including_let sign args =
  let rec instrec = function
    | ((id,b,_) :: sign, c::args) -> (id,c) :: (instrec (sign,args))
    | ([],[])                        -> []
    | ([],_) | (_,[]) ->
    anomaly "Signature and its instance do not match"
  in 
  instrec (sign,args)

let instantiate_evar sign c args =
  let inst = instantiate_sign_including_let sign args in
  if is_id_inst inst then
    c
  else
    replace_vars inst c

(* Existentials. *)

let existential_type sigma (n,args) =
  let info =
    try map sigma n
    with Not_found ->
      anomaly ("Evar "^(string_of_existential n)^" was not declared") in
  let hyps = evar_context info in
  instantiate_evar hyps info.evar_concl (Array.to_list args)

exception NotInstantiatedEvar

let existential_value sigma (n,args) =
  let info = map sigma n in
  let hyps = evar_context info in
  match evar_body info with
    | Evar_defined c ->
	instantiate_evar hyps c (Array.to_list args)
    | Evar_empty ->
	raise NotInstantiatedEvar

let existential_opt_value sigma ev =
  try Some (existential_value sigma ev)
  with NotInstantiatedEvar -> None

(*******************************************************************)
(*                Constraints for sort variables                   *)
(*******************************************************************)

type sort_var = Univ.universe

type sort_constraint =
  | DefinedSort of sorts (* instantiated sort var *)
  | SortVar of sort_var list * sort_var list (* (leq,geq) *)
  | EqSort of sort_var

module UniverseOrdered = struct
  type t = Univ.universe
  let compare = Pervasives.compare
end
module UniverseMap = Map.Make(UniverseOrdered)

type sort_constraints = sort_constraint UniverseMap.t

let rec canonical_find u scstr =
  match UniverseMap.find u scstr with
      EqSort u' -> canonical_find u' scstr
    | c -> (u,c)

let whd_sort_var scstr t =
  match kind_of_term t with
      Sort(Type u) ->
        (try
          match canonical_find u scstr with
              _, DefinedSort s -> mkSort s
            | _ -> t
        with Not_found -> t)
    | _ -> t

let rec set_impredicative u s scstr =
  match UniverseMap.find u scstr with
    | DefinedSort s' ->
        if family_of_sort s = family_of_sort s' then scstr
        else failwith "sort constraint inconsistency"
    | EqSort u' ->
        UniverseMap.add u (DefinedSort s) (set_impredicative u' s scstr)
    | SortVar(_,ul) ->
        (* also set sorts lower than u as impredicative *)
        UniverseMap.add u (DefinedSort s)
          (List.fold_left (fun g u' -> set_impredicative u' s g) scstr ul)

let rec set_predicative u s scstr =
  match UniverseMap.find u scstr with
    | DefinedSort s' ->
        if family_of_sort s = family_of_sort s' then scstr
        else failwith "sort constraint inconsistency"
    | EqSort u' ->
        UniverseMap.add u (DefinedSort s) (set_predicative u' s scstr)
    | SortVar(ul,_) ->
        UniverseMap.add u (DefinedSort s)
          (List.fold_left (fun g u' -> set_impredicative u' s g) scstr ul)

let var_of_sort = function
    Type u -> u
  | _ -> assert false

let is_sort_var s scstr =
  match s with
      Type u ->
        (try
          match canonical_find u scstr with
              _, DefinedSort _ -> false
            | _ -> true
        with Not_found -> false)
    | _ -> false

let new_sort_var cstr =
  let u = Termops.new_univ() in
  (u, UniverseMap.add u (SortVar([],[])) cstr)


let set_leq_sort (u1,(leq1,geq1)) (u2,(leq2,geq2)) scstr =
  let rec search_rec (is_b, betw, not_betw) u1 =
    if List.mem u1 betw then (true, betw, not_betw)
    else if List.mem u1 not_betw then (is_b, betw, not_betw)
    else if u1 = u2 then (true, u1::betw,not_betw) else
      match UniverseMap.find u1 scstr with
          EqSort u1' -> search_rec (is_b,betw,not_betw) u1'
        | SortVar(leq,_) ->
            let (is_b',betw',not_betw') = 
              List.fold_left search_rec (false,betw,not_betw) leq in
            if is_b' then (true, u1::betw', not_betw')
            else (false, betw', not_betw')
        | DefinedSort _ -> (false,betw,u1::not_betw) in
  let (is_betw,betw,_) = search_rec (false, [], []) u1 in
  if is_betw then
    UniverseMap.add u1 (SortVar(leq1@leq2,geq1@geq2))
      (List.fold_left
        (fun g u -> UniverseMap.add u (EqSort u1) g) scstr betw)
  else
    UniverseMap.add u1 (SortVar(u2::leq1,geq1))
      (UniverseMap.add u2 (SortVar(leq2, u1::geq2)) scstr)

let set_leq s1 s2 scstr =
  let u1 = var_of_sort s1 in
  let u2 = var_of_sort s2 in
  let (cu1,c1) = canonical_find u1 scstr in
  let (cu2,c2) = canonical_find u2 scstr in
  if cu1=cu2 then scstr
  else
    match c1,c2 with
        (EqSort _, _ | _, EqSort _) -> assert false
      | SortVar(leq1,geq1), SortVar(leq2,geq2) ->
          set_leq_sort (cu1,(leq1,geq1)) (cu2,(leq2,geq2)) scstr
      | _, DefinedSort(Prop _ as s) -> set_impredicative u1 s scstr
      | _, DefinedSort(Type _) -> scstr
      | DefinedSort(Type _ as s), _ -> set_predicative u2 s scstr
      | DefinedSort(Prop _), _ -> scstr

let set_sort_variable s1 s2 scstr =
  let u = var_of_sort s1 in
  match s2 with
      Prop _ -> set_impredicative u s2 scstr
    | Type _ -> set_predicative u s2 scstr

let pr_sort_cstrs g =
  let l = UniverseMap.fold (fun u c l -> (u,c)::l) g [] in
  str "SORT CONSTRAINTS:" ++ fnl() ++
  prlist_with_sep fnl (fun (u,c) ->
    match c with
        EqSort u' -> Univ.pr_uni u ++ str" == " ++ Univ.pr_uni u'
      | DefinedSort s -> Univ.pr_uni u ++ str " := " ++ print_sort s
      | SortVar(leq,geq) ->
          str"[" ++ hov 0 (prlist_with_sep spc Univ.pr_uni geq) ++
          str"] <= "++ Univ.pr_uni u ++ brk(0,0) ++ str"<= [" ++
          hov 0 (prlist_with_sep spc Univ.pr_uni leq) ++ str"]")
    l

type evar_map = evar_map1 * sort_constraints
let empty = empty, UniverseMap.empty
let add (sigma,sm) k v = (add sigma k v, sm)
let dom (sigma,_) = dom sigma
let map (sigma,_) = map sigma
let rmv (sigma,sm) k = (rmv sigma k, sm)
let remap (sigma,sm) k v = (remap sigma k v, sm)
let in_dom (sigma,_) = in_dom sigma
let to_list (sigma,_) = to_list sigma
let fold f (sigma,_) = fold f sigma
let define (sigma,sm) k v = (define sigma k v, sm)
let is_evar (sigma,_) = is_evar sigma
let is_defined (sigma,_) = is_defined sigma
let existential_value (sigma,_) = existential_value sigma
let existential_type (sigma,_) = existential_type sigma
let existential_opt_value (sigma,_) = existential_opt_value sigma

(*******************************************************************)
type open_constr = evar_map * constr

(*******************************************************************)
(* The type constructor ['a sigma] adds an evar map to an object of
  type ['a] *)
type 'a sigma = {
  it : 'a ;
  sigma : evar_map}
 
let sig_it x = x.it
let sig_sig x = x.sigma
 
(*******************************************************************)
(* Metamaps *)

(*******************************************************************)
(*            Constraints for existential variables                *)
(*******************************************************************)

type 'a freelisted = {
  rebus : 'a;
  freemetas : Intset.t }

(* Collects all metavars appearing in a constr *)
let metavars_of c =
  let rec collrec acc c =
    match kind_of_term c with
      | Meta mv -> Intset.add mv acc
      | _         -> fold_constr collrec acc c
  in
  collrec Intset.empty c

let mk_freelisted c =
  { rebus = c; freemetas = metavars_of c }

let map_fl f cfl = { cfl with rebus=f cfl.rebus }


(* Clausal environments *)

type clbinding =
  | Cltyp of name * constr freelisted
  | Clval of name * constr freelisted * constr freelisted

let map_clb f = function
  | Cltyp (na,cfl) -> Cltyp (na,map_fl f cfl)
  | Clval (na,cfl1,cfl2) -> Clval (na,map_fl f cfl1,map_fl f cfl2)

(* name of defined is erased (but it is pretty-printed) *)
let clb_name = function
    Cltyp(na,_) -> (na,false)
  | Clval (na,_,_) -> (na,true)

(***********************)
                                                                               
module Metaset = Intset
                                                                               
let meta_exists p s = Metaset.fold (fun x b -> b || (p x)) s false

module Metamap = Intmap

let metamap_to_list m =
  Metamap.fold (fun n v l -> (n,v)::l) m []
 
(*************************)
(* Unification state *)

type hole_kind =
  | ImplicitArg of global_reference * (int * identifier option)
  | BinderType of name
  | QuestionMark
  | CasesType
  | InternalHole
  | TomatchTypeParameter of inductive * int

type conv_pb = Reduction.conv_pb
type evar_constraint = conv_pb * constr * constr
type evar_defs =
    { evars : evar_map;
      conv_pbs : evar_constraint list;
      history : (existential_key * (loc * hole_kind)) list;
      metas : clbinding Metamap.t }

let subst_evar_defs sub evd =
  { evd with
    conv_pbs =
      List.map (fun (k,t1,t2) ->(k,subst_mps sub t1,subst_mps sub t2))
        evd.conv_pbs;
    metas = Metamap.map (map_clb (subst_mps sub)) evd.metas }

let create_evar_defs sigma =
  { evars=sigma; conv_pbs=[]; history=[]; metas=Metamap.empty }
let evars_of d = d.evars
let evars_reset_evd evd d = {d with evars = evd}
let reset_evd (sigma,mmap) d = {d with evars = sigma; metas=mmap}
let add_conv_pb pb d =
(*  let (pbty,c1,c2) = pb in
  pperrnl
    (Termops.print_constr c1 ++
    (if pbty=Reduction.CUMUL then str " <="++ spc()
    else str" =="++spc()) ++
    Termops.print_constr c2);*)
  {d with conv_pbs = pb::d.conv_pbs}
let evar_source ev d =
  try List.assoc ev d.history
  with Not_found -> (dummy_loc, InternalHole)

(* define the existential of section path sp as the constr body *)
let evar_define sp body isevars =
  {isevars with evars = define isevars.evars sp body}

let evar_declare hyps evn ty ?(src=(dummy_loc,InternalHole)) evd =
  { evd with
    evars = add evd.evars evn
      {evar_hyps=hyps; evar_concl=ty; evar_body=Evar_empty};
    history = (evn,src)::evd.history }

let is_defined_evar isevars (n,_) = is_defined isevars.evars n

(* Does k corresponds to an (un)defined existential ? *)
let is_undefined_evar isevars c = match kind_of_term c with
  | Evar ev -> not (is_defined_evar isevars ev)
  | _ -> false

let undefined_evars isevars = 
  let evd = 
    fold (fun ev evi sigma -> if evi.evar_body = Evar_empty then 
	    add sigma ev evi else sigma) 
      isevars.evars empty
  in 
    { isevars with evars = evd }

(* extracts conversion problems that satisfy predicate p *)
(* Note: conv_pbs not satisying p are stored back in reverse order *)
let get_conv_pbs isevars p =
  let (pbs,pbs1) = 
    List.fold_left
      (fun (pbs,pbs1) pb ->
    	 if p pb then 
	   (pb::pbs,pbs1)
         else 
	   (pbs,pb::pbs1))
      ([],[])
      isevars.conv_pbs
  in
  {isevars with conv_pbs = pbs1},
  pbs


(**********************************************************)
(* Sort variables *)

let new_sort_variable (sigma,sm) =
  let (u,scstr) = new_sort_var sm in
  (Type u,(sigma,scstr))
let is_sort_variable (_,sm) s =
  is_sort_var s sm
let whd_sort_variable (_,sm) t = whd_sort_var sm t
let set_leq_sort_variable (sigma,sm) u1 u2 =
  (sigma, set_leq u1 u2 sm)
let define_sort_variable (sigma,sm) u s =
  (sigma, set_sort_variable u s sm)
let pr_sort_constraints (_,sm) = pr_sort_cstrs sm

(**********************************************************)
(* Accessing metas *)

let meta_list evd = metamap_to_list evd.metas

let meta_defined evd mv =
  match Metamap.find mv evd.metas with
    | Clval _ -> true
    | Cltyp _ -> false
 
let meta_fvalue evd mv =
  match Metamap.find mv evd.metas with
    | Clval(_,b,_) -> b
    | Cltyp _ -> anomaly "meta_fvalue: meta has no value"
           
let meta_ftype evd mv =
  match Metamap.find mv evd.metas with
    | Cltyp (_,b) -> b
    | Clval(_,_,b) -> b
 
let meta_declare mv v ?(name=Anonymous) evd =
  { evd with metas = Metamap.add mv (Cltyp(name,mk_freelisted v)) evd.metas }
  
let meta_assign mv v evd =
  match Metamap.find mv evd.metas with
      Cltyp(na,ty) ->
        { evd with
          metas = Metamap.add mv (Clval(na,mk_freelisted v, ty)) evd.metas }
    | _ -> anomaly "meta_assign: already defined"

(* If the meta is defined then forget its name *)
let meta_name evd mv =
  try
    let (na,def) = clb_name (Metamap.find mv evd.metas) in
    if def then Anonymous else na
  with Not_found -> Anonymous

let meta_with_name evd id =
  let na = Name id in
  let (mvl,mvnodef) =
    Metamap.fold
      (fun n clb (l1,l2 as l) ->
        let (na',def) = clb_name clb in
        if na = na' then if def then (n::l1,l2) else (n::l1,n::l2)
        else l)
      evd.metas ([],[]) in
  match mvnodef, mvl with
    | _,[]  -> 
	errorlabstrm "Evd.meta_with_name"
          (str"No such bound variable " ++ pr_id id)
    | ([n],_|_,[n]) -> 
	n
    | _  -> 
	errorlabstrm "Evd.meta_with_name"
          (str "Binder name \"" ++ pr_id id ++
           str"\" occurs more than once in clause")


let meta_merge evd1 evd2 =
  {evd2 with
    metas = List.fold_left (fun m (n,v) -> Metamap.add n v m) 
      evd2.metas (metamap_to_list evd1.metas) }


(**********************************************************)
(* Pretty-printing *)

let pr_meta_map mmap =
  let pr_name = function
      Name id -> str"[" ++ pr_id id ++ str"]"
    | _ -> mt() in
  let pr_meta_binding = function
    | (mv,Cltyp (na,b)) ->
      	hov 0 
	  (pr_meta mv ++ pr_name na ++ str " : " ++
           print_constr b.rebus ++ fnl ())
    | (mv,Clval(na,b,_)) ->
      	hov 0 
	  (pr_meta mv ++ pr_name na ++ str " := " ++
           print_constr b.rebus ++ fnl ())
  in
  prlist pr_meta_binding (metamap_to_list mmap)

let pr_idl idl = prlist_with_sep pr_spc pr_id idl

let pr_evar_info evi =
  let phyps = pr_idl (List.rev (ids_of_named_context (evar_context evi))) in
  let pty = print_constr evi.evar_concl in
  let pb =
    match evi.evar_body with
      | Evar_empty -> mt ()
      | Evar_defined c -> spc() ++ str"=> "  ++ print_constr c
  in
  hov 2 (str"["  ++ phyps ++ spc () ++ str"|- "  ++ pty ++ pb ++ str"]")

let pr_evar_map sigma =
  h 0 
    (prlist_with_sep pr_fnl
      (fun (ev,evi) ->
        h 0 (str(string_of_existential ev)++str"=="++ pr_evar_info evi))
      (to_list sigma))

let pr_evar_defs evd =
  let pp_evm =
    if evd.evars = empty then mt() else
      str"EVARS:"++brk(0,1)++pr_evar_map evd.evars++fnl() in
  let n = List.length evd.conv_pbs in
  let cstrs =
    if n=0 then mt() else
      str"=> " ++ int n ++ str" constraints" ++ fnl() ++ fnl() in
  let pp_met =
    if evd.metas = Metamap.empty then mt() else
      str"METAS:"++brk(0,1)++pr_meta_map evd.metas in
  v 0 (pp_evm ++ cstrs ++ pp_met)
