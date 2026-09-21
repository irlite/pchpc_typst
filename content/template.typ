= Introduction
Seismic wave forward modeling is the numerical simulation of how seismic waves propagate through a given earth model. It is used in applications ranging from earthquake hazard assessment and ground motion prediction to subsurface imaging in exploration geophysics. It is also a core building block of inverse problems such as full waveform inversion and seismic tomography, where synthetic waveforms produced by forward modeling are compared against observed data to iteratively refine an estimate of the subsurface.

Solving the elastodynamic wave equation numerically is most commonly done through discretization schemes such as the finite-difference method, in which the spatial and temporal derivatives of the equations are approximated on a grid. Accurately capturing the frequency content and spatial detail required for realistic wave propagation demands high computational power and, in particular, large amounts of memory. While the computation performed at each grid point is simple, many such points need to be updated over many iterations to satisfy the numerical stability conditions required to produce accurate results.

As a result, researchers and industry participants rely on HPC datacenters and the tools available on them to perform these computations within a reasonable amount of time. In modern HPC, this largely comes down to parallelization frameworks such as OpenMP#cite(<dagum1998>) and MPI#cite(<Forum1994MPIAM>), which allow a developer to split the workload across multiple cores within a node and across multiple nodes in a cluster, respectively. Using both together makes it possible to scale a simulation well beyond what a single machine could handle, provided the workload is divided and coordinated correctly.

One major application of this kind of modeling that is commonly performed with parallelization is in the oil and gas industry. To characterize the subsurface and locate oil and gas reservoirs, pressure is generated at the surface, and the resulting waves traveling through the ground or water are recorded. From these measurements, an approximate model of the subsurface is constructed. Forward modeling is then run on that model to simulate the resulting wave propagation, and the outcome is compared against the actual measurements to assess how closely the model matches reality.

To ground this in a concrete case, the numerical scheme and parallelization strategy examined in this work are applied to the Marmousi2#cite(<martin2006>) model, a widely used subsurface model derived from a profile of the North Quenguela trough in the Kwanza Basin, Angola. The goal of our computation is to visualize how a wave travels through this model, displaying the velocity of the medium resulting from a pressure wave injected at the surface.

The remainder of this paper is structured as follows: we first describe
the numerical scheme used for forward modeling and explain how it can be
implemented sequentially, after which we detail how the domain is
decomposed and parallelized using MPI and OpenMP. We then present
performance results obtained on an HPC cluster, examining how the
implementation scales with an increasing number of processes and cores.
Finally, we will discuss these results and potential future work.

= Background
== Marmousi2 Model
Marmousi2#cite(<martin2006>) is an updated version of the original 1988 Marmousi#cite(<versteeg1994>)
model. Its structure is based on the North Quenguela Trough in
the Quanza Basin of Angola, a region composed mostly of shale
with interbedded sand layers, a marl anticline within a faulted
zone, an evacuated salt layer, and hydrocarbon traps near its
centre.

Compared to the original model, Marmousi2 extends both the width
and depth of the domain, increasing the width from 9.2 km to
17 km and adding 41 additional horizons, for a total of 199. The
model was also made fully elastic through the addition of a
shear-wave (S-wave) velocity field, alongside the existing
pressure-wave (P-wave) velocity and density fields. A 450-meter
water layer was also added at the top to represent a deep-water
setting.

#figure(
  image("assets/marmousi-2.jpg", width: 90%),
  caption: [
      Marmousi2 Model
  ],
) <fig:marmousi>

We chose it for three reasons. It is a standard benchmark, it is elastic and therefore allows for more realistic simulations, and at full resolution it is big enough that a parlllel run is worth while.

The SEG open data collection #cite(<segopendata>) distributes the dataset as three SEG-Y files each holding $v_p$, $v_s$ and $rho$ on a 1.25 m grid, which `segyio` reads directly.

#figure(
  table(
    columns: (auto, auto),
    align: (left, right),
    stroke: none,
    inset: (x: 7pt, y: 4.5pt),

    table.hline(stroke: 0.9pt),
    table.header([*Quantity*], [*Value*]),
    table.hline(stroke: 0.5pt),

    [Physical grid $n_(z_0) times n_(x_0)$], [$2801 times 13601$],
    [Physical grid points], [38 095 201],
    [Grid spacing $Delta x = Delta z$], [1.25 m],
    [Model extent (horizontal $times$ depth)], [17.0 km $times$ 3.5 km],
    table.hline(stroke: 0.9pt),
  ),
  caption: [
    Properties of the Marmousi2 model
  ],
) <tab-model>

== Elastodynamic wave equation
Ultimately, the data computed by the simulation represents the particle velocity at every point in the material at every timestep, which is used to visualize how the wave travels through the medium. Since the source and the receivers of interest are placed near the surface, the waves of interest primarily travel upward, so the velocity component of interest is the one aligned with that direction, the vertical velocity $v_z$. This also mirrors real seismic acquisition, where a receiver placed on the surface predominantly measures the vertical component of ground motion from an upward-arriving wave.

Computing this velocity field requires solving the elastic wave equation, and different numerical approaches exist for doing so, trading off complexity against accuracy. In this work, we use a second order accurate finite difference scheme.

The Marmousi2 model provides the P-wave velocity $v_p$, the S-wave velocity $v_s$, and the mass density $rho$ at every point of a realistic, geologically structured subsurface model. From these three quantities, we ultimately want to compute the velocity components $v_x$ and $v_z$ and the stress components $sigma_(x x)$, $sigma_(z z)$, and $sigma_(x z)$ at every grid point and every timestep. To do so, the elastic update equations additionally require the Lamé parameters $lambda$ and $mu$, which are not provided directly by the model but can be derived from $v_p$, $v_s$ like this:

$ mu = rho v_s^2 $

$ lambda = rho v_p^2 - 2 mu $

At each timestep, the stress and velocity variables are updated according to the following equations, which depend on the values at the previous timestep:

$ (∂ v_x) / (∂ t) = 1/rho ((∂ sigma_(x x)) / (∂ x)
                          + (∂ sigma_(x z)) / (∂ z)) $

$ (∂ v_z) / (∂ t) = 1/rho ((∂ sigma_(x z)) / (∂ x)
                          + (∂ sigma_(z z)) / (∂ z)) $

$ (∂ sigma_(x x)) / (∂ t) = (lambda + 2 mu) (∂ v_x) / (∂ x)
                           + lambda (∂ v_z) / (∂ z) $

$ (∂ sigma_(z z)) / (∂ t) = lambda (∂ v_x) / (∂ x)
                           + (lambda + 2 mu) (∂ v_z) / (∂ z) $

$ (∂ sigma_(x z)) / (∂ t) = mu ((∂ v_x) / (∂ z)
                               + (∂ v_z) / (∂ x)) $

== Ricker Wavelet
To initiate wave propagation, a source term is added directly into
the stress update at a single grid point near the surface,
representing an idealized pressure disturbance analogous to an
airgun or explosive source. The time dependence of this
disturbance is given by a Ricker wavelet #cite(<ricker1951>), a
zero-mean pulse commonly used in seismic modeling to approximate
the waveform produced by an impulsive source, defined as

$ r(t) = (1 - 2 a) e^(-a), quad
  a = (pi f_0 (t - t_0))^2 $

where $f_0$ is the dominant frequency of the source, a fixed
constant in this simulation, and $t_0$ delays the peak of the
wavelet, computed from $f_0$ alone using a standard convention.
At every timestep, the value of
$r(t)$ is added directly into $sigma_(x x)$ and $sigma_(z z)$ at
the source location, injecting an isotropic pressure disturbance
that subsequently propagates outward through the model according
to the update equations above.

== Numerical Stability and the CFL Condition

