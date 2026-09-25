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

The velocity field is obtained by numerically solving the elastodynamic wave equation#cite(<aki2002>). Several classes of methods exist for doing so, trading off complexity against accuracy. In this work, a finite difference method is used which approximates each derivative in the governing equations using the difference between nearby values on a grid, rather than the true, continuous derivative, turning the equations into a discrete update rule that can be computed directly.

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
  box(width: 11cm, height: 7cm)[
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
    Layout of a portion of the staggered grid.  ],
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

=== Temporal Staggering

In addition to being staggered in space, the scheme is also staggered in time. Rather than updating stress and velocity from a single shared snapshot of the fields, the two are updated at interleaved half time steps so that each update always consumes the most recently computed values of the other field. This is commonly known as a leapfrog scheme, and it makes the computation second order accurate in time.

== Tiling

As a consequence of the temporal staggering described above, every timestep first advances the velocity fields by half a timestep using the stress values just computed, then advances the stress fields by the next half timestep, using the velocity values just computed. Implemented naively, this ordering can hurt performance. Since the entire velocity field is computed first, sweeping across the full grid, by the time this pass finishes, the values computed early in the sweep have long since been pushed out of the cache to make room for those computed later, as the cache cannot hold the full grid at once. When the stress update immediately afterward needs those same velocity values, most of them are no longer available nearby and must instead be streamed back in from main memory. The resulting cost is especially significant relative to how cheap the underlying arithmetic is.

To remove this bottleneck, this work applies tiling. When using tiling, the grid is divided into many small tiles instead of computing the entire field. For each tile, velocity is computed first, and immediately afterward, while those values are still resident in the cache, the corresponding stress values are computed using them, before the next tile is processed. Only once both fields have been fully advanced for one tile does the computation proceed to the next. In this way, the same round trip to main memory that would otherwise be required twice for every value, once to write it, once to read it back, is reduced to a single round trip, since each value is consumed again while still cheap to access, rather than after it has already been evicted.

= Methodology
== Output

The primary output of the simulation is the vertical particle velocity $v_z$ at every grid point, saved at regular intervals throughout the run rather than only at the final timestep, so that the propagation of the wave through the model can be observed over time rather than only its final state.

Each saved frame is visualized using Matplotlib, rendering $v_z$ as a 2D image over the model domain. Since these frames are saved at fixed intervals, they can be assembled in sequence into a video, producing an animation of the wave as it propagates outward from the source and interacts with the structure of the Marmousi2 model.
== Sequential Design
Every speedup in this report is measured against the sequential solver. It
solves the same equations on the same grid with the same boundary treatment
as the parallel version, and it writes the same output: the vertical
particle velocity $v_z$, saved every hundredth step. Its inner loops are
compiled C rather than interpreted Python, so it is a fair point of
comparison rather than an artificially slow one.

=== Structure of the program

In the following pseudo code, the solver is presented. Setup runs once: it reads the
model, derives the arrays the kernels need, and prepares the output file.
The time loop then repeats four operations for a certain number of times.

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
```
\
\
```c
function update_stress(vx, vz, sxx, szz, sxz, lam, mu, damp, dt):
    for each tile (iz_tile, ix_tile) in domain:
        for i in iz_tile:
            for j in ix_tile:
                update sxx, szz, sxz
                apply damping
function update_velocity(vx, vz, sxx, szz, sxz, invRho, damp, dt):
    for each tile (iz_tile, ix_tile) in domain:
        for i in iz_tile:
            for j in ix_tile:
                update vx, vz
                apply damping
