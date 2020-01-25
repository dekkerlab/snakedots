## snakedots


### little snakemake pipeline to call dots.

the intent is to automate some pre-processing steps required for dot-calling and allow automated way to call dots for multiple samples.

the pipeline is "self-sufficient", i.e. one can start from unbalanced coolers, or try to optimize balancing for better results (`cis-only`, `ignore-diags 1`, etc.). Computation of expected is included in the pipeline as well.

The pipeline will run using the latest stable versions of `cooler` and `cooltools` along with the https://github.com/sergpolly/peaktools required for merging step (would be eventually included in the `cooltools`).

### dot-calling algorithm implemented in `cooltools` is matching `HiCCUPS` with 2 notable expections:
 1. `call-dots` is using fixed size of the "donut"(and other convolution kernels) to calculate local enrichment around each pixel
 2. `call-dots` is surveying only limited range of genomic separations, e.g. between 0 and 10MB
 
in our experience limitation (2) does not affect typical dot-calls for human cell-lines (GM, HFF, ESC, etc), whereas limitation (1) prevents us from calling some "small" dots (near the diagonal on a Hi-C heatmap), e.g. at 5kb resolution dot-calling "starts" at ~75kb. "shirking-donuts" of the GPU version of HiCCUPS allows for as small as ~50kb dots to be caled at 5kb resolution.

### the exact steps included in the pipeline are following:
 - re-balance input coolers at 5kb and 10kb, saving weights into `wsnake` column
 - compute expected at 5kb and 10kb using re-balanced coolers, and removing `chrY` and `chrM` from the output
 - call-dots at 5kb and 10kb using re-balanced coolers and computed expected
 - merge dots called at 5kb and 10kb into a combined list of called dots.

### Running the pipeline

1. install:
```
 - cooler
 - cooltools
 - peaktools
 - snakemake
```
there are plenty of instuctions on how to do it, using `conda`, `pip`, etc.
For `peaktools` one can do following `pip install git+https://github.com/sergpolly/peaktools.git`

2. prepare `project.yml` that contains your input cooler-names and their corresponding locations, e.g.:
```yml
samples:
   - sample1.mcool
   - sample2.mcool
location:
   - /path/to/sample1
   - /path/to/sample2
```

3. clone this repo, tweak the `Snakemake`-file to adjust your balancing options, expected calculations, and dot-calling - unfortunatelly there is no easy clean interface for providing such parameters outside of the `Snakefile` for now

4. Run the pipeline using `snakemake`:

 - one can run the entire pipeline from coolers to dot-calls, locally on a ~6+ core, 16GB+ RAM computer:
  ```bash
  snakemake -j NUMBER_OF_CORES ---configfile /path/to/your/project.yml
  ```
 - run it on the cluster! - we provide an example for LSF batch submission system:
 ```bash
  snakemake -j MAX_NUMBER_OF_JOBS --configfile /path/to/your/project.yml --printshellcmds --cluster-config cluster.json --    cluster \"bsub -q {cluster.queue} -W {cluster.time} -n {cluster.nCPUs} -R {cluster.memory} -R {cluster.resources} -oo {cluster.output} -eo {cluster.error} -J {cluster.name}\"
  ```
  where `cluster.PARAMETER` parameters are provided in the `cluster.json` file.
  
  - alternatively - one can simply run each individual command provided in the `Snakefile` simply using it for guidance and typical parameters.

### Other files in the repo:

 - there are several `project` files that highlight what has been processed for the microC publication.
 - the `downsampled` project is related to the downsampled microC samples that are matching number of cis-interactions with the corresponding HiC maps.
 - `launch.sh` is a bash "script" to run the pipeline on an LSF cluster, i.e. `bash launch.sh my_new.project.yml`
