= Introduction
Seismic wave forward modeling is the numerical simulation of how seismic waves propagate through a given earth model. It is used in applications ranging from earthquake hazard assessment and ground motion prediction to subsurface imaging in exploration geophysics. It is also a core building block of inverse problems such as full waveform inversion and seismic tomography, where synthetic waveforms produced by forward modeling are compared against observed data to iteratively refine an estimate of the subsurface.

Solving the elastodynamic wave equation numerically is most commonly done through discretization schemes such as the finite-difference method, in which the spatial and temporal derivatives of the equations are approximated on a grid. Accurately capturing the frequency content and spatial detail required for realistic wave propagation demands high computational power and, in particular, large amounts of memory. While the computation performed at each grid point is simple, many such points need to be updated over many iterations to satisfy the numerical stability conditions required to produce accurate results.

As a result, researchers and industry participants rely on HPC datacenters and the tools available on them to perform these computations within a reasonable amount of time. In modern HPC, this largely comes down to parallelization frameworks such as OpenMP and MPI, which allow a developer to split the workload across multiple cores within a node and across multiple nodes in a cluster, respectively. Using both together makes it possible to scale a simulation well beyond what a single machine could handle, provided the workload is divided and coordinated correctly.

One major application of this kind of modeling that is commonly performed with parallelization is in the oil and gas industry. To characterize the subsurface and locate oil and gas reservoirs, pressure is generated at the surface, and the resulting waves traveling through the ground or water are recorded. From these measurements, an approximate model of the subsurface is constructed. Forward modeling is then run on that model to simulate the resulting wave propagation, and the outcome is compared against the actual measurements to assess how closely the model matches reality.

To ground this in a concrete case, the numerical scheme and parallelization strategy examined in this work are applied to the Marmousi2 model, a widely used subsurface model derived from a profile of the North Quenguela trough in the Kwanza Basin, Angola. The goal of our computation is to visualize how a wave travels through this model, displaying the velocity of the medium resulting from a pressure wave injected at the surface.

The remainder of this paper is structured as follows: we first describe
the numerical scheme used for forward modeling and explain how it can be
implemented sequentially, after which we detail how the domain is
decomposed and parallelized using MPI and OpenMP. We then present
performance results obtained on an HPC cluster, examining how the
implementation scales with an increasing number of processes and cores.
Finally, we will discuss these results and potential future work.

= Background
== Marmousi2 Model
== Elastodynamic wave equation in velocity-stress formulation
Ultimately, the data computed by the simulation represents the particle velocity at every point in the material at every timestep, which is used to visualize how the wave travels through the medium. Since the source and the receivers of interest are placed near the surface, the waves of interest primarily travel upward, so the velocity component of interest is the one aligned with that direction, the vertical velocity $v_z$. This also mirrors real seismic acquisition, where a receiver placed on the surface predominantly measures the vertical component of ground motion from an upward-arriving wave.

Computing this velocity field requires solving the elastic wave equation, and different numerical approaches exist for doing so, trading off complexity against accuracy. In this work, we use a second order accurate finite difference scheme.

The Marmousi2 model provides the P-wave velocity $v_p$, the S-wave velocity $v_s$, and the mass density $rho$ at every point of a realistic, geologically structured subsurface model. From these three quantities, we ultimately want to compute the velocity components $v_x$ and $v_z$ and the stress components $sigma_(x x)$, $sigma_(z z)$, and $sigma_(x z)$ at every grid point and every timestep. To do so, the elastic update equations additionally require the Lamé parameters $lambda$ and $mu$, which are not provided directly by the model but can be derived from $v_p$, $v_s$, and $rho$ using the isotropic elastic relations

$ v_p = sqrt((lambda + 2mu) / rho), quad v_s = sqrt(mu / rho) $

Solving the second equation for $mu$ gives

$ mu = rho v_s^2 $

Substituting this into the first equation and solving for $lambda$ gives

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
== Staggering
=== Concept and Terminology
To increase the accuracy of the computation, staggering is applied. Staggering refers to deliberately storing or updating different quantities at offset positions, rather than at the same point, whether that offset is in space or in time. The two staggered quantities are never evaluated at exactly the same location, but each is placed exactly halfway between two locations of the other. As shown below, this offset is what allows the finite differences used to update each field to reach second order accuracy without requiring a wider stencil  .

