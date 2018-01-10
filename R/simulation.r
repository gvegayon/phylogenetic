#' Random tree generation
#' 
#' An alternative to [ape::rtree]. This function was written in C++ and is 
#' significantly faster than `rtree`. 
#' 
#' @param n Integer scalar. Number of leaf nodes.
#' @param edge.length A Function. Used to set the length of the edges.
#' 
#' @details The algorithm was implemented as follows
#' 
#' \enumerate{
#'   \item Initialize `N = {1, ..., n}`, `E` to be empty,
#'   `k = 2*n - 1`
#'   \item While `length(N) != 1` do:
#'   \enumerate{
#'     \item Randomly choose a pair `(i, j)` from `N`
#'     \item Add the edges `E = E U {(k, i), (k, j)}`,
#'     \item Redefine `N = (N \ {i, j}) U {k}`
#'     \item Set `k = k - 1`
#'     \item next
#'   }
#'   \item Use `edge.length(2*n - 1)` (simulating branch lengths).
#' }
#' 
#' 
#' @return An object of class [ape::phylo] with the edgelist as a postorderd,
#' `node.label` and `edge.length`.
#' 
#' @examples
#' # A very simple example ----------------------------------------------------
#' set.seed(1223)
#' newtree <- sim_tree(50)
#' 
#' plot(newtree)
#' 
#' 
#' # A performance benchmark with ape::rtree ----------------------------------
#' \dontrun{
#' library(ape)
#' microbenchmark::microbenchmark(
#'   ape = rtree(1e3),
#'   phy = sim_tree(1e3),
#'  unit = "relative"
#' )
#' # This is what you would get.
#' # Unit: relative
#' #   expr     min       lq     mean  median       uq      max neval
#' #    ape 14.7598 14.30809 14.30013 16.7217 14.32843 4.754106   100
#' #    phy  1.0000  1.00000  1.00000  1.0000  1.00000 1.000000   100
#' }
#' @export
sim_tree <- function(n, edge.length = NULL) {
  
  if (!is.null(edge.length) && !is.function(edge.length))
    stop("When not NULL `edge.length` should be a function.")
  
  if (!length(edge.length))
    .sim_tree(n, function(x) {}, FALSE)
  else
    .sim_tree(n, edge.length, TRUE)
  
}

#' Simulate functions on a ginven tree
#' 
#' @param tree An object of class [phylo][ape::read.tree]
#' @param psi A numeric vector of length 2 (see details).
#' @param mu A numeric vector of length 2 (see details).
#' @param Pi A numeric vector of length 2 (see details).
#' @param P Integer scalar. Number of functions to simulate.
#' 
#' @details
#' 
#' Using the model described in the vignette
#' \href{../doc/peeling_phylo.html}{peeling_phylo.html}
#' 
#' @return An matrix of size \code{length(offspring)*P} with values 9, 0 and 1
#' indicating \code{"no information"}, \code{"no function"} and \code{"function"}.
#' 
#' @examples
#' # Example 1 ----------------------------------------------------------------
#' # We need to simulate a tree
#' set.seed(1231)
#' newtree <- sim_tree(1e3)
#' 
#' # Preprocessing the data
#' 
#' # Simulating
#' ans <- sim_fun_on_tree(
#'   newtree,
#'   psi = c(.001, .05),
#'   mu = c(.01, .05),
#'   Pi = c(.5, .5)
#' )
#' 
#' # Tabulating results
#' table(ans)
#' @name sim_fun_on_tree
NULL

#' To register function counts
#' This is just to keep track of how many simulations were needed to have an
#' informative function.
#' @noRd 
sim_counts <- new.env(parent = emptyenv())
sim_counts$n <- vector("integer", 5e4)
sim_counts$i <- 1L
sim_counts$add <-function(n) {
  
  # Adding the number to the counter
  sim_counts$n[sim_counts$i] <- n
  
  # Restarting the counter!
  if (sim_counts$i == 5e4)
    sim_counts$i <- 0L
  
  # Adding one element
  sim_counts$i <- sim_counts$i + 1L
}

#' @rdname sim_fun_on_tree
#' @param informative Logical scalar. When `TRUE` (default) the function 
#' re-runs the simulation algorithm until both 0s and 1s show in the leaf
#' nodes of the tree.
#' @param maxtries Integer scalar. If `informative = TRUE`, then the function
#' will try at most `maxtries` times.
#' @export
sim_fun_on_tree <- function(
  tree,
  psi,
  mu,
  Pi,
  P           = 1L,
  informative = TRUE,
  maxtries    = 20L
) {
  
  # Must be coerced into a tree of class ape::phylo
  if (!inherits(tree, "phylo") & !inherits(tree, "aphylo"))
    stop("`tree` must be of class `phylo` or `aphylo`.", call. = FALSE)
  
  tree <- ape::as.phylo(tree)
  
  # Generating the preorder sequence
  pseq <- ape::postorder(tree)
  pseq <- tree$edge[pseq, 2]
  
  # The preorder is just the inverse of the post order!
  # now, observe that the main function does the call using indexes starting
  # from 0, BUT, that's corrected in the function itself
  pseq <- c(length(tree$tip.label) + 1L, pseq[length(pseq):1L])
  
  # Calling the c++ function that does the hard work
  has_both  <- FALSE
  ntries    <- 1L
  offspring <- list_offspring(tree)
  ntips     <- length(tree$tip.label)
  while (!has_both) {
    f <- .sim_fun_on_tree(
      offspring = offspring,
      pseq      = pseq,
      psi       = psi,
      mu        = mu,
      Pi        = Pi,
      P         = P
    )
    
    # Checking break
    if (!informative | (ntries > maxtries))
      break
    
    # Increasing
    tab <- fast_table_using_labels(as.vector(f[1:ntips,]), c(0, 1))
    has_both <- (tab[1] > 0) & (tab[2] > 0)
    ntries <- ntries + 1L
  }
  
  # Increasing the stats
  sim_counts$add(ntries - 1L)
  
  # Wasn't
  if (informative & !has_both)
    warning("The computed function has either only zeros or only ones.")
  
  f
}