```

The four derived arrays, $mu$, $lambda$, $lambda + 2 mu$ and $1 slash rho$, are
computed once during setup rather than inside the loop. The kernels read
exactly these quantities, so no material property is ever recomputed.
over the grid.

=== The Division Between Python and C

The program is written in two languages. Python reads the three model files, applies padding, derives the elastic parameters, builds the damping ramp, and creates the output file.

C handles the arithmetic, implemented as separate kernels compiled into a shared library and called from Python via `ctypes`. This division exists specifically to enable integration with OpenMP, since expressing the fused, tiled loop structure and thread-level synchronization described in later sections is not practical using vectorized NumPy operations alone.

=== Staggering
In the implementation, this offset is not stored explicitly, there is no separate coordinate array marking a point as "$i+1/2$". Instead, $v_x$, $v_z$, $sigma_(x x)$, $sigma_(z z)$, and $sigma_(x z)$ are all stored as ordinary two dimensional arrays of the same shape, and the staggering exists only implicitly, in which neighboring array index each update kernel reads from. The offset shown in @fig:staggeredgrid is realized purely through the direction of the finite difference used at each point, not through any special indexing scheme.

Concretely, the stress update reads velocity one index ahead, a forward difference, since the velocity powering $sigma_(x x)$ conceptually sits half a cell beyond the current point: $partial v_x \/ partial x$ is approximated as the value of $v_x$ one column to the right minus the value at the current point, divided by $Delta x$, and $partial v_z \/ partial z$ is approximated the same way using the row directly below.

The velocity update reads stress one index behind instead, a backward difference, since the stress powering $v_x$ conceptually sits half a cell before the current point: $partial sigma_(x x) \/ partial x$ is approximated as the value at the current point minus the value one column to the left, and $partial sigma_(x z) \/ partial z$ is approximated the same way using the row directly above.

Both updates perform an ordinary two point finite difference over grid points that are one full grid spacing apart, but because the stress update always looks forward and the velocity update always looks backward, the effective location each result represents is shifted by half a grid spacing relative to its input, without ever needing to track fractional indices.

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
== Setup

*Hardware.* All experiments were run on nodes equipped with Intel Xeon Platinum 8468 ("Sapphire Rapids") processors, with 48 cores per socket and two sockets per node, giving 96 cores per node in total.

*Grid and Model.* Unless stated otherwise, results use the full resolution Marmousi2 grid of $2801 times 13601$ points (@tab-model), padded by 240 cells on each side for the absorbing boundary.

*Timesteps.* The simulation was run for 50000 timesteps.

*Output.* Every 100th frame is being saved giving 500 frames. Results are compressed using lz4.
== Sequential
Throughout this section, `iz0, iz1, jx0, jx1` denote the row and column bounds of the interior range being updated, and `last_i = iz1 - 1`, `last_j = jx1 - 1` denote its final row and column. Since the arrays are stored as flat, row-major buffers, a point at row $i$ and column $j$ sits at flat index `k = i * nx + j`, where `nx` is the number of columns in the local grid, so `k + 1`/`k - 1` reach the neighboring column and `k + nx`/`k - nx` reach the neighboring row. This notation is reused unchanged in the Parallel section below.

//This section describes how the five governing equations introduced in @sec-elastodynamic are translated into the two C kernels referenced in @seq-pseudo-code, `update_stress` and `update_velocity`, and how the staggered grid and tiling strategy described in the Background section are realized concretely in array indexing and loop structure.

=== Staggered Finite Differences

The forward and backward differences described in sec-staggering are implemented directly as two-point array reads. For $sigma_(x x)$, the forward differences of $v_x$ and $v_z$ are computed as:

```c
const float dvx_dx = vx[k + 1]  - vx[k];
const float dvz_dz = vz[k + nx] - vz[k];
```

and for $v_x$, the backward differences of $sigma_(x x)$ and $sigma_(x z)$ are computed as:

#```c
const float dsxx_dx = sxx[k] - sxx[k - 1];
const float dsxz_dz = sxz[k] - sxz[k - nx];
```

=== From Continuous Derivatives to Array Differences

Every term of the form $partial f \/ partial t$ in the governing equations becomes a plain update rule once discretized: $f_"new" = f_"old" + d t dot ("right-hand side")$. Since the right-hand side of every equation is itself built entirely from spatial derivatives, and since $d t \/ d x$ and $d t \/ d z$ appear repeatedly, these two ratios are computed once per kernel call rather than once per grid point:

```c
const float dtx = dt / dx;
const float dtz = dt / dz;
```

Each spatial derivative $partial f \/ partial x$ or $partial f \/ partial z$ is approximated by exactly two neighboring array reads, exploiting the staggered layout established above so that only one grid point in each direction is ever needed, rather than two.

=== The Stress Kernel

`update_stress` implements the three constitutive equations,

$ (∂ sigma_(x x)) / (∂ t) = (lambda + 2 mu) (∂ v_x) / (∂ x) + lambda (∂ v_z) / (∂ z) $
$ (∂ sigma_(z z)) / (∂ t) = lambda (∂ v_x) / (∂ x) + (lambda + 2 mu) (∂ v_z) / (∂ z) $
$ (∂ sigma_(x z)) / (∂ t) = mu ((∂ v_x) / (∂ z) + (∂ v_z) / (∂ x)) $

Since the velocity components sit half a grid spacing ahead of the stress components on the staggered grid, both derivatives use a forward difference, reading the current point and its neighbor one step ahead:

```c
const float dvx_dx = vx[k + 1]  - vx[k];
const float dvx_dz = vx[k + nx] - vx[k];
const float dvz_dx = vz[k + 1]  - vz[k];
const float dvz_dz = vz[k + nx] - vz[k];
```

Each of the three equations is then assembled term for term, using the precomputed Lamé combinations $lambda$, $lambda + 2mu$, and $mu$ read directly from the `lam`, `lam2mu`, and `mu` arrays:

```c
const float sxx_new = sxx[k] + lam2mu[k] * dtx * dvx_dx + lam[k]    * dtz * dvz_dz;
const float szz_new = szz[k] + lam[k]    * dtx * dvx_dx + lam2mu[k] * dtz * dvz_dz;
const float sxz_new = sxz[k] + mu[k]     * (dtz * dvx_dz + dtx * dvz_dx);
```

The absorbing boundary treatment described earlier is applied immediately afterward, by multiplying each updated value by the precomputed damping coefficient at that point before it is written back:

```c
const float d = damp[k];
sxx[k] = sxx_new * d;
szz[k] = szz_new * d;
sxz[k] = sxz_new * d;
```

=== The Velocity Kernel

`update_velocity` implements the two momentum equations,

$ (∂ v_x) / (∂ t) = 1/rho ((∂ sigma_(x x)) / (∂ x) + (∂ sigma_(x z)) / (∂ z)) $
$ (∂ v_z) / (∂ t) = 1/rho ((∂ sigma_(x z)) / (∂ x) + (∂ sigma_(z z)) / (∂ z)) $

Here the roles are reversed: since stress sits half a grid spacing behind velocity on the staggered grid, both derivatives use a backward difference, reading the current point and its neighbor one step behind:

```c
const float dsxx_dx = sxx[k] - sxx[k - 1];
const float dsxz_dz = sxz[k] - sxz[k - nx];
const float dsxz_dx = sxz[k] - sxz[k - 1];
const float dszz_dz = szz[k] - szz[k - nx];
```

The factor $1 \/ rho$ is read directly from the precomputed `inv_rho` array rather than dividing at every point, and the two equations are assembled and damped in the same way as the stress kernel:

```c
const float ir = inv_rho[k];
const float vx_new = vx[k] + ir * (dtx * dsxx_dx + dtz * dsxz_dz);
const float vz_new = vz[k] + ir * (dtx * dsxz_dx + dtz * dszz_dz);
const float d = damp[k];
vx[k] = vx_new * d;
vz[k] = vz_new * d;
```
=== Tiling the Loop Nest

Both kernels sweep the same local grid, but rather than iterating over every row and column in one pass, the iteration space is divided into small tiles, applying the tiling strategy motivated in the Background section. The outer two loops step through the grid in blocks of `tile_z` rows and `tile_x` columns, and only once a tile has been fully advanced does the computation move on to the next one:

```c
for (int ib = iz0; ib < iz1; ib += tile_z) {
    int ie = min(ib + tile_z, iz1);
    for (int jb = jx0; jb < jx1; jb += tile_x) {
        int je = min(jb + tile_x, jx1);
        for (int i = ib; i < ie; ++i) {
            for (int j = jb; j < je; ++j) {
                ...
            }
        }
    }
}
```

Since the sequential baseline runs on a single core, tiling here serves purely as a cache optimization rather than a parallelization strategy. `tile_z` and `tile_x` are chosen so that the working set of the ten arrays involved, five fields and five material properties, for one tile remains small enough to stay resident in the core's own cache while both the stress and velocity update for that tile are computed, rather than being evicted and re-fetched from main memory in between. This is the same tiling technique used in the parallel implementation, applied here without any OpenMP directives, since a single core has no work to divide among threads.

== Parallel

=== MPI

The decomposition search, halo exchange, and six-step execution order described in the Parallel Design section are realized directly in the driver. This section shows how each of those pieces is written in code.

*Building the Cartesian Communicator*

The `(pz, px)` pair chosen by the decomposition search is passed to `Create_cart`, from which each rank derives its coordinates and its four neighbors along both axes:

```python
cart = comm.Create_cart(dims=dims, periods=[False, False], reorder=False)
coord_z, coord_x = cart.Get_coords(rank)
z_minus, z_plus = cart.Shift(0, 1)
x_minus, x_plus = cart.Shift(1, 1)
```

*Forward Exchange*

The forward exchange sends each rank's first real row and column to its minus-side neighbors and receives into the plus-side ghost cells, corresponding to step 1:

```python
def exchange_forward_halos(fields):
    for k, field in enumerate(fields):
        send_x[k] = field[1:-1, 1]
    cart.Sendrecv(send_x, dest=x_minus, recvbuf=recv_x, source=x_plus)
    if x_plus != MPI.PROC_NULL:
        for k, field in enumerate(fields):
            field[1:-1, -1] = recv_x[k]
    # repeated for the z axis using field[1, 1:-1] and field[-1, 1:-1]
