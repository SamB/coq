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
open Util
open Miniml
open Nametab
open Table
open Options

(*s Dummy names. *)

let anonymous = id_of_string "x"
let prop_name = id_of_string "_"

(*s In an ML type, update the arguments to all inductive types [(sp,_)] *)		  

let rec update_args sp vl = function  
  | Tapp ( Tglob r :: l ) -> 
      (match r with 
	| IndRef (s,_) when s = sp -> Tapp ( Tglob r :: l @ vl )
	| _ -> Tapp (Tglob r :: (List.map (update_args sp vl) l)))
  | Tapp l -> Tapp (List.map (update_args sp vl) l) 
  | Tarr (a,b)-> 
      Tarr (update_args sp vl a, update_args sp vl b)
  | a -> a

exception Found_sp

let sp_of_r r = match r with 
    | ConstRef sp -> sp
    | IndRef (sp,_) -> sp
    | ConstructRef ((sp,_),_) -> sp
    | _ -> assert false

let rec parse_ml_type sp = function 
  | Tglob r -> if (sp_of_r r)=sp then raise Found_sp
  | Tapp l -> List.iter (parse_ml_type sp) l
  | Tarr (a,b) -> (parse_ml_type sp a; parse_ml_type sp b)
  | _ -> ()
      
(*s [occurs k t] returns true if [(Rel k)] occurs in [t]. *)

