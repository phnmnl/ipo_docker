##
## This function retrieves runinfos and instrument infos from
## mzfile given in argument
##
getInfos <- function(mzdatafiles) {

  # Get informations about instruments used and run
  ms <- openMSfile(mzdatafiles)

  runInfo <- t(sapply(runInfo(ms), function(x) x[1], USE.NAMES = TRUE))
  instrumentInfo <- t(sapply(instrumentInfo(ms), function(x) x, USE.NAMES = TRUE))

  infos <- list("runInfo" = runInfo, "instrumentInfo" = instrumentInfo)
  return(infos)
}


##
## This function launches IPO functions to get the best parameters for xcmsSet
## 5% but at least 10 files of the whole dataset is used to save processing time
##
ipo4xcmsSet <- function(directory, parametersOutput, listArguments) {
  setwd(directory)

  files <- list.files(".", recursive = T)

  # Check if there are blank files
  # TODO Change the method retrieving blank samples, with a more "official way" then "grep" maybe ?
  blank.files <- grep("blan(k|c)", files, ignore.case = TRUE, value = TRUE)
  # Keep only QCs and/or pool files if possible since they are more representative of the experimental study
  representative.files <- grep("(QC)|(pool)", files, ignore.case = TRUE, value = TRUE)
  if (length(representative.files) != 0) { # If pools or QC, keep only them
    mzfiles <- representative.files
    if (length(blank.files) != 0) { # Keep also blanks if there are
      mzfiles <- c(mzfiles, blank.files)
    }
  } else {
    # To reduce processing time, keep 5% but at least 10 raw data files of the assay
    if (length(files) <= 10) {
      mzfiles <- files
    } else if (ceiling((5 * length(files)) / 100) < 10) {
      mzfiles <- sample(files, 10)
    } else {
      mzfiles <- sample(files, ceiling((5 * length(files)) / 100))
    }
  }

  cat("\t\tSamples used:\n")
  print(mzfiles)

  peakpickingParameters <- getDefaultXcmsSetStartingParams(listArguments[["method"]]) # get default parameters of IPO

  # filter listArguments to only get releavant parameters and complete with those that are not declared
  peakpickingParametersUser <- c(listArguments[names(listArguments) %in% names(peakpickingParameters)], peakpickingParameters[!(names(peakpickingParameters) %in% names(listArguments))])
  peakpickingParametersUser$verbose.columns <- TRUE

  # allow range for min and max peakwidth and ppm if given in arguments
  if (!is.null(listArguments[["minPeakWidth"]])) {
    peakpickingParametersUser$min_peakwidth <- as.vector(as.numeric(unlist(strsplit(listArguments[["minPeakWidth"]], split = ","))))
    listArguments[["minPeakWidth"]] <- NULL
  }

  if (!is.null(listArguments[["maxPeakWidth"]])) {
    peakpickingParametersUser$max_peakwidth <- as.vector(as.numeric(unlist(strsplit(listArguments[["maxPeakWidth"]], split = ","))))
    listArguments[["maxPeakWidth"]] <- NULL
  }

  if (!is.null(listArguments[["ppm"]])) {
    if (grepl(",", listArguments[["ppm"]])) {
      peakpickingParametersUser$ppm <- as.vector(as.numeric(unlist(strsplit(listArguments[["ppm"]], split = ","))))
    } else {
      peakpickingParametersUser$ppm <- listArguments[["ppm"]]
    }
    listArguments[["ppm"]] <- NULL
  }

  # peakpickingParametersUser$profparam <- list(step=0.005) #not yet used by IPO have to think of it for futur improvement
  resultPeakpicking <- optimizeXcmsSet(mzfiles, peakpickingParametersUser, nSlaves = peakpickingParametersUser$nSlaves, subdir = "../IPO_results") # some images generated by IPO

  # Export results
  resultPeakpicking_best_settings_parameters <- resultPeakpicking$best_settings$parameters[!(names(resultPeakpicking$best_settings$parameters) %in% c("nSlaves", "verbose.columns"))]

  # Export:
  # - TSV output for run / instrument informations of all files in the dataset
  # - TSV output for best settings parameters
  table <- NULL
  for (filename in mzfiles) {
    one.file.infos <- getInfos(filename)
    infos <- cbind(filename, one.file.infos$instrumentInfo, one.file.infos$runInfo)
    table <- rbind(table, infos)
  }
  # Export run and instrument infos
  write.table(table, file = "../run_instrument_infos.tsv", sep = "\t", row.names = F, col.names = T, quote = F)
  # Export best parameters of peak picking
  write.table(as.matrix(resultPeakpicking_best_settings_parameters), file = parametersOutput, sep = "\t", row.names = T, col.names = F, quote = F)

  # Returns best settings containing among others:
  # - Best Xset (xcmsSet object)
  # - Best Xset parameters
  # - PeakPickingScore (PPS)
  return(resultPeakpicking)
}







