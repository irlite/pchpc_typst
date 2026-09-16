#import "helpers.typ": *

#set math.equation(numbering: "(1)")

= Background <sec-background>

This section sets up the equations we solve and the way we divide them.
// Readers who only care about the parallelisation can skip to //@sec-parallel
// , but @sec-staggered is worth reading first, because the direction of the
// finite-difference stencil is what makes the halo exchange in //@sec-halo 
// cheaper
// than a textbook four-way exchange.

== Forward modelling <sec-forward>

Forward modelling takes a subsurface with known material properties and computes what a receiver at the surface would record. The reverse problem, working out the properties from real recordings, is solved by running the forward problem over and over inside an optimisation loop. This report covers only the forward step, which is where almost all the arithmetic is.

The material properties that matter for elastic waves are three scalar fields:
the compressional wave speed $v_p$, the shear wave speed $v_s$, and the density
$rho$. From these the Lamé parameters follow directly,

$ mu = rho v_s^2, quad lambda = rho v_p^2 - 2 mu. $ <eq-lame>

Our implementation precomputes $mu$, $lambda$, $lambda + 2 mu$ and $1 slash rho$
once during setup, so the time loop never divides and never squares a velocity.

== The elastic wave equation in velocity-stress form <sec-elastic>

The second-order elastic wave equation can be written as a first-order system in
particle velocity and stress, which is the form Virieux introduced for finite
differences and the one almost every modern code uses //@virieux1986
. In two dimensions with coordinates $x$ (horizontal) and $z$ (depth), the unknowns are
the particle velocities $v_x, v_z$ and the stress components
$sigma_(x x), sigma_(z z), sigma_(x z)$. Momentum conservation gives

$
  rho (partial v_x) / (partial t) &= (partial sigma_(x x)) / (partial x) + (partial sigma_(x z)) / (partial z), \
  rho (partial v_z) / (partial t) &= (partial sigma_(x z)) / (partial x) + (partial sigma_(z z)) / (partial z),
$ <eq-momentum>

and Hooke's law for an isotropic elastic medium gives

$
  (partial sigma_(x x)) / (partial t) &= (lambda + 2 mu) (partial v_x) / (partial x) + lambda (partial v_z) / (partial z), \
  (partial sigma_(z z)) / (partial t) &= lambda (partial v_x) / (partial x) + (lambda + 2 mu) (partial v_z) / (partial z), \
  (partial sigma_(x z)) / (partial t) &= mu ((partial v_x) / (partial z) + (partial v_z) / (partial x)).
$ <eq-hooke>

Five fields, five equations, and every right-hand side is a first spatial
derivative of the other set of fields. That structure is what makes the scheme
easy to parallelise: the equations couple velocities to stresses and back, but
they never couple a point to anything except its immediate spatial neighbours.

The elastic system is the more expensive choice. An acoustic formulation carries
one pressure field and one velocity pair and ignores shear entirely. We used the
elastic system because Marmousi2 ships with an S-wave velocity field, and
because converted waves and shear arrivals are the part of the record that the
acoustic approximation throws away. The price is five fields instead of three
and roughly twice the memory traffic per point.

== Discretisation on a staggered grid <sec-staggered>

We discretise @eq-momentum and @eq-hooke on a uniform grid with spacing
$Delta x = Delta z = 1.25 "m" dot s$, where $s$ is an integer downsampling factor
applied when reading the model, and advance in time with a leapfrog scheme:
stresses are updated from velocities, then velocities from the new stresses.
Spatial derivatives are second-order differences between adjacent cells, which
on a staggered grid means each field lives at a slightly different position
within the cell.

The choice that matters for everything downstream is the direction of the
differences. In our stress update, every derivative is a _forward_ difference,

$
  lr((partial v_x) / (partial x) |)_(i,j) approx (v_x [i, j+1] - v_x [i, j]) / (Delta x), quad
  lr((partial v_x) / (partial z) |)_(i,j) approx (v_x [i+1, j] - v_x [i, j]) / (Delta z),
$ <eq-fwd-partial>

while in the velocity update every derivative is a _backward_ difference,

$
  lr((partial sigma_(x x)) / (partial x) |)_(i,j) approx (sigma_(x x) [i, j] - sigma_(x x) [i, j-1]) / (Delta x), quad
  lr((partial sigma_(x z)) / (partial z) |)_(i,j) approx (sigma_(x z) [i, j] - sigma_(x z) [i-1, j]) / (Delta z).
$ <eq-bwd-partial>

Here $i$ indexes depth and $j$ indexes the horizontal direction, and both
increase downward and to the right respectively.

@fig-stencil shows the consequence. To update the stresses at a point we need
velocities at that point, at the point to its right, and at the point below it.
To update the velocities we need stresses at that point, at the point to its
left, and at the point above it. Neither update needs all four neighbours. When
the grid is cut into tiles, a rank therefore needs velocity values only from its
right and bottom neighbours before the stress update, and stress values only
from its left and top neighbours before the velocity update. //@sec-halo
 turns
that observation into half the messages.

#figure(
  stencil-figure(),
  kind: image,
  caption: [
    Which neighbours each kernel reads. The black dot is the point being
    written. Because the two updates lean in opposite directions, a rank never
    needs data from all four neighbours at the same moment.
  ],
) <fig-stencil>

== Time step and stability <sec-stability>

An explicit scheme is only stable if a wave cannot cross more than a fraction of
a cell per time step, the Courant-Friedrichs-Lewy (CFL) condition. We set

