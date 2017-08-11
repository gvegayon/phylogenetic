
#' @rdname aphylo_estimates-class
#' @param what Either a character scalar or an integer vector. If a character,
#' then it can be either \code{"missings"}, \code{"leafs"}, or \code{"all"}. If an integer vector,
#' then these must be values between \eqn{[0, n - 1]} (node ids).
#' @return In the case of the \code{predict} method, a two-column numeric matrix
#' with values between \eqn{[0,1]} (probabilities).
#' @export
predict.aphylo_estimates <- function(object, what = c("missings", "all"), ...) {
  
  # Parameters
  n <- nrow(object$dat$annotations)
  
  # Checking the default
  if (length(what) == 2 && all(what == c("missings", "all")))
    what <- "missings"
  
  # Checking what to predict
  if (length(what) >= 1 && inherits(what, "integer")) {
    ran <- range(what)
    
    # Out of range
    test <- which(ran < 0 | ran >= n)
    if (length(test))
      stop("Ids in -what- out of range:\n", paste(what[test], collapse=", "), ".")
    
    ids <- what
  } else if (length(what) == 1 && what == "missings") {
    ids <- with(object$dat, which(
      noffspring == 0 & apply(annotations, 1, function(a) any(a == 9)*1L) > 0
    ))
    
    if (!length(ids))
      stop("No missing nodes to predict.")
    
    # Adjusting indices
    ids <- ids - 1L
    
  } else if (length(what) == 1 && what == "all") {
    ids <- 0L:(n-1L)
  } else if (length(what) == 1 && what == "leafs") {
    ids <- which(object$dat$noffspring == 0) - 1L
  } else if (is.vector(what) & inherits(what, "character")) {
    ids <- match(what, rownames(object$dat$annotations))
  } else 
    stop("Undefined method for -what- equal to: ", what)
  
  # Running prediction function
  pred <- with(object, 
               predict_funs(
                 ids         = ids,
                 edges       = dat$edges,
                 annotations = dat$annotations,
                 offspring   = dat$offspring,
                 noffspring  = dat$noffspring,
                 psi         = par[1:2],
                 mu          = par[3:4],
                 Pi          = par[5]
               )
  )
  
  # Adding names
  dimnames(pred) <- list(
    rownames(object$dat$annotations)[ids],
    colnames(object$dat$annotations))
  
  pred
}

#' @rdname aphylo_estimates-class
#' @param expected Integer vector of length \eqn{n}. Expected values (either 0 or 1).
#' @param alpha Numeric scalar. Prior belief of the parameter of the bernoulli distribution
#' used to compute the random imputation score.
#' @param W A square matrix. Must have as many rows as genes in \code{expected}.
#' @export
#' @details In the case of \code{prediction_score}, \code{...} are passed to
#' \code{predict.aphylo_estimates}.
#' 
#' @examples 
#' # Example with prediction_score ---------------------------------------------
#' set.seed(1312)
#' ap  <- sim_annotated_tree(10, P = 1, Pi=.2, mu=c(.05,.02))
#' ans <- aphylo_mcmc(rep(.05, 5), ap, control = list(nbatch=1e4, thin=100),
#'                    priors = function(x) dbeta(x, 1, 30))
#'                    
#' pr <- prediction_score(ans)
#' with(pr, cbind(Expected = expected, Predicted = predicted))
prediction_score <- function(
  x,
  expected = NULL,
  alpha    = 0.5,
  W        = NULL,
  ...) {
  
  # Finding relevant ids
  if (!length(expected)) 
    expected <- x$dat$annotations
  else {
    test <- all(dim(expected) == dim(x$dat$annotations))
    if (!test) 
      stop("-expected- must have the same dimmension as -x$dat$annotations-.")
  }

  # We will only focuse on those that we can actually asses
  ids <- which(apply(expected, 1L, function(x) all(x != 9L)))
  
  # And furthermore, only on the leafs
  ids <- intersect(ids, which(x$dat$noffspring == 0))

  # Prediction
  pred <- predict.aphylo_estimates(x, what = ids - 1L, ...)
  
  # Inverse of Geodesic distances
  if (!length(W)) {
    G     <- approx_geodesic(x$dat$edges, undirected = TRUE)[ids,ids]
    G_inv <- 1/(G + diag(nrow(G)))
  } else {
    G_inv <- W
    if (!all(dim(W) == rep(length(ids), 2)))
      stop(sprintf("-W- must have be of dimmension dim(W) == c(%i, %1$i)", length(ids)))
  }
  
  
  # Observed score
  if (!length(expected))
    expected <- x$dat$annotations[ids, ]
  
  obs <- sqrt(rowSums((pred - expected[ids,,drop = FALSE])^2))
  obs <- t(obs) %*% G_inv %*% obs
  
  # Best case
  best <- 0
  
  # Worst case
  worse <- sum(G_inv)*ncol(pred)
  
  # Random case
  rand  <- prediction_score_rand(expected[ids,,drop=FALSE], G_inv, alpha)
  
  structure(
    list(
      obs       = obs,
      worse     = worse,
      predicted = pred,
      expected  = expected[ids, ,drop=FALSE],
      random    = rand,
      alpha     = alpha
    ), class = "aphylo_prediction_score"
  )
  
}