Because the update equations are explicit, each new value depends
only on values already known at the current timestep, the scheme
is only stable if the timestep is chosen appropriately relative to
the grid spacing and the wave speeds present in the model. This
requirement is known as the Courant-Friedrichs-Lewy, or CFL,
condition #cite(<courant_1928>), and it follows directly from the
combined timestep-to-grid-spacing factor introduced above. If the
timestep were too large relative to the grid spacing, a wave could
effectively advance by more than one grid cell within a single
timestep, which the finite-difference stencil has no way of
representing correctly, causing errors to grow rather than remain
bounded as the simulation progresses.

Since the P-wave is always the fastest wave present in an elastic
medium, the stability limit is governed by the largest P-wave
velocity found anywhere in the model, $v_(p,max)$. Likewise, if the
grid spacing differs between the two axes, the stricter of the two
constraints comes from whichever spacing is smaller. The timestep
used in this work is therefore chosen as

$ d t = 0.4 dot (min(d x, d z)) / v_(p,max) $

where the factor $0.4$ provides a safety margin below the
theoretical stability limit, rather than operating at the limit
itself, to remain robust to the additional approximations present
in the scheme, such as the damping applied near the absorbing
boundaries.
== Absorbing Boundary Damping

Reflections from the edges of the grid are suppressed using a
simple damping mask rather than a physically derived boundary
condition. This technique is known as a sponge boundary #cite(<cerjan1985>).
The model is surrounded by padded regions on all four
sides, and within these regions a damping value $d(i,j) in [0,1]$
is precomputed for every grid point.

In the interior of the model, $d(i,j) = 1$, meaning no damping is
applied. Within the padded regions, $d(i,j)$ decreases smoothly
from $1$ (at the edge closest to the real model) down toward $0$
(at the outer edge of the grid). The bottom boundary uses a
stronger damping profile than the top and sides, so values there
approach $0$ more quickly.

At every time step, after the stress and velocity fields are
updated, each field value is simply multiplied by the damping
value at that location:

$ u(i,j) <- u(i,j) dot d(i,j) $

for each of $sigma_(x x)$, $sigma_(z z)$, $sigma_(x z)$, $v_x$,
and $v_z$. Where $d = 1$, the value is unchanged. Where $d < 1$,
the value is reduced slightly on that step. Because this
multiplication happens at every time step, waves travelling
through the padded region lose amplitude continuously, so that by
the time they would reflect off the true edge of the grid and
travel back into the model, their amplitude has been reduced to a
negligible level.

== Staggering
To increase the accuracy of the computation, staggering is applied. Staggering refers to deliberately storing or updating different quantities at offset positions, rather than at the same point, whether that offset is in space or in time. The two staggered quantities are never evaluated at exactly the same location, but each is placed exactly halfway between two locations of the other. As shown below, this offset is what allows the finite differences used to update each field to reach second order accuracy without requiring a wider stencil  .

=== Second order accuracy

Any time a continuous derivative is approximated using a finite difference, some error is introduced, since the approximation only uses a finite number of nearby values instead of the true, continuous function. The order of accuracy describes how quickly this error shrinks as the discretization is refined, that is, as the grid spacing $Delta$ or timestep $"dt"$ is made smaller. A first order accurate scheme has an error that shrinks proportionally to $Delta$ itself. Halving the spacing only halves the error. A second order accurate scheme has an error that shrinks proportionally to $Delta^2$. Halving the spacing quarters the error. This means that for a small refinement, a second order scheme becomes accurate much faster than a first order one, since its error decreases quadratically rather than linearly as the discretization is refined.

This distinction matters in practice because it directly affects how fine a grid or timestep is needed to reach a given accuracy target. A first order scheme generally requires a much finer discretization, and correspondingly far more computation, to reach the same accuracy as a second order scheme. Both the spatial and temporal staggering described below are specifically what allow the finite difference scheme used in this work to achieve second order accuracy, rather than being limited to first order, without requiring a wider, more expensive stencil.

=== Spatial Staggering

The finite difference scheme used to update the velocity and stress fields is applied on a spatially staggered grid, commonly referred to as a Virieux grid#cite(<virieux1984>). Rather than storing all five field components, $v_x$, $v_z$, $sigma_(x x)$, $sigma_(z z)$, and $sigma_(x z)$, at the same physical location within a grid cell, each component is instead stored at a position offset by half a grid spacing relative to the others. Concretely, the normal stresses $sigma_(x x)$ and $sigma_(z z)$ are defined at integer grid points $(i, j)$, the horizontal velocity $v_x$ is defined half a cell to the side at $(i, j+1/2)$, the vertical velocity $v_z$ is defined half a cell below at $(i+1/2, j)$, and the shear stress $sigma_(x z)$ is defined half a cell in both directions at $(i+1/2, j+1/2)$.
#figure(
  box(width: 11cm, height: 8cm)[
    #let cell = 2.5cm
    #let pad = 1.5cm
    #let r = 0.16cm

    // Field colors.
    #let sxx-color = rgb("#006ddc")
    #let vx-color = rgb("#1bbc3c")
    #let vz-color = rgb("#c31834")
    #let sxz-color = rgb("#ffa028")
    #let black = rgb("#000000")

    // Integer grid-point coordinates.
    #let px(i) = pad + i * cell
    #let py(j) = pad + j * cell

    // Dashed horizontal grid lines.
    #for j in range(3) {
      place(
        top + left,
        dx: px(0),
        dy: py(j),
        line(
          start: (0cm, 0cm),
          end: (2 * cell, 0cm),
          stroke: (
            paint: gray,
            thickness: 0.6pt,
            dash: "dashed",
          ),
        ),
      )
    }

    // Dashed vertical grid lines.
    #for i in range(3) {
      place(
        top + left,
        dx: px(i),
        dy: py(0),
        line(
          start: (0cm, 0cm),
          end: (0cm, 2 * cell),
          stroke: (
            paint: gray,
            thickness: 0.6pt,
            dash: "dashed",
          ),
        ),
      )
    }

    // Normal stresses sigma_xx and sigma_zz
    // at integer grid points.
    #for j in range(3) {
      for i in range(3) {
        place(
          top + left,
          dx: px(i) - r,
          dy: py(j) - r,
          circle(
            radius: r,
            fill: sxx-color,
          ),
        )
      }
    }

    // Horizontal velocity v_x
    // at horizontally staggered points.
    #for j in range(3) {
      for i in range(2) {
        place(
          top + left,
          dx: px(i) + cell / 2 - r,
          dy: py(j) - r,
          circle(
            radius: r,
            fill: vx-color,
          ),
        )
      }
    }

    // Vertical velocity v_z
    // at vertically staggered points.
    #for j in range(2) {
      for i in range(3) {
        place(
          top + left,
          dx: px(i) - r,
          dy: py(j) + cell / 2 - r,
          circle(
            radius: r,
            fill: vz-color,
          ),
        )
      }
    }

    // Shear stress sigma_xz
    // at points staggered in both directions.
    #for j in range(2) {
      for i in range(2) {
        place(
          top + left,
          dx: px(i) + cell / 2 - r,
          dy: py(j) + cell / 2 - r,
          circle(
            radius: r,
            fill: sxz-color,
          ),
        )
      }
    }

    // Place a coordinate label at the top-right
    // of an integer grid point.
    #let coordinate-label(x, y, label) = {
      place(
        top + left,
        dx: x + 0.18cm,
        dy: y - 0.42cm,
        text(
          size: 7pt,
          fill: black,
          label,
        ),
      )
    }

    // Top row.
    #coordinate-label(
      px(0),
      py(0),
      [$(i - 1, j + 1)$],
    )

    #coordinate-label(
      px(1),
      py(0),
      [$(i, j + 1)$],
    )

    #coordinate-label(
      px(2),
      py(0),
      [$(i + 1, j + 1)$],
    )

    // Middle row.
    #coordinate-label(
      px(0),
      py(1),
      [$(i - 1, j)$],
    )

    #coordinate-label(
      px(1),
      py(1),
      [$(i, j)$],
    )

    #coordinate-label(
      px(2),
      py(1),
      [$(i + 1, j)$],
    )

    // Bottom row.
    #coordinate-label(
      px(0),
      py(2),
      [$(i - 1, j - 1)$],
    )

    #coordinate-label(
      px(1),
      py(2),
      [$(i, j - 1)$],
    )

    #coordinate-label(
      px(2),
      py(2),
      [$(i + 1, j - 1)$],
    )

    // Framed legend.
    #let legend-x = px(2) + 2.3cm
    #let legend-y = py(0) + 0.6cm

    #place(
      top + left,
      dx: legend-x,
      dy: legend-y,
      box(
        inset: 0.25cm,
        stroke: 0.7pt + gray,
        radius: 3pt,
        fill: white,
      )[
        #stack(
          dir: ttb,
          spacing: 0.2cm,

          text(
            size: 9pt,
            weight: "bold",
          )[Fields],

          grid(
            columns: (0.4cm, auto),
            column-gutter: 0.12cm,
            row-gutter: 0.22cm,
            align: left,

            // Normal stresses.
            align(center)[
              #circle(
                radius: r,
                fill: sxx-color,
              )
            ],
            text(
              size: 8pt,
              fill: black,
            )[
              $sigma_(x x), sigma_(z z)$
            ],

            // Horizontal velocity.
            align(center)[
              #circle(
                radius: r,
                fill: vx-color,
              )
            ],
            text(
              size: 8pt,
              fill: black,
            )[
              $v_x$
            ],

            // Vertical velocity.
            align(center)[
              #circle(
                radius: r,
                fill: vz-color,
              )
            ],
            text(
              size: 8pt,
              fill: black,
            )[
              $v_z$
            ],

            // Shear stress.
            align(center)[
              #circle(
                radius: r,
                fill: sxz-color,
              )
            ],
            text(
              size: 8pt,
              fill: black,
            )[
              $sigma_(x z)$
            ],
          ),
        )
      ],
    )
  ],
  caption: [
    Layout of a portion of the staggered grid. The normal stresses
    $sigma_(x x)$ and $sigma_(z z)$ are stored at integer grid points.
    The horizontal velocity $v_x$ is offset by half a grid spacing along
    $x$, the vertical velocity $v_z$ is offset by half a grid spacing
    along $z$, and the shear stress $sigma_(x z)$ is offset by half a
    grid spacing in both directions.
  ],
) <fig:staggeredgrid>

