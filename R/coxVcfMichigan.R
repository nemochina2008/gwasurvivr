coxVcfMichigan <- function(data,
                           covariates,
                           maf.filter, 
                           info.filter, 
                           cox.params,
                           cl, 
                           inter.term, 
                           print.covs){
    ####### Get genotype data ############ 
    # read dosage data from collapsed vcf, subset for defined ids
    genotypes <- geno(data)$DS[, cox.params$ids, drop=FALSE]
    ########################################
    # AF MAF R2 ER2
    # calculates sample MAF
    snp.ids <- rownames(data)
    snp.ranges <- data.frame(rowRanges(data))[,c("seqnames",
                                                 "start", 
                                                 "REF", 
                                                 "ALT")]
    snp.ranges$ALT <- sapply(snp.ranges$ALT, as.character)
    snp.ranges$REF <- sapply(snp.ranges$REF, as.character)
    snp.meta <- data.frame(info(data))
    snp.meta$TYPED <- NA
    snp.meta$TYPED[!is.na(snp.meta$ER2)] <- TRUE
    snp.meta$TYPED[is.na(snp.meta$ER2)] <- FALSE
    
    samp.exp_alt <- round(rowMeans2(genotypes)*0.5, 4)
    samp.maf <- ifelse(samp.exp_alt > 0.5, 1-samp.exp_alt, samp.exp_alt)
    snp <- cbind(RSID=snp.ids,
                 snp.ranges,
                 snp.meta,
                 SAMP_FREQ_ALT=samp.exp_alt,
                 SAMP_MAF=samp.maf)
    ##################################################
    ##### SNP Checks #################################
    # remove snps with SD less than 1e-4
    # to put this in perspective:
    # a sample size of 100 000 000 with only 1 person being 1 and rest 0,
    # has an SD = 1e-4
    # x <- c(rep(0, 1e8),1)
    # sd(x)
    snp.keep <- rowSds(genotypes) > 1e-4
    if(!all(snp.keep)){
        genotypes <- genotypes[snp.keep,]
        snp.drop <- snp[!snp.keep,]
        snp <- snp[snp.keep,]
    }else{
        snp.drop <- data.frame()
    }
    
    empty.geno <- tryCatch(
        {
            # Further filter by user defined thresholds
            if(!is.null(maf.filter)){
                ok.maf <- snp$MAF>maf.filter & snp$MAF<(1-maf.filter)
                snp.drop <- base::rbind(snp.drop,snp[!ok.maf,])
                snp <- snp[ok.maf,]
                if(all(!ok.maf)) stop("None of the SNPs pass the MAF threshold")
                genotypes <- genotypes[ok.maf,]
            }
            
            if(!is.null(info.filter)){
                ok.info <- snp$R2 >= info.filter
                snp.drop <- base::rbind(snp.drop,snp[!ok.info,])
                snp <- snp[ok.info,]
                if(all(!ok.info)) {
                    stop("None of the SNPs pass the info threshold")
                }
                genotypes <- genotypes[ok.info,]
            }
            #############################################################
            ########## clean and save dropped and kept SNP info #########
            # rearrange columns for snp info
            snp.cols <- c("RSID",
                          "CHR",
                          "POS", 
                          "REF", 
                          "ALT", 
                          "AF", 
                          "MAF", 
                          "INFO",
                          "ER2",
                          "TYPED",
                          "SAMP_FREQ_ALT",
                          "SAMP_MAF")
            colnames(snp) <- snp.cols
            colnames(snp.drop) <- snp.cols
            snp.ord <- c("RSID",
                         "TYPED",
                         "CHR", 
                         "POS",
                         "REF", 
                         "ALT", 
                         "AF",
                         "MAF",
                         "SAMP_FREQ_ALT",
                         "SAMP_MAF",
                         "INFO",
                         "ER2")
            snp <- snp[, snp.ord]
            snp.drop <- snp.drop[, snp.ord]
            ###########################################################
            ############### fit models in parallel ####################
            if(is.null(inter.term)){
                if(is.matrix(genotypes)){
                    cox.out <- t(parApply(cl=cl,
                                          X=genotypes, 
                                          MARGIN=1, 
                                          FUN=survFit, 
                                          cox.params=cox.params,
                                          print.covs=print.covs))
                } else {
                    cox.out <- survFit(genotypes,
                                       cox.params=cox.params,
                                       print.covs=print.covs) 
                }
            }else if(inter.term %in% covariates){
                if(is.matrix(genotypes)){
                    cox.out <- t(parApply(cl=cl,
                                          X=genotypes,
                                          MARGIN=1,
                                          FUN=survFitInt, 
                                          cox.params=cox.params, 
                                          cov.interaction=inter.term,
                                          print.covs=print.covs))
                } else {
                    cox.out <- survFitInt(genotypes,
                                          cox.params=cox.params,
                                          cov.interaction=inter.term, 
                                          print.covs=print.covs)
                }
            }
            #############################################
            michigan.out <- list(dropped.snps=snp.drop)
            michigan.out$res <- coxExtract(cox.out,
                                           snp,
                                           cox.params$n.sample,
                                           cox.params$n.event,
                                           print.covs)
            return(michigan.out)
        },
        error=function(err) err
    )
    if(inherits(empty.geno, "error")){
        michigan.out <- list(dropped.snps=snp.drop)
        michigan.out$res <- NULL
        return(michigan.out)
    } 
}

