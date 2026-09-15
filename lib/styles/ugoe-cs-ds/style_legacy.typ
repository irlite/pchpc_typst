// Copyright (c) 2026 Lorenz Glißmann
// Creative Commons Zero v1.0 Universal

#let general_style(body) = {
  // make pagebreaks fill up with empty pages so content always starts on a left page (of a book) set pagebreak(to: "odd")
  set pagebreak(to: "odd")
  // set page style
  set page(margin: (left: 25mm, right: 25mm, top: 40mm, bottom: 50mm))
  // set justify (Blocksatz) and make line-spacing consistent with LaTeX
  set par(justify: true, leading: .8em)
  // set font
  set text(font: "FPL Neu", size: 10pt)

  // style links/references with colorful boxes around them
  show link: highlight.with(fill: none, stroke: red)
  show ref: highlight.with(fill: none, stroke: green)
  show cite: highlight.with(fill: none, stroke: green)

  // style outline: chapters as bold and without dots
  set outline.entry(fill: repeat(gap: .3em)[.])
  show outline.entry.where(level: 1): strong
  show outline.entry.where(level: 1): set outline.entry(fill: none)
  show outline: set block(spacing: 1em)

  body
}

#let heading_style_prelude(body) = {
  // style headings in prelude (e.g. for abstract and outline)
  set heading(outlined: false, numbering: none, bookmarked: true)
  show heading.where(level: 1): set text(size: 24.88pt)
  show heading.where(level: 1): set block(above: 50pt, below: 40pt)

  body
}

#let page_style_main_content(body) = {
  set page(
    header: context {},
    // style page numbers to alternate between left and right
    footer: context {
      let alignment = if calc.even(here().page()) { right } else { left }
      align(alignment, counter(page).display("1"))
    },
  )

  body
}

#let heading_style_main_content(translations: none, body) = {
  // style headings in the document to be consistent with LaTeX
  set heading(numbering: "1.1")

  // style level 1 headings (chapters)
  show heading.where(level: 1): set heading(supplement: translations.chapter)
  show heading.where(level: 1): set text(size: 24.88pt)
  show heading.where(level: 1): set block(above: 50pt, below: 40pt)
  show heading.where(level: 1): it => pagebreak(weak: true) + block[
    #text(size: 20.74pt)[Chapter #counter(heading).display()]
    #v(1em)
    #it.body
  ]

  // style level 2 headings (sections)
  show heading.where(level: 2): set heading(supplement: translations.section)
  show heading.where(level: 2): set text(size: 14.4pt)
  show heading.where(level: 2): set block(above: 28.5pt, below: 19pt)

  // style level 3 headings (subsections)
  show heading.where(level: 3): set heading(supplement: translations.subsection)
  show heading.where(level: 3): set text(size: 12pt)
  show heading.where(level: 3): set block(above: 22pt, below: 10.5pt)

  // style level 4 headings (subsubsections)
  show heading.where(level: 4): set heading(
    supplement: translations.subsubsection,
  )
  show heading.where(level: 4): set block(above: 22.1pt, below: 10.2pt)

  body
}

#let page_style_appendix(body) = {
  set page(footer: context align(center)[
    #counter(heading).display("A") - #counter(page).display("1")
  ])

  body
}

#let heading_style_appendix(body) = {
  // style headings in the appendix
  set heading(numbering: "A.1")
  show bibliography: set heading(numbering: "A.1")

  // style level 1 headings (appendix chapters)
  show heading.where(level: 1): set text(size: 24.88pt)
  show heading.where(level: 1): set block(above: 50pt, below: 40pt)

  // style level 2 headings (appendix sections)
  show heading.where(level: 2): set text(size: 14.4pt)
  show heading.where(level: 2): set block(above: 28.5pt, below: 19pt)

  // style level 3 headings (appendix subsections)
  show heading.where(level: 3): set text(size: 12pt)
  show heading.where(level: 3): set block(above: 22pt, below: 10.5pt)

  // style level 4 headings (appendix subsubsections)
  show heading.where(level: 4): set block(above: 22.1pt, below: 10.2pt)

  body
}

#let thesis(
  config,
  chapters,
  abstract: none,
  declaration: none,
  bib: none,
  appendix: none,
  ..other_args,
) = {
  // apply general style to the whole document
  show: general_style

  // 1. Prelude
  {
    show: heading_style_prelude

    // import the first few pages (title page, contact info, declaration, abstract, outline)
    import "./prelude.typ": prelude
    prelude(config: config, abstract: abstract, declaration: declaration)
  }

  // 2. Main content
  {
    counter(page).update(1)

    show: page_style_main_content
    show: heading_style_main_content.with(translations: config.translations)

    // include the actual contents
    assert(type(chapters) == array, message: "Chapters must be an array.")
    for ch in chapters {
      ch
    }
  }

  // 3. Bibliography and appendix
  {
    show: page_style_appendix
    show: heading_style_appendix

    counter(heading).update(0)

    // Bibliography
    if bib != none {
      pagebreak(weak: true)
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
}
