(* L'algo d'inf�rence du pr�dicat doit g�rer le K-r�dex dans le type de b *)
(* Probl�me rapport� par Solange Coupet *)

Section A.

Variables Alpha:Set; Beta:Set.

Definition nodep_prod_of_dep: (sigS Alpha [a:Alpha]Beta)-> Alpha*Beta:=
[c] Cases c of (existS a b)=>(a,b) end.

End A.
