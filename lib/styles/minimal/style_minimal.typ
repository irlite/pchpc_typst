// Copyright (c) 2026 Lorenz Glißmann
// Creative Commons Zero v1.0 Universal

#import "@preview/hydra:0.6.2": hydra


#let page_wrapper(body) = {
  pagebreak(weak: true)
  body
  pagebreak(weak: true)
}

#let header = context {
  set text(size: 10pt)
  box(hydra(1))
  h(.5em)
  h(1fr)
  box(hydra(2))
}

#let config_minimal_style_defaults = (
  bib_two_columns: false,
  highlight_refs: false,
  highlight_cites: false,
)

#let thesis(
  config,
  chapters,
  abstract: none,
  // declaration: none,
  bib: none,
  appendix: none,
  acknowledgements: none,
  ai_usage: none,
  config_minimal_style: (:),
  ..other_args,
) = {
  assert(type(config) == dictionary, message: "config must be a dictionary.")
  assert(type(chapters) == array, message: "Chapters must be an array.")
  assert(chapters.len() > 0, message: "There must be at least one chapter.")
  assert(
    type(config_minimal_style) == dictionary,
    message: "config_minimal_style must be a dictionary.",
  )

  config_minimal_style = config_minimal_style_defaults + config_minimal_style

  /// 0) styling
  // general style for the whole document
  set page(margin: 3cm)

  set pagebreak(weak: true)

  set par(justify: true)
  set text(size: 11pt) // TODO: do we want 10pt?
  set text(font: "New Computer Modern")
  // show link: set text(fill: blue)
  // show link: underline.with(evade: true)

  // headings
  set heading(numbering: "1.1")
  show heading.where(level: 1): it => pagebreak(weak: true) + block(v(1cm) + it)
  show heading.where(level: 1): set block(below: 1cm)
  show heading.where(level: 4): it => strong(it.body + [.])
  show heading.where(level: 4): set heading(outlined: false)

  // outline
  set outline.entry(fill: repeat(gap: .3em)[.])
  show outline.entry.where(level: 1): strong
  show outline.entry.where(level: 1): set outline.entry(fill: none)
  show outline: set block(spacing: 0.8em)

  // chapter elements
  show figure: set block(spacing: 2em)
  show figure.caption: set text(size: 10pt)
  show figure.caption: set align(left)

  show ref: it => if config_minimal_style.highlight_refs {
    highlight(fill: none, stroke: green, it)
  } else { it }
  show cite: it => if config_minimal_style.highlight_cites {
    highlight(fill: none, stroke: red, it)
  } else { it }

  /// 1) title page, abstract, ai usage declaration, outline

  // title page
  page_wrapper[
    #set align(center)

    #v(1fr)
    #title(config.title)
    #v(1fr)
    #config.author
    #v(2fr)
  ]

  set page(numbering: "I")

  // abstract
  page_wrapper[
    #set page(margin: 4cm)
    #v(1fr)
    #align(
      center,
      smallcaps[ABSTRACT],
      // smallcaps[Abstract],
    )
    #abstract
    #v(5fr)
  ]

  // ai usage declaration
  if ai_usage != none {
    assert(type(ai_usage) == array, message: "ai_usage must be an array.")
    assert(ai_usage.len() > 0, message: "There must be at least one ai usage.")
    import "../helpers/ai_usage_page.typ": ai_usage_page
    page_wrapper(ai_usage_page(ai_usage))
  }

  // outline
  page_wrapper(outline())

  /// 2) Main content
  set page(numbering: "1")
  set page(header: header)
  counter(page).update(1)

  // include the actual contents
  for ch in chapters {
    ch
  }

  // acknowledgements
  if acknowledgements != none {
    page_wrapper[
      #set page(header: none)
      #heading(numbering: none, outlined: false)[Acknowledgements]
      // #text(size: 16pt)[Acknowledgements]
      #acknowledgements
    ]
  }

  /// 3) Bibliography and appendix
  set heading(numbering: "A.1")
  show bibliography: set heading(numbering: "A.1")
  counter(heading).update(0)

  // Bibliography
  if bib != none {
    pagebreak(weak: true)
    set text(size: 10pt)
    set page(columns: 2, margin: (x: 2cm)) if config_minimal_style.bib_two_columns
    bib
  }
  if appendix != none {
    assert(
      type(appendix) == array,
      message: "Appendix must be none or an array.",
    )
    for ap in appendix {
      pagebreak(weak: true)
      ap
    }
  }
}