$ Delta t = 0.4 (Delta x) / (max v_p), $ <eq-cfl>

with the maximum taken over the padded model. The factor 0.4 is conservative for
a second-order scheme in two dimensions and we did not tune it.

@eq-cfl is the reason the problem is expensive, and it is worth being explicit
about why. Halving the grid spacing to resolve finer structure quadruples the
number of grid points in 2D, and it also halves $Delta t$, so the number of time
steps for the same simulated duration doubles. Total work therefore grows with
the cube of the resolution in 2D, and with the fourth power in 3D. There is no
way to spend less arithmetic on a fixed accuracy target without changing the
scheme, so the only lever left is running the arithmetic faster and in parallel.

== The source <sec-source>

The source is a Ricker wavelet, the negative second derivative of a Gaussian,
which is the standard synthetic source in exploration seismics because it is
compact in both time and frequency:

$ r(t) = (1 - 2 a) e^(-a), quad a = (pi f_0 (t - t_0))^2. $ <eq-ricker>

We use a peak frequency $f_0 = 8 "Hz"$ and a time shift $t_0 = 1.2 slash f_0$,
which places the wavelet far enough from $t = 0$ that it starts smoothly. The
wavelet is injected as an explosive source: the same value is added to
$sigma_(x x)$ and $sigma_(z z)$ at one grid point near the top of the physical
model, horizontally centred. Adding to the diagonal stresses and not to
$sigma_(x z)$ makes the source isotropic, which is what an explosive or air-gun
source approximates.

== Absorbing boundaries <sec-boundaries>

A finite grid has edges, and without special treatment those edges reflect. The
reflections travel back into the model and contaminate the result, which for a
run of 50 000 steps means the interesting signal disappears under artefacts.

We use a sponge layer, the simplest of the standard options //@cerjan1985
. The model is padded with $n_b = 240$ cells on all four sides, material properties
are extended outward by copying the edge values, and every field is multiplied
by a damping factor after each update:

$
  d [i,j] = "clip"(1 - sigma [i,j] Delta t, 0, 1), quad
  sigma [i,j] = sigma_"max" (("distance into the layer") / n_b)^2.
$ <eq-sponge>

The ramp is quadratic so the damping starts at zero at the inner edge of the
layer, which avoids creating a reflecting discontinuity at the boundary of the
sponge itself. We use $sigma_"max" = 60$ on three sides and $120$ at the bottom,
where the waves arrive closest to normal incidence and need more absorption per
cell. The damping array is precomputed once and enters the kernels as one extra
multiply per field per step.

A perfectly matched layer @berenger1994 @komatitsch2007 absorbs considerably
better, especially at grazing incidence where a sponge layer leaks. We chose the
sponge because it costs one multiplication and one array, whereas a PML needs
additional memory variables and splits the update equations, and because the
performance question we were studying does not change either way. The cost is
accuracy, not speed, and we flag it as a limitation in //@sec-limitations.

The sponge is not free in terms of work. The padded grid is
$(2801 + 480) times (13601 + 480) = 3281 times 14081$, so the absorbing layer
adds 8.0 million points to the 38.1 million physical ones, a 21 % overhead on
every time step for a region whose only job is to make waves go away. At coarse
downsampling factors the overhead is much worse, which matters for the
weak-scaling experiment and is discussed in //@sec-weak-critique.

== The Marmousi2 model <sec-marmousi>

Marmousi2 is the elastic extension of the Marmousi model, a synthetic but
geologically realistic 2D section built from a North Sea-style structural
setting with faulted, dipping layers and a salt body @martin2006 @versteeg1994.
It is distributed through the SEG open data collection @segopendata as three
SEG-Y files holding $v_p$, $v_s$ and $rho$ on a 1.25 m grid. Each file contains
13 601 traces of 2801 samples, so the model spans 17 km horizontally and 3.5 km
in depth.

We picked it for three reasons. It is a real benchmark that other people have
published numbers on, it is large enough that a serious parallel run is
justified, and it arrives in a format we could read with an existing library
rather than writing a parser. @tab-model lists the properties that the rest of
the report refers to.

#figure(
  ruled-table(
    columns: (auto, auto),
    align: (left, right),
    header: ([Quantity], [Value]),
    [Physical grid $n_(z_0) times n_(x_0)$], [$2801 times 13601$],
    [Physical grid points], [38 095 201],
    [Grid spacing $Delta x = Delta z$], [1.25 m],
    [Model extent (horizontal $times$ depth)], [17.0 km $times$ 3.5 km],
    [Sponge layer width $n_b$], [240 cells],
    [Padded grid $n_z times n_x$], [$3281 times 14081$],
    [Padded grid points], [46 199 761],
    [Fields per point (5 wave, 5 material)], [10],
    [Wavefield and material memory], [1.85 GB],
    [Time steps], [50 000],
    [Source peak frequency $f_0$], [8 Hz],
    [Snapshot interval], [every 100 steps],
    [Snapshots written], [500],
  ),
  caption: [
    Properties of the Marmousi2 model and the simulation grid at downsampling
    factor $s = 1$.
  ],
) <tab-model>

The last three rows are the output side of the problem and they are easy to
underestimate. 500 snapshots of the 38.1 million point $v_z$ field at single
precision is 76 GB of uncompressed data per run. That number is the reason
//@sec-io
 exists and the reason the compression filter turned out to matter more
than any kernel optimisation we made.