let rec occurs k = function
  | MLrel i -> i = k
  | MLapp(t,argl) -> (occurs k t) || (occurs_list k argl)
  | MLlam(_,t) -> occurs (k + 1) t
  | MLletin(_,t,t')-> (occurs k t) || (occurs (k+1) t')
  | MLcons(_,argl) -> occurs_list k argl
  | MLcase(t,pv) -> 
      (occurs k t) ||
      (array_exists
	 (fun (_,l,t') -> let k' = List.length l in occurs (k + k') t') pv)
  | MLfix(_,l,cl) -> let k' = Array.length l in occurs_vect (k + k') cl
  | MLcast(t,_) -> occurs k t			
  | MLmagic t -> occurs k t
  | MLglob _ | MLexn _ | MLprop | MLarity -> false

and occurs_list k l = List.exists (occurs k) l

and occurs_vect k v = array_exists (occurs k) v

(* [occurs_itvl k k' t] return true if there is a [(Rel j)] 
   in [t] with [k<=i<=k'] *)

let rec occurs_itvl k k' = function
  | MLrel i -> (k <= i) && (i <= k')
  | MLapp(t,argl) -> (occurs_itvl k k' t) || (occurs_itvl_list k k' argl)
  | MLlam(_,t) -> occurs_itvl (k + 1) (k' + 1) t
  | MLletin(_,t,t') -> (occurs_itvl k k' t) || (occurs_itvl (k+1) (k'+1) t')
  | MLcons(_,argl) -> occurs_itvl_list k k' argl
  | MLcase(t,pv) -> 
      (occurs_itvl k k' t) ||
      (array_exists
         (fun (_,l,t') -> 
            let n = List.length l in occurs_itvl (k + n) (k' + n) t') pv)
  | MLfix(_,l,cl) -> 
      let n = Array.length l in occurs_itvl_vect (k + n) (k' + n) cl
  | MLcast(t,_) -> occurs_itvl k k' t
  | MLmagic t -> occurs_itvl k k' t
  | MLglob _ | MLexn _ | MLprop | MLarity  -> false

and occurs_itvl_list k k' l = List.exists (occurs_itvl k k') l

and occurs_itvl_vect k k' v = array_exists (occurs_itvl k k') v

(*s map over ML asts *)

let rec ast_map f = function
  | MLapp (a,al) -> MLapp (f a, List.map f al)
  | MLlam (id,a) -> MLlam (id, f a)
  | MLletin (id,a,b) -> MLletin (id, f a, f b)
  | MLcons (c,al) -> MLcons (c, List.map f al)
  | MLcase (a,eqv) -> MLcase (f a, Array.map (ast_map_eqn f) eqv)
  | MLfix (fi,ids,al) -> MLfix (fi, ids, Array.map f al)
  | MLcast (a,t) -> MLcast (f a, t)
  | MLmagic a -> MLmagic (f a)
  | MLrel _ | MLglob _ | MLexn _ | MLprop | MLarity as a -> a

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
    | MLcase (t,pv) -> 
	MLcase (liftrec n t,
      	       	Array.map (fun (id,idl,p) -> 
			     let k = List.length idl in
			     (id, idl, liftrec (k+n) p)) pv)
    | MLfix (n0,idl,pv) -> 
	MLfix (n0,idl,
	       let k = Array.length idl in Array.map (liftrec (k+n)) pv)
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
    | MLrel i as a ->
	if i = n then
	  m
	else 
	  if i < n then a else MLrel (i-1)
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
	       let k = Array.length ids in
	       Array.map (subst (n+k) (ml_lift k m)) cl)
    | a ->
        ast_map (subst n m) a
  in 
  subst 1 v

(*s Simplification of any [MLapp (MLapp (_,_),_)] *)

let rec merge_app a = match a with 
  | MLapp (f,l) -> 
      let f' = merge_app f in 
      let l' = List.map merge_app l in 
      (match f' with 
	 | MLapp (f'',l'') -> MLapp (f'',l'' @ l')
	 | _ -> MLapp (f', l'))
  | _ -> ast_map merge_app a

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
	let k = Array.length ids in Array.iter (count (n + k)) cl
    | MLapp (a,l) -> count n a; List.iter (count n) l
    | MLcons (_,l) ->  List.iter (count n) l
    | MLmagic a -> count n a
    | MLcast (a,_) -> count n a
    | MLprop | MLexn _ | MLglob _ | MLarity -> ()
  in 
  count 1 a; !cpt

(*s [collect_lams MLlam(id1,...MLlam(idn,t)...)] returns
    the list [idn;...;id1] and the term [t]. *)

let collect_lams = 
  let rec collect acc = function
    | MLlam(id,t) -> collect (id::acc) t
    | x           -> acc,x
  in 
  collect []

let collect_n_lams = 
  let rec collect acc n t = 
    if n = 0 then acc,t 
    else match t with 
      | MLlam(id,t) -> collect (id::acc) (n-1) t
      | _ -> assert false
  in 
  collect [] 

let rec remove_n_lams n t = 
  if n = 0 then t  
  else match t with 
      | MLlam(id,t) -> remove_n_lams (n-1) t
      | _ -> assert false

let rec nb_lam = function 
  | MLlam(id,t) -> succ (nb_lam t)
  | _ -> 0 

(* [named_abstract] does the converse of [collect_lambda] *)

let rec named_lams a = function 
  | [] -> a 
  | id :: ids -> named_lams (MLlam(id,a)) ids

let rec anonym_lams a = function 
  | 0 -> a 
  | n -> anonym_lams (MLlam(anonymous,a)) (pred n)

(*s The two following functions test and create [MLrel n;...;MLrel 1] *)

let rec test_eta_args n = function 
  | [] -> n=0
  | a :: q -> (a = (MLrel n)) && (test_eta_args (pred n) q)

let rec make_eta_args n = 
  if n = 0 then [] else (MLrel n)::(make_eta_args (pred n))
  
(*s [generalize_check k k' i] return true if there is a [(Rel j)] 
   in [t] with [k<=i<=k'] *)

exception Impossible

let check_and_generalize (r0,l,c) = 
  let nargs = List.length l in 
  let rec genrec k k' = function 
    | MLrel i as c -> 
	if i<k then c 
	else if i>k' then MLrel (i-nargs+1) 
	else raise Impossible
    | MLcons(r,args) when r=r0 -> 
	if test_eta_args nargs args then MLrel k
	else raise Impossible
    | MLlam(id,t) -> MLlam(id,genrec (k + 1) (k' + 1) t)
    | MLletin(id,t,t') -> MLletin(id,(genrec k k' t),(genrec (k+1) (k'+1) t'))
    | MLcase(t,pv) -> 
	MLcase(genrec k k' t,
	       Array.map (fun (id,idl,t') -> 
			    let n = List.length idl in 
			    (id,idl,genrec (k+n) (k'+n) t')) pv)
    | MLfix(n0,idl,pv) -> 
	MLfix(n0,idl,
	      let n = Array.length idl in Array.map (genrec (k+n) (k'+n)) pv)
    | a -> ast_map (genrec k k') a
  in genrec 1 nargs c  

let check_case br = 
  let f = check_and_generalize br.(0) in 
  for i = 1 to Array.length br - 1 do 
    if check_and_generalize br.(i) <> f then raise Impossible 
  done; f

let check_constant_case br = 
  if br = [||] then raise Impossible; 
  let (r,l,t) = br.(0) in
  let n = List.length l in 
  if occurs_itvl 1 n t then raise Impossible; 
  let cst = ml_lift (-n) t in 
  for i = 1 to Array.length br - 1 do 
    let (r,l,t) = br.(i) in
    let n = List.length l in
    if (occurs_itvl 1 n t) || (cst <> (ml_lift (-n) t)) 
    then raise Impossible
  done; cst

(* [permut_rels n n' c] translates [Rel 1 ... Rel n] to [Rel (n'+1) ... Rel (n'+n)]
   and [Rel (n+1) ... Rel (n+n')] to [Rel 1 ... Rel n'] *)

let permut_rels n n' = 
  let rec permut k = function
    | MLrel i as c -> 
	if i<k || i>=k+n+n' then c 
	else if i<n+k then MLrel (i+n')
	else MLrel (i-n)
    | MLlam (id,t) -> MLlam (id, permut (k+1) t)
    | MLletin (id,a,b) -> MLletin (id, permut k a, permut (k+1) b)
    | MLcase (t,pv) -> 
	MLcase (permut k t,
      	       	Array.map (fun (id,idl,p) -> 
			     let nl = List.length idl in
			     (id, idl, permut (k+nl) p)) pv)
    | MLfix (n0,idl,pv) -> 
	MLfix (n0,idl,
	       let nl = Array.length idl in Array.map (permut (k+nl)) pv)
    | a -> ast_map (permut k) a
  in 
  permut 1

let rec permut_case_fun br acc = 
  let (_,_,t0) = br.(0) in 
  let nb = ref (nb_lam t0) in 
  Array.iter (fun (_,_,t) -> let n = nb_lam t in if n < !nb then nb:=n) br;
  let ids,_ = collect_n_lams !nb t0
  in 
  for i = 0 to Array.length br - 1 do 
    let (r,l,t) = br.(i) in 
    let t = permut_rels !nb (List.length l) (remove_n_lams !nb t) 
    in br.(i) <- (r,l,t)
  done;
  ids

(*s Some Beta-iota reductions + simplifications*)

let constructor_index = function
  | ConstructRef (_,j) -> pred j
  | _ -> assert false

let is_atomic = function 
  | MLrel _ | MLglob _ | MLexn _ | MLprop | MLarity -> true
  | _ -> false

let all_constr br = 
  try 
    Array.iter 
      (fun (_,_,t)-> 
	 match t with 
	   | MLcons _ -> () 
	   | _ -> raise Impossible) 
      br;
    true
  with Impossible -> false
  
let normalize a = 
  let o = optim() in 
  let rec simplify = function
    | MLapp (f, []) ->
	simplify f
    | MLapp (f, a) ->
	let f' = simplify f 
	and a' = List.map simplify a in
	(match f' with
	     (* beta redex *)
	   | MLlam (id,t) -> 
	       (match nb_occur t with
		  | 0 -> simplify (MLapp (ml_pop t, List.tl a'))
		  | 1 when o -> 
		      simplify (MLapp (ml_subst (List.hd a') t, List.tl a'))
		  | _ -> 
		      let a'' = List.map (ml_lift 1) (List.tl a') in
		      simplify (MLletin (id, List.hd a', MLapp (t, a''))))
	       (* application of a let in: we push arguments inside *)
	   | MLletin (id,e1,e2) ->
	       MLletin (id, e1, simplify (MLapp (e2, List.map (ml_lift 1) a')))
		 (* application of a case: we push arguments inside *)
	   | MLcase (e,br) ->
	       let br' = 
		 Array.map 
      	       	 (fun (n,l,t) -> 
		    let k = List.length l in
		    let a'' = List.map (ml_lift k) a' in
      	       	    (n, l, simplify (MLapp (t,a'')))) 
		   br 
	       in simplify (MLcase (e,br'))
	   | _ ->
	       MLapp (f',a'))
    | MLcase (e,[||]) ->
	MLexn "Empty inductive"
    | MLcase (e,br) ->
	(match simplify e with
	     (* iota redex *)
	   | MLcons (r,a) ->  
	       let (_,ids,c) = br.(constructor_index r) in
	       let c = List.fold_right (fun id t -> MLlam (id,t)) ids c in
	       simplify (MLapp (c,a))
	   | MLcase(e',br') when o && (all_constr br') ->
	       let new_br= 
		 Array.map 
		   (function 
		      | (n, i, MLcons (r,a))-> 
			  let (_,ids,c) = br.(constructor_index r) in
			  let c = List.fold_right 
				    (fun id t -> MLlam (id,t)) ids c in
			  let c = ml_lift (List.length i) c in 
			  (n,i,simplify (MLapp (c,a)))
		      | _ -> assert false) br'
	       in MLcase(e', new_br)
	   | e' -> 
	       let br' = Array.map (fun (n,l,t) -> (n,l,simplify t)) br in 
	       if o then
		 try 
		   let f = check_case br' in 
		   simplify (MLapp (MLlam (anonymous,f),[e']))
		 with Impossible -> 
	           try check_constant_case br' 
                   with Impossible ->
		     (match e' with 
			| MLrel i -> 
			    let ids = permut_case_fun br' [] in 
			    let ids = List.map 
					(fun id -> 
					   if id = prop_name then anonymous 
					   else id) ids in
			    let n = List.length ids in 
			    if n = 0 then MLcase (e', br') 
			    else named_lams (MLcase (MLrel (i+n), br')) ids
			| _ -> MLcase (e', br'))
	       else MLcase (e', br'))
    | MLletin(_,c,e) when (is_atomic c) || (nb_occur e <= 1) -> 
	(* expansion of a letin in special cases *)
	simplify (ml_subst c e)
    | MLfix(i,ids,c) as t when o -> 
	let n = Array.length ids in 
	if occurs_itvl 1 n c.(i) then 
	  MLfix (i, ids, Array.map simplify c)
	else simplify (ml_lift (-n) c.(i)) (* dummy fixpoint *)
    | a -> 
	ast_map simplify a 
  in simplify (merge_app a)

let normalize_decl = function
 | Dglob (id, a) -> Dglob (id, normalize a)
 | d -> d

(*s special treatment of non-mutual fixpoint for pretty-printing purpose *)

let optimize_fix a = 
  if not (optim()) then a 
  else
    let ids,a' = collect_lams a in 
    let n = List.length ids in 
    if n = 0 then a 
    else  
      (match a' with 
	 | MLfix(_,[|f|],[|c|]) ->
	     let new_f = MLapp (MLrel (n+1),make_eta_args n) in 
	     let new_c = named_lams (ml_subst new_f c) ids
	     in MLfix(0,[|f|],[|new_c|])
	 | MLapp(a',args) ->
	     (match a' with 
		| MLfix(_,[|_|],[|_|]) when (test_eta_args n args)-> a'
		| MLfix(_,[|f|],[|c|]) -> 
		    (try 
		      let m = List.length args in 
		      let v = Array.make n 0 in 
		      for i=0 to (n-1) do v.(i)<-i done;
		      let aux i = function 
			  MLrel j when v.(j-1)>=0 -> v.(j-1)<-(-i-1)
			| _ -> raise Impossible
		      in
		      list_iter_i aux args; 
		      let args_f = List.rev_map (fun i -> MLrel (i+m+1)) (Array.to_list v) in
		      let new_f = anonym_lams (MLapp (MLrel (n+m+1),args_f)) m in  
		      let new_c = named_lams (normalize (MLapp ((ml_subst new_f c),args))) ids
		      in MLfix(0,[|f|],[|new_c|])
		    with Impossible -> a) 
		| _ -> a)
	 | _ -> a)


(*s Utility functions used for the decision of expansion *)

let rec ml_size = function
  | MLapp(t,l) -> List.length l + ml_size t + ml_size_list l
  | MLlam(_,t) -> 1 + ml_size t
  | MLcons(_,l) -> ml_size_list l
  | MLcase(t,pv) -> 
      1 + ml_size t + (Array.fold_right (fun (_,_,t) a -> a + ml_size t) pv 0)
  | MLfix(_,_,f) -> ml_size_array f
  | MLletin (_,_,t) -> ml_size t
  | MLcast (t,_) -> ml_size t
  | MLmagic t -> ml_size t
  | _ -> 0

and ml_size_list l = List.fold_left (fun a t -> a + ml_size t) 0 l

and ml_size_array l = Array.fold_left (fun a t -> a + ml_size t) 0 l

let is_fix = function MLfix _ -> true | _ -> false

let rec is_constr = function
  | MLcons _   -> true
  | MLlam(_,t) -> is_constr t
  | _          -> false


(*s Strictness *)

(* A variable is strict if the evaluation of the whole term implies
   the evaluation of this variable. Non-strict variables can be found 
   behind Match, for example. Expanding a term [t] is a good idea when 
   it begins by at least one non-strict lambda, since the corresponding 
   argument to [t] might be unevaluated in the expanded code. *)

exception Toplevel

let lift n l = List.map ((+) n) l

let pop n l = List.map (fun x -> if x<=n then raise Toplevel else x-n) l 

(* This function returns a list of de Bruijn indices of non-strict variables,
   or raises [Toplevel] if it has an internal non-strict variable. 
   In fact, not all variables are checked for strictness, only the ones which 
   de Bruijn index is in the candidates list [cand]. The flag [add] controls 
   the behaviour when going through a lambda: should we add the corresponding 
   variable to the candidates?  We use this flag to check only the external 
   lambdas, those that will correspond to arguments. *)

let rec non_stricts add cand = function 
  | MLlam (id,t) -> 
      let cand = lift 1 cand in
      let cand = if add then 1::cand else cand in
      pop 1 (non_stricts add cand t)
  | MLrel n -> 
      List.filter ((<>) n) cand  
  | MLapp (MLrel n, _) -> 
      List.filter ((<>) n) cand
	(* In [(x y)] we say that only x is strict. Cf [sig_rec]. 
	   We may gain something if x is replaced by a function like
	   a projection *)
  | MLapp (t,l)-> 
      let cand = non_stricts false cand t in 
      List.fold_left (non_stricts false) cand l 
  | MLcons (_,l) -> 
      List.fold_left (non_stricts false) cand l
  | MLletin (_,t1,t2) -> 
      let cand = non_stricts false cand t1 in 
      pop 1 (non_stricts add (lift 1 cand) t2)
  | MLfix (_,i,f)-> 
      let n = Array.length i in
      let cand = lift n cand in 
      let cand = Array.fold_left (non_stricts false) cand f in 
      pop n cand
  | MLcase (t,v) -> 
      (* The only interesting case: for a variable to be non-strict, 
	 it is sufficient that it appears non-strict in at least one branch,
	 so he make an union (in fact a merge). *)
      let cand = non_stricts false cand t in 
      Array.fold_left 
	(fun c (_,i,t)-> 
	   let n = List.length i in 
	   let cand = lift n cand in 
	   let cand = pop n (non_stricts add cand t) in
	   Sort.merge (<=) cand c) [] v
	(* [merge] may duplicates some indices, but I don't mind. *)
  | MLcast (t,_) -> 
      non_stricts add cand t
  | MLmagic t -> 
      non_stricts add cand t
  | _ -> 
      cand

(* The real test: we are looking for internal non-strict variables, so we start
   with no candidates, and the only positive answer is via the [Toplevel] 
   exception. *)

let is_not_strict t = 
  try 
    let _ = non_stricts true [] t in false
  with 
    | Toplevel -> true

(*s Expansion decision *)

(* [expansion_test] answers the following question: 
   If we could expand [t] (the user said nothing special), 
   should we expand ? 
   
   We don't expand fixpoints, but always inductive constructors
   and small terms.
   Last case of expansion is a term with at least one non-strict 
   variable (i.e. a variable that may not be evaluated). *)

let expansion_test t = 
  (not (is_fix t))
  &&
  ((is_constr t) ||
   (ml_size t < 3) ||
   ((ml_size t < 12) && (is_not_strict t)))

(* If the user doesn't say he wants to keep [t], we expand in two cases:
   \begin{itemize}
   \item the user explicitly requests it 
   \item [expansion_test] answers that the expansion is a good idea, and 
   we are free to act (AutoInline is set)
   \end{itemize} *)

let expand strict_lang r t = 
  (not (to_keep r)) (* the user DOES want to keep it *)
  &&
  ((to_inline r) (* the user DOES want to expand it *) 
   || 
   (auto_inline () && strict_lang && expansion_test t)) 

(*s Optimization *)

let subst_glob_ast r m = 
  let rec substrec = function
    | MLglob r' as t -> if r = r' then m else t
    | t -> ast_map substrec t
  in
  substrec

let subst_glob_decl r m = function
  | Dglob(r',t') -> Dglob(r', subst_glob_ast r m t')
  | d -> d

let warning_expansion r = 
  wARN (hOV 0 [< 'sTR "The constant"; 'sPC;
		 Printer.pr_global r; 
(*    'sTR (" of size "^ (string_of_int (ml_size t))); *)
    'sPC; 'sTR "is expanded." >])

let print_ml_decl prm (r,_) = 
  not (to_inline r) || List.mem r prm.to_appear

let add_ml_decls prm decls = 
  let l = sorted_ml_extractions () in 
  let l = List.filter (print_ml_decl prm) l in 
  let l = List.map (fun (r,s)-> Dcustom (r,s)) l in 
  (List.rev l @ decls)

let strict_language = function
  | "ocaml" -> true
  | "haskell" -> false
  | _ -> assert false

let rec optimize prm = function
  | [] -> 
      []
  | ( Dabbrev (r,_,Tarity) |
	Dabbrev(r,_,Tprop) | 
	  Dglob(r,MLarity) | 
	    Dglob(r,MLprop) ) as d :: l ->
      if List.mem r prm.to_appear then
	d :: (optimize prm l) 
      else optimize prm l
  | Dglob (r,t) :: l ->
      let t = normalize t in
      let b = expand (strict_language prm.lang) r t in
      let l = if b then 
	begin
	  if prm.toplevel then if_verbose warning_expansion r;
	  List.map (subst_glob_decl r t) l
	end
      else l in 
      if (prm.mod_name <> None) || List.mem r prm.to_appear || not b then 
	let t = optimize_fix t in
	Dglob (r,t) :: (optimize prm l)
      else
	optimize prm l
  | (Dtype _ | Dabbrev _ | Dcustom _) as d :: l -> 
      d :: (optimize prm l)

