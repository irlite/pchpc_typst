;; -*- lexical-binding: t; -*-

(TeX-add-style-hook
 "references"
 (lambda ()
   (LaTeX-add-bibitems
    "martin2006"
    "virieux1984"
    "folk2011"
    "dagum1998"
    "Forum1994MPIAM"))
 '(or :bibtex :latex))