```

This is called once, on `[vx, vz]`, before any computation happens in a timestep.

*Backward Exchange*

The backward exchange is split into two calls corresponding to steps 3 and 5, so that the interior can be computed in between. `begin_backward_halos` packs the last real row and column and issues non-blocking sends and receives:

```python
def begin_backward_halos(fields):
    for k, field in enumerate(fields):
        send_x[k] = field[1:-1, -2]
    requests = [
        cart.Irecv(recv_x, source=x_minus, tag=30),
        cart.Isend(send_x, dest=x_plus, tag=30),
    ]
    # repeated for the z axis using field[-2, 1:-1]
    return requests
```

`finish_backward_halos` is called after the interior kernel has run, and only then blocks on the transfer before unpacking the received values into the minus-side ghost cells:

```python
def finish_backward_halos(fields, requests):
    MPI.Request.Waitall(requests)
    if x_minus != MPI.PROC_NULL:
        for k, field in enumerate(fields):
            field[1:-1, 0] = recv_x[k]
    # repeated for the z axis
```

Every kernel call in between passes NumPy arrays directly through `ctypes`, with no copying and no MPI call inside any kernel, so communication and computation remain fully separate at the code level.

=== OpenMP

*Tile Size*

The tile size described in the Parallel Design section is computed once per run by `get_tile_rows`, defaulting to four rows per thread, clamped to between 16 and 256, and overridable through an environment variable for tuning:

```c
int rows = 4 * omp_get_max_threads();
if (rows < 16)  rows = 16;
if (rows > 256) rows = 256;
```

*The Tiled Loop*

`update_stress_velocity_interior` opens a single `#pragma omp parallel` region around the entire tile loop, so the thread team is created once per kernel call rather than once per tile. Each iteration of the outer loop processes one tile, `ib` to `ie`, first computing stress for every row in the tile, then, in a second `#pragma omp for`, computing velocity for the same rows:

