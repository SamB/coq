(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(*i $Id$ i*)

(*i*)
open Pp
open Names
open Term
open Declarations
open Util
open Miniml
open Nametab
open Table
open Options
open Libnames
(*i*)

(*s Exceptions. *)

exception Found
exception Impossible

(*S Names operations. *)

let anonymous = id_of_string "x"
let dummy_name = id_of_string "_"

let id_of_name = function
  | Anonymous -> anonymous
  | Name id when id = dummy_name -> anonymous
  | Name id -> id 

(*S Operations upon ML types (with meta). *)

let meta_count = ref 0 
		     
let reset_meta_count () = meta_count := 0
			      
let new_meta _ = 
  incr meta_count; 
  Tmeta {id = !meta_count; contents = None}

(*s From a type schema to a type. All [Tvar] becomes fresh [Tmeta]. *)

let instantiation (nb,t) =
    let c = !meta_count in 
    let a = Array.make nb {id=0; contents = None} 
    in 
    for i = 0 to nb-1 do 
      a.(i) <- {id=i+c+1; contents=None}
    done; 
    let rec var2meta t = match t with 
      | Tvar i -> Tmeta a.(i-1)
      | Tmeta {contents=None} -> t 
      | Tmeta {contents=Some u} -> var2meta u
      | Tglob (r,l) -> Tglob(r, List.map var2meta l) 
      | Tarr (t1,t2) -> Tarr (var2meta t1, var2meta t2)
      | t -> t
    in 
    meta_count := !meta_count + nb; 
    var2meta t

(*s Occur-check of a uninstantiated meta in a type *)

let rec type_occurs alpha t =
  match t with
  | Tmeta {id=beta; contents=None} -> alpha = beta
  | Tmeta {contents=Some u} -> type_occurs alpha u
  | Tarr (t1, t2) -> type_occurs alpha t1 || type_occurs alpha t2
  | Tglob (r,l) -> List.exists (type_occurs alpha) l  
  | _ -> false

(*s Most General Unificator *)

let rec mgu = function
  | Tmeta m, Tmeta m' when m.id = m'.id -> ()
  | Tmeta m, t when m.contents=None -> 
      if type_occurs m.id t then raise Impossible
      else m.contents <- Some t
  | t, Tmeta m when m.contents=None -> 
      if type_occurs m.id t then raise Impossible
      else m.contents <- Some t
  | Tmeta {contents=Some u}, t -> mgu (u, t)
  | t, Tmeta {contents=Some u} -> mgu (t, u)
  | Tarr(a, b), Tarr(a', b') ->
      mgu (a, a'); mgu (b, b')
  | Tglob (r,l), Tglob (r',l') when r = r' ->
       List.iter mgu (List.combine l l')
  | Tvar i, Tvar j when i = j -> ()
  | Tvar' i, Tvar' j when i = j -> ()
  | Tdummy, Tdummy -> ()
  | Tunknown, Tunknown -> ()
  | _ -> raise Impossible

let needs_magic p = try mgu p; false with Impossible -> true

let put_magic_if b a = if b then MLmagic a else a

let put_magic p a = if needs_magic p then MLmagic a else a


(*S ML type env. *)

module Mlenv = struct 
  
  let meta_cmp m m' = compare m.id m'.id 
  module Metaset = Set.Make(struct type t = ml_meta let compare = meta_cmp end)

  (* Main MLenv type. [env] is the real environment, whereas [free] 
     (tries to) keep trace of the free meta variables occurring in [env]. *)

  type t = { env : ml_schema list; mutable free : Metaset.t}

  (* Empty environment. *)

  let empty = { env = []; free = Metaset.empty }

  (* [get] returns a instantiated copy of the n-th most recently added 
     type in the environment. *)

  let get mle n = 
    assert (List.length mle.env >= n); 
    instantiation (List.nth mle.env (n-1))

  (* [find_free] finds the free meta in a type. *) 

  let rec find_free set = function 
    | Tmeta m when m.contents = None -> Metaset.add m set
    | Tmeta {contents = Some t} -> find_free set t
    | Tarr (a,b) -> find_free (find_free set a) b
    | Tglob (_,l) -> List.fold_left find_free set l
    | _ -> set

  (* The [free] set of an environment can be outdate after 
     some unifications. [clean_free] takes care of that. *) 
			
  let clean_free mle = 
    let rem = ref Metaset.empty 
    and add = ref Metaset.empty in 
    let clean m = match m.contents with 
      | None -> () 
      | Some u -> rem := Metaset.add m !rem; add := find_free !add u
    in 
    Metaset.iter clean mle.free; 
    mle.free <- Metaset.union (Metaset.diff mle.free !rem) !add

  (* From a type to a type schema. If a [Tmeta] is still uninstantiated
     and does appears in the [mle], then it becomes a [Tvar]. *)

  let generalization mle t = 
    let c = ref 0 in 
    let map = ref (Intmap.empty : int Intmap.t) in 
    let add_new i = incr c; map := Intmap.add i !c !map; !c in 
    let rec meta2var t = match t with 
      | Tmeta {contents=Some u} -> meta2var u 
      | Tmeta ({id=i} as m) -> 
	  (try Tvar (Intmap.find i !map) 
	   with Not_found ->  
	     if Metaset.mem m mle.free then t 
	     else Tvar (add_new i))
      | Tarr (t1,t2) -> Tarr (meta2var t1, meta2var t2)
      | Tglob (r,l) -> Tglob (r, List.map meta2var l) 
      | t -> t 
    in !c, meta2var t
	
  (* Adding a type in an environment, after generalizing. *)

  let push_gen mle t = 
    clean_free mle; 
    { env = generalization mle t :: mle.env; free = mle.free }

  let push_type {env=e;free=f} t = 
    { env = (0,t) :: e; free = find_free f t} 
    
  let push_std_type {env=e;free=f} t = 
    { env = (0,t) :: e; free = f}

end


(*S Operations upon ML types (without meta). *)

(*s Does a section path occur in a ML type ? *)

let kn_of_r r = match r with 
    | ConstRef kn -> kn
    | IndRef (kn,_) -> kn
    | ConstructRef ((kn,_),_) -> kn
    | _ -> assert false

let rec type_mem_kn kn = function 
  | Tmeta _ -> assert false
  | Tglob (r,l) -> (kn_of_r r) = kn || List.exists (type_mem_kn kn) l
  | Tarr (a,b) -> (type_mem_kn kn a) || (type_mem_kn kn b)
  | _ -> false

let type_maxvar t = 
  let rec parse n = function 
    | Tmeta _ -> assert false
    | Tvar i -> max i n 
    | Tarr (a,b) -> parse (parse n a) b
    | Tglob (_,l) -> List.fold_left parse n l 
    | _ -> n 
  in parse 0 t

let rec type_decomp = function 
  | Tmeta _ -> assert false
  | Tarr (a,b) -> let l,h = type_decomp b in a::l, h 
  | a -> [],a

let rec type_recomp (l,t) = match l with 
  | [] -> t 
  | a::l -> Tarr (a, type_recomp (l,t))

let rec var2var' = function 
  | Tmeta _ -> assert false
  | Tvar i -> Tvar' i
  | Tarr (a,b) -> Tarr (var2var' a, var2var' b)
  | Tglob (r,l) -> Tglob (r, List.map var2var' l)
  | a -> a

(*s Sustitution of [Tvar i] by [t] in a ML type. *)

let type_subst i t = 
  let rec subst = function 
  | Tvar j when i = j -> t
  | Tarr (a,b) -> Tarr (subst a, subst b)
  | Tglob (r, l) -> Tglob (r, List.map subst l)
  | a -> a 
  in subst

(* Simultaneous substitution of [Tvar 1;...; Tvar n] by [l] in a ML type. *)

let type_subst_all l t = 
  let rec subst = function 
    | Tvar j -> List.nth l (j-1)
    | Tarr (a,b) -> Tarr (subst a, subst b)
    | Tglob (r, l) -> Tglob (r, List.map subst l)
    | a -> a
  in subst t

type abbrev_map = global_reference -> ml_type option

(*s Delta-reduction of type constants everywhere in a ML type [t].
   [env] is a function of type [ml_type_env]. *)

let type_expand env t = 
  let rec expand = function
    | Tglob (r,l) as t ->    
	(match env r with 
	   | Some mlt -> expand (type_subst_all l mlt) 
	   | None -> Tglob (r, List.map expand l))
    | Tarr (a,b) -> Tarr (expand a, expand b)
    | a -> a
  in expand t

(*s Idem, but only at the top level of implications. *)

let is_arrow = function Tarr _ -> true | _ -> false

let type_weak_expand env t = 
  let rec expand = function
    | Tglob (r,l) as t ->    
	(match env r with 
	   | Some mlt -> 
	       let u = expand (type_subst_all l mlt) in 
	       if is_arrow u then u else t
	   | None -> t)
    | Tarr (a,b) -> Tarr (a, expand b)
    | a -> a
  in expand t

(*s Equality over ML types modulo delta-reduction *)

let type_eq env t t' = (type_expand env t = type_expand env t')

let type_neq env t t' = (type_expand env t <> type_expand env t')

let type_to_sign env t = 
  let rec f = function 
    | Tarr (a,b) -> (Tdummy <> a) :: (f b)
    | _ -> [] 
  in f (type_expand env t)

let type_expunge env t = 
  let s = type_to_sign env t in 
  if s = [] then t 
  else if List.mem true s then 
    let rec f t s = 
      if List.mem false s then 
	match t with 
	  | Tarr (a,b) -> 
	      let t = f b (List.tl s) in 
	      if List.hd s then Tarr (a, t) else t  
	  | Tglob (r,l) ->
	      (match env r with 
		 | Some mlt -> f (type_subst_all l mlt) s
		 | None -> assert false)
	  | _ -> assert false
      else t 
    in f t s 
  else Tarr (Tdummy, snd (type_decomp (type_weak_expand env t))) 

(*S Generic functions over ML ast terms. *)

(*s [ast_iter_rel f t] applies [f] on every [MLrel] in t. It takes care 
   of the number of bingings crossed before reaching the [MLrel]. *)

let ast_iter_rel f = 
  let rec iter n = function
    | MLrel i -> f (i-n)
    | MLlam (_,a) -> iter (n+1) a
    | MLletin (_,a,b) -> iter n a; iter (n+1) b
    | MLcase (a,v) ->
	iter n a; Array.iter (fun (_,l,t) -> iter (n + (List.length l)) t) v
    | MLfix (_,ids,v) -> let k = Array.length ids in Array.iter (iter (n+k)) v
    | MLapp (a,l) -> iter n a; List.iter (iter n) l
    | MLcons (_,l) ->  List.iter (iter n) l
    | MLcast (a,_) -> iter n a
    | MLmagic a -> iter n a
    | MLglob _ | MLexn _ | MLdummy -> ()
  in iter 0 

(*s Map over asts. *)

let ast_map_case f (c,ids,a) = (c,ids,f a)

let ast_map f = function
  | MLlam (i,a) -> MLlam (i, f a)
  | MLletin (i,a,b) -> MLletin (i, f a, f b)
  | MLcase (a,v) -> MLcase (f a, Array.map (ast_map_case f) v)
  | MLfix (i,ids,v) -> MLfix (i, ids, Array.map f v)
  | MLapp (a,l) -> MLapp (f a, List.map f l)
  | MLcons (c,l) -> MLcons (c, List.map f l)
  | MLcast (a,t) -> MLcast (f a, t)
  | MLmagic a -> MLmagic (f a)
  | MLrel _ | MLglob _ | MLexn _ | MLdummy as a -> a

(*s Map over asts, with binding depth as parameter. *)

let ast_map_lift_case f n (c,ids,a) = (c,ids, f (n+(List.length ids)) a)

let ast_map_lift f n = function 
  | MLlam (i,a) -> MLlam (i, f (n+1) a)
  | MLletin (i,a,b) -> MLletin (i, f n a, f (n+1) b)
  | MLcase (a,v) -> MLcase (f n a,Array.map (ast_map_lift_case f n) v)
  | MLfix (i,ids,v) -> 
      let k = Array.length ids in MLfix (i,ids,Array.map (f (k+n)) v)
  | MLapp (a,l) -> MLapp (f n a, List.map (f n) l)
  | MLcons (c,l) -> MLcons (c, List.map (f n) l)
  | MLcast (a,t) -> MLcast (f n a, t)
  | MLmagic a -> MLmagic (f n a)
  | MLrel _ | MLglob _ | MLexn _ | MLdummy as a -> a	

(*s Iter over asts. *) 

let ast_iter_case f (c,ids,a) = f a

let ast_iter f = function
  | MLlam (i,a) -> f a
  | MLletin (i,a,b) -> f a; f b
  | MLcase (a,v) -> f a; Array.iter (ast_iter_case f) v
  | MLfix (i,ids,v) -> Array.iter f v
  | MLapp (a,l) -> f a; List.iter f l
  | MLcons (c,l) -> List.iter f l
  | MLcast (a,t) -> f a
  | MLmagic a -> f a
  | MLrel _ | MLglob _ | MLexn _ | MLdummy as a -> ()

(*S Searching occurrences of a particular term (no lifting done). *)

let rec ast_search t a = 
  if t = a then raise Found else ast_iter (ast_search t) a

let decl_search t l = 
  let one_decl = function 
    | Dterm (_,a,_) -> ast_search t a
    | Dfix (_,c,_) -> Array.iter (ast_search t) c
    | _ -> () 
  in 
  try List.iter one_decl l; false with Found -> true

let rec type_search t = function  
  | Tarr (a,b) -> type_search t a; type_search t b 
  | Tglob (r,l) -> List.iter (type_search t) l
  | u -> if t = u then raise Found

let decl_type_search t l = 
  let one_decl = function 
    | Dind(l,_) -> 
	List.iter (fun (_,_,l) -> 
		    (List.iter (fun (_,l) -> 
				  List.iter (type_search t) l) l)) l
    | Dterm (_,_,u) -> type_search t u
    | Dfix (_,_,v) -> Array.iter (type_search t) v
    | Dtype (_,_,u) -> type_search t u
    | _ -> () 
  in 
  try List.iter one_decl l; false with Found -> true

(*S Operations concerning De Bruijn indices. *)

(*s [ast_occurs k t] returns [true] if [(Rel k)] occurs in [t]. *)

let ast_occurs k t = 
  try 
    ast_iter_rel (fun i -> if i = k then raise Found) t; false 
  with Found -> true

(*s [occurs_itvl k k' t] returns [true] if there is a [(Rel i)] 
   in [t] with [k<=i<=k'] *)

let occurs_itvl k k' t = 
  try 
    ast_iter_rel (fun i -> if (k <= i) && (i <= k') then raise Found) t; false 
  with Found -> true

(*s Number of occurences of [Rel k] and [Rel 1] in [t]. *)

let nb_occur_k k t =
  let cpt = ref 0 in 
  ast_iter_rel (fun i -> if i = k then incr cpt) t;
  !cpt

let nb_occur t = nb_occur_k 1 t

(*s Lifting on terms.
    [ast_lift k t] lifts the binding depth of [t] across [k] bindings. *)

let ast_lift k t = 
  let rec liftrec n = function
    | MLrel i as a -> if i-n < 1 then a else MLrel (i+k)
    | a -> ast_map_lift liftrec n a
  in if k = 0 then t else liftrec 0 t

let ast_pop t = ast_lift (-1) t

(*s [permut_rels k k' c] translates [Rel 1 ... Rel k] to [Rel (k'+1) ... 
  Rel (k'+k)] and [Rel (k+1) ... Rel (k+k')] to [Rel 1 ... Rel k'] *)

let permut_rels k k' = 
  let rec permut n = function
    | MLrel i as a ->
	let i' = i-n in
	if i'<1 || i'>k+k' then a 
	else if i'<=k then MLrel (i+k')
	else MLrel (i-k)
    | a -> ast_map_lift permut n a
  in permut 0  

(*s Substitution. [ml_subst e t] substitutes [e] for [Rel 1] in [t]. 
    Lifting (of one binder) is done at the same time. *)

let ast_subst e =
  let rec subst n = function
    | MLrel i as a ->
	let i' = i-n in 
	if i'=1 then ast_lift n e
	else if i'<1 then a 
	else MLrel (i-1)
    | a -> ast_map_lift subst n a
  in subst 0

(*s Generalized substitution. 
   [gen_subst v m d t] applies to [t] the substitution coded in the 
   [v] array: [(Rel i)] becomes [(Rel v.(i))]. [d] is the correction applies 
   to [Rel] greater than [m]. *)

let gen_subst v d t = 
  let rec subst n = function
    | MLrel i as a -> 
	let i'= i-n in 
	if i' < 1 then a 
	else if i' < Array.length v then 
	  if v.(i') = 0 then MLdummy
	  else MLrel (v.(i')+n) 
	else MLrel (i+d) 
    | a -> ast_map_lift subst n a
  in subst 0 t

(*S Operations concerning lambdas. *)

(*s [collect_lams MLlam(id1,...MLlam(idn,t)...)] returns
    [[idn;...;id1]] and the term [t]. *)

let collect_lams = 
  let rec collect acc = function
    | MLlam(id,t) -> collect (id::acc) t
    | x           -> acc,x
  in collect []

(*s [collect_n_lams] does the same for a precise number of [MLlam]. *)

let collect_n_lams = 
  let rec collect acc n t = 
    if n = 0 then acc,t 
    else match t with 
      | MLlam(id,t) -> collect (id::acc) (n-1) t
      | _ -> assert false
  in collect [] 

(*s [remove_n_lams] just removes some [MLlam]. *)

let rec remove_n_lams n t = 
  if n = 0 then t  
  else match t with 
      | MLlam(_,t) -> remove_n_lams (n-1) t
      | _ -> assert false

(*s [nb_lams] gives the number of head [MLlam]. *)

let rec nb_lams = function 
  | MLlam(_,t) -> succ (nb_lams t)
  | _ -> 0 

(*s [named_lams] does the converse of [collect_lams]. *)

let rec named_lams ids a = match ids with 
  | [] -> a 
  | id :: ids -> named_lams ids (MLlam (id,a))

(*s The same in anonymous version. *)

let rec anonym_lams a = function 
  | 0 -> a 
  | n -> anonym_lams (MLlam (anonymous,a)) (pred n)

(*s Idem for [dummy_name]. *)

let rec dummy_lams a = function 
  | 0 -> a 
  | n -> dummy_lams (MLlam (dummy_name,a)) (pred n)

(*s mixed according to a signature. *)

let rec anonym_or_dummy_lams a = function 
  | [] -> a 
  | true :: s -> MLlam(anonymous, anonym_or_dummy_lams a s)
  | false :: s -> MLlam(dummy_name, anonym_or_dummy_lams a s)

(*S Operations concerning eta. *)

(*s The following function creates [MLrel n;...;MLrel 1] *)

let rec eta_args n = 
  if n = 0 then [] else (MLrel n)::(eta_args (pred n))

(*s Same, but filtered by a signature. *)

let rec eta_args_sign n = function 
  | [] -> [] 
  | true :: s -> (MLrel n) :: (eta_args_sign (n-1) s) 
  | false :: s -> eta_args_sign (n-1) s

(*s This one tests [MLrel (n+k); ... ;MLrel (1+k)] *)

let rec test_eta_args_lift k n = function 
  | [] -> n=0
  | a :: q -> (a = (MLrel (k+n))) && (test_eta_args_lift k (pred n) q)

(*s Computes an eta-reduction. *)

let eta_red e = 
  let ids,t = collect_lams e in 
  let n = List.length ids in
  if n = 0 then e 
  else match t with 
    | MLapp (f,a) -> 
	let m = (List.length a) - n in 
	if m < 0 then e 
	else
	  let a1,a2 = list_chop m a in 
	  let f = if m = 0 then f else MLapp (f,a1) in 
	  if test_eta_args_lift 0 n a2 && not (occurs_itvl 1 n f)
	  then ast_lift (-n) f
	  else e 
    | _ -> e

(*S Auxiliary functions used in simplification of ML cases. *)

(*s [check_and_generalize (r0,l,c)] transforms any [MLcons(r0,l)] in [MLrel 1]
  and raises [Impossible] if any variable in [l] occurs outside such a 
  [MLcons] *)

let check_and_generalize (r0,l,c) = 
  let nargs = List.length l in 
  let rec genrec n = function 
    | MLrel i as c -> 
	let i' = i-n in 
	if i'<1 then c 
	else if i'>nargs then MLrel (i-nargs+1) 
	else raise Impossible
    | MLcons(r,args) when r=r0 && (test_eta_args_lift n nargs args) -> 
	MLrel (n+1) 
    | a -> ast_map_lift genrec n a
  in genrec 0 c  

(*s [check_generalizable_case] checks if all branches can be seen as the 
  same function [f] applied to the term matched. It is a generalized version 
  of the identity case optimization. *)

let check_generalizable_case br = 
  let f = check_and_generalize br.(0) in 
  for i = 1 to Array.length br - 1 do 
    if check_and_generalize br.(i) <> f then raise Impossible 
  done; f

(*s Do all branches correspond to the same thing? *)

let check_constant_case br = 
  if br = [||] then raise Impossible; 
  let (r,l,t) = br.(0) in
  let n = List.length l in 
  if occurs_itvl 1 n t then raise Impossible; 
  let cst = ast_lift (-n) t in 
  for i = 1 to Array.length br - 1 do 
    let (r,l,t) = br.(i) in
    let n = List.length l in
    if (occurs_itvl 1 n t) || (cst <> (ast_lift (-n) t)) 
    then raise Impossible
  done; cst

(*s If all branches are functions, try to permut the case and the functions. *)

let rec merge_ids ids ids' = match ids,ids' with 
  | [],[] -> [] 
  | i::ids, i'::ids' -> 
      (if i = dummy_name then i' else i) :: (merge_ids ids ids')
  | _ -> assert false 

let rec permut_case_fun br acc = 
  let br = Array.copy br in 
  let (_,_,t0) = br.(0) in 
  let nb = ref (nb_lams t0) in 
  Array.iter (fun (_,_,t) -> let n = nb_lams t in if n < !nb then nb:=n) br;
  let ids = ref (fst (collect_n_lams !nb t0)) in  
  Array.iter 
    (fun (_,_,t) -> ids := merge_ids !ids (fst (collect_n_lams !nb t))) br; 
  for i = 0 to Array.length br - 1 do 
    let (r,l,t) = br.(i) in 
    let t = permut_rels !nb (List.length l) (remove_n_lams !nb t) 
    in br.(i) <- (r,l,t)
  done; 
  (!ids,br)
  
(*S Generalized iota-reduction. *)

(* Definition of a generalized iota-redex: it's a [MLcase(e,_)] 
   with [(is_iota_gen e)=true]. Any generalized iota-redex is 
   transformed into beta-redexes. *)

let rec is_iota_gen = function 
  | MLcons _ -> true
  | MLcase(_,br)-> array_for_all (fun (_,_,t)->is_iota_gen t) br
  | _ -> false

let constructor_index = function
  | ConstructRef (_,j) -> pred j
  | _ -> assert false

let iota_gen br = 
  let rec iota k = function 
    | MLcons (r,a) ->
	let (_,ids,c) = br.(constructor_index r) in
	let c = List.fold_right (fun id t -> MLlam (id,t)) ids c in
	let c = ast_lift k c in 
	MLapp (c,a)
    | MLcase(e,br') -> 
	let new_br = 
	  Array.map (fun (n,i,c)->(n,i,iota (k+(List.length i)) c)) br'
	in MLcase(e, new_br)
    | _ -> assert false
  in iota 0 

let is_atomic = function 
  | MLrel _ | MLglob _ | MLexn _ | MLdummy -> true
  | _ -> false

(*S The main simplification function. *)

(* Some beta-iota reductions + simplifications. *)

let rec simpl o = function
  | MLapp (f, []) ->
      simpl o f
  | MLapp (f, a) -> 
      simpl_app o (List.map (simpl o) a) (simpl o f)
  | MLcase (e,br) ->
      let br = Array.map (fun (n,l,t) -> (n,l,simpl o t)) br in 
      simpl_case o br (simpl o e) 
  | MLletin(id,c,e) when 
      (id = dummy_name) || (is_atomic c) || (nb_occur e <= 1) -> 
	simpl o (ast_subst c e)
  | MLfix(i,ids,c) as t when o -> 
      let n = Array.length ids in 
      if occurs_itvl 1 n c.(i) then 
	MLfix (i, ids, Array.map (simpl o) c)
      else simpl o (ast_lift (-n) c.(i)) (* Dummy fixpoint *)
  | a -> ast_map (simpl o) a 

and simpl_app o a = function  
  | MLapp (f',a') -> simpl_app o (a'@a) f'
  | MLlam (id,t) when id = dummy_name -> 
      simpl o (MLapp (ast_pop t, List.tl a))
  | MLlam (id,t) -> (* Beta redex *)
      (match nb_occur t with
	 | 0 -> simpl o (MLapp (ast_pop t, List.tl a))
	 | 1 when o -> 
	     simpl o (MLapp (ast_subst (List.hd a) t, List.tl a))
	 | _ -> 
	     let a' = List.map (ast_lift 1) (List.tl a) in
	     simpl o (MLletin (id, List.hd a, MLapp (t, a'))))
  | MLletin (id,e1,e2) -> 
      (* Application of a letin: we push arguments inside *)
      MLletin (id, e1, simpl o (MLapp (e2, List.map (ast_lift 1) a)))
  | MLcase (e,br) -> (* Application of a case: we push arguments inside *)
      let br' = 
	Array.map 
      	  (fun (n,l,t) -> 
	     let k = List.length l in
	     let a' = List.map (ast_lift k) a in
      	     (n, l, simpl o (MLapp (t,a')))) br 
      in simpl o (MLcase (e,br')) 
  | (MLdummy | MLexn _) as e -> e 
	(* We just discard arguments in those cases. *)
  | f -> MLapp (f,a)

and simpl_case o br e = 
  if (not o) then MLcase (e,br)
  else 
    if (is_iota_gen e) then (* Generalized iota-redex *)
      simpl o (iota_gen br e)
    else 
      try (* Does a term [f] exist such as each branch is [(f e)] ? *)
	let f = check_generalizable_case br in 
	simpl o (MLapp (MLlam (anonymous,f),[e]))
      with Impossible -> 
	try (* Is each branch independant of [e] ? *) 
	  check_constant_case br 
	with Impossible ->
	  (* Swap the case and the lam if possible *)
	  let ids,br = permut_case_fun br [] in 
	  let n = List.length ids in 
	  if n = 0 then MLcase (e, br) 
	  else named_lams ids (MLcase (ast_lift n e, br))

let rec post_simpl = function 
  | MLletin(_,c,e) when (is_atomic (eta_red c)) -> 
      post_simpl (ast_subst (eta_red c) e)
  | a -> ast_map post_simpl a 

(*S Local prop elimination. *) 
(* We try to eliminate as many [prop] as possible inside an [ml_ast]. *)

(*s In a list, it selects only the elements corresponding to a [true] 
   in the boolean list [l]. *)

let rec select_via_bl l args = match l,args with 
  | [],_ -> args
  | true::l,a::args -> a :: (select_via_bl l args)
  | false::l,a::args -> select_via_bl l args
  | _ -> assert false 

(*s [kill_some_lams] removes some head lambdas according to the bool list [bl].
   This list is build on the identifier list model: outermost lambda
   is on the right. [true] means "to keep" and [false] means "to eliminate". 
   [Rels] corresponding to removed lambdas are supposed not to occur, and 
   the other [Rels] are made correct via a [gen_subst].
   Output is not directly a [ml_ast], compose with [named_lams] if needed. *)

let kill_some_lams bl (ids,c) =
  let n = List.length bl in
  let n' = List.fold_left (fun n b -> if b then (n+1) else n) 0 bl in 
  if n = n' then ids,c
  else if n' = 0 then [],ast_lift (-n) c 
  else begin 
    let v = Array.make (n+1) 0 in 
    let rec parse_ids i j = function 
      | [] -> ()
      | true :: q -> 
	  v.(i) <- j; parse_ids (i+1) (j+1) q
      | false :: q -> parse_ids (i+1) j q
    in parse_ids 1 1 bl ; 
    select_via_bl bl ids, gen_subst v (n'-n) c
  end

(*s [kill_dummy_lams] uses the last function to kill the lambdas corresponding 
  to a [dummy_name]. It can raise [Impossible] if there is nothing to do, or 
  if there is no lambda left at all. *)

let kill_dummy_lams c = 
  let ids,c = collect_lams c in 
  let bl = List.map ((<>) dummy_name) ids in 
  if (List.mem true bl) && (List.mem false bl) then 
    let ids',c = kill_some_lams bl (ids,c) in 
    ids, named_lams ids' c
  else raise Impossible
      
(*s [kill_dummy_args ids t0 t] looks for occurences of [t0] in [t] and 
  purge the args of [t0] corresponding to a [dummy_name]. 
  It makes eta-expansion if needed. *) 

let kill_dummy_args ids t0 t =
  let m = List.length ids in 
  let bl = List.rev_map ((<>) dummy_name) ids in
  let rec killrec n = function 
    | MLapp(e, a) when e = ast_lift n t0 -> 
	let k = max 0 (m - (List.length a)) in 
	let a = List.map (killrec n) a in  
	let a = List.map (ast_lift k) a in 
	let a = select_via_bl bl (a @ (eta_args k)) in 
	named_lams (list_firstn k ids) (MLapp (ast_lift k e, a)) 
    | e when e = ast_lift n t0 -> 
	let a = select_via_bl bl (eta_args m) in 
	named_lams ids (MLapp (ast_lift m e, a))
    | e -> ast_map_lift killrec n e 
  in killrec 0 t 

(*s The main function for local [dummy] elimination. *)

let rec kill_dummy = function 
  | MLfix(i,fi,c) -> 
      (try 
	 let ids,c = kill_dummy_fix i fi c in 
	 ast_subst (MLfix (i,fi,c)) (kill_dummy_args ids (MLrel 1) (MLrel 1))
       with Impossible -> MLfix (i,fi,Array.map kill_dummy c))
  | MLapp (MLfix (i,fi,c),a) -> 
      (try 
	 let ids,c = kill_dummy_fix i fi c in 
	 let a = List.map (fun t -> ast_lift 1 (kill_dummy t)) a in 
	 let e = kill_dummy_args ids (MLrel 1) (MLapp (MLrel 1,a)) in
	 ast_subst (MLfix (i,fi,c)) e  
       with Impossible -> 
	 MLapp(MLfix(i,fi,Array.map kill_dummy c),List.map kill_dummy a))
  | MLletin(id, MLfix (i,fi,c),e) -> 
      (try 
	 let ids,c = kill_dummy_fix i fi c in
	 let e = kill_dummy (kill_dummy_args ids (MLrel 1) e) in 
	 MLletin(id, MLfix(i,fi,c),e)
      with Impossible -> 
	MLletin(id, MLfix(i,fi,Array.map kill_dummy c),kill_dummy e))
  | MLletin(id,c,e) -> 
      (try 
	 let ids,c = kill_dummy_lams c in 
	 let e = kill_dummy_args ids (MLrel 1) e in 
	 MLletin (id, kill_dummy c,kill_dummy e) 
       with Impossible -> MLletin(id,kill_dummy c,kill_dummy e))
  | a -> ast_map kill_dummy a

and kill_dummy_fix i fi c = 
  let n = Array.length fi in 
  let ids,ci = kill_dummy_lams c.(i) in 
  let c = Array.copy c in c.(i) <- ci; 
  for j = 0 to (n-1) do 
    c.(j) <- kill_dummy (kill_dummy_args ids (MLrel (n-i)) c.(j)) 
  done;
  ids,c

(*s Putting things together. *)

let normalize a = 
  if (optim()) then post_simpl (kill_dummy (simpl true a)) else simpl false a

(*S Special treatment of fixpoint for pretty-printing purpose. *)

let general_optimize_fix f ids n args m c = 
  let v = Array.make n 0 in 
  for i=0 to (n-1) do v.(i)<-i done;
  let aux i = function 
    | MLrel j when v.(j-1)>=0 -> v.(j-1)<-(-i-1)
    | _ -> raise Impossible
  in list_iter_i aux args; 
  let args_f = List.rev_map (fun i -> MLrel (i+m+1)) (Array.to_list v) in
  let new_f = anonym_lams (MLapp (MLrel (n+m+1),args_f)) m in  
  let new_c = named_lams ids (normalize (MLapp ((ast_subst new_f c),args))) in
  MLfix(0,[|f|],[|new_c|])

let optimize_fix a = 
  if not (optim()) then a 
  else
    let ids,a' = collect_lams a in 
    let n = List.length ids in 
    if n = 0 then a 
    else match a' with 
      | MLfix(_,[|f|],[|c|]) ->
	  let new_f = MLapp (MLrel (n+1),eta_args n) in 
	  let new_c = named_lams ids (normalize (ast_subst new_f c))
	  in MLfix(0,[|f|],[|new_c|])
      | MLapp(a',args) ->
	  let m = List.length args in 
	  (match a' with 
	     | MLfix(_,_,_) when 
		 (test_eta_args_lift 0 n args) && not (occurs_itvl 1 m a') 
		 -> a'
	     | MLfix(_,[|f|],[|c|]) -> 
		 (try general_optimize_fix f ids n args m c
		  with Impossible -> 
		    named_lams ids (MLapp (MLfix (0,[|f|],[|c|]),args))) 
	     | _ -> a)
      | _ -> a

(*S Inlining. *)

(* Utility functions used in the decision of inlining. *)

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

let is_ind = function 
  | IndRef _ -> true 
  | _ -> false 

let is_rec_principle = function 
  | ConstRef c -> 
      let m,d,l = repr_kn c in 
      let s = string_of_label l in 
      if Filename.check_suffix s "_rec" then 
	let i' = id_of_string (Filename.chop_suffix s "_rec") in 
	(try is_ind (locate (make_qualid d i'))
	 with Not_found -> false)
      else if Filename.check_suffix s "_rect" then 
	let i' = id_of_string (Filename.chop_suffix s "_rect") in 
	(try is_ind (locate (make_qualid d i'))
	 with Not_found -> false)
      else false
  | _ -> false 

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
	(* In [(x y)] we say that only x is strict. Cf [sig_rec]. We may *)
	(* gain something if x is replaced by a function like a projection *)
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
      (* The only interesting case: for a variable to be non-strict, *)
      (* it is sufficient that it appears non-strict in at least one branch, *)
      (* so he make an union (in fact a merge). *)
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
  try let _ = non_stricts true [] t in false
  with Toplevel -> true

(*s Inlining decision *)

(* [inline_test] answers the following question: 
   If we could inline [t] (the user said nothing special), 
   should we inline ? 
   
   We don't expand fixpoints, but always inductive constructors
   and small terms.
   Last case of inlining is a term with at least one non-strict 
   variable (i.e. a variable that may not be evaluated). *)

let inline_test t = 
  not (is_fix t) && (is_constr t || (ml_size t < 12 && is_not_strict t))

let manual_inline_list = 
  let dir = dirpath_of_string "Coq.Init.Wf" in 
  List.map (fun s -> (encode_kn dir (id_of_string s)))
    [ "well_founded_induction"; 
      "well_founded_induction_type" ]

let manual_inline = function 
  | ConstRef c -> List.mem c manual_inline_list
  | _ -> false 

(* If the user doesn't say he wants to keep [t], we inline in two cases:
   \begin{itemize}
   \item the user explicitly requests it 
   \item [expansion_test] answers that the inlining is a good idea, and 
   we are free to act (AutoInline is set)
   \end{itemize} *)

let inline r t = 
  not (to_keep r) (* The user DOES want to keep it *)
  && (to_inline r (* The user DOES want to inline it *) 
     || (auto_inline () && lang () <> Haskell 
	 && (is_rec_principle r || manual_inline r || inline_test t)))

(*S Optimization. *)

let subst_glob_ast r m = 
  let rec substrec = function
    | MLglob r' as t -> if r = r' then m else t
    | t -> ast_map substrec t
  in substrec

let subst_glob_decl r m = function
  | Dterm(r',t',typ) -> Dterm(r', subst_glob_ast r m t', typ)
  | d -> d

let inline_glob r t l = 
  if not (inline r t) then true, l 
  else false, List.map (subst_glob_decl r t) l

let print_ml_decl prm (r,_) = 
  not (to_inline r) || List.mem r prm.to_appear

let add_ml_decls prm decls = 
  let l1 = ml_type_extractions () in 
  let l1 = List.filter (print_ml_decl prm) l1 in 
  let l1 = List.map (fun (r,s)-> DcustomType (r,s)) l1 in 
  let l2 = ml_term_extractions () in 
  let l2 = List.filter (print_ml_decl prm) l2 in 
  let l2 = List.map (fun (r,s)-> DcustomTerm (r,s)) l2 in
  l1 @ l2 @ decls

let rec expunge_fix_decls prm v c map b = function 
  | [] -> b, [], map  
  | Dterm (r, t, typ) :: l when array_exists ((=) r) v -> 
      let t = normalize t in 
      let t' = optimize_fix t in 
      (match t' with 
	 | MLfix(_,_,c') when c=c' -> 
	     let b',l = inline_glob r t l in 
	     let b = b || b' || List.mem r prm.to_appear in 
	     let map = Refmap.add r typ map in 
	     expunge_fix_decls prm v c map b l 
	 | _ -> raise Impossible)
  | d::l -> let b,l,map = expunge_fix_decls prm v c map b l in b, d::l, map  

let rec optimize prm = function
  | [] -> 
      []
  | (Dtype (r,_,Tdummy) | Dterm(r,MLdummy,_)) as d :: l ->
      if List.mem r prm.to_appear then d :: (optimize prm l) 
      else optimize prm l
  | Dterm (r,t,typ) :: l ->
      let t = normalize t in
      let b,l = inline_glob r t l in 
      let b = b || prm.modular || List.mem r prm.to_appear in 
      let t' = optimize_fix t in
      (try optimize_Dfix prm (r,t',typ) b l 
       with Impossible ->
	 if b then Dterm (r,t',typ) :: (optimize prm l)
	 else optimize prm l)
  | d :: l -> d :: (optimize prm l)

and optimize_Dfix prm (r,t,typ) b l = 
  match t with 
    | MLfix (_, f, c) -> 
	if Array.length f = 1 then 
	  if b then Dfix ([|r|], c,[|typ|]) :: (optimize prm l)
	  else optimize prm l
	else 
	  let v = try 
	    let d = dirpath (sp_of_global None r) in 
	    Array.map (fun id -> locate (make_qualid d id)) f 
	  with Not_found -> raise Impossible 
	  in 
	  let map = Refmap.add r typ (Refmap.empty) in 
	  let b,l,map = expunge_fix_decls prm v c map b l in 
	  if b then 
	    let typs = 
	      Array.map 
		(fun r -> try Refmap.find r map
		 with Not_found -> Tunknown) v 
	    in 
	    Dfix (v, c, typs) :: (optimize prm l)
	  else optimize prm l 
    | _ -> raise Impossible