Placing the two fields on interleaved, offset grids means that whenever a derivative is needed, it is computed from the two nearest neighboring points on the opposite field's grid:
- $v_x$ at $(i, j + 1/2)$: needs
  $sigma_(x x)(i, j + 1)$,#h(0.4em)
  $sigma_(x x)(i, j)$,#h(0.4em)
  $sigma_(x z)(i + 1/2, j + 1/2)$,#h(0.4em)
  $sigma_(x z)(i - 1/2, j + 1/2)$.

- $v_z$ at $(i + 1/2, j)$: needs
  $sigma_(x z)(i + 1/2, j + 1/2)$,#h(0.4em)
  $sigma_(x z)(i + 1/2, j - 1/2)$,#h(0.4em)
  $sigma_(z z)(i + 1, j)$,#h(0.4em)
  $sigma_(z z)(i, j)$.

- $sigma_(x x)$ and $sigma_(z z)$ at $(i, j)$: need
  $v_x (i, j + 1/2)$,#h(0.4em)
  $v_x (i, j - 1/2)$,#h(0.4em)
  $v_z (i + 1/2, j)$,#h(0.4em)
  $v_z (i - 1/2, j)$.

- $sigma_(x z)$ at $(i + 1/2, j + 1/2)$: needs
  $v_x (i + 1, j + 1/2)$,#h(0.4em)
  $v_x (i, j + 1/2)$,#h(0.4em)
  $v_z (i + 1/2, j + 1)$,#h(0.4em)
  $v_z (i + 1/2, j)$.
In the implementation, this offset is not stored explicitly, there is no separate coordinate array marking a point as "$i+1/2$". Instead, $v_x$, $v_z$, $sigma_(x x)$, $sigma_(z z)$, and $sigma_(x z)$ are all stored as ordinary two dimensional arrays of the same shape, and the staggering exists only implicitly, in which neighboring array index each update kernel reads from. The offset shown in @fig:staggeredgrid is realized purely through the direction of the finite difference used at each point, not through any special indexing scheme.

Concretely, the stress update reads velocity one index ahead, a forward difference, since the velocity powering $sigma_(x x)$ conceptually sits half a cell beyond the current point:

```c
dvx_dx = (vx[i][j+1] - vx[i][j]) / dx;
dvz_dz = (vz[i+1][j] - vz[i][j]) / dz;
```

while the velocity update reads stress one index behind, a backward difference, since the stress powering $v_x$ conceptually sits half a cell before the current point:

```c
dsxx_dx = (sxx[i][j] - sxx[i][j-1]) / dx;
dsxz_dz = (sxz[i][j] - sxz[i-1][j]) / dz;
```

Both kernels perform an ordinary two point finite difference over array indices that are one full array step apart, but because one kernel always looks forward and the other always looks backward, the effective location each result represents is shifted by half a grid spacing relative to its input without ever needing to track fractional indices.

=== Temporal Staggering

In addition to being staggered in space, the scheme is also staggered in time. Rather than updating stress and velocity from a single shared snapshot of the fields, the two are updated at interleaved half time steps so that each update always consumes the most recently computed values of the other field. This is commonly known as a leapfrog scheme, and it makes the computation second order accurate in time.

== Tiling

As a consequence of the temporal staggering described above, every timestep first advances the velocity fields by half a timestep using the stress values just computed, then advances the stress fields by the next half timestep, using the velocity values just computed. Implemented naively, this ordering can hurt performance. Since the entire velocity field is computed first, sweeping across the full grid, by the time this pass finishes, the values computed early in the sweep have long since been pushed out of the cache to make room for those computed later, as the cache cannot hold the full grid at once. When the stress update immediately afterward needs those same velocity values, most of them are no longer available nearby and must instead be streamed back in from main memory. The resulting cost is especially significant relative to how cheap the underlying arithmetic is.

To remove this bottleneck, this work applies tiling. When using tiling, the grid is divided into many small tiles instead of computing the entire field. For each tile, velocity is computed first, and immediately afterward, while those values are still resident in the cache, the corresponding stress values are computed using them, before the next tile is processed. Only once both fields have been fully advanced for one tile does the computation proceed to the next. In this way, the same round trip to main memory that would otherwise be required twice for every value, once to write it, once to read it back, is reduced to a single round trip, since each value is consumed again while still cheap to access, rather than after it has already been evicted.

= Methodology
== Sequential Design
Every speedup in this report is measured against the sequential solver. It
solves the same equations on the same grid with the same boundary treatment
as the parallel version, and it writes the same output: the vertical
particle velocity $v_z$, saved every hundredth step. Its inner loops are
compiled C rather than interpreted Python, so it is a fair point of
comparison rather than an artificially slow one.

=== Structure of the program

@seq-pseudo-code gives the solver in full. Setup runs once: it reads the
model, derives the arrays the kernels need, and prepares the output file.
The time loop then repeats four operations fifty thousand times. Everything
else in this chapter and in @sec-seq-impl expands one part of this listing.

