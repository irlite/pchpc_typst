= Introduction
Seismic wave forward modeling is the numerical simulation of how seismic waves
propagate through a given earth model. It is used in applications ranging from
earthquake hazard assessment and ground motion prediction to subsurface imaging
in exploration geophysics. Concretely for inverse problems such as full waveform
inversion and seismic tomography, where synthetic waveforms are compared against
observed data to establish their validity.

Solving the elastodynamic wave equation numerically is most commonly done
through discretization schemes such as the finite-difference method, in
which the spatial and temporal derivatives of the equations are
approximated on a regular grid. Accurately capturing the frequency content
and spatial detail required for realistic wave propagation demands high
computational power and, in particular, large amounts of memory. While the
computation performed at each grid point is simple, many such points need
to be updated over many iterations to satisfy the numerical stability
conditions required to produce accurate results.

As a result, researchers and industry participants rely on HPC datacenters
and the tools available on them to perform these computations within a
reasonable amount of time. In modern HPC, this largely comes down to
parallelization frameworks such as OpenMP and MPI, which allow a developer
to split the workload across multiple cores within a node and across
multiple nodes in a cluster, respectively. Using both together makes it
possible to scale a simulation well beyond what a single machine could
handle, provided the workload is divided and coordinated correctly. This
work examines how this can be applied concretely to the forward modeling
problem described above, covering both the numerical scheme used and the
parallelization strategy built around it.

The remainder of this paper is structured as follows: we first describe
the numerical scheme used for forward modeling and explain how it can be
implemented sequentially, after which we detail how the domain is
decomposed and parallelized using MPI and OpenMP. We then present
performance results obtained on an HPC cluster, examining how the
implementation scales with an increasing number of processes and cores.

= Methodology

== Physical and Numerical Model
=== Elastodynamic wave equation in velocity-stress formulation

The propagation of seismic waves through an elastic medium is described by
the elastodynamic wave equation. Rather than solving it in its standard
second-order displacement form, we adopt the velocity-stress formulation,
which recasts the problem as a system of coupled first-order partial
differential equations in the particle velocities and the stress tensor
components. For the two-dimensional P-SV case considered here, the system
reads

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

Here, $v_x$ and $v_z$ denote the horizontal and vertical particle
velocities, $sigma_(x x)$, $sigma_(z z)$, and $sigma_(x z)$ are the normal
and shear stress components, $rho$ is the mass density, and $lambda$ and
$mu$ are the Lamé parameters. This formulation is well suited to numerical
solution on a staggered grid, since it only involves first-order spatial
derivatives, and it naturally separates the update of the velocity and
stress fields into two distinct steps, which we exploit both in the
sequential and parallel implementations described later.

=== Material parameters

The medium is characterized by three spatially varying physical
quantities: the P-wave velocity $v_p$, the S-wave velocity $v_s$, and the
density $rho$. These are the quantities typically available from
measured or modeled subsurface properties, rather than the Lamé
parameters appearing directly in the wave equation. The Lamé parameters
are therefore derived from $v_p$, $v_s$, and $rho$ using the standard
relations

$ mu = rho v_s^2 $

$ lambda = rho v_p^2 - 2 mu $

with the combined modulus $lambda + 2 mu$ also precomputed, since it
appears directly in the update equations for the normal stresses. In
addition, the inverse density $1 slash rho$ is computed once ahead of
time, since it is required at every velocity update and is more
efficient to precompute than to divide by $rho$ at each grid point during
every iteration.

=== Finite-difference discretization on a staggered grid

The spatial derivatives in the velocity-stress system are approximated
using second-order accurate central differences on a staggered grid,
following the classical scheme introduced for elastic wave modeling by
Virieux. Rather than storing all field components at the same physical
location, the velocity and stress components are defined at spatially
offset grid points, such that the derivatives required by each update
equation can be approximated using values that are naturally centered
between the points where they are needed. This arrangement improves
numerical accuracy and stability compared to a fully collocated grid, at
the cost of requiring some care when injecting sources or extracting
particular field components at a specific physical location.

Since a second-order central difference stencil is used, only a single
layer of neighboring grid points is required on each side of a given
node to evaluate the derivatives involved. This directly determines the
width of the ghost point layer required at subdomain boundaries once the
grid is decomposed for parallel execution, as discussed in the following
sections.

