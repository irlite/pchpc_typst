# Score-P and Vampir material for the report

Three blocks. Where each goes:

1. `== Performance measurement` goes into Methodology, before `== Sequential Design` (line 515). This is the missing description of how every number in the report was measured.
2. `*Instrumentation.*` goes into Implementation, into the `== Setup` list (line 951), after `*Output.*`.
3. The Trace-based analysis block replaces the empty `== Trace Based Analysis with Vampir` heading (line 1288).

Both `#cite(<knupfer2012>)` and `#cite(<knupfer2008>)` need entries in `content/references.bib`. The bracketed `[...]` in block 1 is a placeholder for your run counts. Fill it or delete the sentence.

The four figures reference the screenshots already in `content/assets/`:

- `scorep-1x1x32-gzip.png` and `scorep-1x1x32-blosc.png` are stacked vertically as `@fig:vampir-overview`.
- `scorep-1x1x32-gzip-zoomed.png` and `scorep-1x1x32-blosc-zoomed.png` are stacked vertically as `@fig:vampir-zoom`.

Table provenance. The two kernel rows are read from the Function Summary panels in the overview screenshots: gzip 39.25 s and 35.26 s from `scorep-1x1x32-gzip.png` (window 0 to 38.3 s), Blosc LZ4 18.083 s and 16.1528 s from `scorep-1x1x32-blosc.png` (window 0 to 11.6 s). The `h5py` row, the startup row and the total row are full-trace values that none of the four screenshots shows; they carry `//` comments in the table and are the three rows to verify in your own Vampir session before submitting. The barrier times quoted in the prose (68.3585 s, 61.3758 s, 12.6196 s, 8.92 s) come from the same two Function Summary panels. The gap lengths (0.1375 s and 0.0026 s) come from the two zoomed screenshots.

## Block 1: Methodology

```typst
== Performance measurement

Every wall-clock time in this report covers a complete run of the solver, from
process start until the output files are closed, measured on the nodes listed
in the Setup section. [State how many runs each configuration was repeated
with, and whether the reported value is one run or a mean.]

We collect traces separately from those timed runs. Score-P#cite(<knupfer2012>)
instruments both layers of the program, the compiled C kernels and the Python
driver, and writes an OTF2 trace that Vampir#cite(<knupfer2008>) renders as one
timeline per thread. For a traced run, the job script sets `FWMP_SCOREP=1`,
which rebuilds the kernels with `scorep-gcc --openmp` and starts the driver as
`python -u -m scorep --mpp=mpi --thread=omp fwmp.py`. The script also enables
profiling and tracing, raises `SCOREP_TOTAL_MEMORY` to 256 MB and turns on all
MPI groups with `SCOREP_MPI_ENABLE_GROUPS=ALL`.

Tracing costs time, so no traced run feeds a speedup or scaling number in this
report. We use traced runs to attribute time within one run, and timed runs to
compare configurations.
```

## Block 2: Implementation setup

```typst
*Instrumentation.* Traced runs set `FWMP_SCOREP=1` in the job script. This
recompiles the kernels with `scorep-gcc --openmp` and launches the driver as
`python -u -m scorep --mpp=mpi --thread=omp fwmp.py`, so Score-P records the C
kernels and the Python time loop in the same trace.
```

## Block 3: Results

