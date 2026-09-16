// Helpers shared by the report chapters.
// Nothing here depends on an external Typst package, so the document builds
// offline with the same `make build` the template ships with.

// ---------------------------------------------------------------------------
// Placeholders
// ---------------------------------------------------------------------------

// Everything wrapped in #tbd[...] still needs a real value or a decision.
// Find them all with:  grep -rn "tbd\[" content/
// Once none are left, delete this definition; the build will then fail if one
// was missed.
#let tbd(body) = text(fill: red, weight: "bold")[\[TO FILL: #body\]]

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

// A table with top, mid and bottom rules only, in the style of LaTeX booktabs.
// `header` is an array of cells, `body` the remaining cells row by row.
#let ruled-table(columns: auto, align: auto, header: (), ..body) = table(
  columns: columns,
  align: align,
  stroke: none,
  inset: (x: 7pt, y: 4.5pt),
  table.hline(stroke: 0.9pt),
  table.header(..header.map(c => strong(c))),
  table.hline(stroke: 0.5pt),
  ..body,
  table.hline(stroke: 0.9pt),
)

// ---------------------------------------------------------------------------
// Figure: stencil dependencies
// ---------------------------------------------------------------------------

#let _dot(fill: gray.lighten(50%), r: 2.4pt) = circle(radius: r, fill: fill, stroke: none)

// One 3x3 panel. `corner` is "br" (right and below) or "tl" (left and above).
#let _stencil-panel(corner: "br", accent: blue, label: [], desc: []) = {
  let g = 22pt // grid pitch
  let pad = 14pt
  let side = 2 * g + 2 * pad

  let cx = pad + g // centre dot position
  let cy = pad + g

  // neighbour offsets
  let (nx, ny) = if corner == "br" { (g, 0pt) } else { (-g, 0pt) }
  let (mx, my) = if corner == "br" { (0pt, g) } else { (0pt, -g) }

  align(center)[
    #block(width: side, height: side)[
      // faint background grid
      #for i in range(3) {
        for j in range(3) {
          place(
            dx: pad + j * g - 2.4pt,
            dy: pad + i * g - 2.4pt,
            _dot(),
          )
        }
      }
      // arrows to the two neighbours the kernel reads
      #place(
        dx: cx,
        dy: cy,
        line(end: (nx, ny), stroke: (paint: accent, thickness: 1.1pt)),
      )
      #place(
        dx: cx,
        dy: cy,
        line(end: (mx, my), stroke: (paint: accent, thickness: 1.1pt)),
      )
      // the two neighbours
      #place(dx: cx + nx - 3.2pt, dy: cy + ny - 3.2pt, _dot(fill: accent, r: 3.2pt))
      #place(dx: cx + mx - 3.2pt, dy: cy + my - 3.2pt, _dot(fill: accent, r: 3.2pt))
      // the point being written
      #place(dx: cx - 3.4pt, dy: cy - 3.4pt, _dot(fill: black, r: 3.4pt))
    ]
    #v(2pt)
    #strong(label)
    #v(-4pt)
    #block(width: 5.2cm)[#text(size: 9pt, desc)]
  ]
}

#let stencil-figure() = grid(
  columns: (1fr, 1fr),
  gutter: 10pt,
  _stencil-panel(
    corner: "br",
    accent: rgb("#1f5fa9"),
    label: [stress update],
    desc: [reads $v_x, v_z$ at the cell, to the right and below],
  ),
  _stencil-panel(
    corner: "tl",
    accent: rgb("#b03030"),
    label: [velocity update],
    desc: [reads $sigma_(x x), sigma_(z z), sigma_(x z)$ at the cell, to the left and above],
  ),
)

// ---------------------------------------------------------------------------
// Figure: domain decomposition
// ---------------------------------------------------------------------------

#let _tile(name, highlight: false) = rect(
  width: 100%,
  height: 1.5cm,
  fill: rgb("#dfe6f7"),
  stroke: if highlight { (paint: rgb("#2e7d32"), thickness: 1.6pt) } else { (
    paint: rgb("#3b5da8"),
    thickness: 0.6pt,
  ) },
  inset: 0pt,
)[#align(center + horizon)[#text(size: 10pt, name)]]

#let decomposition-figure() = block(width: 100%)[
  #rect(
    width: 100%,
    fill: rgb("#fbe3c8"),
    stroke: none,
    inset: (x: 16pt, y: 12pt),
  )[
    #align(center)[#text(size: 9pt, fill: rgb("#a35a12"))[sponge layer]]
    #v(2pt)
    #grid(
      columns: (1fr, 1fr, 1fr, 1fr),
      rows: (auto, auto),
      gutter: 0pt,
      _tile($r_(0 \, 0)$),
      _tile($r_(0 \, 1)$),
      _tile($r_(0 \, 2)$),
      _tile($r_(0 \, 3)$),
      _tile($r_(1 \, 0)$),
      _tile($r_(1 \, 1)$, highlight: true),
      _tile($r_(1 \, 2)$),
      _tile($r_(1 \, 3)$),
    )
    #v(2pt)
    #align(center)[#text(size: 9pt, fill: rgb("#a35a12"))[sponge layer]]
  ]
  #v(3pt)
  #align(center)[
    #text(size: 9pt, fill: rgb("#2e7d32"))[
      the green outline marks the one-cell halo carried by $r_(1 \, 1)$
    ]
  ]
]

// ---------------------------------------------------------------------------
// Figure: per-rank files joined by a virtual dataset
// ---------------------------------------------------------------------------

#let _rankbox(n) = rect(
  width: 100%,
  fill: rgb("#dfe6f7"),
  stroke: (paint: rgb("#3b5da8"), thickness: 0.6pt),
  inset: 7pt,
)[
  #align(center)[
    #text(size: 10pt)[rank #n] \
    #text(size: 8pt, raw("rank_000" + str(n) + "/...h5"))
  ]
]

#let vds-figure() = block(width: 100%)[
  #rect(
    width: 100%,
    fill: rgb("#dff2e0"),
    stroke: (paint: rgb("#2e7d32"), thickness: 0.6pt),
    inset: 8pt,
  )[
    #align(center)[
      #text(size: 10pt)[#raw("elastic_wavefield.h5") (virtual dataset)] \
      #text(size: 8pt)[logical shape $500 times 2801 times 13601$, resolved at read time]
    ]
  ]
  #v(4pt)
  #grid(
    columns: (1fr, 1fr, 1fr, 1fr),
    gutter: 8pt,
    align: center,
    text(size: 12pt)[$arrow.t$],
    text(size: 12pt)[$arrow.t$],
    text(size: 12pt)[$arrow.t$],
    text(size: 12pt)[$arrow.t$],
  )
  #v(4pt)
  #grid(
    columns: (1fr, 1fr, 1fr, 1fr),
    gutter: 8pt,
    _rankbox(0),
    _rankbox(1),
    _rankbox(2),
    _rankbox(3),
  )
]