predict_random <- function(P, A, G_inv) {
  n <- nrow(G_inv)
  sapply(1:10000, function(x) {
    A_hat <- matrix(sample(c(0,1), P*n, TRUE), ncol = P)
    obs   <- sqrt(rowSums((A - A_hat)^2))
    t(obs) %*% G_inv %*% obs
  })
}

#' @export
#' @rdname aphylo_estimates-class
print.aphylo_prediction_score <- function(x, ...) {
  cat("PREDICTION SCORE: ANNOTATED PHYLOGENETIC TREE\n")
  with(x, cat(
    sprintf("Observed : %-.2f (%.2f)", obs/worse, obs),
    sprintf("Random   : %-.2f (%.2f)", random/worse, random),
    sprintf("Best     : 0.00 (0.00)"),
    sprintf("Worse    : 1.00 (%.2f)", worse),
    paste0(rep("-", getOption("width")), collapse=""),
    "Values between 0 and 1, 0 been best. Absolute scores in parenthesis.",
    sep ="\n"
  ))
  invisible(x)
}
  

#' @export
#' @param y Ignored.
#' @rdname aphylo_estimates-class  
plot.aphylo_prediction_score <- function(x, y=NULL, ...) {
  
  k <- ncol(x$expected)
  y <- rep(1L, nrow(x$expected))
  
  oldpar <- par(no.readonly = TRUE)
  on.exit(par(oldpar))
  par(mfrow=c(1, k), mai=c(1,.25,1,.25))
  
  for (i in 1:k) {
    
    # Sorting accordingly to predicted
    ord <- order(x$predicted[,i])

    # Processing labels
    L <- c(.1, .25, .5, .75)
    pos <- NULL
    for (l in L)
      pos <- c(pos, which.min(abs(x$predicted[ord,i] - l))[1])
    labs <- rep("", length(ord))
    labs[pos] <- L
    
    piechart(
      y,
      doughnut = .81,
      col=grDevices::gray(1-x$predicted[ord,i]),
      border=NA, 
      labs = labs
    )
    
    graphics::polygon(circle(0, 0, r=1), border = "black")
    
    piechart(
      y,
      doughnut = 0.60,
      r=.80,
      add=TRUE,
      col=grDevices::gray(1-x$expected[ord,i]),
      border=NA
    )
    
    graphics::polygon(circle(0, 0, r=.60), border = "black")
  }
  par(mfrow=c(1,1))
  title(main="Predicted vs Expected", sub = "Inner circle corresponds to expected and outer to predicted")

}
  