=== Time-stepping scheme and stability condition

Time integration is performed explicitly, using a leapfrog-type scheme in
which the stress and velocity fields are updated in an alternating
fashion at every time step: the stress components are advanced first
using the current velocity field, after which the velocity field is
advanced using the newly updated stresses. This staggering in time,
combined with the spatial staggering described above, is what gives the
overall scheme its second-order accuracy in both space and time while
remaining fully explicit.

Because the scheme is explicit, the time step $Delta t$ cannot be chosen
independently of the spatial grid spacing $Delta x$ and the wave
velocities present in the model. Numerical stability is governed by the
Courant-Friedrichs-Lewy (CFL) condition, which bounds the time step
relative to the fastest wave speed in the medium, in this case the
maximum P-wave velocity $v_(p,"max")$, according to

$ Delta t <= C thin Delta x slash v_(p,"max") $

for some Courant number $C$ below the stability threshold of the scheme.
In practice, we choose $Delta t$ as a fixed fraction of this bound,
computed once from the maximum P-wave velocity present in the model
before the simulation begins.

=== Source model: Ricker wavelet excitation

Seismic energy is introduced into the simulation through a time-dependent
source term, rather than through non-zero initial conditions. We use a
Ricker wavelet as the source time function, a commonly used choice in
seismic modeling due to its compact support in both time and frequency
and its resemblance to the far-field pulse generated by many physical
seismic sources. The wavelet is defined as

$ w(t) = (1 - 2 a) e^(-a), quad a = (pi f_0 (t - t_0))^2 $

where $f_0$ is the dominant frequency of the source and $t_0$ is a time
delay introduced so that the wavelet starts from a negligible amplitude
at $t = 0$ rather than being truncated at its peak. At each time step,
the source time function is evaluated and injected as an isotropic
pressure perturbation, added simultaneously to both normal stress
components at the source location, which corresponds to an explosive-type
source. Injecting the source through the stress field, rather than
directly into the velocity field, avoids introducing artificial high
frequency content associated with a velocity discontinuity at the source
location.

=== Absorbing boundary treatment

Since the computational grid necessarily represents only a finite
portion of what is physically an unbounded or much larger medium, the
edges of the grid must be treated so as to prevent artificial reflections
from re-entering the domain and contaminating the simulated wavefield.
We address this by surrounding the physical model with an absorbing
boundary region on all sides, within which the wavefield is
progressively damped as it approaches the edge of the grid.

Within this boundary region, a spatially varying damping coefficient is
constructed that increases smoothly from zero at the interface with the
physical model to a maximum value at the outer edge of the padded grid,
following a smooth ramp profile. This damping coefficient is converted
into a multiplicative damping factor applied to the wavefield at every
time step, attenuating the velocity and stress components within the
boundary region without affecting the solution within the physical
domain. The bottom boundary is given a stronger damping profile than the
remaining sides, reflecting the fact that reflections traveling upward
from depth are typically of greater concern than those entering from the
sides of the model. While simpler than a full perfectly matched layer
formulation, this damping approach is straightforward to implement and
parallelize, and is sufficient to suppress boundary reflections to an
acceptable level for the purposes of this work.

== Sequential Implementation
=== Model loading and preprocessing

Before the simulation can begin, the physical properties of the subsurface
must be loaded and prepared for use on the computational grid. The P-wave
velocity, S-wave velocity, and density models are read from industry
standard SEG-Y files, a format commonly used to store measured or modeled
subsurface properties. Since these models may be given at a resolution
finer than what is required or computationally feasible for a given
simulation, they can optionally be spatially decimated by a fixed
downsampling factor along both axes, coarsening the grid spacing while
scaling the corresponding physical grid interval accordingly.

Because the finite-difference scheme requires an absorbing boundary
region surrounding the physical model, as described in Section 1.6, the
loaded models cannot be used directly as the computational grid. Instead,
each model is embedded into a larger, padded grid, with a fixed-width
border added on all four sides. Within this border, the material
properties are extended outward from the edge of the physical model by
constant extrapolation, so that the absorbing region shares the same
physical properties as the boundary of the original model rather than
introducing an artificial discontinuity. Once this padding has been
applied to the P-wave velocity, S-wave velocity, and density models, the
derived quantities described in Section 1.2, namely the Lamé parameters,
the combined modulus, and the inverse density, are computed once over the
full padded grid, together with the spatially varying absorbing boundary
damping profile described in Section 1.6.