```typst
== Trace-based analysis with Vampir

The compression results in @fig:compression rank four HDF5 filters by total
runtime, but a total leaves two questions open. The gzip run takes
2125 s against 1154 s for Blosc LZ4, and the wall clock does not say which
function produced that difference. It also does not say whether the gap comes
from the compression work itself or from the solver threads waiting while one
thread compresses. We profiled the $1 times 1 times 32$ configuration with
Score-P and read the trace in Vampir to answer both questions. The traced runs
are separate runs from the timing runs, because tracing adds overhead of its
own, and every number in the analysis below comes from a trace.

#figure(
  grid(
    columns: 1,
    gutter: 4pt,
    image("assets/scorep-1x1x32-gzip.png", width: 100%),
    [#align(center)[#text(size: 9pt)[gzip]]],
    image("assets/scorep-1x1x32-blosc.png", width: 100%),
    [#align(center)[#text(size: 9pt)[Blosc LZ4]]],
  ),
  caption: [
    Vampir timeline of the traced $1 times 1 times 32$ run, gzip on top and
    Blosc LZ4 below. Each row is one thread, with the Python driver on the
    master thread. The lower chart gives the exclusive time per function group
    over the same window: `OMP_LOOP` is kernel work and `OMP_SYNC` is threads
    waiting at barriers.
  ],
) <fig:vampir-overview>

Both runs start on a single thread, which imports the modules and sets up the
HDF5 files, and only then the 32 OpenMP threads of the time loop appear. From
there the two lower charts disagree. In the gzip run `OMP_SYNC` reaches 90 %
and holds it, so the threads spend that stretch waiting. In the Blosc LZ4 run
`OMP_LOOP` is the largest band and `OMP_SYNC` stays near 20 %, so the threads
keep computing. @tab:vampir-functions puts the times behind that picture.

#figure(
  table(
    columns: (auto, auto, auto),
    align: (left, right, right),
    stroke: none,
    inset: (x: 7pt, y: 4.5pt),

    table.hline(stroke: 0.9pt),
    table.header([*Function*], [*gzip (s)*], [*Blosc LZ4 (s)*]),
    table.hline(stroke: 0.5pt),

    // Full-trace row. No screenshot shows it, so check it in Vampir before
    // submitting.
    [`h5py._hl.dataset.Dataset::__setitem__`], [1117.6], [104.2],
    // Function Summary values from the window in @fig:vampir-overview, the
    // !$omp for regions at elastic_kernels_tiled.c:296 and :323. gzip covers
    // the first 38.3 s of its trace, Blosc LZ4 the first 11.6 s of its own.
    [`update_stress_c`], [39.25], [18.083],
    [`update_velocity_c`], [35.26], [16.1528],
    // Full-trace row. No screenshot shows it.
    [module import and startup], [27.9], [25.1],
    table.hline(stroke: 0.5pt),
    // Full-trace total. No screenshot shows it.
    [Total traced runtime], [2074.8], [1091.5],
    table.hline(stroke: 0.9pt),
  ),
  kind: table,
  caption: [
    Accumulated exclusive time per function, read from the Score-P traces at
    $1 times 1 times 32$. The two kernel rows are read from the Function
    Summary over the window shown in @fig:vampir-overview, so they cover the
    first 38.3 s of the gzip run and the first 11.6 s of the Blosc LZ4 run.
    The other rows cover the whole traced run. Only functions above one second
    are listed.
  ],
) <tab:vampir-functions>

The two kernel rows are read over the window in @fig:vampir-overview, so they
cover the first 38.3 s of the gzip trace and the first 11.6 s of the Blosc LZ4
trace. The gzip window also holds the two `!$omp implicit barrier` regions at
`elastic_kernels_tiled.c:340` and `:315`, and those take 68.3585 s and
61.3758 s against 39.25 s and 35.26 s in the two loops, so there the threads
wait more than they compute. The Blosc LZ4 window reverses the order: the loops
take 18.083 s and 16.1528 s, the barriers 12.6196 s and 8.92 s, so there the
threads compute more than they wait.

Over the whole traced run the HDF5 write is the largest single cost in the
table. `h5py._hl.dataset.Dataset::__setitem__` takes 1117.6 s of the 2074.8 s
traced gzip run, which is 53.9 %. Switching to Blosc LZ4 takes the same write
to 104.2 s of the 1091.5 s traced run, which is 9.5 %, so the write loses
90.7 % of its cost.

#figure(
  grid(
    columns: 1,
    gutter: 4pt,
    image("assets/scorep-1x1x32-gzip-zoomed.png", width: 100%),
    [#align(center)[#text(size: 9pt)[gzip: 0.1375 s stall]]],
    image("assets/scorep-1x1x32-blosc-zoomed.png", width: 100%),
    [#align(center)[#text(size: 9pt)[Blosc LZ4: 0.0026 s stall]]],
  ),
  caption: [
    Thread-level view of one stall, gzip on top and Blosc LZ4 below. The
    highlighted window is where the 32 OpenMP threads have no work and the
    master thread runs alone. Orange is `OMP_LOOP`, cyan is `OMP_SYNC`.
  ],
) <fig:vampir-zoom>

@fig:vampir-zoom measures such a window. In the gzip trace the 32 threads stop
for 0.1375 s while the master thread works on alone, and the function group
chart drops to zero across the window. The Blosc LZ4 trace has the same shape,
but its window lasts 0.0026 s, about one fiftieth as long.

The traces explain why gzip runs slower than Blosc LZ4. The driver writes the
output from one thread, and gzip compresses on that thread alone, so every
write leaves the 32 solver threads waiting. Blosc LZ4 spreads the same
compression over several threads, so the threads block for a much shorter time
and the run reaches the totals in @tab:vampir-functions. The DEFLATE algorithm
itself accounts for the gap that @fig:compression shows between sequential
gzip and sequential lz4. Single-threaded execution accounts for what Blosc
recovers on top of that.

The trace does not measure memory bandwidth, so it cannot confirm or rule out
the bandwidth explanation for the single node scaling plateau discussed later.
Both traces also use one MPI rank, so they say nothing about communication
between nodes.
```

The `== Analysis and Bottleneck` subsection of Discussion is the place to
reference this finding in one sentence, next to the memory bandwidth argument.
Nothing else in Discussion needs to change.

## BibTeX for content/references.bib

```bibtex
@inproceedings{knupfer2012,
  author    = {Kn\"{u}pfer, Andreas and R\"{o}ssel, Christian and
               an Mey, Dieter and Biersdorff, Scott and Diethelm, Kai and
               Eschweiler, Dominic and Geimer, Markus and Gerndt, Michael and
               Lorenz, Daniel and Malony, Allen and Nagel, Wolfgang E. and
               Oleynik, Yury and Philippen, Peter and Saviankou, Pavel and
               Schmidl, Dirk and Shende, Sameer and Tsch\"{u}ter, Ronny and
               Wagner, Michael and Wesarg, Bert and Wolf, Felix},
  title     = {Score-{P}: A joint performance measurement run-time
               infrastructure for {Periscope}, {Scalasca}, {TAU}, and {Vampir}},
  booktitle = {Tools for High Performance Computing 2011},
  pages     = {79--91},
  year      = {2012},
  publisher = {Springer},
  doi       = {10.1007/978-3-642-31476-6_7}
}

@inproceedings{knupfer2008,
  author    = {Kn\"{u}pfer, Andreas and Brunst, Holger and Doleschal, Jens and
               Jurenz, Matthias and Lieber, Matthias and Mickler, Holger and
               M\"{u}ller, Matthias S. and Nagel, Wolfgang E.},
  title     = {The {Vampir} performance analysis tool-set},
  booktitle = {Tools for High Performance Computing},
  pages     = {139--155},
  year      = {2008},
  publisher = {Springer},
  doi       = {10.1007/978-3-540-68564-7_9}
}
```
