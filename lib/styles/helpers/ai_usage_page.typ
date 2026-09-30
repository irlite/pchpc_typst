// Copyright (c) 2026 Lorenz Glißmann
// Creative Commons Zero v1.0 Universal

// This is a template for a declaration on the use of AI tools.
// Currently the points present in this template were made up by me and are not
// official!
//
// Depending on which style you want to use for the symbols, you might want to
// adjust the font used. (You can also set the font inside the ai_usage()
// function, which might look a bit cleaner for this page without affecting the
// rest of the document.

#let ai_usage_page(ai_usage) = [
  #assert(
    type(ai_usage) == array,
    message: "The ai_usage argument must be an array of (string, bool) pairs.",
  )

  // #set text(font: "Liberation Sans")
  // #set text(font: "New Computer Modern Sans")
  // #set text(font: "Liberation Serif")
  // #set text(font: "Libertinus Serif")
  // #set text(font: "New Computer Modern")
#let checkbox(checked) = box(
  width: 0.9em,
  height: 0.9em,
  inset: 0pt,
  stroke: 0.7pt + black,
)[
  #align(center + horizon)[
    #if checked {
      text(size: 7pt, weight: "bold")[×]
    }
  ]
]
#let check_point(content, checked) = block(
    above: 1.2em,
  below: 0.35em,
)[
  #grid(
    columns: (1.4em, 1fr),
    column-gutter: 0.7em,
    align: (center, left),
    checkbox(checked),
    content,
  )
]

  #text(size: 14pt, weight: "bold")[
    Declaration on the use of AI tools in the context of examinations
  ]

  In this work we have used AI tools as follows:

  #for (body, checked) in ai_usage {
    check_point(body, checked)
  }

  #v(2em)
  We hereby declare that we have stated all uses completely and truthfully.

  Missing or incorrect information will be considered as an attempt to cheat.
]

