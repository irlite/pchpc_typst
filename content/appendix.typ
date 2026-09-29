= Work Sharing
    == Maxim Barnstorf
    Maxim was responsible for the main computation and code, making heavy use of LLMs for the mathematics. His contributions included the main loop which includes reading in the input files, preparing the damping, and writing the kernels for the final iterations using tiling. He implemented the MPI halo exchange and integrated OpenMP tiling into the kernels. He also optimized and parallelized the compression, used HDF5 for output, and split the output into separate parts.
    == Utkarsh Utkarsh
    Utkarsh was responsible for the additional OpenMP kernels seen in the benchmarking, referred to as kernels one, two, and three, which he also benchmarked. He contributed to earlier iterations of the sequential code, performed the Score-P analysis, and created the Vampir visualizations. He plotted and visualized the wave data and refactored the code.
