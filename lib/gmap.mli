
(* $Id$ *)

(* Maps using the generic comparison function of ocaml. Same interface as
   the module [Map] from the ocaml standard library. *)

type ('a,'b) t

val empty : ('a,'b) t
val add : 'a -> 'b -> ('a,'b) t -> ('a,'b) t
val find : 'a -> ('a,'b) t -> 'b
val remove : 'a -> ('a,'b) t -> ('a,'b) t
val mem :  'a -> ('a,'b) t -> bool
val iter : ('a -> 'b -> unit) -> ('a,'b) t -> unit
val map : ('b -> 'c) -> ('a,'b) t -> ('a,'c) t
val fold : ('a -> 'b -> 'c -> 'c) -> ('a,'b) t -> 'c -> 'c

(* Additions with respect to ocaml standard library. *)

val dom : ('a,'b) t -> 'a list
val rng : ('a,'b) t -> 'b list
val to_list : ('a,'b) t -> ('a * 'b) list
