;; -*- lexical-binding: t; -*-

(TeX-add-style-hook
 "references"
 (lambda ()
   (LaTeX-add-bibitems
    "martin2006"
    "virieux1984"
    "folk2011"
    "dagum1998"
    "Forum1994MPIAM"
    "versteeg1994"
    "segopendata"
    "cerjan1985"
    "courant_1928"
    "ricker1951"
    "aki2002"))
 '(or :bibtex :latex))

