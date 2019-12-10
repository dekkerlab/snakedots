# we'll specify configfile as a CLI argument to the snakemake itself --configfile
# configfile: "project.yml"

resolutions = [5000,10000]

sample_dict = {k:v for k,v in zip(config["samples"],config["location"])}

wildcard_constraints:
    res="\d+"

# this statement prevents following rules to be executed on the cluster ...
localrules: all , merge_dots_res 

# simply all of the combined dots to output ...
rule all:
    input:
       expand(
            "{path}/combineddots/cloops_{hic_name}.combined.bedpe.postproc",
            zip,
            path = [_.rstrip('.null.no_filter.500.mcool') for _ in sample_dict.keys()],
            hic_name = sample_dict.keys() )

# re-balance - will be used to tune tolerance, enable cis-only etc.
# wc - stands for wildcard ...
rule custom_rebalance:
    input:
        lambda wc: os.path.join( sample_dict[wc.hic_name], wc.hic_name )
    params:
        # we have to use something like that to prevent numpy from using threaded MKL ...
        mkl_preamble = "export MKL_NUM_THREADS=1;\n echo threads MKL $MKL_NUM_THREADS;\n"
    output:
        touch("{path}/touchtmp/{hic_name}.touch")
    threads: 9
    run:
        for res in resolutions:
            print("Trying to rebalance an mcool {} ...".format(res))
            shell("{params.mkl_preamble} cooler balance -p {threads} --ignore-diags 1 --force --name 'wsnake' {input}::/resolutions/{res}")


# merge compute and cleaning in one rule:
rule compute_n_clean_expected:
    input:
        lambda wc: os.path.join( sample_dict[wc.hic_name], wc.hic_name ),
        "{path}/touchtmp/{hic_name}.touch"
    params:
        # we have to use something like that to prevent numpy from using threaded MKL ...
        mkl_preamble = "export MKL_NUM_THREADS=1;\n echo threads MKL $MKL_NUM_THREADS;\n"
    output:
        expand("{{path}}/expected/{{hic_name}}.{res}.cis.expected",res=resolutions)
    threads: 9
    run:
        for res, out_local in zip(resolutions, output):
            print("Trying to compute expected for {}".format(res))
            shell(" {params.mkl_preamble} "+
                "cooltools compute-expected -p {threads} --weight-name 'wsnake' --drop-diags 1 {input[0]}::/resolutions/{res} |"+
                "grep -v -e \"^chrM\" | grep -v -e \"^chrY\" > {out_local}")


rule call_dots:
    input:
        cooler = lambda wc: os.path.join( sample_dict[wc.hic_name], wc.hic_name ), 
        expected = expand("{{path}}/expected/{{hic_name}}.{res}.cis.expected",res=resolutions)
    params:
        fdr = 0.1,
        diag_width = 10000000,
        tile_size = 5000000,
        # we have to use something like that to prevent numpy from using threaded MKL ...
        mkl_preamble = "export MKL_NUM_THREADS=1;\n echo threads MKL $MKL_NUM_THREADS;\n"
    output:
        signif_dots = expand("{{path}}/dots/cloops_{{hic_name}}.{res}.bedpe",res=resolutions),
        filtered_dots = expand("{{path}}/dots/cloops_{{hic_name}}.{res}.bedpe.postproc",res=resolutions)
    threads: 12
    run:
        for res, inexp, outdots in zip(resolutions,input.expected,output.signif_dots):
            shell(" {params.mkl_preamble} "+
                "cooltools call-dots --nproc {threads} "+
                "    -o {outdots} -v --fdr {params.fdr} "+
                "    --weight-name 'wsnake' "+
                "    --max-nans-tolerated 4 "+
                "    --max-loci-separation {params.diag_width} "+
                "    --dots-clustering-radius 21000 "+
                "    --tile-size {params.tile_size} "+
                "    --temp-dir . "+
                "    {input.cooler}::/resolutions/{res} {inexp}")


rule merge_dots_res:
    input:
        expand("{{path}}/dots/cloops_{{hic_name}}.{res}.bedpe.postproc",res=resolutions)
    params:
        radius = 10000
    output:
        "{path}/combineddots/cloops_{hic_name}.combined.bedpe.postproc"
    shell:
        "peaktools merge-dot-lists-kdtree"
        "    --radius {params.radius} -v "
        "    --output {output} {input}"


