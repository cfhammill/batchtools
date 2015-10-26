#' @title Submit jobs or chunks of jobs to batch system via cluster function.
#'
#' @description
#' Submits all jobs to the batch system using the resources provided via \code{resources}.
#'
#' If an additional column \dQuote{chunk} is present in the table \code{ids},
#' the jobs will be grouped accordingly. See \code{\link{chunkIds}} for more
#' information.
#'
#' @templateVar ids.default findNotSubmitted
#' @template ids
#' @param resources [\code{list}]\cr
#'   Required resources for all batch jobs. The elements of this list
#'   (e.g. something like \dQuote{walltime} or \dQuote{nodes} depend on by your template job file.
#'   Defaults can be set in the \code{\link{Registry}} via \code{default.resources}.
#' @template reg
#' @return [\code{\link{data.table}}]. Table with columns \dQuote{job.id} and \dQuote{chunk}.
#' @export
submitJobs = function(ids = NULL, resources = list(), reg = getDefaultRegistry()) {
  assertRegistry(reg, writeable = TRUE)
  syncRegistry(reg)
  assertList(resources, names = "strict")
  ids = asIds(reg, ids, default = .findNotSubmitted(reg), extra.cols = TRUE)
  drop = setdiff(names(ids), c("job.id", "chunk"))
  if (length(drop) > 0L)
    ids[, drop := NULL, with = FALSE]

  on.sys = .findOnSystem(reg, ids)
  if (nrow(on.sys) > 0L)
    stopf("Some jobs are already on the system, e.g. %s", paste0(head(on.sys$job.id), collapse = ", "))

  if (is.null(ids$chunk)) {
    ids$chunk = seq_row(ids)
    chunks = seq_row(ids)
  } else {
    assertInteger(ids$chunk, any.missing = FALSE)
    chunks = sort(unique(ids$chunk))
  }
  chunk = NULL
  setkeyv(ids, "chunk")

  resources = insert(reg$default.resources, resources)
  resources = resources[order(names2(resources))]
  res.hash = digest::digest(resources)
  resources.hash = NULL
  res.id = head(reg$resources[resources.hash == res.hash, "resource.id", with = FALSE]$resource.id, 1L)
  if (length(res.id) == 0L) {
    res.id = if (nrow(reg$resources) > 0L) max(reg$resources$resource.id) + 1L else 1L
    reg$resources = rbind(reg$resources, data.table(resource.id = res.id, resources.hash = res.hash, resources = list(resources)))
    setkeyv(reg$resources, "resource.id")
  }

  on.exit(saveRegistry(reg))

  wait = 1
  info("Submitting %i jobs in %i chunks using cluster functions '%s' ...", nrow(ids), length(chunks), reg$cluster.functions$name)
  update = data.table(submitted = NA_integer_, started = NA_integer_, done = NA_integer_, error = NA_character_,
    memory = NA_real_, resource.id = res.id, batch.id = NA_character_, job.hash = NA_character_)

  pb = makeProgressBar(total = length(chunks), format = "Submit [:bar] :percent eta: :eta")
  for (ch in chunks) {
    ids.chunk = ids[chunk == ch, nomatch = 0L]
    jd = makeJobDescription(ids.chunk, resources = resources, reg = reg)
    if (reg$cluster.functions$store.job)
      write(jd, file = jd$uri, wait = TRUE)

    repeat {
      submit = reg$cluster.functions$submitJob(reg = reg, jd = jd)

      if (submit$status == 0L) {
        update[,  c("submitted", "batch.id", "job.hash") := list(now(), submit$batch.id, jd$job.hash)]
        reg$status[ids.chunk, names(update) := update]
        break
      } else if (submit$status > 0L && submit$status < 100L) {
        # temp error
        retries = retries + 1L
        Sys.sleep(wait)
      } else if (submit$status > 100L && submit$status <= 200L) {
        # fatal error
        stopf("Fatal error occurred: %i. %s", submit$status, submit$msg)
      }
    }
    pb$tick()
  }

  ### return ids (on.exit handler kicks now in to submit the remaining messages)
  syncRegistry(reg = reg, save = FALSE)
  setkeyv(ids, "job.id")
  return(invisible(ids))
}