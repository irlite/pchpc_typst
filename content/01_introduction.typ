#import "helpers.typ": *

= Introduction <sec-introduction>

Everything we know about the Earth below a few kilometres of depth comes from indirect measurement, and most of it comes from seismics. A source at or near the surface sends elastic waves into the ground, the waves reflect and refract wherever material properties change, and a line of receivers records what comes back. Turning those recordings into an image of the subsurface is an inverse problem, and like most inverse problems it is solved by repeatedly guessing a model, simulating what that model would have recorded, and comparing them. The simulation step is called forward modelling. 

A finite-difference solver for the elastic wave equation updates five fields at every grid point at every time step. For the elastic Marmousi2 benchmark model at its native 1.25 m spacing, the physical grid is $2801 times 13601$, or 38.1 million points,
and a stable simulation of the length we wanted needs 50 000 time steps. Our sequential implementation takes 13 686 s, just under four hours, for one shot in two dimensions. Nothing about that is unusual, and that is the point. Three-dimensional models raise the point count by three or four orders of magnitude, and inversion workflows repeat the whole thing once per shot per iteration.

The established way to solve this problem is spatial domain decomposition. The stencil only reads immediate neighbours, so the grid can be cut into tiles, one tile per process, with a thin layer of shared cells exchanged between neighbouring tiles each step. 
// Bohlen's SOFI2D and the SPECFEM family both do this, and both scale to large machines @bohlen2002 @komatitsch2002. Two things about the published results made us want to measure for ourselves. First, they mostly report pure MPI, whereas current nodes have enough cores that the split between ranks and threads inside a node is a real design choice with no obvious answer. Second, scaling numbers are usually quoted for the compute kernels, with output either disabled or not mentioned. 
Our simulation writes a wavefield snapshot every 100 steps because we want to see the result, and we suspected that this would not be free.

We built a hybrid solver and measured it. The time loop runs in C compiled with OpenMP, called through `ctypes` from a Python driver that owns setup, MPI communication and I/O. Ranks are arranged in a two-dimensional Cartesian topology and exchange a one-cell halo. The staggered stencil is asymmetric, the stress update reading right and bottom neighbours while the velocity update
reads left and top, so each time step needs only two directed halo sweeps rather than a full four-way exchange. Every rank writes its own HDF5 file and a virtual dataset stitches the files into one logical array after the run, which keeps rank 0 out of the write path.

The measurements say two useful things. On one node, going from 1 to 96 cores cuts the runtime from 13 686 s to 830 s, a speedup of 16.5 at a parallel efficiency of 0.17. Spreading the same rank count over four nodes reaches 352 s. Both curves flatten well before the core count does, which is what a memory-bandwidth-bound stencil looks like. Second, and less expected, Score-P tracing showed that with the gzip HDF5 filter the compression of output frames consumed 1118 s out of a 2075 s run, more than `update_stress` and
`update_velocity` together. Switching the filter to Blosc-LZ4 dropped the per-write cost from 2.75 s to 0.22 s and the total runtime from 2125 s to 1154 s at the same core count. We would not have found that by staring at wall-clock totals.

== Contributions <sec-contributions>

- A sequential 2D elastic velocity-stress solver for Marmousi2, written as a Python driver over a C kernel, used as the baseline    for every speedup number in this report.
- A hybrid MPI and OpenMP version with a two-dimensional Cartesian decomposition, a one-cell halo, and a halo-exchange schedule that exploits the direction of the staggered stencil to halve the number of messages.
- An output path built from one HDF5 file per rank plus a virtual dataset, which removes the serialisation point that a single writer or parallel HDF5 would introduce.
- A scaling study over 18 configurations covering 1 to 96 cores on a node and 1 to 8 nodes, including strong scaling, weak scaling, and a sweep of the rank-to-thread split at a fixed core count.
- A Score-P and Vampir trace analysis that identified HDF5 compression as the dominant cost, and a measurement of the four filters we tried.
- An honest account of where the scaling stops and why, including two configurations where more hardware made the run slower.

== Outline <sec-outline>

// @sec-background covers the physics and the discretisation, in enough detail that
// the stencil dependencies in @sec-parallel follow from it. @sec-sequential
// describes the sequential implementation and where its four hours go.
// @sec-parallel is the parallelisation: what we distributed, what we deliberately
// did not, the decomposition, the halo exchange, the threading and the output
// path. @sec-setup states the hardware, software and measurement methodology.
// @sec-results presents the measurements. @sec-discussion argues about what they
// mean and lists what we got wrong. @sec-conclusion closes and names the next
// steps.