```c
#pragma omp parallel
{
    for (int ib = iz0; ib < last_i; ib += tile_rows) {
        int ie = min(ib + tile_rows, last_i);
        #pragma omp for schedule(static)
        for (int i = ib; i < ie; ++i) {
            stress_row(vx, vz, sxx, szz, sxz, lam, lam2mu, mu, damp,
                       dtx, dtz, nx, i, jx0, last_j);
        }
        #pragma omp for schedule(static)
        for (int i = max(ib, iz0 + 1); i < ie; ++i) {
            velocity_row(vx, vz, sxx, szz, sxz, inv_rho, damp,
                         dtx, dtz, nx, i, jx0 + 1, jx1);
        }
    }
}
```

`schedule(static)` divides `[ib, ie)` into contiguous, equally sized blocks decided once for the loop, so a thread is assigned the same rows in the velocity loop that it just computed stress for in the loop above. Since both loops sit inside the same `#pragma omp parallel` region, the implicit barrier at the end of the first `#pragma omp for` is what enforces the ordering: every thread has finished writing stress for the entire tile before any thread starts reading it in the second loop, without any explicit synchronization being written. The velocity loop starts one row later than the stress loop (`max(ib, iz0 + 1)`) and one column later (`jx0 + 1`), since the very first row and column of the interior range depend on halo data and are deferred to the boundary kernel, as described above. After the tile loop finishes, one further `#pragma omp for simd` pass computes velocity for the interior's last row, whose stress was already available locally.

