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

  #let check_point(content, checked) = [
    #let symbol = if checked { sym.ballot.cross } else { sym.ballot }
    // #let symbol = if checked { sym.crossmark } else { sym.ballot }
    // #let symbol = if checked { sym.ballot.check.heavy } else { sym.ballot }

    #grid(
      columns: 2,
      inset: (x: 1em, y: 0em),
      symbol, content,
    )
  ]

  #text(size: 14pt, weight: "bold")[
    Declaration on the use of AI tools in the context of examinations
  ]

  In this work I have used AI tools as follows:

  #for (body, checked) in ai_usage {
    check_point(body, checked)
  }

  #v(2em)
  I hereby declare that I have stated all uses completely and truthfully.

  Missing or incorrect information will be considered as an attempt to cheat.
]

