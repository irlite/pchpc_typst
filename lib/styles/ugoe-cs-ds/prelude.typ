// Copyright (c) 2026 Lorenz Glißmann
// Creative Commons Zero v1.0 Universal

#let page_wrapper(body) = {
  pagebreak(weak: true)
  body
  pagebreak(weak: true)
}

#let titlepage(config: none) = page_wrapper[
  // Title page
  #set align(center)
  #set text(size: 14pt)

  #let logo = image(
    "../../logos/unigoe_logo_svgs/GOE_Logo_Quer_IPC_Farbe.svg",
    width: 8cm,
  )
  #align(left, logo)
#let logo2 = image(
  "../../logos/hps-logo.pdf",
  width: 2.5cm,
)
    #align(right, move(dy: -2.1cm, logo2))
  #v(1fr)
  #par[
    #text(size: 20pt, weight: "bold", config.translations.degree_text)\
    #config.translations.submitted_text
    "#config.course_of_study"
  ]
  #v(1fr)
  #show title: set text(size: 20pt)
  #title(config.title)
  #v(1fr)
  #par(config.author)
  #v(1fr)
  #par(config.translations.institution)
  #v(.5fr)
  #par(config.translations.university)
  #v(0.2cm)
  #par(config.date.display(config.date_format))
]

#let contactpage(config: none) = page_wrapper[
  #v(1fr)
  #par[
    Georg-August-Universität Göttingen\
    #config.translations.institution
  ]
  #par[
    Goldschmidtstraße 7\
    37077 Göttingen\
    Germany
  ]
  #table(
    columns: 2,
    stroke: none,
    [☎], [+49 (551) 39-172000],
    [📠], [+49 (551) 39-14403],
    [📧], link("mailto:office@informatik.uni-goettingen.de"),
    [🌏],
    link(
      "https://www.informatik.uni-goettingen.de",
    )[www.informatik.uni-goettingen.de],
  )
  #v(.5cm)
  #table(
    columns: 2,
    stroke: none,
    [#config.translations.firstsupervisor_text:], config.firstsupervisor,
    [#config.translations.secondsupervisor_text:], config.secondsupervisor,
  )
]

#let declarationpage(
  config: none,
  declaration: none,
  ai_usage: none,
) = page_wrapper[
  #if ai_usage != none {
    import "../helpers/ai_usage_page.typ": ai_usage_page
    ai_usage_page(ai_usage)
  }

  #v(1fr)

  #line(stroke: 0.4pt, length: 100%)
  #declaration

  #if config.style != "legacy" [
    #v(0.2cm)
    Göttingen, #config.date.display(config.date_format)
  ]
]

#let aiusagepage(ai_usage: none) = page_wrapper[
  #assert(type(ai_usage) == array, message: "ai_usage must be an array.")
  #assert(ai_usage.len() > 0, message: "There must be at least one AI usage entry.")

  #text(size: 14pt, weight: "bold")[
    Declaration on the use of ChatGPT and comparable tools
    in the context of examinations
  ]

  #v(1em)

  In this work I have used ChatGPT or another AI as follows:

  #v(0.8em)

  #for entry in ai_usage {
    let body = entry.at(0)
    let checked = entry.at(1)
    let symbol = if checked { sym.ballot.cross } else { sym.ballot }

    block(above: 0.35em, below: 0.35em)[
      #grid(
        columns: (1.5em, 1fr),
        column-gutter: 0.4em,
        align: (center, left),
        symbol,
        body,
      )
    ]
  }

  #v(1em)

  We hereby declare that I have stated all uses completely.\
  Missing or incorrect information will be considered as an attempt to cheat.
]

#let abstractpage(config: none, abstract: none) = page_wrapper[
  #align(center)[
    = Abstract
  ]
  #abstract
]

#let outlinepage(config: none) = page_wrapper[
  #outline(depth: 3, title: config.translations.outline_title)
]

#let prelude(
  config: none,
  declaration: none,
  abstract: none,
  ai_usage: none,

) = {
  // disable page numbering for the first few pages
  set page(numbering: none)

  // 1) Title page
  titlepage(config: config)

  // 2) Contact info page
  contactpage(config: config)

  // Enable page numbering from here on
  set page(numbering: "I")

  // 3) Declaration
  if declaration != none {
  declarationpage(
        config: config,
        declaration: declaration,
        ai_usage: ai_usage,
    )
    }


  // 4) Abstract
  if abstract != none {
    abstractpage(config: config, abstract: abstract)
  }

  // 5) Outline
  outlinepage(config: config)
}