*Inside a Row*

`stress_row` and `velocity_row` receive the row index `i` and the column bounds from the loop above and compute the flat row offset once before iterating over columns:

```c
static inline void stress_row(..., int i, int jx0, int jx1) {
    const int row = i * nx;
    const int rowp = row + nx;
    #pragma omp simd
    for (int j = jx0; j < jx1; ++j) {
        const int k = row + j;
        ...
    }
}
```

By the time this function runs, `#pragma omp for` has already assigned row `i` to exactly one thread, so `#pragma omp simd` here only vectorizes across `j`, the columns of that single row, rather than distributing work across threads itself.

*Edge and Boundary Kernels*

`update_stress_edges` and `update_velocity_boundary` each open their own, shorter `#pragma omp parallel` region, since they run only once per timestep rather than once per tile. In both, the single full row (the bottom row for stress, the top row for velocity) is parallelized with `#pragma omp for simd`, combining both levels directly on one loop:

```c
#pragma omp for simd schedule(static)
for (int j = jx0; j < jx1; ++j) {
    const int k = last_i * nx + j;
    ...
}
```

The remaining column, one point per row, is handled by a separate point-wise helper (`stress_point`, `velocity_point`) and split across threads with a plain `#pragma omp for`, without vectorization, since a single point per iteration gives the compiler nothing to vectorize:

```c
#pragma omp for schedule(static)
for (int i = iz0; i < last_i; ++i) {
    stress_point(vx, vz, sxx, szz, sxz, lam, lam2mu, mu, damp,
                 dtx, dtz, nx, i, last_j);
}
```

= Results
== Sequential Performance
=== Overall Runtime
=== Runtime Breakdown by Program Phase
== Parallel Performance

=== Strong Scaling
When measuring strong scaling, the problem size remains constant while compute resources are increased.

*Strong Scaling Single Node*

@fig:strong_sn hows that the resulting curve has the characteristic roofline shape commonly seen in performance measurements. Speedup rises with core count up to a point, then flattens. What stands out here is how early this plateau occurs, with little further improvement beyond 64 cores.

#figure(
  image("assets/strong_sn.png", width: 90%),
  caption: [
  ],
) <fig:strong_sn>

We attribute this to memory bandwidth becoming saturated. This result is somewhat disappointing, since tiling was introduced specifically to address this bottleneck, and while it did improve performance significantly, and even scaling to a small degree, it did not eliminate the plateau as we had hoped.

Other explanations for this plateau are less consistent with the data. If threads within a rank were split across the node's two CPU sockets, this would introduce additional latency from cross-socket memory access. This cannot be the dominant effect here, however, since the 64 core configuration already places a rank's threads across both sockets, yet shows no comparable drop in performance at that point. Reduced per-core turbo frequency at higher active core counts is similarly unlikely to explain the plateau, since it would degrade performance gradually as more cores become active, rather than producing the sharp cliff observed here.