=== Second order accuracy

Any time a continuous derivative is approximated using a finite difference, some error is introduced, since the approximation only uses a finite number of nearby values instead of the true, continuous function. The order of accuracy describes how quickly this error shrinks as the discretization is refined, that is, as the grid spacing $Delta$ or timestep $"dt"$ is made smaller. A first order accurate scheme has an error that shrinks proportionally to $Delta$ itself. Halving the spacing only halves the error. A second order accurate scheme has an error that shrinks proportionally to $Delta^2$. Halving the spacing quarters the error. This means that for a small refinement, a second order scheme becomes accurate much faster than a first order one, since its error decreases quadratically rather than linearly as the discretization is refined.

This distinction matters in practice because it directly affects how fine a grid or timestep is needed to reach a given accuracy target. A first order scheme generally requires a much finer discretization, and correspondingly far more computation, to reach the same accuracy as a second order scheme. Both the spatial and temporal staggering described below are specifically what allow the finite difference scheme used in this work to achieve second order accuracy, rather than being limited to first order, without requiring a wider, more expensive stencil.

=== Spatial Staggering

The finite difference scheme used to update the velocity and stress fields is applied on a spatially staggered grid, commonly referred to as a Virieux grid. Rather than storing all five field components, $v_x$, $v_z$, $sigma_(x x)$, $sigma_(z z)$, and $sigma_(x z)$, at the same physical location within a grid cell, each component is instead stored at a position offset by half a grid spacing relative to the others. Concretely, the normal stresses $sigma_(x x)$ and $sigma_(z z)$ are defined at integer grid points $(i, j)$, the horizontal velocity $v_x$ is defined half a cell to the side at $(i, j+1/2)$, the vertical velocity $v_z$ is defined half a cell below at $(i+1/2, j)$, and the shear stress $sigma_(x z)$ is defined half a cell in both directions at $(i+1/2, j+1/2)$.
#figure(
  box(width: 11cm, height: 8cm)[
    #let cell = 2.5cm
    #let pad = 1.5cm
    #let r = 0.16cm

    #let sxx-color = rgb("#3050a0")
    #let vx-color = rgb("#c85a1e")
    #let vz-color = rgb("#2a8a2a")
    #let sxz-color = rgb("#8a2ab0")

    #let px(i) = pad + i * cell
    #let py(j) = pad + j * cell

    // dashed grid lines connecting integer (stress) points
    #for j in range(3) {
      place(top + left, dx: px(0), dy: py(j),
        line(start: (0cm, 0cm), end: (2 * cell, 0cm), stroke: (paint: gray, thickness: 0.6pt, dash: "dashed")))
    }
    #for i in range(3) {
      place(top + left, dx: px(i), dy: py(0),
        line(start: (0cm, 0cm), end: (0cm, 2 * cell), stroke: (paint: gray, thickness: 0.6pt, dash: "dashed")))
    }

    // sigma_xx, sigma_zz at integer points (i, j)
    #for j in range(3) {
      for i in range(3) {
        place(top + left, dx: px(i) - r, dy: py(j) - r,
          circle(radius: r, fill: sxx-color))
      }
    }

    // v_x at (i, j + 1/2)
    #for j in range(3) {
      for i in range(2) {
        place(top + left, dx: px(i) + cell / 2 - r, dy: py(j) - r,
          circle(radius: r, fill: vx-color))
      }
    }

    // v_z at (i + 1/2, j)
    #for j in range(2) {
      for i in range(3) {
        place(top + left, dx: px(i) - r, dy: py(j) + cell / 2 - r,
          circle(radius: r, fill: vz-color))
      }
    }

    // sigma_xz at (i + 1/2, j + 1/2)
    #for j in range(2) {
      for i in range(2) {
        place(top + left, dx: px(i) + cell / 2 - r, dy: py(j) + cell / 2 - r,
          circle(radius: r, fill: sxz-color))
      }
    }

    // field labels
    #place(top + left, dx: px(1) + 0.25cm, dy: py(1) - 0.55cm,
      text(size: 8pt, fill: sxx-color)[$sigma_(x x), sigma_(z z)$])
    #place(top + left, dx: px(0) + cell / 2 - 0.35cm, dy: py(1) - 0.55cm,
      text(size: 8pt, fill: vx-color)[$v_x$])
    #place(top + left, dx: px(1) + 0.2cm, dy: py(0) + cell / 2 - 0.15cm,
      text(size: 8pt, fill: vz-color)[$v_z$])
    #place(top + left, dx: px(0) + cell / 2 + 0.2cm, dy: py(0) + cell / 2 - 0.15cm,
      text(size: 8pt, fill: sxz-color)[$sigma_(x z)$])

    // axis labels
    //#place(top + left, dx: px(2) + 0.6cm, dy: py(0) - 0.15cm, text[$x$])
    //#place(top + left, dx: px(0) - 0.15cm, dy: py(2) + 0.6cm, text[$z$])

    // grid index annotation on the middle point instead of the corner
    #place(top + left, dx: px(1) + 0.2cm, dy: py(1) + 0.15cm,
      text(size: 8pt, fill: black)[$(i,j)$])
    #place(top + left, dx: px(2) + 0.25cm, dy: py(2) - 5.00cm,
      text(size: 8pt, fill: black)[$(i + 1,j + 1)$])
  ],
  caption: [
    Layout of one unit cell of the staggered grid. The normal stresses
    $sigma_(x x)$ and $sigma_(z z)$ are stored at integer grid points
    $(i,j)$. The horizontal velocity $v_x$ is offset by half a grid
    spacing along $x$, the vertical velocity $v_z$ is offset by half a
    grid spacing along $z$, and the shear stress $sigma_(x z)$ is offset
    by half a grid spacing in both directions.
  ],
) <fig:staggeredgrid>

