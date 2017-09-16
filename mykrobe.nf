#!/usr/bin/env nextflow
/*

========================================================================================
                          Mykrobe Pipeline
========================================================================================
 Mykrobe predictor
 #### Authors
 Anthony Underwood @bioinformat <anthony.underwood@phe.gov.uk>
----------------------------------------------------------------------------------------
*/

// Pipeline version
version = '1.0'

/***************** Setup inputs and channels ************************/
// Defaults for configurable variables
params.paired_read_dir = false
params.single_read_dir = false
params.bam_dir = false
params.output_dir = false
params.species = false
params.pattern_match = false
params.help = false


// print help if required
def helpMessage() {
    log.info"""
    =========================================
     Mykrobe Predictor Pipeline v${version}
    =========================================
    Usage:
    The typical command for running the pipeline is as follows:
    nextflow run mykrobe.nf -with-docker phelimb/mykrobe_predictor --paired_read_dir /path/to/read_dir --pattern_match='*_{1,2}.fastq.gz' --output_dir /path/to/output_dir --species staph
    Mandatory arguments:
      --output_dir                       Path to output dir "must be surrounded by quotes"
      --species                          tb or staph
      --pattern_match                    The regular expression that will match files e.g '*_{1,2}.fastq.gz' or '*.bam'
    Options:
    One of these must be specified
      --paired_read_dir                  Path to directory containing paired fastq files
      --single_read_dir                  Path to directory containing non-paired fastq files
      --bam_dir                          Path to directory containing bam files
   """.stripIndent()
}

// Show help message
if (params.help){
    helpMessage()
    exit 0
}

def check_parameter(params, parameter_name){
   if ( !params[parameter_name]){
      error "You must specifiy a " + parameter_name
   } else {
      variable = params[parameter_name]
      return variable
   }

}
// set up output directory
output_dir = file(check_parameter(params, "output_dir"))
// set up species
species = check_parameter(params, "species")
// set up pattern_match
pattern_match = check_parameter(params, "pattern_match")

// setup input channels
if ( params.paired_read_dir) {
    /*
     * Creates the `read_pairs` channel that emits for each read-pair a tuple containing
     * three elements: the pair ID, the first read-pair file and the second read-pair file
     */
    fastqs = params.paired_read_dir + '/' + pattern_match
    Channel
      .fromFilePairs( fastqs )
      .ifEmpty { error "Cannot find any reads matching: ${fastqs}" }
      .set { read_pairs }
} else if ( params.single_read_dir ){
    fastqs = params.single_read_dir + '/' + pattern_match
    Channel
      .fromPath( fastqs )
      .ifEmpty { error "Cannot find any bam files matching: ${bams}" }
      .set {reads}
}
else if ( params.bam_dir ){
    bams = params.bam_dir + '/' + pattern_match
    Channel
      .fromPath( bams )
      .ifEmpty { error "Cannot find any bam files matching: ${bams}" }
      .set {bam_files}
}



log.info "======================================================================"
log.info "                  Mykrobe pipeline"
log.info "======================================================================"
log.info "Running version   : ${version}"
if ( params.paired_read_dir || params.single_read_dir ) {
    log.info "Fastq files             : ${fastqs}"
} else if ( params.bam_dir ) {
    log.info "Bam files             : ${bams}"
}
log.info "======================================================================"
log.info "Outputs written to path '${params.output_dir}'"
log.info "======================================================================"
log.info ""

if ( params.paired_read_dir ) {
   process mykrobe_predict {
       publishDir output_dir, mode: 'copy'

       input:
       set id, file(reads) from read_pairs

       output:
       file "${id}.json" into summary_channel

       script:
       """
       mykrobe predict  --skeleton_dir /tmp ${id} ${species} -1 ${reads} > ${id}.json
       """
   }
} else if ( params.single_read_dir ) {
   process mykrobe_predict {
       publishDir output_dir, mode: 'copy'

       input:
       file(read) from reads

       output:
       file "${suffix}.json" into summary_channel

       script:
       suffix = orig_file.baseName
       """
       mykrobe predict --skeleton_dir /tmp ${suffix} ${species} -1 ${read} > ${suffix}.json
       """
   }
} else if ( params.bam_dir ) {
   process mykrobe_predict {
       publishDir output_dir, mode: 'copy'

       input:
       file(bam_file) from bam_files

       output:
       file "${suffix}.json" into summary_channel

       script:
       suffix = bam_file.baseName
       """
       mykrobe predict --skeleton_dir /tmp ${suffix} ${species} -1 ${bam_file} > ${suffix}.json
       """
   }
}

process summarise_jsons {
    publishDir output_dir, mode: 'move'

    input:
    file(json_output) from summary_channel.collect()

    output:
    file "summary.tsv"

    script:
    """
    python /usr/src/app/scripts/json_to_tsv.py ${json_output} > summary.tsv
    """

}

workflow.onComplete {
	log.info "Nextflow Version:  $workflow.nextflow.version"
  	log.info "Command Line:      $workflow.commandLine"
	log.info "Container:         $workflow.container"
	log.info "Durationn:         $workflow.duration"
	log.info "Output Directory:  $params.output_dir"
}