*Strong Scaling Multi Node*

What stands out in the multi node strong scaling benchmark @fig:strong_mn is that performance does not saturate in the same way when additional nodes are added, despite the added MPI communication overhead this introduces. This supports our earlier interpretation of the single node results. Since each additional node provides its own independent memory bandwidth, rather than sharing a single pool of it as additional cores on the same node do, the absence of a similar plateau here suggests that memory bandwidth, and not communication, was indeed the limiting factor within a single node, especially since the communication in a single node is much faster than between nodes.

#figure(
  image("assets/strong_mn.png", width: 90%),
  caption: [
  ],
) <fig:strong_mn>


=== Weak Scaling

When testing weak scaling, the problem size is adjusted in proportion to the compute resources used. How the problem size is adjusted in this case has been detailed in the implementation section. As with strong scaling, weak scaling was again evaluated separately for single node and multi node runs.

*Weak Scaling Single Node*
What is interesting is that scaling is somewhat better when using weak scaling seen in @fig:weak_sn. This is still consistent with the memory bandwidth theory since the data is fewer and the ceiling not reached.

#figure(
  image("assets/weak_sn.png", width: 90%),
  caption: [
  ],
) <fig:weak_sn>

*Weak Scaling Multi Node*

#figure(
  image("assets/weak_mn.png", width: 90%),
  caption: [
  ],
) <fig:weak_mn>

=== Threads per Rank
//@fig:tpr shows how performance differs for the same 96 cores depending on the amound of ranks they are distributed.
=== OpenMP Approaches
//Other OpenMP approaches were tried as well to see which performs the best. They are shown in @fig:omp . Ultimately, the tiling strategy outlined above has shown to perform the best.
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

Additionally, the memory bandwidth restriction remains unproven. LIKWID was used to attempt to measure memory bandwidth usage, we used `likwid-perfctr` with the `MEM` performance group on the stencil kernel. While core-level counters (instruction and cycle counts) were read correctly, the memory-controller counters required for bandwidth computation consistently returned zero. Verbose diagnostic output revealed that these counters were never actually queried by LIKWID, suggesting a permissions restriction.

= Conclusion

This work set out to parallelize a two-dimensional elastic wave forward modeling simulation, applied to the Marmousi2 subsurface model, using a combination of MPI and OpenMP, and to evaluate how well this hybrid approach scales across both single node and multi node configurations. The simulation itself solves the elastodynamic wave equation in its velocity-stress formulation, using a second order accurate finite difference scheme built on a grid that is staggered both spatially and temporally, and distributes the computational domain across MPI ranks with a one cell halo exchanged between neighboring ranks each timestep.

The most important finding of this work was that, beyond a certain point, the dominant bottleneck was not computation itself but memory bandwidth. Single node scaling with OpenMP showed strongly diminishing returns as thread count increased, well before all cores on a socket were saturated, while inter-node scaling using MPI continued to scale considerably better, since each additional node brings its own independent memory subsystem rather than contending for a single shared one.

The project was successful: the parallelized implementation achieved a speedup of [insert concrete number]x over the sequential baseline, while preserving the same numerical scheme and the same physical accuracy. Beyond raw runtime improvements, the parallelization of I/O and compression, switching from a single rank writing compressed output to per rank output files compressed in parallel using Blosc, removed what had been one of the most significant bottlenecks in the original implementation, cutting output related runtime substantially without sacrificing the benefit of a smaller output size.

This work delivered a working hybrid MPI and OpenMP implementation of an elastic wave simulation, a systematic strong and weak scaling study across single and multi node configurations, a comparison of compression strategies and their effect on both runtime and output size, and a identified optimizations, namely GPU acceleration and higher order accurate schemes that were not implemented within the scope of this project but represent clear directions for future work. In this project we have shown that the elastic wave forward modeling problem can be effectively parallelized on a CPU cluster, and also where the practical limits of that parallelization lie.
