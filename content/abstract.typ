Seismic wave forward modeling is a computationally demanding but essential
tool in exploration geophysics, underlying both direct simulation studies
and iterative methods such as full waveform inversion. This work presents a
hybrid MPI and OpenMP implementation for elastic wave propagation using a
second order accurate, staggered grid finite difference scheme, applied to
the Marmousi2 subsurface model at full resolution. We discuss several
parallelization improvements applied to this implementation, including a
two dimensional domain decomposition that balances subdomain shape against
communication cost, halo exchanges overlapped with interior computation to
hide communication latency, cache aware tiling combined with SIMD
vectorization to reduce memory traffic between the stress and velocity
updates, and parallelized, compressed output writing to avoid serializing
I/O through a single process. Compared to a sequential baseline runtime of
12374 seconds, the parallel implementation achieves a runtime of 203 seconds
using 960 CPU cores across ten nodes, corresponding to a speedup of 61 times
and a parallel efficiency of 6.4%. The results show that most of the
achievable gains are captured at moderate core counts, with just 16 cores
already achieving a speedup of 6.3 times, while OpenMP synchronization
overhead, MPI communication and memory bottlenecks reduce scaling at larger
core counts, motivating GPU acceleration as a promising direction for
future work.