##
## This function launches IPO functions to get the best parameters for group and retcor
## Factors are extracted from the sample metadata file to fill the phenoData of the xcmsSet object
## This ensures that the experimental design factors are taken into account
##
ipo4retgroup <- function(xset, sample.metadata.file, directory, parametersOutput, listArguments) {
  setwd(directory)

  files <- list.files(".", recursive = T)

  # Read the sample.metadata (W4M) file to have access to factors of the assay
  sample.metadata <- read.table(sample.metadata.file, header = TRUE)
  # Get all factors columns
  factors <- sample.metadata[, grep("Factor.Value.*", colnames(sample.metadata), value = TRUE, ignore.case = TRUE)]
  if (length(factors) != 0) {
    # Link all files to their factors
    factors <- cbind(sample.metadata$Raw.Spectral.Data.File, factors)
    # Get indexes of files that are in the xcmsSet object
    files.index <- which(as.character(sample.metadata$Raw.Spectral.Data.File) %in% basename(xset@filepaths))
    # Get the factors of these files respectively
    factors.of.files <- factors[files.index, 2:length(factors)]
    # Fill the phenoData of xset: indicate the experimental design factors
    # for grouping and retention time correction
    xset <- `sampclass<-`(xset, factors.of.files)
  } else {
    cat("\n\nWARNING: no factors found, check that the sample metadata file is correct.\nNo sample class is set for the xcmsSet object.\n\n")
  }

  # Retrieve default parameters
  retcorGroupParameters <- getDefaultRetGroupStartingParams(listArguments[["retcorMethod"]]) # get default parameters of IPO
  print(retcorGroupParameters)
  # filter listArguments to only get releavant parameters and complete with those that are not declared
  retcorGroupParametersUser <- c(listArguments[names(listArguments) %in% names(retcorGroupParameters)], retcorGroupParameters[!(names(retcorGroupParameters) %in% names(listArguments))])
  print("retcorGroupParametersUser")
  print(retcorGroupParametersUser)
  # Do the job !
  resultRetcorGroup <- optimizeRetGroup(xset, retcorGroupParametersUser, nSlaves = listArguments[["nSlaves"]], subdir = "../IPO_results") # some images generated by IPO

  # Export  best retCor + grouping parameters
  write.table(t(as.data.frame(resultRetcorGroup$best_settings)), file = parametersOutput, sep = "\t", row.names = T, col.names = F, quote = F) # can be read by user
}




##
## This function checks if xcms will found all the files
##
# @author Gildas Le Corguille lecorguille@sb-roscoff.fr ABiMS TEAM
checkFilesCompatibilityWithXcms <- function(directory) {
  cat("Checking files filenames compatibilities with xmcs...\n")
  # WHAT XCMS WILL FIND
  filepattern <- c("[Cc][Dd][Ff]", "[Nn][Cc]", "([Mm][Zz])?[Xx][Mm][Ll]", "[Mm][Zz][Dd][Aa][Tt][Aa]", "[Mm][Zz][Mm][Ll]")
  filepattern <- paste(paste("\\.", filepattern, "$", sep = ""), collapse = "|")
  info <- file.info(directory)
  listed <- list.files(directory[info$isdir], pattern = filepattern, recursive = TRUE, full.names = TRUE)
  files <- c(directory[!info$isdir], listed)
  files_abs <- file.path(getwd(), files)
  exists <- file.exists(files_abs)
  files[exists] <- files_abs[exists]
  files[exists] <- sub("//", "/", files[exists])

  # WHAT IS ON THE FILESYSTEM
  filesystem_filepaths <- system(paste("find $PWD/", directory, " -not -name '\\.*' -not -path '*conda-env*' -type f -name \"*\"", sep = ""), intern = T)
  filesystem_filepaths <- filesystem_filepaths[grep(filepattern, filesystem_filepaths, perl = T)]

  # COMPARISON
  if (!is.na(table(filesystem_filepaths %in% files)["FALSE"])) {
    write("\n\nERROR: List of the files which will not be imported by xcmsSet", stderr())
    write(filesystem_filepaths[!(filesystem_filepaths %in% files)], stderr())
    stop("\n\nERROR: One or more of your files will not be imported by xcmsSet. It may be due to bad characters in their filenames.")
  }
}



##
## This function check if XML contains special caracters. It also checks integrity and completness.
##
# @author Misharl Monsoor misharl.monsoor@sb-roscoff.fr ABiMS TEAM
checkXmlStructure <- function(directory) {
  cat("Checking XML structure...\n")

  cmd <- paste("IFS=$'\n'; for xml in $(find", directory, "-not -name '\\.*' -not -path '*conda-env*' -type f -iname '*.*ml*'); do if [ $(xmllint --nonet --noout \"$xml\" 2> /dev/null; echo $?) -gt 0 ]; then echo $xml;fi; done;")
  capture <- system(cmd, intern = TRUE)

  if (length(capture) > 0) {
    # message=paste("The following mzXML or mzML file is incorrect, please check these files first:",capture)
    write("\n\nERROR: The following mzXML or mzML file(s) are incorrect, please check these files first:", stderr())
    write(capture, stderr())
    stop("ERROR: xcmsSet cannot continue with incorrect mzXML or mzML files")
  }
}