#figure(
```c
SETUP
    read vp, vs, rho from three SEG-Y files
    pad each field by nb cells
    mu      <- rho * vs^2
    lambda  <- rho * vp^2 - 2*mu
    lam2mu  <- lambda + 2*mu
    inv_rho <- 1 / rho
    damp    <- quadratic sponge ramp on all four sides
    dt      <- 0.4 * dx / max(vp)
TIME LOOP
    for it = 0 .. n_iterations-1:
        inject_source(sxx, szz, vz, it, dt)
        update_stress(vx, vz, sxx, szz, sxz, lam, mu, damp, dt)
        update_velocity(vx, vz, sxx, szz, sxz, invRho, damp, dt)
        if it mod frame_stride == 0:
            save_frame(out, vz)
TEARDOWN
    close the output file

function update_stress(vx, vz, sxx, szz, sxz, lam, mu, damp, dt):
    for each tile (iz_tile, ix_tile) in domain:
        for i in iz_tile:
            for j in ix_tile:
                compute strain rates from vx, vz
                update sxx, szz, sxz
                apply damping
function update_velocity(vx, vz, sxx, szz, sxz, invRho, damp, dt):
    for each tile (iz_tile, ix_tile) in domain:
        for i in iz_tile:
            for j in ix_tile:
                compute stress gradients
                update vx, vz
                apply damping
```,
  caption: [
      The sequential solver in full. The two functions update_stress and update_velocity are the C kernels. The remaining code is Python.
  ],
) <seq-pseudo-code>

The four derived arrays, $mu$, $lambda$, $lambda + 2 mu$ and $1 slash rho$, are
computed once during setup rather than inside the loop. The kernels read
exactly these quantities, so no material property is ever recomputed.
over the grid.

=== The division between Python and C

The program is written in two languages. Python reads the three model
files, applies padding, derives the elastic parameters, builds the damping
ramp and creates the output file.

C handles the other half. The time loop performs the same small amount of
arithmetic at every grid point at every step, fifty thousand times over, and
at that volume every cycle counts. Writing those two kernels by hand is what
makes the baseline worth measuring against.

In the parallel version the same line places MPI communication on the
Python side, alongside the rest of the orchestration. This costs nothing,
because mpi4py passes NumPy buffers directly to the MPI library rather than
copying them. What this means is that the kernels contain no communication.
== Parallel Design
=== Parallelization Coverage

*What was not parallelized*

- *Time stepping loop.* The main loop advances the stress and velocity fields one iteration at a time, and each timestep depends on the result of the previous one. This dependency is the Amdahl bottleneck. Because of it the loop over time cannot be parallelized itself, only the work done within a single timestep can be.

- *One time setup.* Reading the SEGY model files, computing the Lame parameters, building the PML damping profile and determining the domain decomposition all happen once before the time loop starts. This is currently repeated on every rank rather than distributed, since the cost is negligible compared to the roughly 50000 timesteps that follow. The final assembly of the per rank output files into one virtual HDF5#cite(<folk2011>) dataset also happens once, done serially by rank 0 after every rank has finished writing. Since this step only links metadata together using VirtualSource rather than copying any data, it finishes almost instantly.

- *Pressure injection.* The source term is injected at a single grid point, so only the rank that owns this point performs the update. This step cannot be parallelized any further, and the resulting overhead is negligible.

*What was parallelized*

- *Domain decomposition.* The global grid is split across MPI#cite(<Forum1994MPIAM>) ranks using a 2D Cartesian topology built with Compute_dims and Create_cart. Each rank owns a rectangular subdomain plus a one cell halo. Neighboring ranks exchange halo values for the stress and velocity fields every timestep using Sendrecv calls.

- *Stress and velocity updates.* Inside each rank's subdomain, the update kernels update_stress and update_velocity are written in C and parallelized with OpenMP#cite(<dagum1998>). Combined with the MPI domain decomposition, this hybrid MPI and OpenMP scheme forms the main strategy of our parallelization.

- *HDF5 output.* Each rank writes its own wavefield snapshots to an independent file. This avoids the bottleneck that would occur if every rank had to send its data through rank 0 for writing.

- *Compression.* Blosc is used to compress the output data with OpenMP threads handling the compression work in parallel. Before this change, compression was performed by a single rank, meaning all other ranks were forced to wait idly until rank 0 finished compressing its share of the data before the program could proceed. Parallelizing compression with Blosc removed this serial bottleneck and led to a significant improvement in scaling performance.

=== MPI Parallelization


*Domain Decomposition*

The padded global grid of size $n_z times n_x$ is distributed across MPI#cite(<Forum1994MPIAM>) ranks by arranging them on a two-dimensional Cartesian topology. Rather than relying on the default balancing provided by `MPI_Dims_create`, we search over all factor pairs $(p_z, p_x)$ of the process count and choose the pair that minimizes $n_z / p_z + n_x / p_x$. Since the cost of the halo exchange scales with the perimeter of a subdomain, this avoids long, thin tiles that would otherwise increase communication relative to computation. Within each dimension, the grid is then split as evenly as possible, so that no rank is assigned a disproportionately large share of the domain and no rank becomes a bottleneck.

Once the Cartesian communicator is created, each rank locates its four neighbors automatically along the $z$ and $x$ axes. Ranks that lie on the boundary of the global domain receive a null neighbor on the corresponding side. Their halo exchange on that side is therefore skipped, and the PML absorbing layer is used instead of neighbor data. Figure @fig:domdecomp illustrates the resulting layout, with the PML region surrounding the inner grid of MPI ranks and one cell highlighted to show the halo shared between neighboring subdomains.