Placing the two fields on interleaved, offset grids means that whenever a derivative is needed, it is computed from the two nearest neighboring points on the opposite field's grid:
- $v_x$ at $(i, j+1/2)$: needs $sigma_(x x)(i,j+1) - sigma_(x x)(i,j)$ and $sigma_(x z)(i+1\/2,j+1\/2) - sigma_(x z)(i-1\/2,j+1\/2)$

- $v_z$ at $(i+1/2, j)$: needs $sigma_(x z)(i+1\/2,j+1\/2) - sigma_(x z)(i+1\/2,j-1\/2)$ and $sigma_(z z)(i+1,j) - sigma_(z z)(i,j)$

- $sigma_(x x)$, $sigma_(z z)$ at $(i, j)$: need $v_x (i,j+1\/2) - v_x (i,j-1\/2)$ and $v_z (i+1\/2,j) - v_z (i-1\/2,j)$

- $sigma_(x z)$ at $(i+1/2, j+1/2)$: needs $v_x (i+1,j+1\/2) - v_x (i,j+1\/2)$ and $v_z (i+1\/2,j+1) - v_z (i+1\/2,j)$
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

= Implementation
== Sequential

== Parallel
=== Parallelization Coverage

*What was not parallelized*

- *Time stepping loop.* The main loop advances the stress and velocity fields one iteration at a time, and each timestep depends on the result of the previous one. This dependency is the Amdahl bottleneck. Because of it the loop over time cannot be parallelized itself, only the work done within a single timestep can be.

- *One time setup.* Reading the SEGY model files, computing the Lame parameters, building the PML damping profile and determining the domain decomposition all happen once before the time loop starts. This is currently repeated on every rank rather than distributed, since the cost is negligible compared to the roughly 50000 timesteps that follow. The final assembly of the per rank output files into one virtual HDF5 dataset also happens once, done serially by rank 0 after every rank has finished writing. Since this step only links metadata together using VirtualSource rather than copying any data, it finishes almost instantly.

- *Pressure injection.* The source term is injected at a single grid point, so only the rank that owns this point performs the update. This step cannot be parallelized any further, and the resulting overhead is negligible.

