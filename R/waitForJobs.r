#' @title Wait for termination of jobs on the batch system
#'
#' @templateVar ids.default all
#' @template ids
#' @param sleep [\code{numeric(1)}]\cr
#'   Seconds to sleep between status updates. Default is \code{10}.
#' @param timeout [\code{numeric(1)}]\cr
#'   After waiting \code{timeout} seconds, show a message and return \code{FALSE}.
#'   This argument may be required on some systems where, e.g., expired jobs or jobs on hold
#'   are problematic to detect. If you don't want a timeout, set this to \code{Inf}.
#'   Default is \code{604800} (one week).
#' @param stop.on.error [\code{logical(1)}]\cr
#'   Immediately cancel if a job terminates with an error? Default is \code{FALSE}.
#' @template reg
#' @return [\code{logical(1)}]. Returns \code{TRUE} if all jobs terminated successfully
#'   and \code{FALSE} if either an error occurred and \code{stop.on.error} is set to \code{TRUE} or the timeout is reached.
#' @export
waitForJobs = function(ids = NULL, sleep = 10, timeout = 604800, stop.on.error = FALSE, reg = getDefaultRegistry()) {
  assertRegistry(reg, writeable = FALSE)
  syncRegistry(reg)
  ids = asIds(reg, ids, default = .findOnSystem(reg))
  assertNumber(sleep, lower = 1)
  if (is.infinite(sleep))
    stop("Argument 'sleep' must be finite")
  assertNumber(timeout, lower = sleep)
  assertFlag(stop.on.error)

  # anything to do at all?
  cf = reg$cluster.functions
  if (is.null(cf$listJobs) || nrow(ids) == 0L)
    return(TRUE)

  info("Waiting for %i jobs ...", nrow(ids))
  timeout = now() + timeout

  n = length(nrow(ids))
  pb = makeProgressBar(total = n, format = "Waiting [:bar] :percent eta: :eta")
  repeat {
    ids = ids[.findOnSystem(reg, ids), nomatch = 0L]
    if (stop.on.error && nrow(.findError(reg, ids)) > 0L)
      return(FALSE)
    if (nrow(ids) == 0L)
      return(TRUE)
    if (now() > timeout)
      return(FALSE)
    pb$tick(n - nrow(ids))
    n = nrow(ids)
    Sys.sleep(sleep)
    suppressMessages(syncRegistry(reg = reg))
  }
}