#figure(
  box(width: 11.5cm, height: 8.5cm)[
    #let margin = 1cm      // sponge thickness
    #let cell = 2cm        // size of one rank tile
    #let cols = 3
    #let rows = 2
    #let grid-w = cols * cell
    #let grid-h = rows * cell
    #let pml-w = grid-w + 2 * margin
    #let pml-h = grid-h + 2 * margin
    #let pad = 1cm         // outer padding for axes/labels
    #let line-w = 1.3pt    // uniform grid line thickness
    #let halo-w = 2.6pt    // halo border thickness

    // PML background region (fill only)
    #place(top + left, dx: pad, dy: pad,
      rect(width: pml-w, height: pml-h, fill: rgb("#f5c896"), stroke: none))

    // Cell fills (no stroke here, lines are drawn separately below)
    #for row in range(rows) {
      for col in range(cols) {
        place(
          top + left,
          dx: pad + margin + col * cell,
          dy: pad + margin + row * cell,
          box(width: cell, height: cell, fill: rgb("#c8d8f5"),
            align(center + horizon, $r_(#row,#col)$)),
        )
      }
    }

    // Uniform grid lines drawn as a separate layer, same thickness everywhere
    #for col in range(cols + 1) {
      place(top + left,
        dx: pad + margin + col * cell,
        dy: pad + margin,
        line(start: (0cm, 0cm), end: (0cm, grid-h), stroke: line-w + rgb("#3050a0")))
    }
    #for row in range(rows + 1) {
      place(top + left,
        dx: pad + margin,
        dy: pad + margin + row * cell,
        line(start: (0cm, 0cm), end: (grid-w, 0cm), stroke: line-w + rgb("#3050a0")))
    }

    // Halo highlight, drawn on top as its own outline so it is fully controlled
    #place(top + left,
      dx: pad + margin + cell,
      dy: pad + margin + cell,
      rect(width: cell, height: cell, fill: none, stroke: halo-w + rgb("#2a8a2a")))

    // PML labels
    #place(top + left, dx: pad + margin + grid-w / 2 - 0.6cm, dy: pad + margin / 2 - 0.3cm,
      text(size: 8pt, fill: rgb("#a05000"))[PML])
    #place(top + left, dx: pad + margin + grid-w / 2 - 0.6cm, dy: pad + margin + grid-h + margin / 2 - 0.3cm,
      text(size: 8pt, fill: rgb("#a05000"))[PML])
    #place(top + left, dx: pad + margin / 2 - 0.3cm, dy: pad + margin + grid-h / 2 - 0.6cm,
      box(width: 1cm, height: 1cm, rotate(-90deg, reflow: true, text(size: 8pt, fill: rgb("#a05000"))[PML])))
    #place(top + left, dx: pad + margin + grid-w + margin / 2 - 0.3cm, dy: pad + margin + grid-h / 2 - 0.6cm,
      box(width: 1cm, height: 1cm, rotate(-90deg, reflow: true, text(size: 8pt, fill: rgb("#a05000"))[PML])))

    // Axes
    #place(top + left, dx: pad, dy: pad - 0.4cm,
      line(start: (0cm, 0cm), end: (0cm, pml-h + 0.8cm), stroke: 1pt + black))
    #place(top + left, dx: pad - 0.5cm, dy: pad - 0.75cm, text[$z$])

    #place(top + left, dx: pad - 0.4cm, dy: pad + pml-h,
      line(start: (0cm, 0cm), end: (pml-w + 0.8cm, 0cm), stroke: 1pt + black))
    #place(top + left, dx: pad + pml-w + 0.5cm, dy: pad + pml-h - 0.15cm, text[$x$])

    // Halo callout, moved left so it clears the bottom PML label
    #place(top + left,
      dx: pad + margin + cell,
      dy: pad + margin + grid-h + 0.3cm,
      line(start: (0cm, 0cm), end: (-1.5cm, 1.3cm), stroke: 1pt + rgb("#2a8a2a")))
    #place(top + left, dx: pad + margin + cell - 2.3cm, dy: pad + margin + grid-h + 1.7cm,
      text(fill: rgb("#2a8a2a"))[halo])
  ],
  caption: [
    Decomposition of the padded grid into a Cartesian arrangement of MPI
    ranks, surrounded by the PML absorbing boundary. Each rank exchanges
    a one-cell-wide halo with its neighboring ranks every timestep.
  ],
) <fig:domdecomp>

*Halo Exchange*

As detailed earlier, the grid is staggered spatially, meaning that the velocity and stress components are not stored at the same physical location but are offset from one another by half a grid spacing. Physically, this means that a velocity value is treated as living midway between two neighboring stress points, rather than coinciding with them. This does not just provide improved accuracy, it also cuts the data that has to be exchanged via MPI#cite(<Forum1994MPIAM>) in half. Because each velocity value sits between two stress points rather than on top of one, computing the spatial derivative needed to update it only requires the single stress value immediately behind it, not the values on both the left and the right. The same holds in reverse for updating stress from velocity. As a result, each rank only ever needs a neighboring value from one direction per axis instead of two, so only one side needs to be communicated for a given field, rather than both. Concretely, without staggering all five fields would require neighbor values from both directions along each axis, giving ten directional transfers per axis, whereas with staggering the two velocity fields only require one direction and the three stress fields only require the other, giving five.