*What was parallelized*

- *Domain decomposition.* The global grid is split across MPI ranks using a 2D Cartesian topology built with Compute_dims and Create_cart. Each rank owns a rectangular subdomain plus a one cell halo. Neighboring ranks exchange halo values for the stress and velocity fields every timestep using Sendrecv calls.

- *Stress and velocity updates.* Inside each rank's subdomain, the update kernels update_stress and update_velocity are written in C and parallelized with OpenMP. Combined with the MPI domain decomposition, this hybrid MPI and OpenMP scheme forms the main strategy of our parallelization.

- *HDF5 output.* Each rank writes its own wavefield snapshots to an independent file. This avoids the bottleneck that would occur if every rank had to send its data through rank 0 for writing.

- *Compression.* Blosc is used to compress the output data with OpenMP threads handling the compression work in parallel. Before this change, compression was performed by a single rank, meaning all other ranks were forced to wait idly until rank 0 finished compressing its share of the data before the program could proceed. Parallelizing compression with Blosc removed this serial bottleneck and led to a significant improvement in scaling performance.

=== Domain Decomposition and Halo Exchange

The padded global grid of size $n_z times n_x$ is distributed across MPI ranks by arranging them on a two-dimensional Cartesian topology. Rather than relying on the default balancing provided by `MPI_Dims_create`, we search over all factor pairs $(p_z, p_x)$ of the process count and choose the pair that minimizes $n_z / p_z + n_x / p_x$. Since the cost of the halo exchange scales with the perimeter of a subdomain, this avoids long, thin tiles that would otherwise increase communication relative to computation. Within each dimension, the grid is then split as evenly as possible, so that no rank is assigned a disproportionately large share of the domain and no rank becomes a bottleneck.

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

As detailed earlier, the grid is staggered spatially, meaning that the velocity and stress components are not stored at the same physical location but are offset from one another by half a grid spacing. Physically, this means that a velocity value is treated as living midway between two neighboring stress points, rather than coinciding with them. This does not just provide improved accuracy, it also cuts the data that has to be exchanged via MPI in half. Because each velocity value sits between two stress points rather than on top of one, computing the spatial derivative needed to update it only requires the single stress value immediately behind it, not the values on both the left and the right. The same holds in reverse for updating stress from velocity. As a result, each rank only ever needs a neighboring value from one direction per axis instead of two, so only one side needs to be communicated for a given field, rather than both. Concretely, without staggering all five fields would require neighbor values from both directions along each axis, giving ten directional transfers per axis, whereas with staggering the two velocity fields only require one direction and the three stress fields only require the other, giving five. Since the stencils used are otherwise compact, reaching only one grid point in each required direction, the halo itself remains a single ghost cell wide regardless of staggering, staggering only changes which side that one cell comes from.

Two separate exchanges are still required per timestep, one for the velocity fields and one for the stress fields, but this is a consequence of the temporal staggering rather than of the spatial staggering itself. The stress fields must be fully updated using the exchanged velocity values before they can, in turn, be exchanged and used to update velocity. Spatial staggering therefore determines the direction and amount of data in each of these two exchanges, not the fact that two are needed in the first place.

