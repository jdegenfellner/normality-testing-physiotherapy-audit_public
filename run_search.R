suppressMessages({library(rentrez); library(tidyverse); library(xml2)})

normality_terms <- c('"Shapiro-Wilk"','"Shapiro Wilk"','"Kolmogorov-Smirnov"','"Kolmogorov Smirnov"',
  '"Lilliefors"','"Anderson-Darling"','"normality test"','"test for normality"',
  '"tested for normality"','"assess normality"','"check normality"',"\"D'Agostino\"")
normality_query <- paste0("(", paste(normality_terms, collapse = "[tiab] OR "), "[tiab])")

physio_journals <- c('"J Physiother"','"Phys Ther"','"Physiother Theory Pract"','"J Orthop Sports Phys Ther"',
  '"Physiotherapy"','"Arch Phys Med Rehabil"','"Clin Rehabil"','"Disabil Rehabil"','"Eur J Phys Rehabil Med"',
  '"J Phys Ther Sci"','"Musculoskelet Sci Pract"','"J Hand Ther"','"Braz J Phys Ther"','"Hong Kong Physiother J"',
  '"Phys Ther Sport"','"Physiother Can"')
journal_query <- paste0("(", paste(physio_journals, collapse = "[ta] OR "), "[ta])")

YEAR_FROM <- 2015; YEAR_TO <- 2024
date_query <- paste0('("', YEAR_FROM, '/01/01"[dp] : "', YEAR_TO, '/12/31"[dp])')
full_query <- paste(normality_query, "AND", journal_query, "AND", date_query)

sr <- entrez_search(db="pubmed", term=full_query, retmax=0, use_history=TRUE)
cat(sprintf("TOTAL HITS: %d\n", sr$count))
srf <- entrez_search(db="pubmed", term=full_query, retmax=min(sr$count,9999), use_history=TRUE)
all_ids <- srf$ids
cat(sprintf("Retrieved %d IDs\n", length(all_ids)))
saveRDS(all_ids, "all_ids.rds")