#figure(
  box(width: 16cm, height: 8.5cm)[
    #let panel(x0, mirror, title) = {
      let s = 3cm       // rank body size
      let h = 0.4cm     // halo strip thickness
      let dy0 = 2.4cm   // vertical offset of the square within the panel

      let green-fill = rgb("#1bbc3c")
      let green-stroke = rgb("#014a0f")
      let red-fill = rgb("#c13834")
      let red-stroke = rgb("#7c1326")

      // top-left sides vs bottom-right sides swap color depending on mirror
      let tl-color = if mirror { (green-fill, green-stroke) } else { (red-fill, red-stroke) }
      let br-color = if mirror { (red-fill, red-stroke) } else { (green-fill, green-stroke) }

      // title
      place(top + left, dx: x0, dy: 0.9cm,
        box(width: s + 2 * h, align(center, text(size: 9pt)[#title])))

      // rank body
      place(top + left, dx: x0 + h, dy: dy0 + h,
        rect(width: s, height: s, fill: rgb("#ffa028"), stroke: 1pt + rgb("#3050a0")))

      // top halo strip
      place(top + left, dx: x0 + h, dy: dy0,
        rect(width: s, height: h, fill: tl-color.at(0), stroke: 0.8pt + tl-color.at(1)))
      // left halo strip
      place(top + left, dx: x0, dy: dy0 + h,
        rect(width: h, height: s, fill: tl-color.at(0), stroke: 0.8pt + tl-color.at(1)))
      // bottom halo strip
      place(top + left, dx: x0 + h, dy: dy0 + h + s,
        rect(width: s, height: h, fill: br-color.at(0), stroke: 0.8pt + br-color.at(1)))
      // right halo strip
      place(top + left, dx: x0 + h + s, dy: dy0 + h,
        rect(width: h, height: s, fill: br-color.at(0), stroke: 0.8pt + br-color.at(1)))

      // top-left corner callout
      let tl-label = if mirror { "send" } else { "received" }
      place(top + left, dx: x0 - 1cm, dy: dy0 - 1cm,
        line(start: (0cm, 0cm), end: (1cm, 1cm), stroke: 1pt + tl-color.at(1)))
      place(top + left, dx: x0 - 1.7cm, dy: dy0 - 1.5cm,
        text(size: 8pt, fill: tl-color.at(1))[#tl-label])

      // bottom-right corner callout
      let br-label = if mirror { "received" } else { "send" }
      place(top + left, dx: x0 + 2 * h + s, dy: dy0 + 2 * h + s,
        line(start: (0cm, 0cm), end: (1cm, 1cm), stroke: 1pt + br-color.at(1)))
      place(top + left, dx: x0 + 2 * h + s + 1.1cm, dy: dy0 + 2 * h + s + 1.1cm,
        text(size: 8pt, fill: br-color.at(1))[#br-label])
    }

    #panel(2cm, false, "Stress exchange")
    #panel(9cm, true, "Velocity exchange")
  ],
  caption: [
    The two halo exchanges performed each timestep. For the stress fields
    (left), each rank sends its bottom and right edge to its plus-side
    neighbors and receives into its top and left ghost cells from its
    minus-side neighbors. For the velocity fields (right), the direction
    is reversed: each rank sends its top and left edge and receives into
    its bottom and right ghost cells. This mirrors the forward and
    backward differences used by the staggered grid stencils.
  ],
) <fig:halodirs>

*Execution Order and Tiling*

Two separate exchanges are still required per timestep, one for the velocity fields and one for the stress fields, but this is a consequence of the temporal staggering rather than of the spatial staggering itself. The stress fields must be fully updated using the exchanged velocity values before they can, in turn, be exchanged and used to update velocity.

The naive version previously applied performed each timestep in two fully separate sweeps. First, velocity was exchanged and used to compute stress everywhere, then stress was exchanged and used to compute velocity everywhere. This ordering is required by the temporal staggering described earlier, and it appears to prevent fusing the two kernels together, since velocity generally cannot be computed until the full stress exchange has completed.

But this is only true at the border of a rank's subdomain. Since the stencils used here reach only a single neighboring point, the vast majority of a rank's points depend only on data the rank already owns, regardless of any exchange. Only a thin strip at the edge actually needs data from a neighbor. This makes it possible to fuse stress and velocity for the interior immediately, while only the border falls back to waiting for the exchange, and since the interior does not depend on the exchange at all, the exchange can be issued in the background and left to complete while the interior is tiled, hiding its latency behind useful computation.

This latency hiding only applies to the stress exchange. The velocity exchange still has to complete beforehand, since the interior stress computation itself depends on it.

The velocity values at the upper left edge and the stress values at the lower right edge each have a dedicated kernel. At the rightmost column and lowest row, stress has already been computed before the fused kernel runs, in order to send it ahead of the backward halo exchange, so the fused kernel only needs to compute velocity for these points. At the top row and leftmost column, by contrast, the stress values needed for velocity are not yet available when the fused kernel runs, so the fused kernel only computes stress for these points, leaving their velocity to be completed afterward.

Concretely, one timestep is carried out in the following six steps, illustrated in @fig:timestep-stages:

1. `exchange_forward_halos`: velocity is exchanged with the minus-side neighbors, blocking until complete.
2. `update_stress_edges_c`: stress is computed for the thin border strip, using the freshly exchanged velocity.
3. `begin_backward_halos`: the border stress values just computed are sent to the plus-side neighbors, using a non-blocking call that returns immediately.
4. `update_stress_velocity_interior_c`: stress and velocity are fused and tiled for the interior, running while the exchange from step 3 completes in the background. Stress values at the upper left edge are calculated and velocity values for the lower right edge.
5. `finish_backward_halos`: the rank waits for the exchange from step 3 to complete and unpacks the received stress values.
6. `update_velocity_boundary_c`: velocity is computed for the border strip, using the stress values that just arrived.

#figure(
  box(width: 15cm, height: 5.7cm)[
    #let cell = 0.38cm
    #let n = 7

    #let blue = rgb("#006DDC")
    #let red = rgb("#c31834")
    #let orange = rgb("#ffa028")
    #let purple = rgb("#fe00fd")
    #let green = rgb("#1bbc3c")
    #let grey = rgb("#d9d9d9")
    #let stroke-color = 0.4pt + rgb("#888888")

    #let grid1 = (
("BR","BR","BR","BR","BR","BR","I"),
("BR","N","N","N","N","N","TL"),
("BR","N","N","N","N","N","TL"),
("BR","N","N","N","N","N","TL"),
("BR","N","N","N","N","N","TL"),
("BR","N","N","N","N","N","TL"),
("I","TL","TL","TL","TL","TL","TL"),
    )

    #let grid2 = (
      ("G","G","G","G","G","G","I"),
      ("G","O","O","O","O","O","I"),
      ("G","O","O","O","O","O","I"),
      ("G","O","O","O","O","O","I"),
      ("G","O","O","O","O","O","I"),
      ("G","O","O","O","O","O","I"),
      ("I","I","I","I","I","I","I"),
    )

    #let grid3 = (
("TL","TL","TL","TL","TL","TL","I"),
("TL","N","N","N","N","N","BR"),
("TL","N","N","N","N","N","BR"),
("TL","N","N","N","N","N","BR"),
("TL","N","N","N","N","N","BR"),
("TL","N","N","N","N","N","BR"),
("I","BR","BR","BR","BR","BR","BR"),
    )

    #let split-cell-ver(x0, y0, size, left-color, right-color) = {
      place(top + left, dx: x0, dy: y0,
        rect(width: size / 2, height: size, fill: left-color, stroke: none))
      place(top + left, dx: x0 + size / 2, dy: y0,
        rect(width: size / 2, height: size, fill: right-color, stroke: none))
      place(top + left, dx: x0, dy: y0,
        rect(width: size, height: size, fill: none, stroke: stroke-color))
    }
    #let split-cell-hor(x0, y0, size, top-color, bottom-color) = {
    place(top + left, dx: x0, dy: y0,
        rect(width: size, height: size / 2, fill: top-color, stroke: none))
    place(top + left, dx: x0, dy: y0 + size / 2,
        rect(width: size, height: size / 2, fill: bottom-color, stroke: none))
    place(top + left, dx: x0, dy: y0,
        rect(width: size, height: size, fill: none, stroke: stroke-color))
    }


    #let draw-grid(x0, grid) = {
      for i in range(n) {
        for j in range(n) {
          let token = grid.at(i).at(j)
          let x = x0 + j * cell
          let y = 0.7cm + i * cell
        if token == "VS" {
            split-cell-ver(x, y, cell, blue, red)
        }
        else if token == "VSR" {
            split-cell-ver(x, y, cell, red, blue)
        }
        else if token == "HS" {
            split-cell-hor(x, y, cell, blue, red)
        }
        else if token == "HSR" {
            split-cell-hor(x, y, cell, red, blue)
        }
        else {
            let c = if token == "TL" { blue }
            else if token == "BR" { red }
            else if token == "I" { purple }
            else if token == "G" { green }
            else if token == "O" { orange }
            else { grey }
            place(top + left, dx: x, dy: y,
            rect(width: cell, height: cell, fill: c, stroke: stroke-color))
        }
        }
      }
    }

    #let legend-entry(x0, y0, color, label) = {
      place(top + left, dx: x0, dy: y0 + 0.05cm,
        rect(width: 0.3cm, height: 0.3cm, fill: color, stroke: stroke-color))
      place(top + left, dx: x0 + 0.45cm, dy: y0,
        text(size: 8pt)[#label])
    }

    #let gap = 5.3cm

    #place(top + left, dx: 0cm, dy: 0cm,
      box(width: n * cell, align(center, text(size: 9pt, weight: "bold")[Velocity\ Exchange])))
    #draw-grid(0cm, grid1)
    #legend-entry(0cm, 0.7cm + n * cell + 0.4cm, red, "1. Forward Halo Exchange")
    #legend-entry(0cm, 0.7cm + n * cell + 0.85cm, blue, "2. Update Stress Edges")
    #legend-entry(0cm, 0.7cm + n * cell + 1.3cm, purple, "Do Both")

    #place(top + left, dx: gap, dy: 0cm,
      box(width: n * cell, align(center, text(size: 9pt, weight: "bold")[Stress Send +\ Tiling])))
    #draw-grid(gap, grid2)
      #legend-entry(gap, 0.7cm + n * cell + 0.4cm, purple, "3. Begin Backward Halo Exchange")
    #legend-entry(gap, 0.7cm + n * cell + 0.85cm, orange, "4A. Perform Interior Tiling")
    #legend-entry(gap, 0.7cm + n * cell + 1.3cm, green, "4B. Only Compute Stress")
    #legend-entry(gap, 0.7cm + n * cell + 1.75cm, purple, "4C. Only Compute Velocity")

    #place(top + left, dx: 2 * gap, dy: 0cm,
      box(width: n * cell, align(center, text(size: 9pt, weight: "bold")[Stress \ Completion])))
    #draw-grid(2 * gap, grid3)
    #legend-entry(2 * gap, 0.7cm + n * cell + 0.4cm, red, "5. Finish Backward Halo Exchange")
    #legend-entry(2 * gap, 0.7cm + n * cell + 0.85cm, blue, "6. Update Velocity Edges")
    #legend-entry(2 * gap, 0.7cm + n * cell + 1.3cm, purple, "Do Both")
  ],
  caption: [
    The three stages of one timestep, shown for a single rank's local
      subdomain. Cells that are involved in both are colored in two colors. ],
) <fig:timestep-stages>

It is also worth noting that both halo exchanges cannot be hidden behind tiling, since the two exchanges must occur sequentially within a single timestep, while the fused kernel is only run once.


== OpenMP Parallelization

While the previous sections describe how work is distributed across MPI ranks and how tiling reduces the memory traffic within a rank, this section describes how the work within a single rank is further split across the CPU cores available to it using OpenMP.

=== Tile Division

A tile is a portion of the grid for which stress is fully updated first, followed immediately by velocity, before moving on to the next tile in sequence. The purpose of this ordering, as established earlier, is that the newly computed stress values are still resident in cache when they are needed again moments later for the velocity update.