=== Grid layout and field arrays

The computational grid is represented using two-dimensional arrays
indexed by depth and horizontal position, stored in row-major order so
that the horizontal direction corresponds to contiguous memory locations.
All simulation fields, comprising the two velocity components and three
stress components, are stored as separate arrays of this shape, alongside
the precomputed material parameter and damping arrays described
previously. Rather than allocating separate buffers to hold updated
values at each time step, the update is performed in place: since the
stress update reads only from the velocity field and the velocity update
reads only from the stress field, both belonging to the previous time
level, no ambiguity arises from immediately overwriting a field with its
own updated values.

Each field array additionally carries a one grid-point border surrounding
the domain of interest, sized to match the width of the finite-difference
stencil described in Section 1.3. Sequentially, this border serves to
hold the outermost layer of the grid fixed, before any wave energy
reaching it has already been strongly attenuated by the surrounding
absorbing boundary layer.

=== Update equations: stress update step and velocity update step

At the core of the simulation are two computational kernels, corresponding
directly to the two half-steps of the time-stepping scheme described in
Section 1.4. The stress update kernel loops over every interior grid
point of the domain and, using only the current velocity field, evaluates
the finite-difference approximations to the spatial derivatives given in
Section 1.1, before combining them with the local Lamé parameters to
compute the updated stress components, which are then attenuated by the
local absorbing boundary damping factor. The velocity update kernel
proceeds analogously, looping over the same interior region, but computes
finite differences of the just-updated stress field, combining them with
the local inverse density to obtain updated particle velocities, again
followed by the boundary damping factor.

Structurally, each of these kernels consists of two nested loops, an
outer loop over depth and an inner loop over horizontal position, with
the innermost loop written so that it can be vectorized efficiently by
the compiler, since consecutive iterations access contiguous memory and
operate independently of one another. Even in a purely sequential
setting, expressing the kernels in this form is important, as it
establishes the loop structure that is later parallelized across
threads, described in Section 3.3, without requiring any restructuring
of the underlying computation.

=== Time loop structure and source injection

The simulation advances by repeatedly invoking the stress and velocity
update kernels inside a single time loop, executed for a fixed number of
iterations. At the beginning of each iteration, the source time function
described in Section 1.5 is evaluated for the current simulation time and
added directly to the two normal stress components at the fixed grid
location corresponding to the source position, before the stress update
kernel is invoked for the current iteration, followed immediately by the
velocity update kernel. Because the source is injected before the stress
update executes, its contribution is immediately incorporated into the
same time step at which it is evaluated, rather than only affecting the
following iteration.

To allow the resulting wavefield to be inspected after the simulation, at
fixed intervals of a specified number of iterations, the vertical
velocity component is written out as a snapshot of the current wavefield
across the domain, alongside the corresponding simulation time. Since
only these strided snapshots are stored rather than the state of the
wavefield at every single iteration, the ratio of the total iteration
count to this stride directly determines how many snapshots are produced
over the course of the simulation.

=== Limitations of the sequential approach

Executed sequentially, this scheme has both a memory footprint and a
runtime that scale directly with the size of the computational grid and
the number of time steps performed. Every field and precomputed parameter
array occupies memory proportional to the total number of grid points, so
refining the resolution, or extending the width of the absorbing boundary
region, increases memory usage accordingly. Similarly, since every grid
point in the domain is visited at every iteration by both update kernels,
the total computational work scales with the product of the number of
grid points and the number of time steps performed, and since the time
step itself is bounded from above by the stability condition given in
Section 1.4, simulating a fixed physical duration at a finer spatial
resolution correspondingly requires more, and more costly, iterations.

On a single processor, both of these factors quickly become limiting:
sufficiently large or long simulations require more memory than is
available on a single machine, or take longer to complete than is
practical, even though the computation performed at each individual grid
point remains simple throughout. This motivates distributing both the
memory footprint and the computational work of the simulation across
multiple processors, as described in the following section.