#figure(
  box(width: 16cm, height: 8.5cm)[
    #let panel(x0, mirror, title) = {
      let s = 3cm       // rank body size
      let h = 0.4cm     // halo strip thickness
      let dy0 = 2.4cm   // vertical offset of the square within the panel

      let green-fill = rgb("#c8f5c8")
      let green-stroke = rgb("#2a8a2a")
      let red-fill = rgb("#f5d0d0")
      let red-stroke = rgb("#b5342a")

      // top-left sides vs bottom-right sides swap color depending on mirror
      let tl-color = if mirror { (green-fill, green-stroke) } else { (red-fill, red-stroke) }
      let br-color = if mirror { (red-fill, red-stroke) } else { (green-fill, green-stroke) }

      // title
      place(top + left, dx: x0, dy: 0.9cm,
        box(width: s + 2 * h, align(center, text(size: 9pt)[#title])))

      // rank body
      place(top + left, dx: x0 + h, dy: dy0 + h,
        rect(width: s, height: s, fill: rgb("#c8d8f5"), stroke: 1pt + rgb("#3050a0")))

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

At a high level, one of these two exchanges can be summarized as follows:

```
function exchange_forward(fields)
    for f in fields
        send_x[f] = f[first_real_column]
        send_z[f] = f[first_real_row]

    Sendrecv(send_x, dest = x_minus, recv = recv_x, source = x_plus)
    Sendrecv(send_z, dest = z_minus, recv = recv_z, source = z_plus)

    for f in fields
        f[last_ghost_column] = recv_x[f]
        f[last_ghost_row]    = recv_z[f]
```

In the implementation, the neighboring ranks are obtained directly from the Cartesian communicator with a single call per axis:

```python
z_minus, z_plus = cart.Shift(0, 1)
x_minus, x_plus = cart.Shift(1, 1)
```

The exchange itself is then carried out with a combined send-and-receive operation. For example, for the $x$ direction of the forward pass:

```python
cart.Sendrecv(
    send_minus, dest=x_minus, sendtag=10,
    recvbuf=recv_plus, source=x_plus, recvtag=10
)
```

When a neighboring rank does not exist because a rank lies on the edge of the global grid, `cart.Shift` returns `MPI.PROC_NULL` for that side. The corresponding `Sendrecv` is therefore a no-op, leaving the PML boundary values in place rather than replacing them with data from a nonexistent neighboring subdomain.

=== OpenMP

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

What stands out is how poor the single node scaling was, particularly in comparison to the efficiency of inter-node parallelization using MPI. The most likely explanation is that memory bandwidth becomes saturated once enough OpenMP threads are placed on a single CPU. Each timestep requires reading and writing all five field arrays, $v_x$, $v_z$, $sigma_(x x)$, $sigma_(z z)$, and $sigma_(x z)$, together with the five precomputed material property arrays, for every grid point, regardless of how much of that data is ultimately written to disk. This amounts to roughly [x9] bytes of memory traffic per grid point per iteration, or approximately [x10] GB in total over the full run, which [is / is not] consistent with saturating the node's peak memory bandwidth of [x11] GB/s. Since all OpenMP threads on a single node share the same memory bus, increasing the thread count beyond a certain point no longer increases throughput once this bandwidth limit is reached, whereas MPI ranks on separate nodes each have access to their own independent memory bandwidth, which is why multi node scaling continued to yield efficiency gains where single node scaling did not.
== Improvements

While the parallelization strategy presented in this work achieves substantial speedups over the sequential baseline, several further improvements were identified over the course of this project that were not implemented yet.

*GPU acceleration.* In real world production use, seismic forward modeling are accelerated using GPUs rather than, or in addition to, multi core CPUs. The update kernels used here are a good example of a workload well suited to it. The computation performed at each grid point is simple and identical across the entire grid, with no data dependent branching, which maps naturally onto the thousands of lightweight threads a GPU provides. The bottleneck identified in this work was memory bandwidth rather than arithmetic throughput, and GPUs typically offer severalfold higher memory bandwidth than a CPU socket.

*Communication and computation overlap.* As discussed in the parallelization section, the current implementation performs a blocking halo exchange before each kernel call. Splitting each rank's subdomain into an interior region, which does not depend on data from neighboring ranks, and a thin boundary region, which does, would allow the interior to be computed using non blocking MPI calls while the halo exchange for the boundary is still in flight. This was partially explored in the interior and boundary tiling scheme described earlier, but extending it to fully overlap communication with computation was not pursued further, since the expected gain is bounded by the fraction of runtime spent on communication latency, which appeared to be small relative to the memory bandwidth cost of the kernels themselves.

*Higher order accurate schemes.* The scheme used in this work is second order accurate in both space and time, achieved through spatial and temporal staggering. Higher order finite difference schemes, for example fourth or eighth order accurate in space, are commonly used in production seismic modeling codes, since they allow a coarser grid to be used for the same accuracy, directly reducing both memory footprint and computation. While this could have been done, this improvement is not related to parallelization so it was not the focus of this project.