#' Simulation of Annotated Phylogenetic Trees
#' 
#' @param n Integer scalar. Number of leafs. If not specified, then 
#' @param tree An object of class [phylo][ape::read.tree].
#' @param P Integer scalar. Number of functions to generate.
#' @template parameters
#' @templateVar psi 1
#' @templateVar mu 1
#' @templateVar Pi 1
#' @param informative,maxtries Passed to [sim_fun_on_tree].
#' @return An object of class [aphylo]
#' @family Simulation Functions 
#' @export
#' @examples 
#' # A simple example ----------------------------------------------------------
#' 
#' set.seed(1231)
#' ans <- sim_annotated_tree(n=500)
#' 
sim_annotated_tree <- function(
  n           = NULL,
  tree        = NULL,
  P           = 1,
  psi         = c(.05, .05),
  mu          = c(.1,.05),
  Pi          = 1,
  informative = TRUE,
  maxtries    = 20L
  ) {
  
  
  # Step 1: Simulate a tree
  if (!length(tree)) {
    
    # Checking if there's n
    if (!length(n))
      stop("When -tree- is not specified, -n- must be specified.")
    tree  <- sim_tree(n)
    
  } else 
    tree <- as.phylo(tree)
  
  
  # Step 2: Simulate the annotations
  ans <- sim_fun_on_tree(
    tree  = tree,
    psi   = psi,
    mu    = mu,
    Pi    = Pi,
    P     = P
  )
  
  # Creating the aphylo object
  nleaf <- length(tree$tip.label)
  as_aphylo(
    tip.annotation  = ans[1L:nleaf, ,drop=FALSE],
    node.annotation = ans[(nleaf + 1L):nrow(ans), , drop=FALSE],
    tree            = tree
  )
  
}

#' Randomly drop leaf annotations
#' 
#' The function takes an annotated tree and randomly selects leaf nodes to set
#' annotations as 9 (missing). The function allows specifying a proportion of
#' annotations to drop, and also the relative probability that has dropping
#' a 0 with respecto to a 1.
#' 
#' @param x An object of class [aphylo].
#' @param pcent Numeric scalar. Proportion of the annotations to remove.
#' @param prob.drop.0 Numeric scalar. Probability of removing a 0, conversely,
#' `1 - prob.drop.0` is the probability of removing a 1.
#' @param informative Logical scalar. If `TRUE` (the default) the algorithm drops
#' annotations only if the number of annotations to drop of either 0s or 1s are
#' less than the currently available in the data.
#' @return `x` with fewer annotations (more 9s).
#' 
#' @examples 
#' # The following tree has roughtly the same proportion of 0s and 1s
#' # and 0 mislabeling.
#' set.seed(1)
#' x <- sim_annotated_tree(200, Pi=.5, mu=c(.5,.5), psi=c(0,0))
#' summary(x)
#' 
#' # Dropping half of the annotations
#' summary(rdrop_annotations(x, .5))
#' 
#' # Dropping half of the annotations, but 0 are more likely to drop
#' summary(rdrop_annotations(x, .5, prob.drop.0 = 2/3))
#' 
#' @export
rdrop_annotations <- function(
  x, pcent,
  prob.drop.0 = .5,
  informative = TRUE
  ) {
  
  # Number of leafs
  n       <- length(x$tree$tip.label)
  nremove <- max(ceiling(pcent*n), 1L)
  
  # Cannot be strictly 0 or 1
  prob.drop.0 <- max(.0001, min(prob.drop.0, .9999))

  # We do this for each function
  prob.drop.0     <- c(prob.drop.0, 1 - prob.drop.0)
  prob.drop.0[8L] <- 0L
  for (p in 1L:ncol(x$tip.annotation)) {
    
    # How many non 9 are there?
    tab <- fast_table_using_labels(x$tip.annotation[,p], c(0L, 1L, 9L))
    nleft <- n - tab[3L]

    # Which ones will be removed
    ids <- sample.int(
      n, 
      size    = min(nleft, nremove),
      replace = FALSE,
      prob    = prob.drop.0[x$tip.annotation[,p] + 1L]
      )
    
    # Only removing if must keep informative
    if (informative) {
      n0 <- tab[1]
      n1 <- tab[2]
      
      tab <- fast_table_using_labels(x$tip.annotation[ids, p], c(0L, 1L, 9L))
      
      # If we are dropping the same number of 0 and 1 that are in the table
      # currently, then we don't, and go to the next try
      if ((tab[1] == n0) | (tab[2] == n1))
        next
    }
    
    stopifnot(!is.null(ids))
    x$tip.annotation[ids, p] <- 9L
  }
  
  x
}