== Parallelization Strategy
=== Domain decomposition

To distribute the simulation across multiple processes, the computational
grid is partitioned into a set of non-overlapping rectangular subdomains,
arranged as a two-dimensional grid of processes along the depth and
horizontal directions. Given the total number of available processes, the
number of subdomains along each axis is chosen so as to keep the
resulting subdomains as close to square as possible, minimizing the
combined size of the two local grid dimensions for a given number of
processes, subject to the number of processes along each axis evenly
dividing the total process count. This choice is motivated by the fact
that, for a fixed number of grid points, subdomains that are closer to
square minimize the total length of the boundary shared with neighboring
subdomains, and therefore the volume of data that must be exchanged
between processes at every iteration.

Once the number of subdomains along each axis has been fixed, the grid
points along each axis are distributed among the corresponding processes
as evenly as possible, with any remaining grid points that do not divide
evenly assigned one at a time to the first few processes along that axis.
This ensures that no process is assigned a subdomain more than one grid
point larger, along either axis, than any other process responsible for
the same axis, keeping the computational workload balanced across all
processes.

=== Distributed-memory parallelization with MPI

Each process is assigned its subdomain of the grid, together with a
local copy of the corresponding portion of the material parameter and
absorbing boundary damping arrays. Since the finite-difference stencil
used by the update kernels requires access to neighboring grid points, a
single layer of ghost cells is added around each local subdomain,
mirroring the one-point border already introduced in the sequential
formulation, but now additionally serving to hold values that physically
belong to a neighboring process rather than to the process itself.

The processes are arranged using a two-dimensional Cartesian virtual
topology, which assigns each process a coordinate along the depth and
horizontal axes matching its position within the decomposed grid, and
from which the identities of its immediate neighbors along both axes can
be directly obtained. Since the grid is not periodic in either direction,
processes located along the outer edge of the process grid simply have
no neighbor on the corresponding side.

Before the stress update kernel is executed, each process exchanges the
outermost layer of its local velocity field with its neighboring
processes, so that the ghost cells adjacent to a shared subdomain
boundary contain a consistent, up to date copy of the neighboring
process's boundary values before any derivatives are computed across that
boundary. An analogous exchange is performed for the stress field after
the stress update but before the velocity update, since the velocity
kernel in turn requires neighboring stress values. In both cases,
communication proceeds independently along the depth and horizontal
directions, with each process simultaneously sending its own boundary
values to one neighbor while receiving the corresponding boundary values
from the opposite neighbor, so that both halo exchanges required by each
field can be completed using a single pair of messages per axis.
Processes without a neighbor on a given side simply do not participate in
the corresponding exchange, since such subdomains lie along the outer
edge of the computational grid.

=== Shared-memory parallelization with OpenMP

Within each process, the stress and velocity update kernels are further
parallelized across the cores available on the node executing that
process. Since the outer loop of each kernel iterates independently over
the rows of the local subdomain, with no data dependency between rows
within a single kernel invocation, this loop is distributed statically
across the available threads, giving every thread an equally sized,
contiguous range of rows to process. Because the computational cost per
grid point is uniform across the domain, this static division of work
results in a naturally balanced distribution of the workload among
threads, without requiring dynamic load balancing.

Within each thread's assigned rows, the innermost loop over horizontal
position is additionally vectorized, allowing multiple adjacent grid
points to be processed simultaneously by a single core using its
available SIMD instructions. Combined with the outer loop parallelization
across threads, this results in two nested levels of parallelism being
exploited within a single process: coarse-grained parallelism across the
cores of a node, and fine-grained parallelism within each core.

=== Combining MPI and OpenMP

The overall parallelization strategy therefore combines two levels of
parallelism operating at different scales: MPI processes divide the
computational grid across the distributed-memory nodes of the cluster,
while OpenMP threads divide the work within each subdomain across the
shared-memory cores available to a single process. In practice, each MPI
process is allocated a number of cores on which it is permitted to spawn
OpenMP threads, so that the total number of cores used by the simulation
corresponds to the number of MPI processes multiplied by the number of
threads used per process. This hybrid arrangement allows the simulation
to scale across a large number of nodes without requiring every
individual grid point to be managed by a separate MPI process, reducing
both the number of messages exchanged between processes and the amount of
bookkeeping required per process, while still making full use of the
cores available within each node.

