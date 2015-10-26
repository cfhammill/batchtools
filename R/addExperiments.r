#' @title Add Experiemts to the Registry
#'
#' @description
#' Adds experiments for running algorithms on problems to the registry and thereby defines batch jobs.
#' Each element in the Cartesian product of problem designs and algorithm designs defines one computational job.
#'
#' @param prob.designs [named list of \code{\link[data.table]{data.table}} or \code{link[base]{data.frame}}]\cr
#'   Named list of data frames. The name must match the problem name while the column names correspond to parameters
#'   of the problem.
#' @param algo.designs [named list of \code{\link[data.table]{data.table}} or \code{link[base]{data.frame}}]\cr
#'   Named list of data frames. The name must match the algorithm name while the column names correspond to parameters
#'   of the algorithm.
#' @param repls [\code{integer(1)}]\cr
#'   Number of replications for each distinct experiment.
#' @template expreg
#' @return [\code{data.table}]. Generated job ids are stored in the column \dQuote{job.id}.
#' @export
addExperiments = function(prob.designs, algo.designs, repls = 1L, reg = getDefaultRegistry()) {
  assertExperimentRegistry(reg, writeable = TRUE)
  assertList(prob.designs, types = "data.frame", names = "named")
  assertList(algo.designs, types = "data.frame", names = "named")
  assertSubset(names(prob.designs), reg$problems)
  assertSubset(names(algo.designs), reg$algorithms)
  repls = asCount(repls)

  maxId = function(ids) if (length(ids) == 0L) 0L else max(ids)
  combine = function(i, j) list(prob.name = pn, prob.pars = as.list(pd[i]), algo.name = an, algo.pars = as.list(ad[j]))
  all.ids = integer(0L)
  def.id = NULL

  for (i in seq_along(prob.designs)) {
    pn = names(prob.designs)[i]
    pd = prob.designs[[i]]
    n.pd = max(nrow(pd), 1L)

    for (j in seq_along(algo.designs)) {
      an = names(algo.designs)[j]
      ad = algo.designs[[j]]
      n.ad = max(nrow(ad), 1L)

      n.jobs = n.pd * n.ad * repls
      info("Adding %i experiments ('%s'[%i] x '%s'[%i] x repls[%i]) ...", n.jobs, pn, n.pd, an, n.ad, repls)

      tab = data.table(pars = .mapply(combine, CJ(i = seq_len(n.pd), j = seq_len(n.ad)), MoreArgs = list()))
      tab$pars.hash = vcapply(tab$pars, digest::digest)
      tab = merge(reg$defs[, !"pars", with = FALSE], tab, by = "pars.hash", all.x = FALSE, all.y = TRUE, sort = FALSE)

      miss = tab[is.na(def.id), which = TRUE]
      tab[miss, "def.id" := maxId(reg$defs$def.id) + seq_along(miss)]
      reg$defs = rbind(reg$defs, tab[miss])

      tab = CJ(def.id = tab$def.id, repl = seq_len(repls))
      tab = tab[!reg$status, on = c("def.id", "repl")]
      if (nrow(tab) < n.jobs)
        info("Skipping %i duplicated experiments ...", n.jobs - nrow(tab))
      tab$job.id = maxId(reg$status$job.id) + seq_row(tab)
      reg$status = rbind(reg$status, tab, fill = TRUE)
      all.ids = c(all.ids, tab$job.id)
    }
  }
  setkeyv(reg$defs, "def.id")
  setkeyv(reg$status, "job.id")
  saveRegistry(reg)
  invisible(data.table(job.id = all.ids, key = "job.id"))
}