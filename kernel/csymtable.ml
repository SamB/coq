open Names
open Term
open Vm
open Cemitcodes
open Cbytecodes
open Declarations
open Environ
open Cbytegen
open Cemitcodes

external tcode_of_code : emitcodes -> int -> tcode = "coq_tcode_of_code"
external free_tcode : tcode -> unit = "coq_static_free"
external eval_tcode : tcode -> values array -> values = "coq_eval_tcode"
 
(*******************)
(* Linkage du code *)
(*******************)

(* Table des globaux *)

(* [global_data] contient les valeurs des constantes globales 
   (axiomes,definitions), les annotations des switch et les structured 
   constant *)
external global_data : unit -> values array = "get_coq_global_data"

(* [realloc_global_data n] augmente de n la taille de [global_data] *)
external realloc_global_data : int -> unit = "realloc_coq_global_data"

let check_global_data n =
  if n >= Array.length (global_data()) then realloc_global_data n
  
let num_global = ref 0

let set_global v = 
  let n = !num_global in
  check_global_data n;
  (global_data()).(n) <- v;
  incr num_global;
  n

(* [global_transp],[global_boxed] contiennent les valeurs des 
   definitions gelees. Les deux versions sont maintenues en //. 
   [global_transp] contient la version transparente.
   [global_boxed] contient la version gelees. *)

external global_boxed : unit -> bool array = "get_coq_global_boxed"

(* [realloc_global_data n] augmente de n la taille de [global_data] *)
external realloc_global_boxed : int -> unit = "realloc_coq_global_boxed"

let check_global_boxed n =
  if n >= Array.length (global_boxed()) then realloc_global_boxed n
  
let num_boxed = ref 0

let boxed_tbl = Hashtbl.create 53

let cst_opaque = ref Cpred.full

let is_opaque kn = Cpred.mem kn !cst_opaque

let set_global_boxed kn v = 
  let n = !num_boxed in
  check_global_boxed n;
  (global_boxed()).(n) <- (is_opaque kn);
  Hashtbl.add boxed_tbl kn n ;
  incr num_boxed;
  set_global (val_of_constant_def n kn v)

(* table pour les structured_constant et les annotations des switchs *)

let str_cst_tbl = Hashtbl.create 31
    (* (structured_constant * int) Hashtbl.t*)

let annot_tbl = Hashtbl.create 31
    (* (annot_switch * int) Hashtbl.t  *)

(************************)
(* traduction des patch *)

(* slot_for_*, calcul la valeur de l'objet, la place
   dans la table global, rend sa position dans la table *)
 
let slot_for_str_cst key =
  try Hashtbl.find str_cst_tbl key 
  with Not_found -> 
    let n = set_global (val_of_str_const key) in
    Hashtbl.add str_cst_tbl key n;
    n

let slot_for_annot key =
  try Hashtbl.find annot_tbl key 
  with Not_found -> 
    let n =  set_global (Obj.magic key) in
    Hashtbl.add annot_tbl key n;
    n

let rec slot_for_getglobal env kn =
  let ck = lookup_constant_key kn env in
  try constant_key_pos ck
  with NotEvaluated ->
    match force (constant_key_body ck).const_body_code with
    | BCdefined(boxed,(code,pl,fv)) -> 
	let v = eval_to_patch env (code,pl,fv) in
   	let pos = 
	  if boxed then set_global_boxed kn v 
	  else set_global v in
	set_pos_constant ck pos;
	pos
    | BCallias kn' ->
	let pos = slot_for_getglobal env kn' in
	set_pos_constant ck pos;
	pos
    | BCconstant -> 
	let v = val_of_constant kn in
	let pos = set_global v in
	set_pos_constant ck pos;
	pos  

and slot_for_fv env fv=
  match fv with
  | FVnamed id -> 
      let nv = lookup_namedval id env in
      begin
	match kind_of_named nv with
	| VKvalue v -> v
	| VKaxiom id ->
	    let v = val_of_named id in
	    set_namedval nv v; v
	| VKdef(c,e) ->
	    let v = val_of_constr e c in
	    set_namedval nv v; v
      end
  | FVrel i ->
      let rv = lookup_relval i env in
      begin
	match kind_of_rel rv with
	| VKvalue v -> v
	| VKaxiom k ->
	    let v = val_of_rel k in
	    set_relval rv v; v
	| VKdef(c,e) ->
	    let v = val_of_constr e c in
	    let k = nb_rel e in
	    set_relval rv v; v
      end
 
and eval_to_patch env (buff,pl,fv) = 
  let patch = function
    | Reloc_annot a, pos -> patch_int buff pos (slot_for_annot a)
    | Reloc_const sc, pos -> patch_int buff pos (slot_for_str_cst sc)
    | Reloc_getglobal kn, pos -> 
	patch_int buff pos (slot_for_getglobal env kn)
  in 
  List.iter patch pl;
  let nfv = Array.length fv in
  let vm_env = Array.map (slot_for_fv env) fv in 
  let tc = tcode_of_code buff (length buff) in
  eval_tcode tc vm_env

and val_of_constr env c = 
  let (_,fun_code,_ as ccfv) = compile env c in
  eval_to_patch env (to_memory ccfv)
 
let set_transparent_const kn =
  cst_opaque := Cpred.remove kn !cst_opaque;
  List.iter (fun n -> (global_boxed()).(n) <- false) 
    (Hashtbl.find_all boxed_tbl kn)

let set_opaque_const kn =
  cst_opaque := Cpred.add kn !cst_opaque;
  List.iter (fun n -> (global_boxed()).(n) <- true) 
    (Hashtbl.find_all boxed_tbl kn)


