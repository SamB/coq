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
open Term
open Declarations
open Libobject
open Lib
open Util
open Miniml

(*s Dummy names. *)

let anonymous = id_of_string "x"
let prop_name = id_of_string "_"

(* In an ML type, update the arguments to all inductive types [(sp,_)] *)		  

let rec update_args sp vl = function  
  | Tapp ( Tglob r :: l ) -> 
      (match r with 
	| IndRef (s,_) when s = sp -> Tapp ( Tglob r :: vl)
	| _ -> Tapp (Tglob r :: (List.map (update_args sp vl) l)))
  | Tapp l -> Tapp (List.map (update_args sp vl) l) 
  | Tarr (a,b)-> 
      Tarr (update_args sp vl a, update_args sp vl b)
  | a -> a

(*s [occurs k t] returns true if [(Rel k)] occurs in [t]. *)

let rec occurs k = function
  | MLrel i -> i = k
  | MLapp(t,argl) -> (occurs k t) || (occurs_list k argl)
  | MLlam(_,t) -> occurs (k + 1) t
  | MLcons(_,_,argl) -> occurs_list k argl
  | MLcase(t,pv) -> 
      (occurs k t) ||
      (array_exists
	 (fun (_,l,t') -> let k' = List.length l in occurs (k + k') t') pv)
  | MLfix(_,l,cl) -> let k' = List.length l in occurs_list (k + k') cl
  | _ -> false

and occurs_list k l = List.exists (occurs k) l

(*s map over ML asts *)

let rec ast_map f = function
  | MLapp (a,al) -> MLapp (f a, List.map f al)
  | MLlam (id,a) -> MLlam (id, f a)
  | MLletin (id,a,b) -> MLletin (id, f a, f b)
  | MLcons (c,n,al) -> MLcons (c, n, List.map f al)
  | MLcase (a,eqv) -> MLcase (f a, Array.map (ast_map_eqn f) eqv)
  | MLfix (fi,ids,al) -> MLfix (fi, ids, List.map f al)
  | MLcast (a,t) -> MLcast (f a, t)
  | MLmagic a -> MLmagic (f a)
  | a -> a

and ast_map_eqn f (c,ids,a) = (c,ids,f a)


(*s Lifting on terms.
    [ml_lift k t] lifts the binding depth of [t] across [k] bindings. 
    We use a generalization [ml_lift k n t] lifting the vars
    of [t] under [n] bindings. *)

let ml_liftn k n c = 
  let rec liftrec n = function
    | MLrel i as c -> if i < n then c else MLrel (i+k)
    | MLlam (id,t) -> MLlam (id, liftrec (n+1) t)
    | MLletin (id,a,b) -> MLletin (id, liftrec n a, liftrec (n+1) b)
    | MLcase (t,pl) -> 
	MLcase (liftrec n t,
      	       	Array.map (fun (id,idl,p) -> 
			     let k = List.length idl in
			     (id, idl, liftrec (n+k) p)) pl)
    | MLfix (n0,idl,pl) -> 
	MLfix (n0,idl,
	       let k = List.length idl in List.map (liftrec (n+k)) pl)
    | a -> ast_map (liftrec n) a
  in 
  if k = 0 then c else liftrec n c

let ml_lift k c = ml_liftn k 1 c

let ml_pop c = ml_lift (-1) c

(*s Substitution. [ml_subst e t] substitutes [e] for [Rel 1] in [t]. 
    It uses a generalization [subst] substituting [m] for [Rel n]. 
    Lifting (of one binder) is done at the same time. *)

let rec ml_subst v =
  let rec subst n m = function
    | MLrel i ->
	if i = n then
	  m
	else 
	  if i < n then MLrel i else MLrel (i-1)
    | MLlam (id,t) ->
	MLlam (id, subst (n+1) (ml_lift 1 m) t)
    | MLletin (id,a,b) ->
	MLletin (id, subst n m a, subst (n+1) (ml_lift 1 m) b)
    | MLcase (t,pv) ->
	MLcase (subst n m t,
		Array.map (fun (id,ids,t) ->
			     let k = List.length ids in
      	       		     (id,ids,subst (n+k) (ml_lift k m) t)) pv)
    | MLfix (i,ids,cl) -> 
	MLfix (i,ids, 
	       let k = List.length ids in
	       List.map (subst (n+k) (ml_lift k m)) cl)
    | a -> ast_map (subst n m) a
  in 
  subst 1 v

(*s Number of occurences of [Rel 1] in [a]. *)

let nb_occur a =
  let cpt = ref 0 in
  let rec count n = function
    | MLrel i -> if i = n then incr cpt
    | MLlam (id,t) -> count (n + 1) t
    | MLletin (id,a,b) -> count n a; count (n + 1) b
    | MLcase (t,pv) ->
	count n t;
	Array.iter (fun (_,l,t) -> let k = List.length l in count (n + k) t) pv
    | MLfix (_,ids,cl) -> 
	let k = List.length ids in List.iter (count (n + k)) cl
    | MLapp (a,l) -> count n a; List.iter (count n) l
    | MLcons (_,_,l) ->  List.iter (count n) l
    | MLmagic a -> count n a
    | MLcast (a,_) -> count n a
    | MLprop | MLexn _ | MLglob _ | MLarity -> ()
  in 
  count 1 a; !cpt

(* elimination of inductive type with one constructor expecting
   one argument (such as [Exist]) *)

let rec elim_singleton_ast rl = function 
  | MLcase (t, [|r,[a],t'|]) when (List.mem r rl) 
      -> MLletin (a,elim_singleton_ast rl t,elim_singleton_ast rl t')   
  | MLcons (r, n, [t]) when (List.mem r rl) 
      -> elim_singleton_ast rl t
  | t -> ast_map (elim_singleton_ast rl) t

let elim_singleton = 
  let rec elim_rec rl = function 
    | [] -> [] 
    | Dtype [il, ir, [cr,[t]]] :: dl -> 
	Dabbrev (ir, il, t) :: (elim_rec (cr::rl) dl) 
    | Dglob (r, a) :: dl -> 
	Dglob (r, elim_singleton_ast rl a)  :: (elim_rec rl dl)
    | d:: dl ->	d :: (elim_rec rl dl)
  in elim_rec []

(*s Beta-reduction *)

let rec betared_ast = function
  | MLapp (f, []) ->
      betared_ast f
  | MLapp (f, a) ->
      let f' = betared_ast f 
      and a' = List.map betared_ast a in
      (match f' with
	 | MLlam (id,t) -> 
	     (match nb_occur t with
		| 0 -> betared_ast (MLapp (ml_pop t, List.tl a'))
		| 1 -> betared_ast (MLapp (ml_subst (List.hd a') t,List.tl a'))
		| _ -> MLletin (id, List.hd a', 
				betared_ast (MLapp (t, List.tl a'))))
	 | _ ->
	     MLapp (f',a'))
  | a -> 
      ast_map betared_ast a
    
let betared_decl = function
 | Dglob (id, a) -> Dglob (id, betared_ast a)
 | d -> d

(*s [uncurrify] uncurrifies the applications of constructors. *)

let rec is_constructor_app = function
  | MLcons _ -> true
  | MLapp (a,_) -> is_constructor_app a
  | _ -> false

let rec decomp_app = function
  | MLapp (f,args) -> 
      let (c,n,args') = decomp_app f in (c, n, args' @ args)
  | MLcons (c,n,args) ->
      (c,n,args)
  | _ ->
      assert false

let rec n_lam n a =
  if n = 0 then a else MLlam (anonymous, n_lam (pred n) a)

let eta_expanse c n args =
  let dif = n - List.length args in
  assert (dif >= 0);
  if dif > 0 then
    let rels = List.rev_map (fun n -> MLrel n) (interval 1 dif) in
    n_lam dif (MLcons (c, n, (List.map (ml_lift dif) args) @ rels))
  else
    MLcons (c,n,args)

let rec uncurrify_ast a = match a with
  | MLapp (f,_) when is_constructor_app f -> 
      let (c,n,args) = decomp_app a in
      let args' = List.map uncurrify_ast args in
      eta_expanse c n args'
  | MLcons (c,n,args) ->
      let args' = List.map uncurrify_ast args in
      eta_expanse c n args'
  | _ -> 
      ast_map uncurrify_ast a

let uncurrify_decl = function
 | Dglob (id, a) -> Dglob (id, uncurrify_ast a)
 | d -> d


(*s Optimization. *)

module Refset = 
  Set.Make(struct type t = global_reference let compare = compare end)

type extraction_params = {
  modular : bool;       (* modular extraction *)
  optimization : bool;  (* we need optimization *)
  to_keep : Refset.t;   (* globals to keep *)
  to_expand : Refset.t; (* globals to expand *)
}

let subst_glob_ast r m = 
  let rec substrec = function
    | MLglob r' as t -> if r = r' then m else t
    | t -> ast_map substrec t
  in
  substrec

let subst_glob_decl r m = function
  | Dglob(r',t') -> Dglob(r', subst_glob_ast r m t')
  | d -> d

let normalize = betared_ast

let expansion_test r t = false

let expand prm r t = 
  (not (Refset.mem r prm.to_keep)) &&
  (Refset.mem r prm.to_expand || (prm.optimization && expansion_test r t))

let warning_expansion r = 
  wARN (hOV 0 [< 'sTR "The constant"; 'sPC;
		 Printer.pr_global r; 'sPC; 'sTR "is expanded." >])

let rec optimize prm = function
  | [] -> 
      []
  | (Dtype _ | Dabbrev _) as d :: l -> 
      d :: (optimize prm l)
  (*i
  | Dglob(id,(MLexn _ as t)) as d :: l ->
      let l' = List.map (expand (id,t)) l in optimize prm l'
  i*)	    
  | [ Dglob(r,t) ] ->
      let t' = normalize t in [ Dglob(r,t') ]
  | Dglob(r,t) as d :: l ->
      let t' = normalize t in
      if expand prm r t' then begin
	warning_expansion r;
	let l' = List.map (subst_glob_decl r t') l in
	if prm.modular then 
	  (Dglob (r,t')) :: (optimize prm l')
	else
	  optimize prm l'
      end else 
	(Dglob(r,t')) :: (optimize prm l)

(*s Table for direct ML extractions. *)

module Refmap = 
  Map.Make(struct type t = global_reference let compare = compare end)

let empty_extractions = (Refmap.empty, Refset.empty)

let extractions = ref empty_extractions

let ml_extractions () = snd !extractions

let add_ml_extraction r s = 
  let (map,set) = !extractions in
  extractions := (Refmap.add r s map, Refset.add r set)

let is_ml_extraction r = Refset.mem r (snd !extractions)

let find_ml_extraction r = Refmap.find r (fst !extractions)

(*s Registration of operations for rollback. *)

let (in_ml_extraction,_) = 
  declare_object ("ML extractions",
		  { cache_function = (fun (_,(r,s)) -> add_ml_extraction r s);
		    load_function = (fun (_,(r,s)) -> add_ml_extraction r s);
		    open_function = (fun _ -> ());
		    export_function = (fun x -> Some x) })

(*s Registration of the table for rollback. *)

open Summary

let _ = declare_summary "ML extractions"
	  { freeze_function = (fun () -> !extractions);
	    unfreeze_function = ((:=) extractions);
	    init_function = (fun () -> extractions := empty_extractions);
	    survive_section = true }

(*s Grammar entries. *)

open Vernacinterp

let string_of_varg = function
  | VARG_IDENTIFIER id -> string_of_id id
  | VARG_STRING s -> s
  | _ -> assert false

let no_such_reference q =
  errorlabstrm "reference_of_varg" 
    [< Nametab.pr_qualid q; 'sTR ": no such reference" >]

let reference_of_varg = function
  | VARG_QUALID q -> 
      (try Nametab.locate q with Not_found -> no_such_reference q)
  | _ -> assert false

(*s \verb!Extract Constant qualid => string! *)

let extract_constant r s = match r with
  | ConstRef _ -> 
      add_anonymous_leaf (in_ml_extraction (r,s))
  | _ -> 
      errorlabstrm "extract_constant"
	[< Printer.pr_global r; 'sPC; 'sTR "is not a constant" >]

let _ = 
  vinterp_add "EXTRACT_CONSTANT"
    (function 
       | [id; s] -> 
	   (fun () -> 
	      extract_constant (reference_of_varg id) (string_of_varg s))
       | _ -> assert false)

(*s \verb!Extract Inductive qualid => string [ string ... string ]! *)

let extract_inductive r (id2,l2) = match r with
  | IndRef ((sp,i) as ip) ->
      let mib = Global.lookup_mind sp in
      let n = Array.length mib.mind_packets.(i).mind_consnames in
      if n <> List.length l2 then
	error "not the right number of constructors";
      add_anonymous_leaf (in_ml_extraction (r,id2));
      list_iter_i
	(fun j s -> 
	   add_anonymous_leaf 
	     (in_ml_extraction (ConstructRef (ip,succ j),s))) l2
  | _ -> 
      errorlabstrm "extract_inductive"
	[< Printer.pr_global r; 'sPC; 'sTR "is not an inductive type" >]

let _ = 
  vinterp_add "EXTRACT_INDUCTIVE"
    (function 
       | [q1; VARG_VARGLIST (id2 :: l2)] ->
	   (fun () -> 
	      extract_inductive (reference_of_varg q1) 
		(string_of_varg id2, List.map string_of_varg l2))
       | _ -> assert false)
