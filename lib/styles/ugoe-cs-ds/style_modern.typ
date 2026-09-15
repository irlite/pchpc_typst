// Copyright (c) 2026 Lorenz Glißmann
// Creative Commons Zero v1.0 Universal

#let general_style(body) = {
  // set page style
  set page(margin: (left: 25mm, right: 25mm, top: 25mm, bottom: 25mm))
  // set justify (Blocksatz) and make line-spacing consistent with LaTeX
  set par(justify: true) //, leading: .8em
  // set font
  // set text(font: "FPL Neu", size: 10pt)
  set text(font: "New Computer Modern") // or TeX Gyre Schola

  // style links/references with colorful boxes around them
  show link: highlight.with(fill: none, stroke: red)
  show ref: highlight.with(fill: none, stroke: green)
  show cite: highlight.with(fill: none, stroke: green)

  // style outline: chapters as bold and without dots
  set outline.entry(fill: repeat(gap: .3em)[.])
  show outline.entry.where(level: 1): strong
  show outline.entry.where(level: 1): set outline.entry(fill: none)
  show outline: set block(spacing: 0.8em)

  body
}

#let heading_style_prelude(body) = {
  // style headings in prelude (e.g. for abstract and outline)
  set heading(outlined: false, numbering: none, bookmarked: true)
  show heading.where(level: 1): set text(size: 20pt)
  show heading.where(level: 1): set block(above: 2em, below: 1em)

  body
}

#let page_style_main_content(
  title: none,
  author: none,
  translations: none,
  body,
) = {
  // style pages in the main content to have headers and footers
  set page(
    header: context {
      align(right)[#title.replace("\n", " ")]
      v(.5em, weak: true)
      line(stroke: .7pt, length: 100%)
    },
    footer: context {
      line(stroke: 0.7pt, length: 100%)
      v(.5em, weak: true)

      grid(
        columns: (1fr, 2fr, 1fr),
        align: (left, center, right),
        // [#context query(selector(heading).before(here())).filter(x => x.level == 1).at(-1)],
        [#{
          let selector = query(selector(heading).before(here())).at(
            -1,
            default: none,
          )
          if selector == none {
            // return none
            panic(
              "No heading found before the current page. This should never happen, as the footer is only applied after the introductory pages, which don't have a footer.",
            )
          }
          let level = counter(heading).at(selector.location()).first()
          [#translations.chapter #level]
        }],
        author,
        // box(width: 1pt * float.inf, author), // this is a hack to ensure the author is always on one line, even if it's very long. it can cause overlapping with the cell to the left or right.
        counter(page).display("1"),
      )
    },
  )

  body
}

#let heading_style_main_content(translations: none, body) = {
  // style headings in the document to be consistent with LaTeX
  set heading(numbering: "1.1")

  // style level 1 headings (chapters)
  show heading.where(level: 1): set heading(supplement: translations.chapter)
  show heading.where(level: 1): set text(size: 20pt)
  show heading.where(level: 1): it => pagebreak(weak: true) + block(below: 1em, v(1cm) + it)

  // style level 2 headings (sections)
  show heading.where(level: 2): set heading(supplement: translations.section)
  show heading.where(level: 2): set text(size: 16pt)
  show heading.where(level: 2): set block(above: 1.5em, below: 1em)

  // style level 3 headings (subsections)
  show heading.where(level: 3): set heading(supplement: translations.subsection)
  show heading.where(level: 3): set text(size: 13pt)
  show heading.where(level: 3): set block(above: 1.5em, below: 1em)

  // style level 4 headings (subsubsections)
  show heading.where(level: 4): set heading(
    supplement: translations.subsubsection,
  )
  show heading.where(level: 4): set block(above: 1.5em, below: 1em)

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
  show heading.where(level: 1): set text(size: 20pt)
  show heading.where(level: 1): set block(above: 2em, below: 1em)

  // style level 2 headings (appendix sections)
  show heading.where(level: 2): set text(size: 16pt)
  show heading.where(level: 2): set block(above: 1.5em, below: 1em)

  // style level 3 headings (appendix subsections)
  show heading.where(level: 3): set text(size: 13pt)
  show heading.where(level: 3): set block(above: 1.5em, below: 1em)

  // style level 4 headings (appendix subsubsections)
  show heading.where(level: 4): set block(above: 1.5em, below: 1em)

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

    show: page_style_main_content.with(
      title: config.title,
      author: config.author,
      translations: config.translations,
    )
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