== Handling of Simulation Output
=== Challenges of storing full wavefield snapshots at scale

Beyond the computation itself, a distributed simulation of this kind also
produces a considerable amount of output data. Recording a snapshot of
the wavefield at regular intervals throughout the simulation, across a
grid that may be decomposed across many processes, can quickly accumulate
a substantial volume of data, particularly for simulations run over many
iterations or at high spatial resolution. Since only the physical extent
of the model is of interest for later analysis, rather than the
surrounding absorbing boundary region, it is furthermore preferable to
avoid storing or transmitting the padded portion of each local subdomain
at all. Collecting all of this output onto a single process before
writing it to disk would introduce both a memory bottleneck on that
process and a serialization point at every recorded time step,
undermining the benefits of having distributed the computation in the
first place.

=== Per-process output strategy

To avoid this bottleneck, each process is instead responsible for writing
its own share of the output independently, directly to its own output
file, without requiring coordination with any other process during the
simulation itself. Before doing so, each process first determines the
overlap, if any, between its local subdomain and the physical extent of
the model, discarding the portion of its subdomain that falls entirely
within the absorbing boundary region. Processes whose subdomain does not
intersect the physical model at all, which can occur for subdomains
located entirely within the padded border, skip writing wavefield output
altogether, since they hold no data of interest.

For processes that do hold part of the physical model, an output dataset
is created ahead of time, sized to hold every snapshot that will be
produced over the course of the simulation, with the data organized into
chunks and compressed as it is written, to reduce both the storage
footprint and the I/O bandwidth required to write it. The chunk size used
for this dataset is chosen based on the number of cores available to the
writing process, so that the amount of data associated with a single
chunk remains proportional to the resources available for producing and
compressing it. At every interval at which a snapshot is due, the
relevant, non-padded portion of the local vertical velocity field is
written directly into the next available slot of this dataset, without
requiring any communication with other processes.

=== Assembly of distributed output into a unified dataset

While this strategy allows every process to write its output
independently and efficiently, it leaves the full wavefield distributed
across as many separate files as there are contributing processes. To
present this distributed output as a single, coherent dataset, each
process communicates a small amount of metadata to a designated
coordinating process once the simulation has completed, describing the
region of the physical model covered by its output and the location of
its output file. Using this metadata, the coordinating process constructs
a single virtual dataset that maps the corresponding region of each
contributing file into its correct position within a dataset spanning the
full physical extent of the model. Since a virtual dataset of this kind
only stores references to the underlying per-process files, rather than
duplicating their contents, this assembly step introduces negligible
additional storage overhead, while allowing the complete wavefield to be
read and analyzed as though it had been produced by a single process,
without ever requiring the full dataset to be gathered into the memory of
any individual process at any point.

== Experimental Setup
=== HPC cluster environment and hardware specification

All experiments were carried out on [cluster name], a [brief description
of cluster, e.g. number of nodes / partition used]. Each compute node
used in this work is equipped with [CPU model], providing [number of
physical cores] cores per node and [amount of RAM] of memory, and nodes
are interconnected via [interconnect, e.g. InfiniBand]. Jobs were
submitted and resources allocated through [job scheduler, e.g. Slurm],
with the number of MPI processes per node and the number of OpenMP
threads per process configured explicitly for each experiment via
[relevant environment variables / job script settings].

=== Test model / dataset description

The test model used throughout this work is [name/description of
dataset], consisting of P-wave velocity, S-wave velocity, and density
models given as SEG-Y files at a native spatial resolution of [value].
The model spans [physical dimensions] before the addition of the
absorbing boundary region described in Section 1.6, and is representative
of [brief description of geological setting / relevance of the model].

=== Simulation parameters

Unless otherwise stated, simulations were run using a grid spacing of
[value], an absorbing boundary width of [value] grid points on each side
of the model, and a total of [value] time steps, corresponding to a
simulated duration of [value]. The source was modeled as a Ricker
wavelet with a dominant frequency of [value], injected at [source
location description]. Wavefield snapshots were recorded every [value]
iterations for later analysis.