Since each CPU core has its own private L2 cache, a tile is not processed as a single unit but is itself divided into smaller row groups, one per OpenMP thread, so that every thread's share of the tile fits within its own core's cache rather than competing for space in a cache shared across cores. Within a tile, every thread first computes stress for its assigned rows, and only once every thread has finished, enforced by an implicit barrier, does any thread proceed to compute velocity for those same rows, ensuring the required stress values are both correct and still cache resident when they are read again.

How many rows each thread is assigned is therefore not arbitrary, but should be chosen so that the resulting working set, the row width multiplied by the number of fields stored per point and the size of each value, fits somewhat within the L2 cache. Once every thread has advanced through both the stress and velocity update for its rows within a tile, the computation proceeds to the next tile in the same fashion, continuing until the entire local grid has been processed.

=== Two Levels of Parallelism

Within this tiling scheme, each kernel exploits two distinct, nested levels of parallelism, corresponding to the two axes of the local grid. Along $z$, `#pragma omp for` is what actually assigns each thread its own row group within a tile, so that different threads work on entirely different rows at the same time rather than one thread working through the tile alone. Along $x$, the innermost loop over a single row is marked with `#pragma omp simd`, allowing the compiler to vectorize the update of many neighboring points using a single SIMD instruction on one core. These two levels are independent of one another: thread-level parallelism is what distributes row groups across cores in the first place, while SIMD parallelism speeds up the work each individual thread performs on its own assigned rows.

=== Handling the Domain Boundary When Tiling

The very first row of a rank's interior range, as well as the very leftmost column of every row, are treated specially. Their velocity depends on stress from the row directly above or the column directly to the left, both of which belong to the thin edge strip received from a neighboring rank rather than being available locally. The interior kernel therefore computes only stress for these points and skips their velocity entirely, leaving it to be computed later by the boundary kernel, once the corresponding halo data has arrived.

The bottom row and rightmost column are handled differently as well. Their stress is already computed early, by the edge kernel, specifically so that it can be sent to the neighboring rank without delay, and since that same stress value is exactly what their own velocity update needs, velocity for the bottom row and rightmost column is computed within the interior kernel.

=== Parallelizing the Edge Kernels

As was outlined in the MPI section, the stress values of the rightmost column and the bottom row are computed separately, and so are the velocity values of the leftmost column and the top row. These are parallelized with `#pragma omp for simd` for the single full row shared between both points (the bottom row for stress, the top row for velocity), combining thread-level and SIMD parallelism even for this thin strip, and with a plain `#pragma omp for` for the remaining column, which is split across threads point by point rather than vectorized, since its access pattern is too irregular to benefit from SIMD. This ensures that every stage of the timestep, not just the interior, makes use of the available cores, even though the potential speedup is naturally much smaller here given how little work these strips represent relative to the interior.

= Implementation
== Sequential <sec-seq-impl>
This section gives the code behind @seq-pseudo-code, in the order the program executes it.


=== Calling the kernel <seq-calling-kernel>

The kernels are invoked through `ctypes`. NumPy's `ndpointer` declares each argument as a two-dimensional, C-contiguous `float32` array, so the arrays are passed as raw pointers with nothing copied and nothing converted.

#figure(
```python
  _float2 = np.ctypeslib.ndpointer(dtype=np.float32, ndim=2,
                                   flags="C_CONTIGUOUS")

  lib = ctypes.CDLL(kernel_library_path)
  lib.update_stress.argtypes = (
      [_float2] * 9            # vx, vz, sxx, szz, sxz, lam, lam2mu, mu, damp
      + [ctypes.c_float] * 3   # dt, dx, dz
      + [ctypes.c_int] * 6     # nz, nx, iz0, iz1, jx0, jx1
  )
```,
  caption: [
    Binding the C kernel.
  ],
) <lst-ctypes>

The library path is the only place the sequential and parallel drivers differ on the Python side, since each loads its own build of the kernel.

=== Setup 


The model is read with `segyio`, which returns the traces. These are stacked and transposed into $(n_z, n_x)$ order, so that depth is the first index and the horizontal position varies fastest in memory.

#figure(
```python
  def load_segy(path):
      with segyio.open(path, "r", ignore_geometry=True) as f:
          return np.stack([np.array(tr) for tr in f.trace]).T
```,
  caption: [
    Reading one SEG-Y file. The trace geometry is ignored, since only the sample values are required.
  ],
) <lst-segy>

Each field is then padded by $n_b = 240$ cells on every side and the elastic parameters are derived from it. Padding copies the outermost row or column outward rather than inserting a constant, which avoids introducing an artificial contrast at the edge of the physical model.

#figure(
```python
  vp  = pad_field(vp0,  nz, nx, nz0, nx0, pad_top, pad_left)
  vs  = pad_field(vs0,  nz, nx, nz0, nx0, pad_top, pad_left)
  rho = pad_field(rho0, nz, nx, nz0, nx0, pad_top, pad_left)

  mu      = (rho * vs ** 2).astype(np.float32)
  lam     = (rho * vp ** 2 - 2.0 * mu).astype(np.float32)
  lam2mu  = (lam + 2.0 * mu).astype(np.float32)
  inv_rho = (1.0 / rho).astype(np.float32)
```,
  caption: [
    Padding the model and deriving the Lamé parameters. Storing $lambda + 2 mu$ and $1 slash rho$ removes an addition and a division from the inner loop.
  ],
) <lst-material>

The damping array is built next. Each side receives a ramp that rises quadratically towards the outer edge and falls to zero where the absorbing layer meets the physical model. 

#figure(
```python
  def ramp(n, power=2.0):
      return np.linspace(0.0, 1.0, n, dtype=np.float32) ** power

  sigma = np.zeros((nz, nx), dtype=np.float32)
  r = ramp(pad_left)
  for i in range(pad_left):                      # left edge; right and top alike
      sigma[:, i] = np.maximum(sigma[:, i], 60.0 * r[pad_left - 1 - i])
  ...
  r = ramp(pad_bottom)
  for i in range(pad_bottom):                    # bottom absorbs twice as hard
      sigma[-1 - i, :] = np.maximum(sigma[-1 - i, :], 120.0 * r[pad_bottom - 1 - i])

  damp = np.clip(1.0 - sigma * dt, 0.0, 1.0).astype(np.float32)
```,
  caption: [
    Construction of the sponge layer. The right and top edges are omitted, as they mirror the left.
  ],
) <lst-damping>

=== The time loop

The source is a Ricker wavelet evaluated at the current time and added to both diagonal stress components at a single grid point. In the parallel version one rank owns that point; in the sequential case it is always the only rank.


#figure(
```python
  def ricker(self, t):
      a = (np.pi * self.f0 * (t - self.src_t0)) ** 2
      return (1.0 - 2.0 * a) * np.exp(-a)

  src = np.float32(self.src_amp * self.ricker(np.float32(it) * self.dt))
  w.sxx[li, lj] += src
  w.szz[li, lj] += src
```,
  caption: [
    The Ricker source. Adding to $sigma_(x x)$ and $sigma_(z z)$ but not to
    $sigma_(x z)$ renders the source isotropic.
  ],
) <lst-source>

With that in place, the loop itself is four statements.

#figure(
```python
  for it in range(n_iterations):
      inject_ricker_source(sxx, szz, it)          # one grid point
      update_stress_c(vx, vz, sxx, szz, sxz,      # C kernel
                      lam, lam2mu, mu, damp, dt, dx, dz)
      update_velocity_c(vx, vz, sxx, szz, sxz,    # C kernel
                        inv_rho, damp, dt, dx, dz)
      if it % frame_stride == 0:
          write_frame_to_hdf5(vz)
```,
  caption: [The sequential time-stepping loop.],
) <lst-seqloop>

=== The stress kernel 

@lst-stresskernel gives the stress update. It is a loop over rows containing a loop over columns, with the row offsets computed once outside the inner loop and every pointer marked `restrict`, so that the compiler may assume the arrays do not overlap.

#figure(
```c
  for (int i = iz0; i < iz1; ++i) {
      int row  = i * nx;
      int rowp = (i + 1) * nx;          // the row below

      for (int j = jx0; j < jx1; ++j) {
          int k = row + j;

          float dvx_dx = vx[k + 1]     - vx[k];     // forward differences
          float dvx_dz = vx[rowp + j]  - vx[k];
          float dvz_dx = vz[k + 1]     - vz[k];
          float dvz_dz = vz[rowp + j]  - vz[k];

          float sxx_new = sxx[k] + lam2mu[k]*dtx*dvx_dx + lam[k]*dtz*dvz_dz;
          float szz_new = szz[k] + lam[k]*dtx*dvx_dx + lam2mu[k]*dtz*dvz_dz;
          float sxz_new = sxz[k] + mu[k]*(dtz*dvx_dz + dtx*dvz_dx);

          float d = damp[k];            // sponge, folded into the same pass
          sxx[k] = sxx_new * d;
          szz[k] = szz_new * d;
          sxz[k] = sxz_new * d;
      }
  }
```,
  caption: [
    The sequential stress update kernel. The velocity kernel has the same     structure with backward differences, the row above in place of the row below, and two output fields rather than three.
  ],
) <lst-stresskernel>

The loop bounds `iz0`, `iz1`, `jx0` and `jx1` arrive as arguments rather than being derived inside the kernel. This is what allows the parallel version to confine each process to its own tile without a second copy of the code.

= Results
== Sequential Performance
=== Overall Runtime
=== Runtime Breakdown by Program Phase
== Parallel Performance
=== Strong Scaling
*Strong Scaling Single Node*

*Strong Scaling Multi Node*
=== Weak Scaling

When testing weak scaling, the problem size is adjusted in proportion to the compute resources used. How the problem size is adjusted in this case has been detailed in the implementation section. As with strong scaling, weak scaling was again evaluated separately for single node and multi node runs.

*Weak Scaling Single Node*

*Weak Scaling Multi Node*

=== Threads per Rank
=== OpenMP Approaches
=== Compression Approaches

As detailed in the parallelization section, Blosc has been used to parallelize the compression step. Without this, waiting for rank 0 to finish compressing the output on its own was the dominant bottleneck. This bottleneck is examined further in the Vampir section. In addition to parallelizing the compression itself, we also switched from gzip to lz4 as the underlying compression algorithm, since lz4 is substantially faster while still providing a useful reduction in output size.

@fig:compression shows the effect of these two changes on total runtime. Running with no compression at all takes 1085 seconds, which serves as a lower bound on runtime. Compressing with sequential gzip on rank 0 takes 2125 seconds, roughly doubling the runtime compared to no compression at all. Switching the compression algorithm to lz4, while still running it sequentially on rank 0, already reduces this to 1630 seconds, a 23% improvement over gzip. Parallelizing this lz4 compression across ranks using Blosc brings the runtime down further still, to 1154 seconds, a 29% improvement over sequential lz4 and a 46% improvement over the original sequential gzip approach. This is only 6% slower than running with no compression at all.

#figure(
  image("assets/compression.png", width: 90%),
  caption: [
    Runtime comparison using no compression, sequential gzip compression
    on rank 0, sequential lz4 compression on rank 0, and parallel lz4
    compression distributed across ranks via Blosc.
  ],
) <fig:compression>

Without compression, the output totals 70GB, compared to 34GB when using lz4. Despite the runtime cost of compression, this reduction in output size can be considered worthwhile, and this will matter even more once the simulation is scaled to 3D, where the volume of output data grows substantially.

== Trace Based Analysis with Vampir
= Discussion
== Analysis and Bottleneck

The sequential run, using the full resolution grid with no downsampling and 50000 iterations, took [x1] seconds. The fastest parallel run, using 4 nodes with 64 cores each ([x2] total cores), took [x3] seconds. This is a speedup of [x4]x, which is a significant improvement, but only a fraction of the [x5]x increase in compute resources used, corresponding to a parallel efficiency of [x6]%. A noticeably more efficient configuration was the 4-node, 16-core-per-node run, which took [x7] seconds and achieved [x8]% efficiency.

What stands out is how poor the single node scaling was, particularly in comparison to the efficiency of inter-node parallelization using MPI#cite(<Forum1994MPIAM>). The most likely explanation is that memory bandwidth becomes saturated once enough OpenMP#cite(<dagum1998>) threads are placed on a single CPU. Each timestep requires reading and writing all five field arrays, $v_x$, $v_z$, $sigma_(x x)$, $sigma_(z z)$, and $sigma_(x z)$, together with the five precomputed material property arrays, for every grid point, regardless of how much of that data is ultimately written to disk. This amounts to roughly [x9] bytes of memory traffic per grid point per iteration, or approximately [x10] GB in total over the full run, which [is / is not] consistent with saturating the node's peak memory bandwidth of [x11] GB/s. Since all OpenMP threads on a single node share the same memory bus, increasing the thread count beyond a certain point no longer increases throughput once this bandwidth limit is reached, whereas MPI ranks on separate nodes each have access to their own independent memory bandwidth, which is why multi node scaling continued to yield efficiency gains where single node scaling did not.
== Improvements

While the parallelization strategy presented in this work achieves substantial speedups over the sequential baseline, in real world production use, seismic forward modeling are accelerated using GPUs rather than, or in addition to, multi core CPUs. The update kernels used here are a good example of a workload well suited to it. The computation performed at each grid point is simple and identical across the entire grid, with no data dependent branching, which maps naturally onto the thousands of lightweight threads a GPU provides. The bottleneck identified in this work was memory bandwidth rather than arithmetic throughput, and GPUs typically offer severalfold higher memory bandwidth than a CPU socket.

= Conclusion

This work set out to parallelize a two-dimensional elastic wave forward modeling simulation, applied to the Marmousi2 subsurface model, using a combination of MPI and OpenMP, and to evaluate how well this hybrid approach scales across both single node and multi node configurations. The simulation itself solves the elastodynamic wave equation in its velocity-stress formulation, using a second order accurate finite difference scheme built on a grid that is staggered both spatially and temporally, and distributes the computational domain across MPI ranks with a one cell halo exchanged between neighboring ranks each timestep.

The most important finding of this work was that, beyond a certain point, the dominant bottleneck was not computation itself but memory bandwidth. Single node scaling with OpenMP showed strongly diminishing returns as thread count increased, well before all cores on a socket were saturated, while inter-node scaling using MPI continued to scale considerably better, since each additional node brings its own independent memory subsystem rather than contending for a single shared one.

The project was successful: the parallelized implementation achieved a speedup of [insert concrete number]x over the sequential baseline, while preserving the same numerical scheme and the same physical accuracy. Beyond raw runtime improvements, the parallelization of I/O and compression, switching from a single rank writing compressed output to per rank output files compressed in parallel using Blosc, removed what had been one of the most significant bottlenecks in the original implementation, cutting output related runtime substantially without sacrificing the benefit of a smaller output size.

This work delivered a working hybrid MPI and OpenMP implementation of an elastic wave simulation, a systematic strong and weak scaling study across single and multi node configurations, a comparison of compression strategies and their effect on both runtime and output size, and a identified optimizations, namely GPU acceleration and higher order accurate schemes that were not implemented within the scope of this project but represent clear directions for future work. In this project we have shown that the elastic wave forward modeling problem can be effectively parallelized on a CPU cluster, and also where the practical limits of that parallelization lie.
